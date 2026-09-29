import json
import os
import re
import socket
from contextlib import contextmanager
from decimal import Decimal
from typing import Any

import boto3
import psycopg
from boto3.dynamodb.types import TypeDeserializer, TypeSerializer
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError
from fastapi import FastAPI, File, Request, UploadFile
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel

ENDPOINT = os.environ.get("AWS_ENDPOINT_URL")
TABLA = os.environ.get("TABLA", "productos_atributos")
BUCKET_ORIG = os.environ.get("BUCKET_ORIGINALES", "lomax-originales")
BUCKET_MINI = os.environ.get("BUCKET_MINIATURAS", "lomax-miniaturas")
FUNCION = os.environ.get("FUNCION_MINIATURAS", "miniaturas")
MAX_BYTES = 5 * 1024 * 1024
INSTANCIA = socket.gethostname()

_cfg = Config(retries={"max_attempts": 2}, connect_timeout=5, read_timeout=15,
              s3={"addressing_style": "path"})
s3 = boto3.client("s3", endpoint_url=ENDPOINT, config=_cfg)
dynamo = boto3.client("dynamodb", endpoint_url=ENDPOINT, config=_cfg)
lam = boto3.client("lambda", endpoint_url=ENDPOINT,
                   config=Config(retries={"max_attempts": 1}, connect_timeout=5, read_timeout=120))
deser = TypeDeserializer()
ser = TypeSerializer()

TIPOS = {"Teclados": "TECLADO", "Monitores": "MONITOR", "Televisores": "TELEVISOR"}
ESPERADOS = {"TECLADO": ("conexion", "distribucion"),
             "MONITOR": ("pulgadas", "resolucion"),
             "TELEVISOR": ("pulgadas", "resolucion")}

app = FastAPI(title="Lomax Catalogo API")


class ApiError(Exception):
    def __init__(self, status, mensaje, paso=None, **extra):
        self.status, self.mensaje, self.paso, self.extra = status, mensaje, paso, extra


@app.exception_handler(ApiError)
async def _api_error(request: Request, exc: ApiError):
    cuerpo = {"detail": exc.mensaje}
    if exc.paso:
        cuerpo["paso_fallido"] = exc.paso
    cuerpo.update(exc.extra)
    return JSONResponse(status_code=exc.status, content=cuerpo)


@app.exception_handler(RequestValidationError)
async def _validacion(request: Request, exc: RequestValidationError):
    errores = [{"campo": ".".join(str(x) for x in e["loc"]), "mensaje": e["msg"]}
               for e in exc.errors()]
    return JSONResponse(status_code=400, content={"detail": "entrada invalida", "errores": errores})


@app.middleware("http")
async def _instancia(request: Request, call_next):
    resp = await call_next(request)
    resp.headers["X-Instance-Id"] = INSTANCIA
    return resp


@contextmanager
def paso(nombre):
    try:
        yield
    except ApiError:
        raise
    except (BotoCoreError, ClientError) as e:
        raise ApiError(502, "fallo el servicio %s: %s" % (nombre, e), paso=nombre)
    except (psycopg.OperationalError, psycopg.InterfaceError) as e:
        raise ApiError(503, "fallo el servicio rds: %s" % e, paso="rds")


def db():
    return psycopg.connect(
        host=os.environ.get("DB_HOST", "floci"), port=int(os.environ.get("DB_PORT", "7001")),
        dbname=os.environ.get("DB_NAME", "postgres"), user=os.environ.get("DB_USER", "postgres"),
        password=os.environ.get("DB_PASSWORD", ""), connect_timeout=5)


def plano(v):
    if isinstance(v, Decimal):
        return int(v) if v == v.to_integral_value() else float(v)
    if isinstance(v, dict):
        return {k: plano(x) for k, x in v.items()}
    if isinstance(v, list):
        return [plano(x) for x in v]
    return v


def desde_dynamo(item):
    return plano({k: deser.deserialize(v) for k, v in item.items()})


def leer_item(pid):
    with paso("dynamodb"):
        r = dynamo.get_item(TableName=TABLA, Key={"producto_id": {"N": str(pid)}}, ConsistentRead=True)
    return desde_dynamo(r["Item"]) if r.get("Item") else None


