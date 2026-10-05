// ================================================================
// catalogo.js — menú público de Taku Monky (Fase 4)
// Comparten este archivo: index.html, menu-platillos.html,
// menu-bebidas.html, menu-postres.html.
//
// Junta en UNO lo que en EJEMPLOS eran dos archivos separados
// (supabase-config.js + catalog-cache.js), más el render de tarjetas
// y estados — pedido explícito del dueño: "un solo .js compartido
// para lo del catálogo", para no repetir el HTML de la tarjeta en
// cuatro páginas.
// ================================================================

// ----------------------------------------------------------------
// Cliente de Supabase — mismo patrón que EJEMPLOS/supabase-config.js
//
// ¿Por qué persistSession/autoRefreshToken/detectSessionInUrl en false?
// En Anxie Store, el navegador bloqueaba localStorage (Tracking
// Prevention de Edge/Safari) y el SDK de Supabase reintentaba
// inicializar la sesión de auth en cada llamada — eso generó ~312
// consultas a pg_timezone_names, el 67% del tiempo de base de datos.
// Esta página nunca hace login (solo lee platillos con la anon key),
// así que ni falta hace que el SDK maneje sesión: con
// persistSession:false ese problema no puede repetirse aquí, sin
// importar cuántas veces se consulte el catálogo.
// ----------------------------------------------------------------
const SUPABASE_URL = "https://yiafxeibhqyghrkwvmju.supabase.co";
const SUPABASE_ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlpYWZ4ZWliaHF5Z2hya3d2bWp1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc2NTQwNzUsImV4cCI6MjEwMzIzMDA3NX0.9y0KMot1CllL5ix_PRv5ouaVXJ-engikGbUsbI4OKWg";
// Pública a propósito: por sí sola solo lee filas visible = true (lo
// aplica RLS del lado de Supabase, no esta llave). NUNCA poner aquí el
// SUPABASE_ACCESS_TOKEN, ni ningún token de Cloudflare que no sea una
// URL pública de imagen — esta página solo LEE, nunca sube ni borra
// nada en Supabase ni en R2.

const { createClient } = supabase;
const _supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
    detectSessionInUrl: false,
  },
});

// ----------------------------------------------------------------
// WhatsApp — número de PLACEHOLDER a propósito (ver CLAUDE.md/roadmap,
// Fase 4). Cuando tengas el número real del negocio, cámbialo AQUÍ —
// una sola vez: esta constante alimenta el botón del hero Y el del
// footer de las 4 páginas, no está escrita por separado en ningún
// otro archivo.
// ----------------------------------------------------------------
const NUMERO_WHATSAPP = "5215500000000"; // ← reemplazar aquí con el número real
const MENSAJE_WHATSAPP = "Hola, quiero hacer un pedido";
const URL_WHATSAPP = `https://wa.me/${NUMERO_WHATSAPP}?text=${encodeURIComponent(
  MENSAJE_WHATSAPP
)}`;

/** El mismo número, pero con el platillo ya escrito en el mensaje — lo
 * usa el botón "Pedir por WhatsApp" de cada tarjeta en las páginas de
 * categoría (ver menu.js). Vive AQUÍ y no en menu.js justamente para
 * que NUMERO_WHATSAPP siga teniendo un solo lugar de verdad: el día
 * que llegue el número real del negocio se cambia una vez, arriba, y
 * queda bien el hero, el footer y los botones de todas las tarjetas. */
function urlWhatsAppPlatillo(nombre) {
  const texto = nombre ? `Hola, quiero pedir: ${nombre}` : MENSAJE_WHATSAPP;
  return `https://wa.me/${NUMERO_WHATSAPP}?text=${encodeURIComponent(texto)}`;
}

