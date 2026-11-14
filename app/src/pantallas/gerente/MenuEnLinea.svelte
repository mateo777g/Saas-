<!--
  «Tu menú en línea» (rediseño del 10 al 12 nov 2026; maqueta UDArhiEZceT7rmSKxqRA5r v59, notas en
  planes/trabajo/rediseno/tu-menu-en-linea.md; código, parte D, 13 nov 2026). La vista solo es el diseño de su menú, en
  filas: a la izquierda, Tu link y tu QR · Tema y colores · Barra de arriba · Carteles · Búsqueda · Categorías · Títulos
  de categoría · Productos · Abajo, cada una con sus formas; a la derecha, un solo teléfono (el iPhone 16 Pro) con su
  menú entero y lo que todavía no guarda, fijo mientras baja. Al elegir una forma, el teléfono va a esa pieza. Carteles,
  Búsqueda y Categorías se acomodan con ↑ ↓, y su fila cambia de lugar con el resorte de las ventanas.

  Dos modos con el dock de Mi menú en la barra de arriba: «Tu menú» (las filas de arriba) y «Producto» (Ventana, Título
  y Opciones: lo que se abre al tocar un producto; el teléfono lo tiene abierto). Una sola barra de guardar para los dos
  (diseno/BarraGuardar.svelte): «Descartar» en rojo y «Guardar» en verde; si sale con cambios, «Tienes cambios sin
  guardar» (lib/salida.ts). El botón negro «Carteles» abre «Tus carteles», que se guardan al momento. Los productos salen
  de Mi menú, y el logo y el horario de Tu restaurante. «Hago envíos» se fue a Tu restaurante. El chip de arriba dice si
  está abierto y cuántos productos están a la vista, contados por Postgres igual que el menú; si el asistente no
  contesta, un aviso abajo de la descripción dice por qué y a quién pedírselo.
