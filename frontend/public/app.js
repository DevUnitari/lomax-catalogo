const API = "/api";
const CLAVE_PENDIENTE = "lomax_pendiente";
const $ = (s) => document.querySelector(s);

const CAMPOS_TECLADO = [["conexion", "Conexion", "text"], ["distribucion", "Distribucion", "text"]];
const CAMPOS_PANTALLA = [["pulgadas", "Pulgadas", "number"], ["resolucion", "Resolucion (ej. 1920x1080)", "text"]];
// categoria 1 = Teclados; 2 y 3 = Monitores y Televisores (mismos atributos)
const camposDe = (categoriaId) => (Number(categoriaId) === 1 ? CAMPOS_TECLADO : CAMPOS_PANTALLA);

function el(tag, clase, texto) {
  const e = document.createElement(tag);
  if (clase) e.className = clase;
  if (texto !== undefined) e.textContent = texto;
  return e;
}

function mostrar(caja, texto, tipo) {
  caja.textContent = texto;
  caja.className = "mensaje " + tipo;
}

async function api(ruta, opciones) {
  const r = await fetch(API + ruta, opciones);
  const instancia = r.headers.get("X-Instance-Id");
  if (instancia) $("#instancia").textContent = "instancia: " + instancia;
  return r;
}

async function leerJson(r) {
  try { return await r.json(); } catch (e) { return {}; }
}

function textoError(d, status) {
  const detalle = typeof d.detail === "string" ? d.detail : JSON.stringify(d.detail || d);
  return "HTTP " + status + ": " + detalle + (d.paso_fallido ? " (paso fallido: " + d.paso_fallido + ")" : "");
}

const urlMiniatura = (id) => API + "/productos/" + id + "/imagen";
const precio = (p) => "$ " + Number(p).toFixed(2);

/* ---------- Catalogo ---------- */
async function cargarCatalogo() {
  const estado = $("#estado-catalogo");
  const rejilla = $("#rejilla");
  rejilla.replaceChildren();
  mostrar(estado, "Cargando...", "info");
  try {
    const r = await api("/productos");
    const lista = await leerJson(r);
    if (!r.ok) throw new Error(textoError(lista, r.status));
    mostrar(estado, lista.length + " productos publicados", "info");
    lista.forEach((p) => rejilla.append(tarjeta(p)));
  } catch (e) {
    mostrar(estado, e.message, "error");
  }
}

function tarjeta(p) {
  const a = el("a", "tarjeta");
  a.href = "#/producto/" + p.producto_id;
  const img = el("img");
  img.src = urlMiniatura(p.producto_id);
  img.alt = p.nombre;
  img.loading = "lazy";
  a.append(img, el("h3", null, p.nombre), el("div", "precio", precio(p.precio)), el("div", "categoria", p.categoria));
  return a;
}

/* ---------- Detalle ---------- */
async function cargarDetalle(id) {
  const estado = $("#estado-detalle");
  const cont = $("#detalle");
  cont.replaceChildren();
  mostrar(estado, "Cargando...", "info");
  try {
    const r = await api("/productos/" + id);
    const p = await leerJson(r);
    if (!r.ok) throw new Error(textoError(p, r.status));
    estado.textContent = "";
    estado.className = "mensaje";
    const img = el("img", "foto");
    img.src = urlMiniatura(p.producto_id);
    img.alt = p.nombre;
    img.onerror = () => img.replaceWith(el("p", "meta", "Sin miniatura disponible"));
    const atributos = el("dl");
    Object.entries(p.atributos || {}).forEach(([k, v]) => atributos.append(el("dt", null, k), el("dd", null, String(v))));
    cont.append(
      img,
      el("h2", null, p.nombre),
      el("p", "precio", precio(p.precio)),
      el("p", "meta", "producto_id " + p.producto_id + " | " + p.codigo + " | " + p.categoria + " | estado " + p.estado),
      el("p", null, p.descripcion),
      el("h3", null, "Atributos"),
      atributos
    );
  } catch (e) {
    mostrar(estado, e.message, "error");
  }
}

/* ---------- Registro ---------- */
let categorias = [];

function dibujarAtributos() {
  const cont = $("#atributos");
  cont.replaceChildren();
  camposDe($("#categoria").value).forEach(([nombre, etiqueta, tipo]) => {
    const label = el("label", null, etiqueta);
    const input = el("input");
    input.name = nombre;
    input.type = tipo;
    if (tipo === "number") input.step = "any";
    label.append(input);
    cont.append(label);
  });
}

function mostrarPendiente() {
  const id = localStorage.getItem(CLAVE_PENDIENTE);
  $("#pendiente").hidden = !id;
  if (id) $("#pendiente-id").textContent = id;
}

