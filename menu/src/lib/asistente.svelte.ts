// El asistente del menú (libreta 6, parte 6c; maqueta 2UPwZw31WrcYRZkH8jaT1Y; lo que decidí yo en
// planes/trabajo/6c/menu-6c.md). La plática vive en el celular, una por restaurante, como el
// carrito: se borra tras 12 horas sin preguntar. Cada pregunta va al Worker (POST /menu/pregunta)
// con el pase de una hora que dio la revisión de Cloudflare, o con una revisión nueva si no hay pase
// o ya venció; si el Worker no acepta el pase (motivo «pase»), se hace la revisión y se manda otra
// vez, una vez. Los avisos (sin IA, los dos límites, «No pude contestar») los escribe el menú.
import { API, escribir, leer, marcaDelCelular } from './pedido';
import type { Moneda } from './preferencias';
import type { Lengua } from './textos';

export type Motivo = 'sin_ia' | 'limite_celular' | 'limite_conexion';

export type Mensaje =
  | { rol: 'cliente'; texto: string }
  | { rol: 'asistente'; texto: string; productos: number[] }
  // Un aviso se guarda por su motivo: su texto sigue al ES / EN de la barra.
  | { rol: 'aviso'; motivo: Motivo };

const DOCE_HORAS = 12 * 60 * 60 * 1000;
const PREGUNTAS_GUARDADAS = 30;
// Sus últimas 3 preguntas con sus 3 respuestas.
const MENSAJES_AL_WORKER = 6;
const ESPERA = 60 * 1000;
// Un pase que vence en menos de un minuto ya no se manda: podría vencer en el camino.
const MARGEN_PASE = 60 * 1000;
const llavePlatica = (slug: string) => `pidemenu-platica-${slug}`;
const llavePase = (slug: string) => `pidemenu-pase-${slug}`;

function leerPlatica(slug: string): Mensaje[] {
  const g = leer<{ mensajes: Mensaje[]; tocado: number }>(llavePlatica(slug));
  if (!g || !Array.isArray(g.mensajes) || Date.now() - g.tocado > DOCE_HORAS) return [];
  return g.mensajes;
}

// Solo sus últimas 30 preguntas, con lo que vino después de cada una.
function guardarPlatica(slug: string, mensajes: Mensaje[]): Mensaje[] {
  let desde = 0;
  let preguntas = 0;
  for (let i = mensajes.length - 1; i >= 0; i--) {
    if (mensajes[i].rol === 'cliente' && ++preguntas === PREGUNTAS_GUARDADAS) {
      desde = i;
      break;
    }
  }
  const guardados = mensajes.slice(desde);
  escribir(llavePlatica(slug), { mensajes: guardados, tocado: Date.now() });
  return guardados;
}

// Al Worker solo van las preguntas que se contestaron, las últimas 3 con su respuesta.
function paraElWorker(mensajes: Mensaje[]): { rol: 'cliente' | 'asistente'; texto: string }[] {
  const platica: { rol: 'cliente' | 'asistente'; texto: string }[] = [];
  mensajes.forEach((m, i) => {
    const sigue = mensajes[i + 1];
    if (m.rol === 'cliente' && sigue?.rol === 'asistente') {
      platica.push({ rol: 'cliente', texto: m.texto }, { rol: 'asistente', texto: sigue.texto });
    }
  });
  return platica.slice(-MENSAJES_AL_WORKER);
}

function leerPase(slug: string): string | null {
  const p = leer<{ pase: string; vence: string }>(llavePase(slug));
  return p && typeof p.pase === 'string' && Date.parse(p.vence) - Date.now() > MARGEN_PASE ? p.pase : null;
}

// ─── El Worker ───
type DelWorker = (
  | { ok: true; respuesta: string; productos: number[] }
  | { ok: false; motivo: Motivo | 'pase' }
) & { pase?: string; pase_vence?: string };

type Contestacion = { ok: true; respuesta: string; productos: number[] } | { ok: false; motivo: Motivo };

