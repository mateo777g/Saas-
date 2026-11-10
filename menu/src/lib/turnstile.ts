// La revisión de Cloudflare (Turnstile, modo «Administrado») antes de cada pedido (relevo de la 6b).
// Va invisible: solo si duda enseña su casilla, dentro de la hoja «Tu pedido». Su script se carga la
// primera vez que hace falta, no al abrir el menú. Cada token sirve una vez: se pide uno nuevo para
// cada pedido. Si en 30 segundos no contesta (su script no carga o la revisión se queda pensando),
// falla: el menú dice «No pudimos mandar tu pedido. Intenta otra vez.» y se puede volver a tocar el
// botón (decidido el 26 de octubre de 2026, en la prueba de verdad).
// Desde el botón único (9 de noviembre de 2026), «Tu pedido» la corre al abrirse (adelantarToken), no
// al tocar «Pedir por WhatsApp»; el asistente la sigue pidiendo al preguntar.
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
      // La que se quedó esperando ya no cuenta: el siguiente toque empieza de nuevo.
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

// ─── Por adelantado (el botón único, 9 de noviembre de 2026) ───
// «Tu pedido» pide su token al abrirse, para que el toque de «Pedir por WhatsApp» no espere a
// Cloudflare: entre el toque y abrir WhatsApp solo queda la vuelta al Worker, porque Safari en el
// iPhone no deja abrir WhatsApp si pasó un momento desde el toque. Un token sirve una vez y vence a
// los 5 minutos: se pide otro a los 4, y `renovar` pide otro después de usarlo (si el pedido no se
// guardó y la hoja sigue abierta). Si el adelantado no salió, el toque lo pide y lo espera, como antes.
const VIDA = 4 * 60 * 1000;

export type Adelantado = {
  // El token para este toque: el adelantado si sigue vigente (o si ya viene en camino), o uno nuevo.
  tomar: () => Promise<string>;
  renovar: () => void;
  soltar: () => void;
};

export function adelantarToken(donde: HTMLElement, lengua: Lengua): Adelantado {
  let actual: { promesa: Promise<string>; hasta: number } | null = null;
  let reloj: ReturnType<typeof setTimeout> | undefined;
  let suelto = false;

  function pedir() {
    clearTimeout(reloj);
    if (suelto) return;
    const mio = { promesa: pedirToken(donde, lengua), hasta: Infinity };
    actual = mio;
    mio.promesa.then(
      () => {
        if (actual !== mio || suelto) return;
        mio.hasta = Date.now() + VIDA;
        reloj = setTimeout(pedir, VIDA);
      },
      (error) => {
        if (actual === mio) actual = null;
        if (!suelto) console.warn('[menu] la revisión por adelantado no salió:', error);
      },
    );
  }

  pedir();
  return {
    tomar() {
      clearTimeout(reloj);
      const listo = actual && Date.now() < actual.hasta ? actual.promesa : null;
      actual = null;
      return listo ?? pedirToken(donde, lengua);
    },
    renovar: pedir,
    soltar() {
      suelto = true;
      clearTimeout(reloj);
      actual = null;
    },
  };
}
