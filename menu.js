// ================================================================
// menu.js — el menú completo de menu.html
// Pinta las 3 secciones de la página (Platillos, Bebidas, Postres) con
// sus tarjetas, el orden ("Ordenar por"), la búsqueda y el visor de
// foto grande.
//
// DEPENDE de globals de catalogo.js, así que en el HTML
// <script src="catalogo.js"> va SIEMPRE antes que este archivo:
//   obtenerCatalogo, agruparPorCategoria, iniciarAutoRefresco,
//   escapeHtml, formatearPrecio, textoContador, htmlEstadoError,
//   htmlEstadoVacio, urlWhatsAppPlatillo.
// ================================================================

// Criterios del dropdown "Ordenar por". `null` = dejar la lista tal
// como viene de la consulta, que ya está ordenada por `orden` y luego
// `id` (o sea: el orden que el dueño acomodó en el panel). Por eso el
// valor por defecto se llama "Recomendado" y no "Predeterminado".
const _CAT_ORDENES = {
  recomendado: null,
  "precio-asc": (a, b) => Number(a.precio) - Number(b.precio),
  "precio-desc": (a, b) => Number(b.precio) - Number(a.precio),
  nombre: (a, b) =>
    String(a.nombre || "").localeCompare(String(b.nombre || ""), "es", {
      sensitivity: "base",
    }),
};
const _CAT_ORDEN_DEFECTO = "recomendado";

const _CAT_ICONO_WA =
  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M20.5 11.5a8.5 8.5 0 0 1-12.3 7.6L4 20l1-4a8.5 8.5 0 1 1 15.5-4.5Z"/><path d="M8.7 9.8c.25-.6.5-.6.75-.6h.4c.15 0 .35 0 .5.35l.6 1.35c.1.2 0 .45-.1.55l-.4.5c-.1.15-.1.35 0 .5.25.5 1.25 1.6 2.2 1.95.2.1.35 0 .45-.1l.5-.5c.15-.2.35-.2.5-.1l1.3.65c.15.1.25.25.25.45 0 .65-.75 1.3-1.4 1.3-1.45 0-4.15-1.25-5.25-3.7-.4-.9-.4-1.85 0-2.5Z" fill="currentColor" stroke="none"/></svg>';
const _CAT_ICONO_LUPA =
  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="7.5"/><line x1="20.5" y1="20.5" x2="16.5" y2="16.5"/></svg>';

/** Minúsculas y sin acentos, para que "cafe" encuentre "Café" y
 * "jamaica" encuentre "Agua de Jamaica" sin escribir el acento. */
function _catNormalizar(texto) {
  return String(texto == null ? "" : texto)
    .toLowerCase()
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "");
}

function _catImagen(platillo) {
  // Mismo fallback que menu_view.py: sin foto se ve el placeholder del
  // proyecto, no un ícono roto.
  return escapeHtml(platillo.image_url || "assets/sin-foto.png");
}

// ----------------------------------------------------------------
// La tarjeta del menú — versión "abierta" (sin caja): etiqueta arriba,
// foto, texto y botón de ancho completo al pie.
// ----------------------------------------------------------------
function tarjetaCatalogoHTML(platillo) {
  const nombre = escapeHtml(platillo.nombre || "");
  const descripcion = escapeHtml(platillo.descripcion || "");
  const categoria = escapeHtml(platillo.categoria || "");
  const precio = formatearPrecio(platillo.precio);

  return `
    <article class="tk-cat-tarjeta" id="platillo-${platillo.id}">
      <span class="tk-cat-etiqueta">${categoria}</span>
      <div class="tk-cat-foto">
        <img src="${_catImagen(platillo)}" alt="${nombre}" loading="lazy"
             onerror="this.onerror=null; this.src='assets/sin-foto.png';">
      </div>
      <div class="tk-cat-info">
        <h3 class="tk-cat-nombre">${nombre}</h3>
        ${descripcion ? `<p class="tk-cat-desc">${descripcion}</p>` : ""}
        <p class="tk-cat-precio">${precio}</p>
        <div class="tk-cat-btn">
          <a href="${escapeHtml(urlWhatsAppPlatillo(platillo.nombre))}"
             target="_blank" rel="noopener">${_CAT_ICONO_WA} Pedir por WhatsApp</a>
        </div>
      </div>
    </article>
  `;
}

/** Resultado compacto del modal de búsqueda. Lleva el chip de
 * categoría porque la búsqueda mezcla las 3. */
