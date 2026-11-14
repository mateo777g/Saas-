// La vista previa del panel (app/src/lib/vistaMenu.ts): el teléfono de «Tu menú en línea» y la tira de la ventana del
// color son este mismo menú dentro de un marco, con ?muestra=menu|barra. El panel le manda lo que Don Chuy todavía no
// guarda (el tema y el color; desde «Tu menú en línea», también el color de la barra, el fondo y las formas) para
// pintarlo sin guardarlo, y le pide volver a leer tras cambiar un cartel. El menú solo hace caso en modo muestra, y
// solo a los orígenes de la app.
//
// Desde la parte C2 (13 nov 2026; maqueta UDArhiEZceT7rmSKxqRA5r v59, «El teléfono a la derecha», v35 a v37) el teléfono
// se toca como lo toca un cliente, sin mandar pedidos ni preguntas de verdad (Menu.svelte). Lo que se dicen:
//
// Del panel al menú:
//   {fragmentless: 'muestra', tema, color, colorBarra?, fondo?, formas?, cambio?}
//       Lo que pinta. `cambio` es la forma que se acaba de elegir (su nombre en `Formas`): el teléfono va a esa pieza
//       y la pieza nueva aparece con el desvanecido corto. Sin `cambio` (el tema, los colores) no se mueve.
//   {fragmentless: 'recargar'}            Que vuelva a leer menu_publico (después de cambiar un cartel).
//   {fragmentless: 'modo', modo}          'producto': el producto de muestra abierto; 'menu': todo cerrado.
//   {fragmentless: 'cerrar'}              Escape en el panel: cierra lo de más arriba.
//   {fragmentless: 'cartel', ruta}        Crear anuncios (13 nov 2026, `crear-anuncios.md`): en el celular del cartel, la
//       muestra del estilo (estilos/<clave>/<32 hex>.webp) va sola en el lugar de los carteles, quieta y con su etiqueta
//       «Muestra», y el teléfono va a ella. Con `ruta` null, sus carteles de siempre. La primera llega en la dirección
//       (?muestra=menu&cartel=<ruta>), para que no se vean sus carteles antes de la muestra.
// Del menú al panel:
//   {fragmentless: 'menu-listo'}          Ya pintó sus datos: el panel le manda lo que no ha guardado.
//   {fragmentless: 'esqueleto', esqueleto} El esqueleto del teléfono, medido del menú ya armado (el `Recuerdo` de
//       lib/esqueleto.ts, a 390 de ancho y del alto de la pantalla): el panel lo pinta con sus colores mientras lee.
//   {fragmentless: 'encima', abierto}     Si hay algo abierto en el teléfono (para que Escape lo cierre).
//   {fragmentless: 'alto', alto}          Solo la tira: cuánto mide.
import type { TemaMenu } from '@app/lib/color';
import { FORMAS_DE_SIEMPRE, leerFormas, type Formas } from './formas';
import { quieto } from './movimiento';

export type ModoMuestra = 'menu' | 'barra' | null;

// Lo que no llega se queda como está guardado (un panel de antes solo manda el tema y el color).
export type Pintura = { tema: TemaMenu; color: string | null; colorBarra?: string | null; fondo?: string | null; formas?: Formas };

// La forma que se acaba de elegir en el panel.
export type Cambio = keyof Formas;

export type ModoPanel = 'menu' | 'producto';

const ORIGENES = (import.meta.env.VITE_ORIGENES_APP ?? '')
  .split(',')
  .map((o) => o.trim())
  .filter(Boolean);

export function modoMuestra(): ModoMuestra {
  const modo = new URLSearchParams(location.search).get('muestra');
  return modo === 'menu' || modo === 'barra' ? modo : null;
}

// Quién nos tiene dentro: solo se le habla si es la app.
function origenDelPanel(): string | null {
  if (window.parent === window) return null;
  const origen = location.ancestorOrigins?.[0] ?? (document.referrer ? new URL(document.referrer).origin : null);
  return origen && ORIGENES.includes(origen) ? origen : null;
}