def leer_items(ids):
    salida = {}
    with paso("dynamodb"):
        for i in range(0, len(ids), 100):
            pendientes = {TABLA: {"Keys": [{"producto_id": {"N": str(x)}} for x in ids[i:i + 100]]}}
            intentos = 0
            while pendientes and intentos < 5:
                r = dynamo.batch_get_item(RequestItems=pendientes)
                for it in r["Responses"].get(TABLA, []):
                    d = desde_dynamo(it)
                    salida[d["producto_id"]] = d
                pendientes = r.get("UnprocessedKeys") or None
                intentos += 1
    return salida


SQL_PRODUCTO = ("SELECT p.producto_id, p.codigo, p.nombre, p.descripcion, p.precio, p.categoria_id, "
                "c.nombre, p.fecha_registro, p.estado "
                "FROM productos p JOIN categorias c ON c.categoria_id = p.categoria_id ")


def fila_a_dict(f):
    return {"producto_id": f[0], "codigo": f[1], "nombre": f[2], "descripcion": f[3],
            "precio": float(f[4]), "categoria_id": f[5], "categoria": f[6],
            "fecha_registro": f[7].isoformat(), "estado": f[8]}


def get_producto(pid):
    with paso("rds"):
        with db() as conn:
            f = conn.execute(SQL_PRODUCTO + "WHERE p.producto_id = %s", (pid,)).fetchone()
    return fila_a_dict(f) if f else None


def poner_estado(pid, estado):
    with paso("rds"):
        with db() as conn:
            conn.execute("UPDATE productos SET estado = %s WHERE producto_id = %s", (estado, pid))


def validar_atributos(tipo, a):
    esperados = ESPERADOS[tipo]
    faltan = [c for c in esperados if c not in a]
    sobran = [c for c in a if c not in esperados]
    if faltan or sobran:
        raise ApiError(400, "atributos invalidos para %s: faltan %s, sobran %s" % (tipo, faltan, sobran))
    limpio = {}
    for c in esperados:
        v = a[c]
        if c == "pulgadas":
            if isinstance(v, bool) or not isinstance(v, (int, float)) or not (0 < v <= 200):
                raise ApiError(400, "pulgadas debe ser un numero entre 0 y 200")
            limpio[c] = Decimal(str(v))
        elif c == "resolucion":
            if not isinstance(v, str) or not re.fullmatch(r"\d{3,5}x\d{3,5}", v.strip()):
                raise ApiError(400, "resolucion debe tener el formato 1920x1080")
            limpio[c] = v.strip()
        else:
            if not isinstance(v, str) or not v.strip() or len(v.strip()) > 40:
                raise ApiError(400, "%s debe ser un texto no vacio de hasta 40 caracteres" % c)
            limpio[c] = v.strip()
    return limpio


def detectar_formato(b):
    if b[:3] == b"\xff\xd8\xff":
        return "jpg", "image/jpeg"
    if b[:8] == b"\x89PNG\r\n\x1a\n":
        return "png", "image/png"
    return None


def procesar_y_publicar(pid, key):
    payload = json.dumps({"producto_id": pid, "bucket": BUCKET_ORIG, "key": key}).encode()
    with paso("lambda"):
        r = lam.invoke(FunctionName=FUNCION, Payload=payload)
        cuerpo = r["Payload"].read()
    if r.get("FunctionError"):
        raise ApiError(502, "la funcion Lambda fallo: " + cuerpo.decode(errors="replace")[:300],
                       paso="lambda", producto_id=pid, estado="PENDIENTE")
    try:
        res = json.loads(cuerpo)
    except ValueError:
        raise ApiError(502, "respuesta ilegible de Lambda", paso="lambda", producto_id=pid, estado="PENDIENTE")
    if not res.get("ok"):
        poner_estado(pid, "PENDIENTE")
        raise ApiError(400, res.get("error", "imagen invalida"), paso="imagen",
                       producto_id=pid, estado="PENDIENTE")
    item = leer_item(pid)
    if not item or not item.get("atributos"):
        raise ApiError(409, "el producto no tiene atributos registrados en DynamoDB",
                       paso="dynamodb", producto_id=pid, estado="PENDIENTE")
    if item.get("estado_procesamiento") != "LISTA" or not item.get("miniatura_key"):
        raise ApiError(502, "Lambda no confirmo la miniatura", paso="lambda",
                       producto_id=pid, estado="PENDIENTE")
    with paso("s3"):
        try:
            s3.head_object(Bucket=BUCKET_MINI, Key=item["miniatura_key"])
        except ClientError as e:
            if e.response["Error"]["Code"] in ("404", "NoSuchKey", "NotFound"):
                raise ApiError(502, "la miniatura no existe en S3", paso="s3",
                               producto_id=pid, estado="PENDIENTE")
            raise
    poner_estado(pid, "PUBLICADO")
    return {"producto_id": pid, "estado": "PUBLICADO", "miniatura_key": item["miniatura_key"],
            "ancho": item.get("miniatura_ancho"), "alto": item.get("miniatura_alto")}