async function prepararRegistro() {
  mostrarPendiente();
  if (categorias.length) return;
  try {
    const r = await api("/categorias");
    categorias = await leerJson(r);
    if (!r.ok) throw new Error(textoError(categorias, r.status));
    $("#categoria").replaceChildren(...categorias.map((c) => new Option(c.nombre, c.categoria_id)));
    dibujarAtributos();
  } catch (e) {
    mostrar($("#resultado"), "No se pudieron cargar las categorias: " + e.message, "error");
  }
}

function leerFormulario() {
  const f = $("#formulario").elements;
  const atributos = {};
  camposDe(f.categoria_id.value).forEach(([nombre, , tipo]) => {
    const v = f[nombre].value.trim();
    atributos[nombre] = tipo === "number" && v !== "" ? Number(v) : v;
  });
  const p = f.precio.value.trim();
  return {
    cuerpo: {
      codigo: f.codigo.value.trim(),
      nombre: f.nombre.value.trim(),
      descripcion: f.descripcion.value.trim(),
      precio: p === "" ? NaN : Number(p),
      categoria_id: Number(f.categoria_id.value),
      atributos: atributos,
    },
    foto: f.foto.files[0],
  };
}

function validar(c, foto) {
  const errores = [];
  if (!c.codigo) errores.push("El codigo es obligatorio.");
  if (!c.nombre) errores.push("El nombre es obligatorio.");
  if (!c.descripcion) errores.push("La descripcion es obligatoria.");
  if (!(c.precio >= 0)) errores.push("El precio debe ser un numero mayor o igual a 0.");
  Object.entries(c.atributos).forEach(([k, v]) => {
    if (v === "" || (typeof v === "number" && isNaN(v))) errores.push("Completa el atributo: " + k + ".");
  });
  if (!foto) errores.push("Selecciona una fotografia.");
  return errores;
}

async function subirImagen(id, foto) {
  const resultado = $("#resultado");
  mostrar(resultado, "Producto " + id + " PENDIENTE: procesando imagen...", "info");
  try {
    let r;
    if (foto) {
      const datos = new FormData();
      datos.append("archivo", foto);
      r = await api("/productos/" + id + "/imagen", { method: "POST", body: datos });
    } else {
      r = await api("/productos/" + id + "/reprocesar", { method: "POST" });
    }
    const d = await leerJson(r);
    if (!r.ok) {
      mostrar(resultado, textoError(d, r.status) + " | el producto " + id + " sigue PENDIENTE", "error");
      return;
    }
    localStorage.removeItem(CLAVE_PENDIENTE);
    mostrar(resultado, "Producto " + id + " " + d.estado + ". Ver detalle: #/producto/" + id, "ok");
    $("#formulario").reset();
    dibujarAtributos();
    mostrarPendiente();
  } catch (e) {
    mostrar(resultado, "Sin conexion con la API (" + e.message + "). Producto " + id + " sigue PENDIENTE.", "error");
  }
}

async function enviarFormulario(ev) {
  ev.preventDefault();
  const { cuerpo, foto } = leerFormulario();
  const errores = validar(cuerpo, foto);
  $("#errores").replaceChildren(...errores.map((t) => el("li", null, t)));
  if (errores.length) return;

  const boton = $("#enviar");
  const resultado = $("#resultado");
  boton.disabled = true;
  mostrar(resultado, "Registrando producto...", "info");
  try {
    const r = await api("/productos", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(cuerpo),
    });
    const d = await leerJson(r);
    if (!r.ok) {
      mostrar(resultado, textoError(d, r.status), "error");
      return;
    }
    localStorage.setItem(CLAVE_PENDIENTE, String(d.producto_id));
    mostrarPendiente();
    await subirImagen(d.producto_id, foto);
  } catch (e) {
    mostrar(resultado, "Sin conexion con la API: " + e.message, "error");
  } finally {
    boton.disabled = false;
  }
}

/* ---------- Rutas (la vista vive en la URL: sobrevive al refrescar) ---------- */
const VISTAS = { catalogo: cargarCatalogo, registrar: prepararRegistro, producto: cargarDetalle };

function enrutar() {
  const partes = location.hash.split("/");
  const vista = VISTAS[partes[1]] ? partes[1] : "catalogo";
  document.querySelectorAll("main > section").forEach((s) => { s.hidden = s.id !== "vista-" + vista; });
  document.querySelectorAll("nav a").forEach((a) => a.classList.toggle("activa", a.dataset.vista === vista));
  VISTAS[vista](partes[2]);
}

$("#categoria").addEventListener("change", dibujarAtributos);
$("#formulario").addEventListener("submit", enviarFormulario);
$("#reintentar").addEventListener("click", () => subirImagen(localStorage.getItem(CLAVE_PENDIENTE), $("#foto").files[0]));
window.addEventListener("hashchange", enrutar);
enrutar();