// ----------------------------------------------------------------
// Caché — mismo mecanismo que EJEMPLOS/catalog-cache.js
// (sessionStorage), con dos diferencias a propósito, ver CLAUDE.md:
//   1. TTL bajado de 5 min a 30s.
//   2. iniciarAutoRefresco() más abajo refresca sola la página abierta,
//      no solo en la siguiente visita/navegación.
//
// El problema real de Anxie Store (312 queries, 67% del tiempo de DB)
// NO era la FRECUENCIA de consultas — era persistSession peleando con
// localStorage bloqueado (ver el bloque de arriba, ya resuelto). Con
// eso fuera de la ecuación, este TTL queda libre de bajarse sin miedo
// a repetir ese problema: con 7 filas en la tabla, una consulta cada
// 30s por visitante no le cuesta nada a Supabase.
//
// El panel de Flet NO invalida esta caché — es una app de escritorio,
// no tiene forma de tocar el sessionStorage del navegador de un
// cliente (ni siquiera en Anxie Store eso limpiaba el navegador de un
// cliente, solo el del dueño en su propia máquina). La frescura sale
// de este TTL corto + el refresco activo de abajo, no de una
// invalidación remota que no es técnicamente posible desde Python.
// ----------------------------------------------------------------
const CACHE_KEY = "taku_monky_catalogo_v1";
const CACHE_DURACION_MS = 30 * 1000;

// image_url_recortada (Fase 4.3) — la versión sin fondo de un platillo,
// generada en el panel (rembg) SOLO para categoría Platillos. La usa
// carta.js (la sección de celular del index); las demás páginas la reciben
// igual (una sola consulta para todas) pero simplemente no la pintan.
const _COLUMNAS = "id, nombre, descripcion, categoria, precio, image_url, image_url_recortada, orden";

async function obtenerCatalogo({ forzar = false } = {}) {
  // `forzar` lo manda SOLO iniciarAutoRefresco() (ver abajo) — nunca la
  // carga inicial de una página. Es a propósito: el intervalo del
  // refresco activo dispara cada CACHE_DURACION_MS, el mismo número que
  // el TTL de la caché — si aquí se respetara la caché también en esos
  // ticks, un tick que cae unos milisegundos después de que la caché se
  // acaba de refrescar (por el tick ANTERIOR) la vería "todavía fresca"
  // por ese margen y se saltaría el fetch, duplicando la espera real a
  // ~60s en vez de ~30s. Se comprobó en vivo (Fase 4): el caso "mostrar"
  // de la prueba de propagación tardó más de 40s en una pestaña abierta
  // hasta que se agregó este bypass. Con `forzar`, cada tick programado
  // SIEMPRE pega a la red, sin depender de ese margen de milisegundos.
  if (!forzar) {
    try {
      const guardado = sessionStorage.getItem(CACHE_KEY);
      if (guardado) {
        const cache = JSON.parse(guardado);
        if (Date.now() - cache.timestamp < CACHE_DURACION_MS) {
          return cache.datos;
        }
      }
    } catch (e) {
      // sessionStorage puede venir bloqueado (modo privado, etc.) — seguir sin caché.
    }
  }

  // SOLO las columnas que las tarjetas pintan — nunca select('*').
  // Mismo criterio que platillo_dao.py y EJEMPLOS/catalog-cache.js.
  // visible=true va explícito además de RLS, para que quede claro leyendo
  // este archivo (sin tener que saber de memoria las políticas de Supabase)
  // que esta página nunca puede traer un platillo oculto.
  const { data, error } = await _supabase
    .from("platillos")
    .select(_COLUMNAS)
    .eq("visible", true)
    .order("orden", { ascending: true })
    .order("id", { ascending: true });

  if (error) throw error;
  const datos = data || [];

  try {
    sessionStorage.setItem(CACHE_KEY, JSON.stringify({ datos, timestamp: Date.now() }));
  } catch (e) {
    // Cuota llena o bloqueado — no es fatal, solo no queda cacheado.
  }

  return datos;
}