const color = (v: unknown) => (typeof v === 'string' && /^#[0-9A-F]{6}$/i.test(v) ? v.toUpperCase() : null);
const cambio = (v: unknown): Cambio | null => (typeof v === 'string' && v in FORMAS_DE_SIEMPRE ? (v as Cambio) : null);
// La muestra de un estilo, como la guarda la base (puedo_subir_muestra) y la revisa el Worker (api/src/estilos.ts).
const RUTA_MUESTRA = /^estilos\/[a-z0-9]+(-[a-z0-9]+)*\/[0-9a-f]{32}\.webp$/;
const rutaMuestra = (v: unknown) => (typeof v === 'string' && RUTA_MUESTRA.test(v) ? v : null);

// La primera muestra del celular del cartel de Crear anuncios, desde la dirección.
export function cartelDeInicio(): string | null {
  return rutaMuestra(new URLSearchParams(location.search).get('cartel'));
}

export type DelPanel = {
  alPintar: (p: Pintura, cambio: Cambio | null) => void;
  alRecargar: () => void;
  alModo?: (modo: ModoPanel) => void;
  alCerrar?: () => void;
  alCartel?: (ruta: string | null) => void;
};

export function escucharPanel({ alPintar, alRecargar, alModo, alCerrar, alCartel }: DelPanel): () => void {
  const escuchar = (e: MessageEvent) => {
    if (!ORIGENES.includes(e.origin) || e.source !== window.parent) return;
    const d = e.data as Record<string, unknown> | null;
    if (!d || typeof d !== 'object') return;
    if (d.fragmentless === 'recargar') return alRecargar();
    if (d.fragmentless === 'modo') return alModo?.(d.modo === 'producto' ? 'producto' : 'menu');
    if (d.fragmentless === 'cerrar') return alCerrar?.();
    if (d.fragmentless === 'cartel') return alCartel?.(rutaMuestra(d.ruta));
    if (d.fragmentless !== 'muestra') return;
    const p: Pintura = { tema: d.tema === 'oscuro' ? 'oscuro' : 'claro', color: color(d.color) };
    if ('colorBarra' in d) p.colorBarra = color(d.colorBarra);
    if ('fondo' in d) p.fondo = color(d.fondo);
    if ('formas' in d) p.formas = leerFormas(d.formas);
    alPintar(p, cambio(d.cambio));
  };
  window.addEventListener('message', escuchar);
  return () => window.removeEventListener('message', escuchar);
}

export function avisarAlPanel(mensaje: Record<string, unknown>) {
  const origen = origenDelPanel();
  if (origen) window.parent.postMessage(mensaje, origen);
}

// ─── Al elegir una forma, el teléfono va a esa pieza ───
// Como irAPiezaEnTel de la maqueta: sube o baja (suave) hasta la pieza y ella aparece con el desvanecido corto (0.22 s).
// La barra va hasta arriba del todo; lo de abajo ya se ve siempre, así que no se mueve. Al subir o bajar una pieza con
// las flechas, va a la primera pieza de en medio. Con el producto abierto, baja dentro de él: hasta sus opciones si
// cambiaron, o hasta arriba.
const PIEZA: Partial<Record<Cambio, string>> = {
  barra: 'header.barra',
  con_nombre: 'header.barra',
  idioma: 'header.barra',
  moneda: 'header.barra',
  carteles: '.carteles',
  info: '.carteles',
  info_lugar: '.carteles',
  carteles_producto: '.carteles',
  busqueda: '.columna > .fila, .f-tarjeta-busca, .f-lupa-caja',
  categorias: '.pestanas, .f-cats',
  orden: '.columna > :nth-child(2)',
  titulos: '[data-seccion]',
  productos: '[data-seccion]',
  abajo: '.f-app',
  abajo_con_nombres: '.f-app',
};

function desvanecer(el: Element) {
  if (!quieto()) el.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 220, easing: 'ease' });
}

export function irAPieza(menu: HTMLElement, c: Cambio) {
  const suave: ScrollBehavior = quieto() ? 'auto' : 'smooth';
  if (c.startsWith('producto_')) {
    const vista = menu.querySelector<HTMLElement>(':scope > .f-prod');
    const desliza = vista?.querySelector<HTMLElement>('.f-prod-desliza');
    if (!vista || !desliza) return;
    const grupo = c === 'producto_opciones' ? vista.querySelector('.f-pasos, .f-prod-grupo') : null;
    const arriba = grupo ? grupo.getBoundingClientRect().top - desliza.getBoundingClientRect().top + desliza.scrollTop : 0;
    desliza.scrollTo({ top: grupo ? Math.max(0, arriba - (vista.classList.contains('ventana') ? 76 : 110)) : 0, behavior: suave });
    desvanecer(grupo ?? vista);
    return;
  }
  const el = PIEZA[c] ? menu.querySelector<HTMLElement>(PIEZA[c]!) : null;
  if (!el) return;
  if (!el.closest('.f-app')) {
    const y = el.matches('header.barra') ? 0 : Math.max(0, el.getBoundingClientRect().top + scrollY - 70);
    scrollTo({ top: y, behavior: suave });
  }
  desvanecer(el);
}
