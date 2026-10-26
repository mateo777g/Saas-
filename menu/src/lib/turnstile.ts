// La revisión de Cloudflare (Turnstile, modo «Administrado») antes de cada «Hacer pedido» (relevo de
// la 6b). Va invisible: solo si duda enseña su casilla, dentro de la hoja «Tu pedido». Su script se
// carga la primera vez que hace falta, no al abrir el menú. Cada token sirve una vez: se pide uno
// nuevo en cada «Hacer pedido». Si en 30 segundos no contesta (su script no carga o la revisión se
// queda pensando), falla: el menú dice «No pudimos mandar tu pedido. Intenta otra vez.» y se puede
// volver a tocar «Hacer pedido» (decidido el 26 de octubre de 2026, en la prueba de verdad).
import type { Lengua } from './textos';

const SITIO = import.meta.env.VITE_TURNSTILE_SITIO;
if (!SITIO) throw new Error('Falta VITE_TURNSTILE_SITIO en menu/.env');

type Opciones = {
  sitekey: string;
  execution: 'execute';
  appearance: 'interaction-only';
  language: string;
  callback: (token: string) => void;
  'error-callback': (codigo: string) => boolean;
  'expired-callback': () => void;
};
type Api = {
  render: (donde: HTMLElement, opciones: Opciones) => string;
  execute: (widget: string) => void;
  reset: (widget: string) => void;
  remove: (widget: string) => void;
};

declare global {
  interface Window {
    turnstile?: Api;
    alCargarTurnstile?: () => void;
  }
}

const ESPERA = 30 * 1000;

let cargando: Promise<Api> | null = null;

function cargar(): Promise<Api> {
  cargando ??= new Promise<Api>((listo, falla) => {
    window.alCargarTurnstile = () => (window.turnstile ? listo(window.turnstile) : falla(new Error('Turnstile cargó sin su API')));
    const script = document.createElement('script');
    script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit&onload=alCargarTurnstile';
    script.async = true;
    script.onerror = () => {
      cargando = null;
      script.remove();
      falla(new Error('No cargó el script de Turnstile'));
    };
    document.head.append(script);
  });
  return cargando;
}

// Un token nuevo. El widget vive en `donde` (un hueco de la hoja) mientras la hoja está abierta;
// quitarRevision lo borra al cerrarla.
type Widget = { id: string; donde: HTMLElement; esperando: { listo: (t: string) => void; falla: (e: Error) => void } | null };
let widget = null as Widget | null;

export function pedirToken(donde: HTMLElement, lengua: Lengua): Promise<string> {
  let reloj: ReturnType<typeof setTimeout> | undefined;
  const tarde = new Promise<never>((_, falla) => {
    reloj = setTimeout(() => {
      // La que se quedó esperando ya no cuenta: el siguiente «Hacer pedido» empieza de nuevo.
      if (widget?.esperando) {
        widget.esperando = null;
        window.turnstile?.reset(widget.id);
      }
      falla(new Error(`Turnstile no contestó en ${ESPERA / 1000} s`));
    }, ESPERA);
  });
  return Promise.race([token(donde, lengua), tarde]).finally(() => clearTimeout(reloj));
}

async function token(donde: HTMLElement, lengua: Lengua): Promise<string> {
  const api = await cargar();
  if (widget && widget.donde !== donde) quitarRevision();
  return new Promise<string>((listo, falla) => {
    if (!widget) {
      const nuevo: Widget = { id: '', donde, esperando: null };
      nuevo.id = api.render(donde, {
        sitekey: SITIO,
        execution: 'execute',
        appearance: 'interaction-only',
        language: lengua,
        callback: (token) => {
          nuevo.esperando?.listo(token);
          nuevo.esperando = null;
        },
        'error-callback': (codigo) => {
          console.error('[menu] Turnstile falló:', codigo);
          nuevo.esperando?.falla(new Error(`Turnstile: ${codigo}`));
          nuevo.esperando = null;
          return true;
        },
        'expired-callback': () => api.reset(nuevo.id),
      });
      widget = nuevo;
    } else {
      api.reset(widget.id);
    }
    const actual = widget as Widget;
    actual.esperando = { listo, falla };
    api.execute(actual.id);
  });
}

export function quitarRevision() {
  if (!widget) return;
  widget.esperando?.falla(new Error('Se cerró la hoja'));
  window.turnstile?.remove(widget.id);
  widget = null;
}