function _catResultadoHTML(platillo) {
  const nombre = escapeHtml(platillo.nombre || "");
  const categoria = escapeHtml(platillo.categoria || "");
  return `
    <a class="tk-cat-resultado" href="#platillo-${platillo.id}" data-id="${platillo.id}">
      <img class="tk-cat-resultado-foto" src="${_catImagen(platillo)}" alt="${nombre}"
           loading="lazy" onerror="this.onerror=null; this.src='assets/sin-foto.png';">
      <span class="tk-cat-resultado-nombre">${nombre}</span>
      <span class="tk-cat-resultado-pie">
        <span class="tk-cat-resultado-precio">${formatearPrecio(platillo.precio)}</span>
        <span class="tk-cat-resultado-chip">${categoria}</span>
      </span>
    </a>
  `;
}

// ----------------------------------------------------------------
// Marcado de los dos modales (búsqueda y foto grande). Se inyecta
// desde aquí para que menu.html se quede con lo que tiene que verse
// sin JS: header, secciones, sidebar y footer.
// ----------------------------------------------------------------
function _catMontarModales() {
  const html = `
    <div class="tk-cat-busqueda" id="tk-cat-busqueda">
      <div class="tk-cat-busqueda-caja" role="dialog" aria-modal="true" aria-label="Buscar en el menú">
        <div class="tk-cat-busqueda-barra">
          ${_CAT_ICONO_LUPA}
          <input type="text" id="tk-cat-busqueda-input" class="tk-cat-busqueda-input"
                 placeholder="Busca un platillo, bebida o postre..." autocomplete="off">
          <button class="tk-cat-busqueda-cerrar" id="tk-cat-busqueda-cerrar" aria-label="Cerrar búsqueda">&times;</button>
        </div>
        <div class="tk-cat-busqueda-cuerpo">
          <p class="tk-cat-busqueda-rotulo">Todo el menú</p>
          <div class="tk-cat-busqueda-grid" id="tk-cat-busqueda-grid"></div>
        </div>
      </div>
    </div>

    <div class="tk-cat-zoom" id="tk-cat-zoom">
      <div class="tk-cat-zoom-caja">
        <button class="tk-cat-zoom-cerrar" id="tk-cat-zoom-cerrar" aria-label="Cerrar foto">&times;</button>
        <img class="tk-cat-zoom-img" id="tk-cat-zoom-img" src="" alt="">
        <p class="tk-cat-zoom-pie" id="tk-cat-zoom-pie"></p>
      </div>
    </div>
  `;
  const caja = document.createElement("div");
  caja.innerHTML = html;
  while (caja.firstElementChild) document.body.appendChild(caja.firstElementChild);
}

