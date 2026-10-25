// El menú en línea visto desde el panel: su dirección (pidemenu.mx/<slug>; en pruebas, el servidor
// local de menu/) y su vista previa. La vista previa es el menú de verdad dentro de un marco, así
// enseña exactamente lo que ven los clientes; lo que Don Chuy todavía no guarda (el tema, el color y
// el tipo de cambio) se le manda con postMessage y el menú lo pinta sin guardarlo.
import type { TemaMenu } from './color';

const MENU_URL = import.meta.env.VITE_MENU_URL;
if (!MENU_URL) throw new Error('Falta VITE_MENU_URL en app/.env');
const ORIGEN_MENU = new URL(MENU_URL).origin;

export function linkDelMenu(slug: string): string {
  return `${MENU_URL}/${slug}`;
}

// Como se enseña en el panel, sin https://: «pidemenu.mx».
export const HOST_MENU = new URL(MENU_URL).host;

// barra: solo la barra de arriba y las categorías, para probar un color en su ventana.
export function linkDeMuestra(slug: string, como: 'menu' | 'barra'): string {
  return `${MENU_URL}/${slug}?muestra=${como}`;
}

export type Muestra = { tema: TemaMenu; color: string | null; tipo_cambio_usd: number | null };

export function mandarMuestra(marco: HTMLIFrameElement | undefined, muestra: Muestra) {
  marco?.contentWindow?.postMessage({ fragmentless: 'muestra', ...muestra }, ORIGEN_MENU);
}

// Después de cambiar algo que el menú lee de la base (un cartel): que lo vuelva a pedir.
export function recargarMuestra(marco: HTMLIFrameElement | undefined) {
  marco?.contentWindow?.postMessage({ fragmentless: 'recargar' }, ORIGEN_MENU);
}

// El menú avisa cuando ya pintó sus datos; entonces se le manda lo que no se ha guardado.
export function alListo(marco: () => HTMLIFrameElement | undefined, enviar: () => void): () => void {
  const escuchar = (e: MessageEvent) => {
    if (e.origin === ORIGEN_MENU && e.source === marco()?.contentWindow && e.data?.fragmentless === 'menu-listo') enviar();
  };
  window.addEventListener('message', escuchar);
  return () => window.removeEventListener('message', escuchar);
}