type Envio = {
  pregunta: string;
  conversacion: { rol: 'cliente' | 'asistente'; texto: string }[];
  lengua: Lengua;
  moneda: Moneda;
};

// Lo que no es un «sí» ni un «no» del Worker (sin red, 60 segundos sin respuesta, un 4xx o 5xx) es
// una falla: ella lee «No pude contestar».
async function mandar(cuerpo: object): Promise<DelWorker> {
  const corte = new AbortController();
  const reloj = setTimeout(() => corte.abort(new Error(`${ESPERA / 1000} s sin respuesta del Worker`)), ESPERA);
  try {
    const respuesta = await fetch(`${API}/menu/pregunta`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(cuerpo),
      signal: corte.signal,
    });
    const datos = (await respuesta.json().catch(() => null)) as (DelWorker & { error?: string }) | null;
    if (respuesta.ok && datos && typeof datos.ok === 'boolean') return datos;
    throw new Error(`el Worker regresó ${respuesta.status}${datos?.error ? `: ${datos.error}` : ''}`);
  } finally {
    clearTimeout(reloj);
  }
}

async function preguntarAlWorker(slug: string, envio: Envio, revision: () => Promise<string>): Promise<Contestacion> {
  const base = { slug, ...envio, marca: marcaDelCelular() };
  const pase = leerPase(slug);
  let r = await mandar(pase ? { ...base, pase } : { ...base, turnstile: await revision() });
  if (!r.ok && r.motivo === 'pase' && pase) {
    // El Worker no aceptó el pase: la revisión y la misma pregunta otra vez, una vez.
    escribir(llavePase(slug), null);
    r = await mandar({ ...base, turnstile: await revision() });
  }
  if (r.pase && r.pase_vence) escribir(llavePase(slug), { pase: r.pase, vence: r.pase_vence });
  if (!r.ok && r.motivo === 'pase') throw new Error('el Worker pidió la revisión después de pasarla');
  return r as Contestacion;
}

// ─── La plática ───
// Vive en Menu.svelte, no en su hoja: si ella cierra la plática mientras piensa, la respuesta llega
// igual y la ve al volver. Lo que dejó en la caja y «No pude contestar» se quedan mientras no cierre
// la pestaña.
export class Platica {
  mensajes = $state<Mensaje[]>([]);
  // La pregunta que espera su respuesta: se guarda en el celular hasta que llega lo que le toca.
  pendiente = $state<string | null>(null);
  borrador = $state('');
  noContesto = $state(false);
  readonly #slug: string;

  constructor(slug: string) {
    this.#slug = slug;
    this.mensajes = leerPlatica(slug);
  }

  // Regresa el motivo de un «no» (sin IA o un límite), para que el menú se vuelva a leer sin IA.
  async preguntar(
    pregunta: string,
    { lengua, moneda, revision }: { lengua: Lengua; moneda: Moneda; revision: () => Promise<string> },
  ): Promise<Motivo | null> {
    if (!pregunta || this.pendiente !== null) return null;
    this.pendiente = pregunta;
    this.noContesto = false;
    try {
      const envio = { pregunta, conversacion: paraElWorker(this.mensajes), lengua, moneda };
      const r = await preguntarAlWorker(this.#slug, envio, revision);
      const llego: Mensaje = r.ok
        ? { rol: 'asistente', texto: r.respuesta, productos: r.productos }
        : { rol: 'aviso', motivo: r.motivo };
      this.mensajes = guardarPlatica(this.#slug, [...this.mensajes, { rol: 'cliente', texto: pregunta }, llego]);
      return r.ok ? null : r.motivo;
    } catch (error) {
      console.error('[menu] el asistente no contestó:', error);
      // Su pregunta vuelve a la caja, como en el Agente IA, si no escribió otra mientras pensaba.
      if (!this.borrador.trim()) this.borrador = pregunta;
      this.noContesto = true;
      return null;
    } finally {
      this.pendiente = null;
    }
  }
}
