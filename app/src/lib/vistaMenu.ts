// El menú en línea visto desde el panel: su dirección (abremenu.com/<slug>; en pruebas, el servidor
// local de menu/) y su vista previa. La vista previa es el menú de verdad dentro de un marco, así
// enseña exactamente lo que ven los clientes; lo que Don Chuy todavía no guarda (el tema, los colores
// y las formas) se le manda con postMessage y el menú lo pinta sin guardarlo. Lo que se dicen está
// arriba de menu/src/lib/muestra.ts.
import type { TemaMenu } from './color';
import type { Formas } from './formasMenu';

const MENU_URL = import.meta.env.VITE_MENU_URL;
if (!MENU_URL) throw new Error('Falta VITE_MENU_URL en app/.env');
const ORIGEN_MENU = new URL(MENU_URL).origin;

export function linkDelMenu(slug: string): string {
  return `${MENU_URL}/${slug}`;
}

// Como se enseña en el panel, sin https://: «abremenu.com».
export const HOST_MENU = new URL(MENU_URL).host;

// menu: el teléfono de «Tu menú en línea». barra: la tira de la ventana del color, con la barra de arriba y, según el
// color que se prueba, las categorías (el de tu menú), la búsqueda y las categorías (el de la barra) o los productos
// (el fondo).
export type TiraDeColor = 'color' | 'colorBarra' | 'fondo';

export function linkDeMuestra(slug: string, como: 'menu' | 'barra', tira?: TiraDeColor): string {
  return `${MENU_URL}/${slug}?muestra=${como}${tira && tira !== 'color' ? `&tira=${tira}` : ''}`;
}

export type Muestra = { tema: TemaMenu; color: string | null; colorBarra?: string | null; fondo?: string | null; formas?: Formas };

// `cambio`: la forma que se acaba de elegir; el teléfono va a esa pieza.
export function mandarMuestra(marco: HTMLIFrameElement | undefined, muestra: Muestra, cambio?: keyof Formas | null) {
  const datos = { fragmentless: 'muestra', ...muestra, ...(cambio ? { cambio } : {}) };
  // Las formas van como objeto simple (sin el proxy de $state, que postMessage no sabe copiar).
  marco?.contentWindow?.postMessage(JSON.parse(JSON.stringify(datos)), ORIGEN_MENU);
}

// Después de cambiar algo que el menú lee de la base (un cartel): que lo vuelva a pedir.
export function recargarMuestra(marco: HTMLIFrameElement | undefined) {
  marco?.contentWindow?.postMessage({ fragmentless: 'recargar' }, ORIGEN_MENU);
}

// El dock: 'producto' abre el producto de muestra; 'menu' cierra todo.
export function mandarModo(marco: HTMLIFrameElement | undefined, modo: 'menu' | 'producto') {
  marco?.contentWindow?.postMessage({ fragmentless: 'modo', modo }, ORIGEN_MENU);
}

// Escape en el panel: que cierre lo de más arriba del teléfono.
export function mandarCerrar(marco: HTMLIFrameElement | undefined) {
  marco?.contentWindow?.postMessage({ fragmentless: 'cerrar' }, ORIGEN_MENU);
}

// Lo que el menú le dice al panel (solo el de este marco y del origen del menú).
export type DelMenu =
  | { fragmentless: 'menu-listo' }
  | { fragmentless: 'esqueleto'; esqueleto: EsqueletoTelefono }
  | { fragmentless: 'encima'; abierto: boolean }
  | { fragmentless: 'alto'; alto: number };

export function oirAlMenu(marco: () => HTMLIFrameElement | undefined, al: (m: DelMenu) => void): () => void {
  const escuchar = (e: MessageEvent) => {
    if (e.origin !== ORIGEN_MENU || !marco() || e.source !== marco()?.contentWindow) return;
    const d = e.data as { fragmentless?: unknown } | null;
    if (d && typeof d === 'object' && typeof d.fragmentless === 'string') al(d as DelMenu);
  };
  window.addEventListener('message', escuchar);
  return () => window.removeEventListener('message', escuchar);
}

// El menú avisa cuando ya pintó sus datos; entonces se le manda lo que no se ha guardado.
export function alListo(marco: () => HTMLIFrameElement | undefined, enviar: () => void): () => void {
  return oirAlMenu(marco, (m) => {
    if (m.fragmentless === 'menu-listo') enviar();
  });
}

// ─── El esqueleto del teléfono ───
// Lo mide el menú ya armado (menu/src/lib/esqueleto.ts, su `Recuerdo`) y se lo manda al panel, que lo pinta con sus
// colores (Simple o Cristal) mientras lee la próxima vez. Cada pieza es [x, y, ancho, alto, esquinas] a 390 de ancho;
// con un 1 al final es una tapa (lo que flota con su fondo y tapa lo de debajo). Lo de abajo va pegado abajo.
export type PiezaEsqueleto = [number, number, number, number, number] | [number, number, number, number, number, 1];
export type EsqueletoTelefono = {
  ancho: number;
  piezas: PiezaEsqueleto[];
  abajo: { alto: number; piezas: PiezaEsqueleto[] } | null;
};

const llaveEsqueleto = (restauranteId: string) => `fragmentless-esqueleto-menu-${restauranteId}`;

function esPieza(p: unknown): p is PiezaEsqueleto {
  return Array.isArray(p) && (p.length === 5 || p.length === 6) && p.every((n) => typeof n === 'number' && Number.isFinite(n));
}

// Solo rectángulos: lo que no tenga esa forma no se pinta (el menú es de otro origen).
export function limpiarEsqueleto(e: unknown): EsqueletoTelefono | null {
  if (!e || typeof e !== 'object') return null;
  const d = e as Record<string, unknown>;
  if (typeof d.ancho !== 'number' || !Array.isArray(d.piezas) || d.piezas.length > 3000) return null;
  const abajo = d.abajo as Record<string, unknown> | null;
  return {
    ancho: d.ancho,
    piezas: d.piezas.filter(esPieza),
    abajo:
      abajo && typeof abajo === 'object' && typeof abajo.alto === 'number' && Array.isArray(abajo.piezas)
        ? { alto: abajo.alto, piezas: abajo.piezas.filter(esPieza).slice(0, 100) }
        : null,
  };
}

export function leerEsqueletoTelefono(restauranteId: string): EsqueletoTelefono | null {
  try {
    return limpiarEsqueleto(JSON.parse(localStorage.getItem(llaveEsqueleto(restauranteId)) ?? 'null'));
  } catch (error) {
    console.error('[menu en linea] no se pudo leer el esqueleto del teléfono que se recordaba; sale el general:', error);
    return null;
  }
}

export function guardarEsqueletoTelefono(restauranteId: string, e: EsqueletoTelefono) {
  try {
    localStorage.setItem(llaveEsqueleto(restauranteId), JSON.stringify(e));
  } catch (error) {
    console.error('[menu en linea] no se pudo recordar el esqueleto del teléfono:', error);
  }
}
