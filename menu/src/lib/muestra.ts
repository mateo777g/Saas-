// La vista previa del panel (app/src/lib/vistaMenu.ts): «Así lo ven tus clientes» y la tira de la
// ventana del color son este mismo menú dentro de un marco, con ?muestra=menu|barra. El panel le
// manda lo que Don Chuy todavía no guarda (el tema, el color y el tipo de cambio) para pintarlo sin
// guardarlo, y le pide volver a leer tras cambiar un cartel. El menú solo hace caso en modo
// muestra, y solo a los orígenes de la app.
import type { TemaMenu } from '@app/lib/color';

export type ModoMuestra = 'menu' | 'barra' | null;

export type Pintura = { tema: TemaMenu; color: string | null; tipo_cambio_usd: number | null };

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

export function escucharPanel(alPintar: (p: Pintura) => void, alRecargar: () => void): () => void {
  const escuchar = (e: MessageEvent) => {
    if (!ORIGENES.includes(e.origin) || e.source !== window.parent) return;
    const d = e.data as Record<string, unknown> | null;
    if (!d || typeof d !== 'object') return;
    if (d.fragmentless === 'recargar') return alRecargar();
    if (d.fragmentless !== 'muestra') return;
    const tema = d.tema === 'oscuro' ? 'oscuro' : 'claro';
    const color = typeof d.color === 'string' && /^#[0-9A-F]{6}$/i.test(d.color) ? d.color.toUpperCase() : null;
    const cambio = typeof d.tipo_cambio_usd === 'number' && d.tipo_cambio_usd > 0 ? d.tipo_cambio_usd : null;
    alPintar({ tema, color, tipo_cambio_usd: cambio });
  };
  window.addEventListener('message', escuchar);
  return () => window.removeEventListener('message', escuchar);
}

// {fragmentless: 'menu-listo'} cuando ya pintó; en la tira, {fragmentless: 'alto', alto}.
export function avisarAlPanel(mensaje: Record<string, unknown>) {
  const origen = origenDelPanel();
  if (origen) window.parent.postMessage(mensaje, origen);
}