/** Refresca sola la página mientras sigue abierta: cuando la pestaña
 * vuelve a estar visible (el cliente la dejó en la mesa y regresa a
 * verla), y cada CACHE_DURACION_MS mientras siga visible. Así el
 * cliente no se queda viendo un precio o una disponibilidad vieja solo
 * porque no le dio F5 — el contenido en pantalla se corrige solo. */
function iniciarAutoRefresco(callback) {
  // callback(true) — fuerza bypass de caché en cada disparo programado,
  // ver el comentario de `forzar` en obtenerCatalogo() arriba.
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") callback(true);
  });
  setInterval(() => {
    if (document.visibilityState === "visible") callback(true);
  }, CACHE_DURACION_MS);
}

// ----------------------------------------------------------------
// Navbar / sidebar móvil — mismo patrón que EJEMPLOS/style.css
// (barra fija tipo "sombra" arriba + un sidebar deslizante en móvil
// con overlay), solo que aquí los colores/tipografía son los de Taku
// Monky. El HTML del botón hamburguesa + sidebar es idéntico en las
// 4 páginas (mismos ids), solo cambian los enlaces adentro, así que
// basta con una sola función enganchando los botones por id.
// ----------------------------------------------------------------
function iniciarNavbar() {
  const boton = document.getElementById("tk-menu-boton");
  const sidebar = document.getElementById("tk-sidebar");
  const overlay = document.getElementById("tk-sidebar-overlay");
  const cerrar = document.getElementById("tk-sidebar-cerrar");
  if (!boton || !sidebar || !overlay) return;

  function abrir() {
    sidebar.classList.add("tk-activo");
    overlay.classList.add("tk-activo");
  }
  function ocultar() {
    sidebar.classList.remove("tk-activo");
    overlay.classList.remove("tk-activo");
  }

  boton.addEventListener("click", abrir);
  overlay.addEventListener("click", ocultar);
  if (cerrar) cerrar.addEventListener("click", ocultar);
  // Cerrar al navegar a un enlace del sidebar (ancla o página nueva).
  sidebar.querySelectorAll("a").forEach((enlace) => enlace.addEventListener("click", ocultar));
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") ocultar();
  });

  // Esconder/mostrar el header según la dirección del scroll — solo en
  // móvil (≤640px, mismo corte que el resto del nav móvil; en
  // escritorio/tablet el header se queda fijo como siempre). Bajando se
  // esconde, subiendo vuelve, y cerca del tope siempre se ve (para no
  // desaparecer justo al salir del hero/arrancar la página).
  //
  // Dos headers en el sitio, cada página trae solo uno de los dos:
  // .tk-navbar (index.html, fixed y transparente sobre el hero) y
  // .tk-cat-header (las 3 páginas de categoría, sticky y sólido —
  // pedido del dueño el 4 sep 2026, "igual que la navbar del index").
  // position:sticky con top:0 pinta igual que fixed una vez "pegado" —
  // el contenido de abajo ya scrollea por debajo de él, así que el
  // mismo transform:translateY(-100%) lo esconde sin dejar un hueco en
  // blanco; no hace falta un mecanismo distinto para el segundo.
  iniciarOcultarAlScroll(document.querySelector(".tk-navbar"), "tk-navbar--oculta");
  iniciarOcultarAlScroll(document.querySelector(".tk-cat-header"), "tk-cat-header--oculta");
}

function iniciarOcultarAlScroll(elemento, claseOculta) {
  if (!elemento) return;
  const esMovil = () => window.matchMedia("(max-width: 640px)").matches;
  let ultimoScrollY = window.scrollY;
  let ticking = false;
  window.addEventListener("scroll", () => {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(() => {
      const actual = window.scrollY;
      if (!esMovil() || actual <= 80 || actual < ultimoScrollY) {
        elemento.classList.remove(claseOculta);
      } else {
        elemento.classList.add(claseOculta);
      }
      ultimoScrollY = actual;
      ticking = false;
    });
  }, { passive: true });
}