// ----------------------------------------------------------------
// Punto de entrada — menu.html llama a iniciarMenu().
// ----------------------------------------------------------------
async function iniciarMenu() {
  const main = document.querySelector(".tk-cat-main");
  const estado = document.getElementById("estado-menu");
  const secciones = [...document.querySelectorAll(".tk-cat-seccion[data-categoria]")];
  if (!main || !estado || !secciones.length) return;

  _catMontarModales();

  // Lista COMPLETA del catálogo (la usa la búsqueda) y la misma lista
  // repartida por categoría, en el orden que trae la consulta. El
  // criterio de orden se aplica siempre sobre una copia, así
  // "Recomendado" puede volver sin reconsultar.
  let _catalogo = [];
  let _grupos = {};
  let _orden = _CAT_ORDEN_DEFECTO;
  let _cargado = false;

  // ---------------- Secciones ----------------
  function pintarSecciones() {
    const comparador = _CAT_ORDENES[_orden];
    for (const seccion of secciones) {
      const categoria = seccion.dataset.categoria;
      const items = _grupos[categoria] || [];
      const contenido = seccion.querySelector(".tk-cat-contenido");
      const conteo = seccion.querySelector(".tk-cat-conteo");
      if (conteo) conteo.textContent = textoContador(categoria, items.length);
      if (!items.length) {
        contenido.className = "tk-cat-contenido";
        contenido.innerHTML = htmlEstadoVacio(categoria);
        continue;
      }
      const lista = comparador ? [...items].sort(comparador) : items;
      contenido.className = "tk-cat-contenido tk-cat-grid";
      contenido.innerHTML = lista.map(tarjetaCatalogoHTML).join("");
    }
  }

  async function cargar(forzar = false) {
    try {
      _catalogo = await obtenerCatalogo({ forzar });
      _grupos = agruparPorCategoria(_catalogo);
      pintarSecciones();
      estado.hidden = true;
      secciones.forEach((s) => (s.hidden = false));
      _cargado = true;
      // Si el modal está abierto durante un refresco automático, sus
      // resultados también se actualizan — si no, se quedaría mostrando
      // un platillo que el dueño acaba de ocultar desde el panel.
      if (modalBusqueda.classList.contains("tk-activo")) buscar(input.value);
    } catch (e) {
      console.error("[menu] error cargando el menú", e);
      // Si el menú ya se ve, un refresco fallido no lo borra: se queda
      // lo último que se leyó y el siguiente refresco lo corrige.
      if (_cargado) return;
      estado.innerHTML = htmlEstadoError();
      estado.hidden = false;
    }
  }

  // ---------------- Filtro / orden ----------------
  const cajaFiltro = document.getElementById("tk-cat-filtro-caja");
  const botonFiltro = document.getElementById("tk-cat-filtro-boton");
  const menuFiltro = document.getElementById("tk-cat-filtro-menu");

  if (botonFiltro && menuFiltro) {
    const opciones = menuFiltro.querySelectorAll(".tk-cat-filtro-opt");

    botonFiltro.addEventListener("click", (e) => {
      e.stopPropagation();
      menuFiltro.classList.toggle("tk-activo");
    });
    document.addEventListener("click", (e) => {
      if (!menuFiltro.contains(e.target) && !botonFiltro.contains(e.target)) {
        menuFiltro.classList.remove("tk-activo");
      }
    });

    opciones.forEach((opcion) => {
      opcion.addEventListener("click", () => {
        _orden = opcion.dataset.orden || _CAT_ORDEN_DEFECTO;
        opciones.forEach((o) => o.classList.toggle("tk-activo", o === opcion));
        if (cajaFiltro) {
          cajaFiltro.classList.toggle("tk-cat-filtrado", _orden !== _CAT_ORDEN_DEFECTO);
        }
        menuFiltro.classList.remove("tk-activo");
        if (_cargado) pintarSecciones();
      });
    });
  }

  // ---------------- Búsqueda ----------------
  const modalBusqueda = document.getElementById("tk-cat-busqueda");
  const input = document.getElementById("tk-cat-busqueda-input");
  const gridBusqueda = document.getElementById("tk-cat-busqueda-grid");
  const abrirBusquedaBtn = document.getElementById("tk-cat-abrir-busqueda");
  const cerrarBusquedaBtn = document.getElementById("tk-cat-busqueda-cerrar");

  function buscar(consulta) {
    const termino = _catNormalizar(consulta).trim();
    const lista = !termino
      ? _catalogo
      : _catalogo.filter((p) => {
          const enNombre = _catNormalizar(p.nombre).includes(termino);
          const enDesc = _catNormalizar(p.descripcion).includes(termino);
          const enCategoria = _catNormalizar(p.categoria).includes(termino);
          return enNombre || enDesc || enCategoria;
        });

    gridBusqueda.innerHTML = lista.length
      ? lista.map(_catResultadoHTML).join("")
      : '<p class="tk-cat-busqueda-vacio">No encontramos nada con ese nombre. Prueba con otra palabra.</p>';
  }

  function abrirBusqueda() {
    modalBusqueda.classList.add("tk-activo");
    _catBloquearScroll();
    input.value = "";
    buscar("");
    setTimeout(() => input.focus(), 120);
  }
  function cerrarBusqueda() {
    modalBusqueda.classList.remove("tk-activo");
    _catBloquearScroll();
  }

  if (abrirBusquedaBtn) abrirBusquedaBtn.addEventListener("click", abrirBusqueda);
  if (cerrarBusquedaBtn) cerrarBusquedaBtn.addEventListener("click", cerrarBusqueda);
  modalBusqueda.addEventListener("click", (e) => {
    if (e.target === modalBusqueda) cerrarBusqueda();
  });
  input.addEventListener("input", (e) => buscar(e.target.value));

  // Todo el menú vive en esta página: un resultado cierra el modal y
  // baja a su tarjeta.
  gridBusqueda.addEventListener("click", (e) => {
    const item = e.target.closest(".tk-cat-resultado");
    if (!item) return;
    e.preventDefault();
    const id = item.dataset.id;
    cerrarBusqueda();
    setTimeout(() => saltarAlPlatillo(id), 160);
  });

  function saltarAlPlatillo(id) {
    const tarjeta = document.getElementById(`platillo-${id}`);
    if (!tarjeta) return;
    tarjeta.scrollIntoView({ behavior: "smooth", block: "center" });
    tarjeta.classList.remove("tk-cat-resaltada");
    // Reinicia la animación aunque se salte dos veces seguidas a la
    // misma tarjeta (sin este "reflow" el navegador reusa la animación
    // ya terminada y no se ve nada la segunda vez).
    void tarjeta.offsetWidth;
    tarjeta.classList.add("tk-cat-resaltada");
  }

  // ---------------- Visor de foto grande ----------------
  const modalZoom = document.getElementById("tk-cat-zoom");
  const zoomImg = document.getElementById("tk-cat-zoom-img");
  const zoomPie = document.getElementById("tk-cat-zoom-pie");
  const zoomCerrar = document.getElementById("tk-cat-zoom-cerrar");
  let acercada = false;

  function cerrarZoom() {
    modalZoom.classList.remove("tk-activo");
    _catBloquearScroll();
    acercada = false;
    zoomImg.classList.remove("tk-acercada");
    zoomImg.style.transform = "scale(1)";
    zoomImg.style.transformOrigin = "center center";
  }

  main.addEventListener("click", (e) => {
    const foto = e.target.closest(".tk-cat-foto");
    if (!foto) return;
    const img = foto.querySelector("img");
    const tarjeta = foto.closest(".tk-cat-tarjeta");
    if (!img) return;
    zoomImg.src = img.src;
    zoomImg.alt = img.alt || "";
    zoomPie.textContent = tarjeta ? tarjeta.querySelector(".tk-cat-nombre").textContent : "";
    modalZoom.classList.add("tk-activo");
    _catBloquearScroll();
    acercada = false;
    zoomImg.classList.remove("tk-acercada");
    zoomImg.style.transform = "scale(1)";
  });

  zoomCerrar.addEventListener("click", cerrarZoom);
  modalZoom.addEventListener("click", (e) => {
    if (e.target === modalZoom || e.target.classList.contains("tk-cat-zoom-caja")) cerrarZoom();
  });

  // Acercar/alejar solo en escritorio: en táctil el navegador ya hace
  // pinch-zoom y un toque que dispara scale(2) estorba más que ayuda.
  zoomImg.addEventListener("click", (e) => {
    if (window.innerWidth <= 860) return;
    acercada = !acercada;
    zoomImg.classList.toggle("tk-acercada", acercada);
    if (!acercada) {
      zoomImg.style.transform = "scale(1)";
      zoomImg.style.transformOrigin = "center center";
      return;
    }
    zoomImg.style.transform = "scale(2)";
    _catOrigenDesdeCursor(zoomImg, e);
  });
  zoomImg.addEventListener("mousemove", (e) => {
    if (acercada && window.innerWidth > 860) _catOrigenDesdeCursor(zoomImg, e);
  });

  // ---------------- Escape ----------------
  // Cierra primero lo que esté más "arriba": si están la foto grande y
  // la búsqueda abiertas a la vez, un Escape no debería tumbar las dos.
  document.addEventListener("keydown", (e) => {
    if (e.key !== "Escape") return;
    if (modalZoom.classList.contains("tk-activo")) cerrarZoom();
    else if (modalBusqueda.classList.contains("tk-activo")) cerrarBusqueda();
  });

  // ---------------- Arranque ----------------
  await cargar();

  // Enlace directo a un platillo (menu.html#platillo-2) o a una
  // sección (#bebidas): las secciones estaban ocultas hasta ahora, así
  // que el navegador no pudo saltar solo al abrir la página.
  const anclaId = (location.hash.match(/^#platillo-(\d+)$/) || [])[1];
  if (anclaId) setTimeout(() => saltarAlPlatillo(anclaId), 220);
  else if (location.hash.length > 1) {
    const destino = document.getElementById(location.hash.slice(1));
    if (destino) destino.scrollIntoView();
  }

  iniciarAutoRefresco(cargar);
}

/** El <body> se bloquea si CUALQUIERA de los dos modales está abierto —
 * con un flag por modal se desbloquearía de más al cerrar uno mientras
 * el otro sigue arriba. */
function _catBloquearScroll() {
  const hayModal = !!document.querySelector(
    ".tk-cat-busqueda.tk-activo, .tk-cat-zoom.tk-activo"
  );
  document.body.classList.toggle("tk-sin-scroll", hayModal);
}

/** Deja el punto que está bajo el cursor como centro del acercamiento,
 * para poder "recorrer" la foto moviendo el mouse. */
function _catOrigenDesdeCursor(img, evento) {
  const caja = img.getBoundingClientRect();
  const x = ((evento.clientX - caja.left) / caja.width) * 100;
  const y = ((evento.clientY - caja.top) / caja.height) * 100;
  img.style.transformOrigin = `${x}% ${y}%`;
}