-->
<script lang="ts">
  import { onMount, tick } from 'svelte';
  import { flip } from 'svelte/animate';
  import BarraArriba from '../../diseno/BarraArriba.svelte';
  import BarraGuardar from '../../diseno/BarraGuardar.svelte';
  import Boton from '../../diseno/Boton.svelte';
  import CajaError from '../../diseno/CajaError.svelte';
  import { cascada } from '../../diseno/cascada';
  import Dock from '../../diseno/Dock.svelte';
  import Esqueleto from '../../diseno/Esqueleto.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import { trazosCategoria } from '../../diseno/iconosCategorias';
  import { quieto, RESORTE } from '../../diseno/ventanaSeMueve';
  import { ALGO_SALIO_PANEL, esDeRed, Fallo, SIN_CONEXION } from '../../lib/errores';
  import { FORMAS_DE_SIEMPRE, type Formas, type Pieza } from '../../lib/formasMenu';
  import { diaYMes } from '../../lib/formato';
  import type { Sucursal } from '../../lib/gerente';
  import { leerMenu, type Menu } from '../../lib/menu';
  import {
    guardarDisenoMenu,
    leerCarteles,
    leerDisenoMenu,
    leerEstadoMenu,
    type Cartel,
    type DisenoMenu,
    type EstadoMenu,
  } from '../../lib/restaurante';
  import { ponerGuardia } from '../../lib/salida';
  import { linkDelMenu } from '../../lib/vistaMenu';
  import CajaSucursales from './CajaSucursales.svelte';
  import type { ClaveColor } from './menuEnLinea/colores';
  import Fila from './menuEnLinea/Fila.svelte';
  import FilaColores from './menuEnLinea/FilaColores.svelte';
  import FilaLink from './menuEnLinea/FilaLink.svelte';
  import Formas_ from './menuEnLinea/Formas.svelte';
  import { descargarQr } from './menuEnLinea/QrMenu.svelte';
  import Telefono from './menuEnLinea/Telefono.svelte';
  import TusCarteles from './menuEnLinea/TusCarteles.svelte';
  import VentanaColor from './menuEnLinea/VentanaColor.svelte';
  import VentanaSalir from './menuEnLinea/VentanaSalir.svelte';

  let {
    sucursal,
    sucursales,
    alElegir,
  }: { sucursal: Sucursal; sucursales: Sucursal[]; alElegir: (s: Sucursal) => void } = $props();

  // ─── Los íconos que no están en diseno/iconos.ts (los de la maqueta) ───
  const TRAZOS = {
    titulo: '<path d="M6 12h12"></path><path d="M6 20V4"></path><path d="M18 20V4"></path>',
    lista:
      '<path d="M8 6h12"></path><path d="M8 12h12"></path><path d="M8 18h12"></path><path d="M4 6h.01"></path><path d="M4 12h.01"></path><path d="M4 18h.01"></path>',
    mundo:
      '<circle cx="12" cy="12" r="9.2"></circle><path d="M12 2.8a13.5 13.5 0 0 0 0 18.4 13.5 13.5 0 0 0 0-18.4"></path><path d="M2.8 12h18.4"></path>',
    monedas:
      '<circle cx="6.6" cy="6.6" r="4.7"></circle><circle cx="17.4" cy="6.6" r="4.7"></circle><circle cx="6.6" cy="17.4" r="4.7"></circle><circle cx="17.4" cy="17.4" r="4.7"></circle>' +
      '<g fill="currentColor" stroke="none" font-family="Plus Jakarta Sans, sans-serif" font-weight="800" font-size="6.4" text-anchor="middle"><text x="6.6" y="8.9">€</text><text x="17.4" y="8.9">$</text><text x="6.6" y="19.7">£</text><text x="17.4" y="19.7">¥</text></g>',
  };

  // ─── Lo que se lee y lo que se elige ───
  let guardado = $state<DisenoMenu | null>(null);
  let s = $state<DisenoMenu>({ tema: 'claro', color: null, colorBarra: null, fondo: null, formas: { ...FORMAS_DE_SIEMPRE } });
  let carteles = $state<Cartel[]>([]);
  let estado = $state<EstadoMenu | null>(null);
  let menu = $state<Menu | null>(null);
  let errorLectura = $state<string | null>(null);

  let modo = $state<'menu' | 'producto'>('menu');
  let paso = $state<null | 'guardando' | 'listo'>(null);
  let errorGuardar = $state<string | null>(null);
  // Las ventanas, cada una en su estado: un {@const} que lee de una ventana que ya se cerró truena (Svelte 5).
  let colorAbierto = $state<ClaveColor | null>(null);
  let cartelesAbierto = $state(false);
  let salida = $state<(() => void) | null>(null);
  let telefono = $state<ReturnType<typeof Telefono>>();
  let columna = $state<HTMLDivElement>();
  let error = $state<string | null>(null);

  // svelte-ignore state_referenced_locally
  const link = linkDelMenu(sucursal.slug);
  // Sin datos todavía (la primera lectura): esqueletos en lo que viene de la base (regla «Los esqueletos»).
  const cargando = $derived(!guardado && !errorLectura);

  const copia = (d: DisenoMenu): DisenoMenu => ({ ...d, formas: { ...d.formas, orden: [...d.formas.orden] } });

  // Cuántas cosas cambió: el tema, cada color y cada forma (el orden cuenta como una).
  const cambios = $derived.by(() => {
    if (!guardado) return 0;
    const g = guardado;
    let n = (['tema', 'color', 'colorBarra', 'fondo'] as const).filter((k) => s[k] !== g[k]).length;
    for (const k of Object.keys(FORMAS_DE_SIEMPRE) as (keyof Formas)[]) {
      if (k === 'orden' ? s.formas.orden.join() !== g.formas.orden.join() : s.formas[k] !== g.formas[k]) n++;
    }
    return n;
  });

  async function leer() {
    try {
      const [d, c, e, m] = await Promise.all([
        leerDisenoMenu(sucursal.id),
        leerCarteles(sucursal.id),
        leerEstadoMenu(sucursal.id),
        leerMenu(sucursal.id),
      ]);
      carteles = c;
      estado = e;
      menu = m;
      s = copia(d);
      guardado = d;
      errorLectura = null;
    } catch (falla) {
      console.error('[menu en linea] no se pudo leer:', falla);
      errorLectura = esDeRed(falla) ? SIN_CONEXION : 'No se pudo leer tu menú en línea. Intenta de nuevo en un momento.';
    }
  }

  onMount(() => {
    leer();
    // Si se va con cambios (la barra lateral, la búsqueda, otra sucursal, cerrar sesión), primero lo pregunta.
    const quitarGuardia = ponerGuardia((seguir) => {
      if (!cambios || paso) return false;
      salida = seguir;
      return true;
    });
    // Y si cierra o recarga la pestaña, el navegador también pregunta.
    const alIrse = (e: BeforeUnloadEvent) => {
      if (cambios) e.preventDefault();
    };
    window.addEventListener('beforeunload', alIrse);
    return () => {
      quitarGuardia();
      window.removeEventListener('beforeunload', alIrse);
    };
  });

  // ─── Lo que se cambia: cada cambio se pinta en el teléfono ───
  function elegir<K extends keyof Formas>(k: K, v: Formas[K]) {
    s.formas[k] = v;
    errorGuardar = null;
    telefono?.pintar(k);
  }

  function cambiarTema() {
    s.tema = s.tema === 'claro' ? 'oscuro' : 'claro';
    errorGuardar = null;
    telefono?.pintar();
  }

  function ponerColor(clave: ClaveColor, valor: string | null) {
    s[clave] = valor;
    errorGuardar = null;
    telefono?.pintar();
  }

  // Carteles, Búsqueda y Categorías: la primera no sube y la última no baja (nunca pasan arriba de la barra ni abajo de
  // los títulos y los productos). El título del producto: ↑ lo sube arriba de la foto, ↓ lo baja debajo.
  function mover(pieza: Pieza, hacia: -1 | 1) {
    const o = [...s.formas.orden];
    const i = o.indexOf(pieza);
    const j = i + hacia;
    if (i < 0 || j < 0 || j >= o.length) return;
    [o[i], o[j]] = [o[j], o[i]];
    elegir('orden', o);
  }

  async function guardar(): Promise<string | null> {
    if (!guardado || paso) return null;
    errorGuardar = null;
    paso = 'guardando';
    const lo = copia(s);
    try {
      await guardarDisenoMenu(sucursal.id, lo);
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[menu en linea] no se pudo guardar:', falla);
      errorGuardar = falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL;
      paso = null;
      return errorGuardar;
    }
    guardado = lo;
    paso = 'listo';
    setTimeout(() => (paso = null), 1600);
    return null;
  }

  function descartar() {
    if (!guardado || paso) return;
    s = copia(guardado);
    errorGuardar = null;
    telefono?.pintar();
  }

  // ─── El dock: las filas del otro modo entran en cascada, como al cambiar de sección en Mi menú ───
  async function cambiarModo(nuevo: 'menu' | 'producto') {
    if (nuevo === modo) return;
    modo = nuevo;
    const cuerpo = columna?.parentElement;
    if (cuerpo) cuerpo.scrollTop = 0;
    await tick();
    cascada(columna, ':scope > *');
  }

  // Después de cambiar un cartel: la lista, el chip y el teléfono.
  async function alCambiarCarteles() {
    try {
      [carteles, estado] = await Promise.all([leerCarteles(sucursal.id), leerEstadoMenu(sucursal.id)]);
    } catch (falla) {
      console.error('[menu en linea] no se pudieron volver a leer los carteles:', falla);
    }
    telefono?.recargar();
  }

  async function copiar(): Promise<boolean> {
    try {
      await navigator.clipboard.writeText(link);
      return true;
    } catch (falla) {
      console.error('[menu en linea] no se pudo copiar el link:', falla);
      error = 'No se pudo copiar. Selecciona el link y cópialo a mano.';
      return false;
    }
  }

  async function bajarQr() {
    try {
      await descargarQr(link, `qr-menu-${sucursal.slug}.png`);
    } catch (falla) {
      console.error('[menu en linea] no se pudo hacer el PNG del QR:', falla);
      error = 'No se pudo descargar el QR. Intenta de nuevo.';
    }
  }

  // Escape: primero las ventanas del panel (lo hace cada ventana), luego el QR (FilaLink) y luego lo abierto en el teléfono.
  function alTeclear(e: KeyboardEvent) {
    if (e.key !== 'Escape' || e.defaultPrevented || document.querySelector('dialog[open]')) return;
    if (telefono?.cerrarEncima()) e.preventDefault();
  }

  // «Abierto · 3 de 3 productos a la vista».
  const chip = $derived.by(() => {
    if (!estado) return errorLectura ? { texto: 'No se pudo leer', vivo: false } : null;
    const abierto = estado.estado === null ? 'Sin horario' : estado.estado.abierto ? 'Abierto' : 'Cerrado';
    const vista = estado.productos ? `${estado.a_la_vista} de ${estado.productos} productos a la vista` : 'Todavía sin productos';
    return { texto: `${abierto} · ${vista}`, vivo: !!estado.estado?.abierto };
  });

  const avisoAsistente = $derived.by(() => {
    const a = estado?.asistente;
    if (!a || a.puede) return null;
    if (a.motivo === 'limite') {
      return `El asistente de tu menú llegó a su límite de este mes. Vuelve el ${diaYMes(a.vuelve)} o ${
        a.con_distribuidor ? 'pídele a tu distribuidor que lo suba' : 'escríbele a Fragmentless para que lo suba'
      }.`;
    }
    return `El asistente de tu menú todavía no está activo. ${
      a.con_distribuidor ? 'Pídele a tu distribuidor que lo active' : 'Escríbele a Fragmentless para que lo active'
    }.`;
  });

  // ─── Las filas de cada modo ───
  type Grupo = {
    clave: keyof Formas;
    etiqueta: string;
    opciones: { valor: string | boolean; texto: string; trazos?: string }[];
    pista?: string;
    apagado?: boolean;
  };
  type FilaDeFormas = {
    clave: string;
    icono: string;
    trazos?: string;
    titulo: string;
    nota: string;
    pieza?: Pieza;
    grupos: Grupo[];
  };

  const centro = $derived(s.formas.barra === 'centro');
  const conCartelDeProducto = $derived(carteles.some((c) => c.producto_id !== null));

  const filasPorClave = $derived.by((): Record<string, FilaDeFormas> => ({
    barra: {
      clave: 'barra',
      icono: 'tienda',
      titulo: 'Barra de arriba',
      nota: 'Tu logo y tu nombre salen de Tu restaurante.',
      grupos: [
        {
          clave: 'barra',
          etiqueta: 'FORMA',
          opciones: [
            { valor: 'izquierda', texto: 'Logo a la izquierda' },
            { valor: 'centro', texto: 'Logo al centro' },
          ],
          pista: 'Al centro: la lupa a la izquierda y, a la derecha, el engrane con el idioma y la moneda.',
        },
        {
          clave: 'con_nombre',
          etiqueta: 'NOMBRE',
          opciones: [
            { valor: true, texto: 'Con tu nombre' },
            { valor: false, texto: 'Solo el logo' },
          ],
          pista: 'Sin logo, tu nombre sale igual.',
        },
        {
          clave: 'idioma',
          etiqueta: 'IDIOMA',
          opciones: [
            { valor: 'letras', texto: 'ES · EN' },
            { valor: 'planeta', texto: 'Mundito', trazos: TRAZOS.mundo },
            { valor: 'cuadro', texto: 'Cuadrito' },
          ],
          apagado: centro,
          pista: 'Cuadrito: un solo botón con el otro idioma; al tocarlo, cambia.',
        },
        {
          clave: 'moneda',
          etiqueta: 'MONEDA',
          opciones: [
            { valor: 'letras', texto: 'MXN · USD' },
            { valor: 'monedas', texto: 'Monedas', trazos: TRAZOS.monedas },
            { valor: 'cuadro', texto: 'Cuadrito' },
          ],
          apagado: centro,
          pista: centro ? 'Con el logo al centro, el idioma y la moneda van en el engrane.' : '',
        },
      ],
    },
    carteles: {
      clave: 'carteles',
      icono: 'cartel',
      titulo: 'Carteles',
      nota: 'Pasan solos. Los pones con «Carteles», arriba.',
      pieza: 'carteles',
      grupos: [
        {
          clave: 'carteles',
          etiqueta: 'FORMA',
          opciones: [
            { valor: 'esquinas', texto: 'Con esquinas' },
            { valor: 'completo', texto: 'Pantalla completa' },
            { valor: 'bajito', texto: 'Bajito' },
          ],
          pista: 'Bajito: haz tus carteles de 3 a 1 (por ejemplo, 1500 × 500); los de otra forma se recortan al centro.',
        },
        {
          clave: 'info',
          etiqueta: 'LA «i»',
          opciones: [
            { valor: 'capsula', texto: 'Con si estás abierto' },
            { valor: 'icono', texto: 'Solo la «i»' },
          ],
          pista: 'Con solo la «i», si estás abierto se ve al picarla.',
        },
        {
          clave: 'info_lugar',
          etiqueta: 'DÓNDE VA LA «i»',
          opciones: [
            { valor: 'arriba', texto: 'Arriba a la derecha' },
            { valor: 'abajo', texto: 'Abajo a la derecha' },
          ],
          pista: 'Abajo puede tapar el texto de tus carteles.',
        },
        {
          clave: 'carteles_producto',
          etiqueta: 'LOS DE TUS PRODUCTOS',
          opciones: [
            { valor: 'nombre', texto: 'Con nombre y precio' },
            { valor: 'foto', texto: 'Solo la foto' },
          ],
          apagado: !conCartelDeProducto,
          pista: conCartelDeProducto
            ? 'Tu menú escribe el nombre y el precio encima de la foto; la foto no cambia.'
            : 'Para cuando pongas la foto de un producto en tus carteles.',
        },
      ],
    },
    busqueda: {
      clave: 'busqueda',
      icono: 'buscar',
      titulo: 'Búsqueda',
      nota: 'Todas dejan ordenar por precio o por nombre.',
      pieza: 'busqueda',
      grupos: [
        {
          clave: 'busqueda',
          etiqueta: 'FORMA',
          opciones: [
            { valor: 'gris', texto: 'Caja gris' },
            { valor: 'blanca', texto: 'Caja blanca' },
            { valor: 'tarjeta', texto: 'Tarjeta que se abre' },
          ],
          apagado: centro,
          pista: centro ? 'Con el logo al centro, tu búsqueda es la lupa de la barra.' : '',
        },
      ],
    },
    categorias: {
      clave: 'categorias',
      icono: 'menu',
      titulo: 'Categorías',
      nota: 'Se quedan arriba mientras bajan por tu menú.',
      pieza: 'categorias',
      grupos: [
        {
          clave: 'categorias',
          etiqueta: 'FORMA',
          opciones: [
            { valor: 'pestanas', texto: 'Pestañas' },
            { valor: 'rectangulos', texto: 'Rectángulos' },
            { valor: 'tarjeta', texto: 'En una tarjeta' },
            { valor: 'pildoras', texto: 'Píldoras' },
            { valor: 'circulos_icono', texto: 'Círculos con ícono' },
            { valor: 'circulos_foto', texto: 'Círculos con foto' },
          ],
          pista: 'Con foto: la de su primer producto que tenga foto; si ninguno tiene, su ícono.',
        },
      ],
    },
    titulos: {
      clave: 'titulos',
      icono: 'titulo',
      trazos: TRAZOS.titulo,
      titulo: 'Títulos de categoría',
      nota: 'Van arriba de los productos de cada categoría.',
      grupos: [
        {
          clave: 'titulos',
          etiqueta: 'FORMA',
          opciones: [
            { valor: 'icono', texto: 'Con su ícono' },
            { valor: 'nombre', texto: 'Solo el nombre' },
            { valor: 'raya', texto: 'Con raya' },
          ],
          pista: 'La raya va en el color de tu menú.',
        },
      ],
    },
    productos: {
      clave: 'productos',
      icono: 'tabla',
      titulo: 'Productos',
      nota: 'Salen de Mi menú, con su foto y su precio.',
      grupos: [
        {
          clave: 'productos',
          etiqueta: 'FORMA',
          opciones: [
            { valor: 'a_lo_largo', texto: 'A lo largo' },
            { valor: 'intercalado', texto: 'Intercalado' },
            { valor: 'dos_en_dos', texto: 'De dos en dos' },
            { valor: 'clasicas', texto: 'Clásicas' },
          ],
          pista: 'Intercalado: cada producto cambia de lado su foto. Clásicas: si tus fotos tienen fondo blanco, se funden con la tarjeta.',
        },
      ],
    },
    abajo: {
      clave: 'abajo',
      icono: 'celular',
      titulo: 'Abajo',
      nota: 'Dónde quedan tu pedido y el asistente.',
      grupos: [
        {
          clave: 'abajo',
          etiqueta: 'FORMA',
          opciones: [
            { valor: 'barra', texto: 'Barra como app' },
            { valor: 'pildora', texto: 'Píldora flotando' },
          ],
          pista: 'Cuándo recibes pedidos se ve al abrir Pedido.',
        },
        {
          clave: 'abajo_con_nombres',
          etiqueta: 'NOMBRES',
          opciones: [
            { valor: true, texto: 'Con su nombre' },
            { valor: false, texto: 'Solo los íconos' },
          ],
          pista: 'Para la barra como app y la píldora.',
        },
      ],
    },
    pventana: {
      clave: 'pventana',
      icono: 'r-producto',
      titulo: 'Ventana',
      nota: 'Lo que se abre cuando tocan un producto de tu menú.',
      grupos: [
        {
          clave: 'producto_ventana',
          etiqueta: 'FORMA',
          opciones: [
            { valor: 'completa', texto: 'Pantalla completa' },
            { valor: 'ventana', texto: 'Ventana' },
          ],
          pista: 'Ventana: sube desde abajo y deja ver tu menú arriba.',
        },
      ],
    },
    ptitulo: {
      clave: 'ptitulo',
      icono: 'titulo',
      trazos: TRAZOS.titulo,
      titulo: 'Título',
      nota:
        s.formas.producto_titulo === 'arriba'
          ? 'Va arriba de la foto, en la cabeza de la ventana, y se queda a la vista al bajar.'
          : 'Va debajo de la foto, con su descripción.',
      grupos: [],
    },
    popciones: {
      clave: 'popciones',
      icono: 'lista',
      trazos: TRAZOS.lista,
      titulo: 'Opciones',
      nota: 'Los grupos de Mi menú, como la salsa o los extras.',
      grupos: [
        {
          clave: 'producto_opciones',
          etiqueta: 'CÓMO SE ELIGEN',
          opciones: [
            { valor: 'juntas', texto: 'Todas juntas' },
            { valor: 'pasos', texto: 'Por pasos' },
          ],
          pista: 'Por pasos: un grupo a la vez, con su avance; al elegir una, pasa solo al siguiente.',
        },
      ],
    },
  }));

  // En su orden: la barra arriba, las tres de en medio en el orden de su menú, y abajo títulos, productos y lo de abajo.
  // En el modo Producto, el Título sube encima de Ventana cuando va arriba de la foto.
  const filas = $derived(
    modo === 'producto'
      ? s.formas.producto_titulo === 'arriba'
        ? ['ptitulo', 'pventana', 'popciones']
        : ['pventana', 'ptitulo', 'popciones']
      : ['barra', ...s.formas.orden, 'titulos', 'productos', 'abajo'],
  );

  function flechasDe(f: FilaDeFormas) {
    if (f.clave === 'ptitulo') {
      return {
        sube: 'Subir arriba de la foto',
        baja: 'Bajar debajo de la foto',
        puedeSubir: s.formas.producto_titulo !== 'arriba',
        puedeBajar: s.formas.producto_titulo === 'arriba',
        alMover: (hacia: -1 | 1) => elegir('producto_titulo', hacia < 0 ? 'arriba' : 'abajo'),
      };
    }
    if (!f.pieza) return undefined;
    const pieza = f.pieza;
    const i = s.formas.orden.indexOf(pieza);
    return {
      sube: 'Subir en tu menú',
      baja: 'Bajar en tu menú',
      puedeSubir: i > 0,
      puedeBajar: i < s.formas.orden.length - 1,
      alMover: (hacia: -1 | 1) => mover(pieza, hacia),
    };
  }

  // Al moverse, cada fila sale de donde estaba con el resorte de las ventanas (520 ms); con «reducir movimiento», quieta.
  const resorte = () => (quieto() ? { duration: 0 } : { duration: 520, easing: RESORTE });