// ----------------------------------------------------------------
// Categorías fijas — mismas 3 del CHECK de la tabla (ver CLAUDE.md):
// Platillos, Bebidas, Postres, en ese orden.
// ----------------------------------------------------------------
const CATEGORIAS = ["Platillos", "Bebidas", "Postres"];
const _SINGULAR = { Platillos: "platillo", Bebidas: "bebida", Postres: "postre" };

function agruparPorCategoria(lista) {
  // La consulta ya viene ordenada por orden/id — agrupar aquí conserva
  // ese orden dentro de cada categoría (partición estable), no hace
  // falta volver a ordenar.
  const grupos = { Platillos: [], Bebidas: [], Postres: [] };
  for (const p of lista) {
    if (grupos[p.categoria]) grupos[p.categoria].push(p);
  }
  return grupos;
}

function textoContador(categoria, cantidad) {
  const singular = _SINGULAR[categoria] || categoria.toLowerCase();
  const plural = categoria.toLowerCase();
  if (cantidad === 1) return `1 ${singular} disponible`;
  return `${cantidad} ${plural} disponibles`;
}

function escapeHtml(texto) {
  const div = document.createElement("div");
  div.textContent = texto == null ? "" : String(texto);
  return div.innerHTML;
}

function formatearPrecio(valor) {
  // Mismo criterio que _formatear_precio() en menu_view.py: sin
  // decimales cuando el valor es entero.
  const numero = Number(valor);
  if (Number.isNaN(numero)) return "$0";
  if (Number.isInteger(numero)) return `$${numero.toLocaleString("es-MX")}`;
  return `$${numero.toLocaleString("es-MX", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`;
}

// ----------------------------------------------------------------
// LA tarjeta de platillo — única definición en todo el sitio. La usan
// el preview del index Y las 3 páginas de categoría completa. Si un
// día cambia el diseño de la tarjeta, se toca aquí y ya — no hay una
// segunda copia en ningún archivo .html.
// ----------------------------------------------------------------
function tarjetaPlatilloHTML(platillo) {
  const nombre = escapeHtml(platillo.nombre || "");
  const descripcion = escapeHtml(platillo.descripcion || "");
  const categoria = escapeHtml(platillo.categoria || "");
  const precio = formatearPrecio(platillo.precio);
  // Igual que platillo.get("image_url") or "assets/sin-foto.png" en
  // menu_view.py: sin foto todavía (el caso normal hoy) cae al mismo
  // placeholder que ya usa el panel, no a un ícono roto.
  const imagen = escapeHtml(platillo.image_url || "assets/sin-foto.png");

  return `
    <article class="tk-tarjeta">
      <div class="tk-tarjeta-foto">
        <img src="${imagen}" alt="${nombre}" loading="lazy"
             onerror="this.onerror=null; this.src='assets/sin-foto.png';">
      </div>
      <div class="tk-tarjeta-cuerpo">
        <div class="tk-tarjeta-encabezado">
          <span class="tk-tarjeta-nombre">${nombre}</span>
          <span class="tk-tarjeta-precio">${precio}</span>
        </div>
        ${descripcion ? `<p class="tk-tarjeta-descripcion">${descripcion}</p>` : ""}
        <span class="tk-tarjeta-chip">${categoria}</span>
      </div>
    </article>
  `;
}

// ----------------------------------------------------------------
// Estados compartidos — mismo lenguaje visual que el panel (ver
// menu_view.py: _estado_cargando() / _estado_vacio() / _estado_error()).
// ----------------------------------------------------------------
const _ICONO_ERROR =
  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9.25"/><line x1="12" y1="7.5" x2="12" y2="12.5"/><circle cx="12" cy="16.3" r="1" fill="currentColor" stroke="none"/></svg>';
