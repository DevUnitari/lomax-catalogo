import io
import os

import boto3
from botocore.exceptions import ClientError
from PIL import Image, ImageOps

MAX_BYTES = 5 * 1024 * 1024
MAX_LADO = 300
FORMATOS = ("JPEG", "PNG")
TABLA = os.environ.get("TABLA", "productos_atributos")
BUCKET_MINIATURAS = os.environ.get("BUCKET_MINIATURAS", "lomax-miniaturas")
ENDPOINT = os.environ.get("AWS_ENDPOINT_URL")

s3 = boto3.client("s3", endpoint_url=ENDPOINT)
dynamo = boto3.client("dynamodb", endpoint_url=ENDPOINT)


class ImagenInvalida(Exception):
    pass


def leer_original(bucket, key):
    try:
        cabecera = s3.head_object(Bucket=bucket, Key=key)
    except ClientError as e:
        if e.response["Error"]["Code"] in ("404", "NoSuchKey", "NotFound"):
            raise ImagenInvalida("original no encontrado en S3")
        raise
    if cabecera["ContentLength"] > MAX_BYTES:
        raise ImagenInvalida("el original supera 5 MB")
    return s3.get_object(Bucket=bucket, Key=key)["Body"].read()


def generar_miniatura(datos):
    try:
        im = Image.open(io.BytesIO(datos))
        formato = im.format
        if formato not in FORMATOS:
            raise ImagenInvalida("formato no permitido: %s" % formato)
        im.verify()
        im = Image.open(io.BytesIO(datos))
        im.load()
    except ImagenInvalida:
        raise
    except Exception:
        raise ImagenInvalida("el archivo no es una imagen valida")

    im = ImageOps.exif_transpose(im)
    if im.mode in ("RGBA", "LA", "P"):
        im = im.convert("RGBA")
        fondo = Image.new("RGB", im.size, (255, 255, 255))
        fondo.paste(im, mask=im.split()[-1])
        im = fondo
    else:
        im = im.convert("RGB")

    im.thumbnail((MAX_LADO, MAX_LADO), Image.Resampling.LANCZOS)
    salida = io.BytesIO()
    im.save(salida, "JPEG", quality=85, optimize=True)
    return salida.getvalue(), im.width, im.height


def registrar_ok(producto_id, key, thumb_key, ancho, alto):
    dynamo.update_item(
        TableName=TABLA,
        Key={"producto_id": {"N": str(producto_id)}},
        UpdateExpression=(
            "SET imagen_original_key=:o, miniatura_key=:m, estado_procesamiento=:e, "
            "miniatura_ancho=:w, miniatura_alto=:h REMOVE error_detalle"
        ),
        ConditionExpression="attribute_exists(producto_id)",
        ExpressionAttributeValues={
            ":o": {"S": key},
            ":m": {"S": thumb_key},
            ":e": {"S": "LISTA"},
            ":w": {"N": str(ancho)},
            ":h": {"N": str(alto)},
        },
    )


def registrar_error(producto_id, key, thumb_key, detalle):
    s3.delete_object(Bucket=BUCKET_MINIATURAS, Key=thumb_key)
    dynamo.update_item(
        TableName=TABLA,
        Key={"producto_id": {"N": str(producto_id)}},
        UpdateExpression=(
            "SET imagen_original_key=:o, miniatura_key=:m, estado_procesamiento=:e, "
            "error_detalle=:d REMOVE miniatura_ancho, miniatura_alto"
        ),
        ConditionExpression="attribute_exists(producto_id)",
        ExpressionAttributeValues={
            ":o": {"S": key},
            ":m": {"NULL": True},
            ":e": {"S": "ERROR"},
            ":d": {"S": detalle},
        },
    )
    return {"ok": False, "estado": "ERROR", "producto_id": producto_id, "error": detalle}


def lambda_handler(event, context):
    try:
        producto_id = int(event["producto_id"])
        bucket = event["bucket"]
        key = event["key"]
    except (KeyError, TypeError, ValueError):
        return {"ok": False, "estado": "ERROR",
                "error": "evento invalido: se requiere producto_id, bucket y key"}

    thumb_key = "miniaturas/%d.jpg" % producto_id
    try:
        datos = leer_original(bucket, key)
        miniatura, ancho, alto = generar_miniatura(datos)
    except ImagenInvalida as e:
        return registrar_error(producto_id, key, thumb_key, str(e))

    s3.put_object(Bucket=BUCKET_MINIATURAS, Key=thumb_key,
                  Body=miniatura, ContentType="image/jpeg")
    registrar_ok(producto_id, key, thumb_key, ancho, alto)
    return {"ok": True, "estado": "LISTA", "producto_id": producto_id,
            "miniatura_bucket": BUCKET_MINIATURAS, "miniatura_key": thumb_key,
            "ancho": ancho, "alto": alto}