</script>

<svelte:window onkeydown={alTeclear} />

<BarraArriba titulo="Tu menú en línea" estado={chip} chipAntes>
  {#snippet junto()}
    {#if cargando}<span class="chip-esqueleto"><Esqueleto ancho="232px" alto="26px" redondo="13px" /></span>{/if}
    <Dock
      etiqueta="Qué editas"
      opciones={[
        { valor: 'menu', texto: 'Tu menú', icono: 'celular' },
        { valor: 'producto', texto: 'Producto', icono: 'comida', trazos: trazosCategoria('comida') },
      ]}
      elegida={modo}
      alElegir={cambiarModo}
    />
  {/snippet}
  <Boton etiqueta="Carteles" icono="cartel" tono="tinta" apagado={!!errorLectura} onclick={() => (cartelesAbierto = true)} />
  <CajaSucursales {sucursales} actual={sucursal} {alElegir} />
</BarraArriba>

<main class="cuerpo" aria-label="Tu menú en línea">
  <div class="col" bind:this={columna}>
    <div class="cabeza">
      {#if modo === 'producto'}
        <span class="etiqueta">LA VENTANA DE TUS PRODUCTOS</span>
        <p class="nota">
          Cómo se ve un producto cuando lo tocan en tu menú. Sus colores y su fondo son los de tu menú; su foto, su precio y
          sus opciones salen de Mi menú.
        </p>
      {:else}
        <span class="etiqueta">TU MENÚ EN LÍNEA</span>
        <p class="nota">
          Cómo se ve tu menú: su tema, sus colores y la forma de cada pieza. Los productos salen de Mi menú, y tu logo y tu
          horario de Tu restaurante.
        </p>
      {/if}
    </div>
    {#if avisoAsistente}
      <p class="aviso"><Icono nombre="info" tamano={16} /><span>{avisoAsistente}</span></p>
    {/if}
    {#if errorLectura}
      <CajaError mensaje={errorLectura} />
    {:else}
      {#if error}<CajaError mensaje={error} />{/if}
      <FilaLink slug={sucursal.slug} {link} {cargando} alCopiar={copiar} alBajarQr={bajarQr} />
      {#if modo === 'menu'}
        <FilaColores
          tema={s.tema}
          color={s.color}
          colorBarra={s.colorBarra}
          fondo={s.fondo}
          {cargando}
          alTema={cambiarTema}
          alElegir={(clave) => (colorAbierto = clave)}
          alQuitar={(clave) => ponerColor(clave, null)}
        />
      {/if}
      {#each filas as clave (clave)}
        {@const f = filasPorClave[clave]}
        <div class="lugar" animate:flip={resorte()}>
          <Fila clave={f.clave} icono={f.icono} trazos={f.trazos} titulo={f.titulo} nota={f.nota} flechas={flechasDe(f)} {cargando}>
            {#each f.grupos as g (g.clave)}
              <Formas_
                etiqueta={g.etiqueta}
                opciones={g.opciones}
                elegida={s.formas[g.clave] as string | boolean}
                alElegir={(v) => elegir(g.clave, v as never)}
                pista={g.pista}
                apagado={g.apagado}
                {cargando}
              />
            {/each}
          </Fila>
        </div>
      {/each}
    {/if}
  </div>

  {#if !errorLectura}
    <Telefono bind:this={telefono} slug={sucursal.slug} restauranteId={sucursal.id} muestra={s} {modo} leido={!!guardado} />
  {/if}
</main>

<BarraGuardar {cambios} {paso} cargando={cargando || !!errorLectura} error={errorGuardar} alGuardar={guardar} alDescartar={descartar} />

{#if colorAbierto && guardado}
  <VentanaColor
    clave={colorAbierto}
    colores={{ tema: s.tema, color: s.color, colorBarra: s.colorBarra, fondo: s.fondo }}
    formas={s.formas}
    slug={sucursal.slug}
    alUsar={(c) => {
      if (colorAbierto) ponerColor(colorAbierto, c);
      colorAbierto = null;
    }}
    alCerrar={() => (colorAbierto = null)}
  />
{/if}

{#if cartelesAbierto}
  <TusCarteles
    restauranteId={sucursal.id}
    {carteles}
    productos={menu?.productos.filter((p) => !p.es_envio) ?? []}
    categorias={menu?.categorias ?? []}
    bajito={s.formas.carteles === 'bajito'}
    conNombre={s.formas.carteles_producto === 'nombre'}
    {cargando}
    alCambiar={alCambiarCarteles}
    alCerrar={() => (cartelesAbierto = false)}
  />
{/if}

{#if salida}
  <VentanaSalir
    {cambios}
    alSalir={() => {
      const ir = salida;
      salida = null;
      if (guardado) s = copia(guardado);
      ir?.();
    }}
    alGuardar={guardar}
    alCerrar={() => (salida = null)}
  />
{/if}

<style>
  /* Entre la barra de arriba (56) y la de guardar (64): las filas a la izquierda y el teléfono a la derecha. */
  .cuerpo {
    position: absolute;
    left: 0;
    right: 0;
    top: 56px;
    bottom: 64px;
    overflow-y: auto;
    scrollbar-gutter: stable;
    /* Al mover una fila con sus flechas, el navegador no corre la vista: solo se mueven las dos filas que cambian. */
    overflow-anchor: none;
    padding: 20px 14px 28px 24px;
    display: grid;
    grid-template-columns: minmax(0, 1fr) 418px;
    align-items: start;
    gap: 0 24px;
  }

  .col {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  .lugar {
    display: flex;
    flex-direction: column;
  }

  .cabeza {
    padding: 2px 4px 0;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .nota {
    margin: 0;
    font-size: 12.5px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .aviso {
    display: flex;
    align-items: flex-start;
    gap: 10px;
    margin: 0;
    padding: 11px 14px;
    border-radius: 12px;
    background: var(--chip);
    font-size: 12.5px;
    line-height: 1.5;
    color: var(--suave);
  }

  .aviso :global(svg) {
    flex: none;
    margin-top: 2px;
  }

  .chip-esqueleto {
    display: flex;
  }

  /* La fila del link va encima de las demás: su QR sale hacia abajo. */
  .col :global(.fila-tml[data-fila='link']) {
    position: relative;
    z-index: 3;
  }
</style>
