// El asistente del menú (libreta 6, parte 6c; maqueta 2UPwZw31WrcYRZkH8jaT1Y; lo que decidí yo en
// planes/trabajo/6c/menu-6c.md). La plática vive en el celular, una por restaurante, como el
// carrito: se borra tras 12 horas sin preguntar. Cada pregunta va al Worker (POST /menu/pregunta)
// con el pase de una hora que dio la revisión de Cloudflare, o con una revisión nueva si no hay pase
// o ya venció; si el Worker no acepta el pase (motivo «pase»), se hace la revisión y se manda otra
// vez, una vez. Los avisos (sin IA, los dos límites, «No pude contestar») los escribe el menú.
// Los «no» llegan en JSON normal; el «sí» llega por partes, con sus pasos por clave, que el menú
// escribe en su idioma (planes/trabajo/estrella/worker.md, puntos 31 a 34).
import { Compas, leerRenglones, vienePorPartes, type Aviso } from '@app/lib/pasos';
import { API, escribir, leer, marcaDelCelular } from './pedido';
import type { Moneda } from './preferencias';
import type { Lengua } from './textos';

export type Motivo = 'sin_ia' | 'limite_celular' | 'limite_conexion';

export type ClavePaso = 'buscar' | 'recomendar' | 'escribir';
export type PasoMenu = { clave: ClavePaso; hecho: boolean };

export type Mensaje =
  | { rol: 'cliente'; texto: string }
  // Sus pasos se guardan por su clave, por lo mismo que los avisos. Las de antes no los traen.
  | { rol: 'asistente'; texto: string; productos: number[]; segundos?: number; pasos?: ClavePaso[] }
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

// Lee el «sí»: los pasos con su compás (cada uno se deja leer 400 ms) y, al final, la respuesta.
async function leerPorPartes(
  respuesta: Response,
  senal: AbortSignal,
  alPasos: (pasos: PasoMenu[]) => void,
): Promise<DelWorker> {
  const compas = new Compas();
  const parar = () => compas.parar();
  senal.addEventListener('abort', parar);
  let pasos: PasoMenu[] = [];
  const poner = (nuevos: PasoMenu[]) => {
    pasos = nuevos;
    alPasos(pasos);
  };
  let fin: Aviso | null = null;
  try {
    await leerRenglones(respuesta, (a) => {
      if (a.tipo === 'paso') compas.entra(() => poner([...pasos, { clave: a.clave as ClavePaso, hecho: false }]));
      else if (a.tipo === 'hecho') compas.sale(() => poner(pasos.map((p) => (p.clave === a.clave ? { ...p, hecho: true } : p))));
      else if (a.tipo === 'fin') fin = a;
      else if (a.tipo === 'error') throw new Error('el Worker avisó de un error a media respuesta');
    });
    if (!fin) throw new Error('la respuesta se acabó sin su final');
    compas.sale(() => {});
    await compas.termina();
    senal.throwIfAborted();
    return fin as unknown as DelWorker;
  } finally {
    senal.removeEventListener('abort', parar);
    compas.parar();
  }
}

// Lo que no es un «sí» ni un «no» del Worker (sin red, 60 segundos sin la respuesta completa, un 4xx o
// 5xx) es una falla: ella lee «No pude contestar».
async function mandar(cuerpo: object, alPasos: (pasos: PasoMenu[]) => void): Promise<DelWorker> {
  const corte = new AbortController();
  const reloj = setTimeout(() => corte.abort(new Error(`${ESPERA / 1000} s sin respuesta del Worker`)), ESPERA);
  try {
    const respuesta = await fetch(`${API}/menu/pregunta`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(cuerpo),
      signal: corte.signal,
    });
    if (respuesta.ok && vienePorPartes(respuesta)) return await leerPorPartes(respuesta, corte.signal, alPasos);
    const datos = (await respuesta.json().catch(() => null)) as (DelWorker & { error?: string }) | null;
    if (respuesta.ok && datos && typeof datos.ok === 'boolean') return datos;
    throw new Error(`el Worker regresó ${respuesta.status}${datos?.error ? `: ${datos.error}` : ''}`);
  } finally {
    clearTimeout(reloj);
  }
}

async function preguntarAlWorker(
  slug: string,
  envio: Envio,
  revision: () => Promise<string>,
  alPasos: (pasos: PasoMenu[]) => void,
): Promise<Contestacion> {
  const base = { slug, ...envio, marca: marcaDelCelular() };
  const pase = leerPase(slug);
  let r = await mandar(pase ? { ...base, pase } : { ...base, turnstile: await revision() }, alPasos);
  if (!r.ok && r.motivo === 'pase' && pase) {
    // El Worker no aceptó el pase: la revisión y la misma pregunta otra vez, una vez.
    escribir(llavePase(slug), null);
    r = await mandar({ ...base, turnstile: await revision() }, alPasos);
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
  // Sus pasos: al llegar la respuesta se doblan en su «Pensé 2 s». Y qué mensaje acaba de llegar, el único que entra animado.
  pasos = $state<PasoMenu[]>([]);
  nuevo = $state<number | null>(null);
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
    this.pasos = [];
    this.nuevo = null;
    this.noContesto = false;
    try {
      const envio = { pregunta, conversacion: paraElWorker(this.mensajes), lengua, moneda };
      // Los segundos cuentan desde el primer paso: la revisión de Cloudflare no es pensar.
      let inicio = 0;
      const r = await preguntarAlWorker(this.#slug, envio, revision, (pasos) => {
        inicio ||= performance.now();
        this.pasos = pasos;
      });
      const llego: Mensaje = r.ok
        ? {
            rol: 'asistente',
            texto: r.respuesta,
            productos: r.productos,
            segundos: Math.max(1, Math.round((performance.now() - inicio) / 1000)),
            pasos: this.pasos.map((p) => p.clave),
          }
        : { rol: 'aviso', motivo: r.motivo };
      this.mensajes = guardarPlatica(this.#slug, [...this.mensajes, { rol: 'cliente', texto: pregunta }, llego]);
      this.nuevo = this.mensajes.length - 1;
      return r.ok ? null : r.motivo;
    } catch (error) {
      console.error('[menu] el asistente no contestó:', error);
      // Su pregunta vuelve a la caja, como en el Agente IA, si no escribió otra mientras pensaba.
      if (!this.borrador.trim()) this.borrador = pregunta;
      this.noContesto = true;
      return null;
    } finally {
      this.pendiente = null;
      this.pasos = [];
    }
  }
}