class ProductoIn(BaseModel):
    codigo: str
    nombre: str
    descripcion: str
    precio: Decimal
    categoria_id: int
    atributos: dict[str, Any]


@app.get("/health")
def health():
    return {"status": "ok", "instancia": INSTANCIA}


@app.get("/categorias")
def categorias():
    with paso("rds"):
        with db() as conn:
            filas = conn.execute("SELECT categoria_id, nombre FROM categorias ORDER BY categoria_id").fetchall()
    return [{"categoria_id": f[0], "nombre": f[1]} for f in filas]


@app.post("/productos", status_code=201)
def crear_producto(p: ProductoIn):
    codigo, nombre, descripcion = p.codigo.strip(), p.nombre.strip(), p.descripcion.strip()
    if not codigo or len(codigo) > 30:
        raise ApiError(400, "codigo obligatorio, maximo 30 caracteres")
    if not nombre or len(nombre) > 120:
        raise ApiError(400, "nombre obligatorio, maximo 120 caracteres")
    if not descripcion:
        raise ApiError(400, "descripcion obligatoria")
    if not p.precio.is_finite() or p.precio < 0 or p.precio > Decimal("99999999.99"):
        raise ApiError(400, "el precio debe ser un numero entre 0 y 99999999.99")
    if p.precio.as_tuple().exponent < -2:
        raise ApiError(400, "el precio admite como maximo 2 decimales")

    with paso("rds"):
        with db() as conn:
            fila = conn.execute("SELECT nombre FROM categorias WHERE categoria_id = %s",
                                (p.categoria_id,)).fetchone()
            if not fila:
                raise ApiError(400, "la categoria no existe")
            tipo = TIPOS.get(fila[0])
            if not tipo:
                raise ApiError(400, "la categoria no tiene esquema de atributos")
            atributos = validar_atributos(tipo, p.atributos)
            try:
                pid = conn.execute(
                    "INSERT INTO productos (codigo, nombre, descripcion, precio, categoria_id) "
                    "VALUES (%s, %s, %s, %s, %s) RETURNING producto_id",
                    (codigo, nombre, descripcion, p.precio, p.categoria_id)).fetchone()[0]
            except psycopg.errors.UniqueViolation:
                raise ApiError(409, "ya existe un producto con ese codigo")

    item = {"producto_id": {"N": str(pid)}, "tipo": {"S": tipo}, "atributos": ser.serialize(atributos),
            "imagen_original_key": {"NULL": True}, "miniatura_key": {"NULL": True},
            "estado_procesamiento": {"S": "PENDIENTE"}}
    try:
        with paso("dynamodb"):
            dynamo.put_item(TableName=TABLA, Item=item,
                            ConditionExpression="attribute_not_exists(producto_id)")
    except ApiError as e:
        e.extra.update({"producto_id": pid, "estado": "PENDIENTE"})
        raise
    return {"producto_id": pid, "codigo": codigo, "estado": "PENDIENTE"}