const _ICONO_VACIO =
  '<svg class="tk-icono-vacio" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="8.5"/><path d="M8.3 7.2v9.6M6.8 7.2v4a1.5 1.5 0 0 0 3 0v-4M15.6 7.2c-1.05 0-1.9 1.3-1.9 2.9 0 1.3.55 2.35 1.3 2.75v4.3"/></svg>';

function htmlEstadoCargando(mensaje) {
  return `<div class="tk-estado"><div class="tk-spinner"></div><p>${escapeHtml(
    mensaje || "Cargando el menú..."
  )}</p></div>`;
}
function htmlEstadoError() {
  return `<div class="tk-estado tk-estado--error">${_ICONO_ERROR}<p>No hay conexión con el servidor. Revisa tu internet.</p></div>`;
}
function htmlEstadoVacio(categoria) {
  const nombre = categoria ? categoria.toLowerCase() : "platillos";
  return `<div class="tk-estado">${_ICONO_VACIO}<p class="tk-estado-titulo">Todavía no hay ${escapeHtml(
    nombre
  )} en el menú.</p><p>Vuelve pronto, estamos preparando algo nuevo.</p></div>`;
}

// ----------------------------------------------------------------
// index.html — un preview (máx. 3) por categoría, UNA sola consulta
// para las tres secciones (obtenerCatalogo() ya trae todo el catálogo
// visible; aquí solo se reparte por categoría). Si una categoría no
// tiene ningún platillo visible, su sección se ESCONDE por completo
// — no se queda un hueco a medias.
// ----------------------------------------------------------------
async function iniciarIndex() {
  const secciones = {
    Platillos: document.getElementById("platillos"),
    Bebidas: document.getElementById("bebidas"),
    Postres: document.getElementById("postres"),
  };
  const contenedores = {
    Platillos: document.getElementById("contenedor-platillos"),
    Bebidas: document.getElementById("contenedor-bebidas"),
    Postres: document.getElementById("contenedor-postres"),
  };

  async function cargar(forzar = false) {
    try {
      const lista = await obtenerCatalogo({ forzar });
      const grupos = agruparPorCategoria(lista);
      for (const categoria of CATEGORIAS) {
        const items = grupos[categoria].slice(0, 3);
        const seccion = secciones[categoria];
        const contenedor = contenedores[categoria];
        if (!seccion || !contenedor) continue;
        if (items.length === 0) {
          seccion.style.display = "none";
          continue;
        }
        seccion.style.display = "";
        contenedor.innerHTML = items.map(tarjetaPlatilloHTML).join("");
      }
    } catch (e) {
      console.error("[catalogo] error cargando el índice:", e);
      for (const categoria of CATEGORIAS) {
        const seccion = secciones[categoria];
        const contenedor = contenedores[categoria];
        if (!seccion || !contenedor) continue;
        seccion.style.display = "";
        contenedor.innerHTML = htmlEstadoError();
      }
    }
  }

  await cargar();
  iniciarAutoRefresco(cargar);
}

// ----------------------------------------------------------------
// Páginas de categoría completa (menu-platillos/bebidas/postres.html)
//
// Ya NO viven aquí: desde el rediseño del 28 ago 2026 esas 3 páginas
// las arma iniciarCatalogo(categoria) en menu.js, que además del
// listado trae el orden/filtro, la búsqueda y el visor de foto grande.
// La función iniciarCategoria() que estaba en este lugar se eliminó al
// quedarse sin quien la llamara — no se dejó "por si acaso" para no
// terminar con dos caminos distintos pintando lo mismo.
//
// Lo que este archivo SÍ le sigue prestando a esas páginas (y por eso
// catalogo.js se carga antes que menu.js): el cliente de Supabase, la
// caché + auto-refresco, iniciarNavbar(), agruparPorCategoria(),
// textoContador(), escapeHtml(), formatearPrecio(), los estados
// htmlEstadoError()/htmlEstadoVacio() y urlWhatsAppPlatillo().
// ----------------------------------------------------------------