@app.post("/productos/{producto_id}/imagen")
def subir_imagen(producto_id: int, archivo: UploadFile = File(...)):
    if not get_producto(producto_id):
        raise ApiError(404, "el producto no existe")
    datos = archivo.file.read(MAX_BYTES + 1)
    if len(datos) > MAX_BYTES:
        raise ApiError(413, "el archivo supera 5 MB")
    if not datos:
        raise ApiError(400, "el archivo esta vacio")
    formato = detectar_formato(datos)
    if not formato:
        raise ApiError(415, "formato no permitido: solo JPEG o PNG")
    ext, ctype = formato

    item = leer_item(producto_id)
    if not item:
        raise ApiError(409, "el producto no tiene atributos registrados en DynamoDB",
                       paso="dynamodb", producto_id=producto_id, estado="PENDIENTE")
    anterior = item.get("imagen_original_key")
    key = "originales/%d.%s" % (producto_id, ext)
    with paso("s3"):
        s3.put_object(Bucket=BUCKET_ORIG, Key=key, Body=datos, ContentType=ctype)
        if anterior and anterior != key:
            s3.delete_object(Bucket=BUCKET_ORIG, Key=anterior)
    with paso("dynamodb"):
        dynamo.update_item(
            TableName=TABLA, Key={"producto_id": {"N": str(producto_id)}},
            UpdateExpression="SET imagen_original_key = :o, estado_procesamiento = :e REMOVE error_detalle",
            ConditionExpression="attribute_exists(producto_id)",
            ExpressionAttributeValues={":o": {"S": key}, ":e": {"S": "PENDIENTE"}})
    return procesar_y_publicar(producto_id, key)


@app.post("/productos/{producto_id}/reprocesar")
def reprocesar(producto_id: int):
    if not get_producto(producto_id):
        raise ApiError(404, "el producto no existe")
    item = leer_item(producto_id)
    key = item.get("imagen_original_key") if item else None
    if not key:
        raise ApiError(409, "el producto no tiene imagen original guardada", producto_id=producto_id)
    with paso("s3"):
        try:
            s3.head_object(Bucket=BUCKET_ORIG, Key=key)
        except ClientError as e:
            if e.response["Error"]["Code"] in ("404", "NoSuchKey", "NotFound"):
                raise ApiError(409, "la imagen original no existe en S3", producto_id=producto_id)
            raise
    return procesar_y_publicar(producto_id, key)


@app.get("/productos")
def listar_productos():
    with paso("rds"):
        with db() as conn:
            filas = conn.execute(SQL_PRODUCTO + "WHERE p.estado = 'PUBLICADO' ORDER BY p.producto_id").fetchall()
    productos = [fila_a_dict(f) for f in filas]
    items = leer_items([p["producto_id"] for p in productos])
    for p in productos:
        it = items.get(p["producto_id"], {})
        p["atributos"] = it.get("atributos", {})
        p["miniatura_key"] = it.get("miniatura_key")
        p["imagen_url"] = "/productos/%d/imagen" % p["producto_id"]
    return productos


@app.get("/productos/{producto_id}")
def detalle_producto(producto_id: int):
    p = get_producto(producto_id)
    if not p:
        raise ApiError(404, "el producto no existe")
    it = leer_item(producto_id) or {}
    p["tipo"] = it.get("tipo")
    p["atributos"] = it.get("atributos", {})
    p["imagen"] = {"estado_procesamiento": it.get("estado_procesamiento"),
                   "miniatura_key": it.get("miniatura_key"),
                   "error_detalle": it.get("error_detalle"),
                   "imagen_url": ("/productos/%d/imagen" % producto_id)
                   if it.get("estado_procesamiento") == "LISTA" else None}
    return p


@app.get("/productos/{producto_id}/imagen")
def imagen_producto(producto_id: int):
    it = leer_item(producto_id)
    key = it.get("miniatura_key") if it else None
    if not key or it.get("estado_procesamiento") != "LISTA":
        raise ApiError(404, "la miniatura no esta disponible")
    with paso("s3"):
        try:
            obj = s3.get_object(Bucket=BUCKET_MINI, Key=key)
        except ClientError as e:
            if e.response["Error"]["Code"] in ("404", "NoSuchKey", "NotFound"):
                raise ApiError(404, "la miniatura no esta disponible")
            raise
        contenido = obj["Body"].read()
    return Response(content=contenido, media_type=obj.get("ContentType") or "image/jpeg",
                    headers={"Cache-Control": "public, max-age=300"})
