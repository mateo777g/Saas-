// Las llamadas a OpenAI, con la llave de Fragmentless (libreta 3: vive solo en el Worker). El
// agente va por la Responses API, la única con la que gpt-6.1-sol usa herramientas; el saludo, por
// Chat Completions, como en Flet. Ninguna lleva temperature (los dos modelos solo aceptan la de por
// defecto). Aquí no se calcula ningún costo: solo se leen los tokens que reporta OpenAI, y
// Postgres los convierte en dinero (anotar_uso_ia).
import type { Env } from './index';
import { Rechazo } from './respuestas';

// Los modelos no se negocian; OPENAI_MODEL y OPENAI_MODEL_SALUDO solo existen para cambiarlos sin
// publicar código (y el modelo nuevo necesita su fila en precios_ia).
export function modeloAgente(env: Env): string {
  return env.OPENAI_MODEL || 'gpt-6.1-sol';
}

export function modeloSaludo(env: Env): string {
  return env.OPENAI_MODEL_SALUDO || 'gpt-5.6-luna';
}

export function modeloAsistente(env: Env): string {
  return env.OPENAI_MODEL_MENU || 'gpt-5.6-luna';
}

// Los de Crear contenido: la imagen, como en Flet (OPENAI_MODEL_IMAGEN), y el paso de texto.
export function modeloImagen(env: Env): string {
  return env.OPENAI_MODEL_IMAGEN || 'gpt-image-2.5-sunburst';
}

export function modeloPalabras(env: Env): string {
  return env.OPENAI_MODEL_PALABRAS || 'gpt-5.6-luna';
}

// OpenAI cobra al doble la entrada de una llamada que pasa de aquí, y precios_ia no lo sabe.
const ENTRADA_PRECIO_NORMAL = 272_000;

// Los tokens de una o varias llamadas, como los pide anotar_uso_ia. La entrada trae dentro lo que
// se leyó de caché y lo que se guardó en caché.
export type Tokens = { entrada: number; entrada_cache: number; escritura_cache: number; salida: number };

export const SIN_TOKENS: Tokens = { entrada: 0, entrada_cache: 0, escritura_cache: 0, salida: 0 };

export function sumar(a: Tokens, b: Tokens): Tokens {
  return {
    entrada: a.entrada + b.entrada,
    entrada_cache: a.entrada_cache + b.entrada_cache,
    escritura_cache: a.escritura_cache + b.escritura_cache,
    salida: a.salida + b.salida,
  };
}

function numero(valor: unknown): number {
  return typeof valor === 'number' && Number.isFinite(valor) && valor >= 0 ? Math.trunc(valor) : 0;
}

// Lo que reportó OpenAI, en la forma de anotar_uso_ia. Si la caché y la escritura suman más que la
// entrada (pasó en el foro con GPT-5.6), queda en el registro y la escritura se recorta a lo que
// cabe, para que el gasto se anote igual.
function tokens(modelo: string, entrada: unknown, cache: unknown, escritura: unknown, salida: unknown, crudo: unknown): Tokens {
  const t = { entrada: numero(entrada), entrada_cache: numero(cache), escritura_cache: numero(escritura), salida: numero(salida) };
  if (t.entrada_cache > t.entrada) t.entrada_cache = t.entrada;
  if (t.entrada_cache + t.escritura_cache > t.entrada) {
    console.warn('[openai] la caché y la escritura suman más que la entrada', modelo, JSON.stringify(crudo));
    t.escritura_cache = t.entrada - t.entrada_cache;
  }
  if (t.entrada > ENTRADA_PRECIO_NORMAL) {
    console.error(
      `[openai] una llamada a ${modelo} pasó de ${ENTRADA_PRECIO_NORMAL} tokens de entrada (${t.entrada}): OpenAI la cobra al doble y precios_ia no lo sabe`,
    );
  }
  return t;
}

function llave(env: Env): string {
  if (!env.OPENAI_LLAVE) {
    console.error('[openai] falta el secreto OPENAI_LLAVE en Cloudflare');
    throw new Rechazo(500, 'El agente todavía no está conectado. Intenta más tarde.');
  }
  return env.OPENAI_LLAVE;
}

// Con `soloCodigo`, un error se registra solo con su código: lo del menú en línea nunca deja su
// texto en el registro. Con `espera`, se deja de esperar a los tantos milisegundos.
async function pedir(
  env: Env,
  ruta: string,
  cuerpo: unknown,
  opciones: { soloCodigo?: boolean; espera?: number } = {},
): Promise<Record<string, unknown>> {
  let respuesta: Response;
  try {
    respuesta = await fetch(`https://api.openai.com/v1/${ruta}`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${llave(env)}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(cuerpo),
      signal: opciones.espera ? AbortSignal.timeout(opciones.espera) : undefined,
    });
  } catch (e) {
    if (!(e instanceof DOMException && e.name === 'TimeoutError')) throw e;
    console.error(`[openai] ${ruta} no contestó en ${opciones.espera} ms; si cobró algo, no quedó anotado`);
    throw new Rechazo(502, 'El agente no pudo contestar. Intenta de nuevo.');
  }
  const texto = await respuesta.text();
  if (!respuesta.ok) {
    // El cuerpo de error de OpenAI no trae la llave: dice qué pasó (cuota, modelo, argumentos).
    console.error(`[openai] ${ruta} falló con ${respuesta.status}`, opciones.soloCodigo ? codigoDeError(texto) : texto.slice(0, 2000));
    throw new Rechazo(502, 'El agente no pudo contestar. Intenta de nuevo.');
  }
  return JSON.parse(texto) as Record<string, unknown>;
}

function codigoDeError(texto: string): string {
  try {
    const { error } = JSON.parse(texto) as { error?: { type?: unknown; code?: unknown; param?: unknown } };
    return JSON.stringify({ type: error?.type ?? null, code: error?.code ?? null, param: error?.param ?? null });
  } catch {
    return 'sin JSON';
  }
}

// ─── El agente: Responses API ─────────────────────────────────────────────────

// Lo que entra y sale de la Responses API. Los items de la salida (lo que razonó, las llamadas a
// herramientas y los mensajes) se le regresan tal cual en la siguiente ronda: con store: false,
// OpenAI no guarda nada y lo razonado viaja cifrado.
export type Item = Record<string, unknown> & { type?: string };

export type Ronda = { items: Item[]; texto: string; llamadas: Llamada[]; tokens: Tokens };
export type Llamada = { call_id: string; name: string; arguments: string };

export async function rondaDelAgente(
  env: Env,
  peticion: { instrucciones: string; entrada: Item[]; herramientas: readonly unknown[]; sinHerramientas: boolean; cache: string },
): Promise<Ronda> {
  const modelo = modeloAgente(env);
  const r = await pedir(env, 'responses', {
    model: modelo,
    instructions: peticion.instrucciones,
    input: peticion.entrada,
    tools: peticion.herramientas,
    tool_choice: peticion.sinHerramientas ? 'none' : 'auto',
    store: false,
    include: ['reasoning.encrypted_content'],
    max_output_tokens: 25_000,
    prompt_cache_key: peticion.cache,
  });

  const uso = (r.usage ?? {}) as Record<string, Record<string, unknown> | unknown>;
  const detalle = (uso.input_tokens_details ?? {}) as Record<string, unknown>;
  const t = tokens(modelo, uso.input_tokens, detalle.cached_tokens, detalle.cache_write_tokens, uso.output_tokens, r.usage);

  if (r.status !== 'completed') {
    console.error('[agente] OpenAI no terminó la respuesta', r.status, JSON.stringify(r.incomplete_details ?? r.error ?? null));
    throw new RondaFallida(t);
  }

  const items = Array.isArray(r.output) ? (r.output as Item[]) : [];
  const llamadas: Llamada[] = [];
  let texto = '';
  for (const item of items) {
    if (item.type === 'function_call') {
      llamadas.push({ call_id: String(item.call_id ?? ''), name: String(item.name ?? ''), arguments: String(item.arguments ?? '') });
    } else if (item.type === 'message' && Array.isArray(item.content)) {
      for (const parte of item.content as Record<string, unknown>[]) {
        if (parte.type === 'output_text' && typeof parte.text === 'string') texto += parte.text;
      }
    }
  }
  return { items, texto: texto.trim(), llamadas, tokens: t };
}

// Una ronda que OpenAI cobró pero no terminó: lleva sus tokens para anotarlos igual.
export class RondaFallida extends Error {
  constructor(readonly tokens: Tokens) {
    super('OpenAI no terminó la respuesta');
  }
}

// ─── El saludo: Chat Completions ──────────────────────────────────────────────

export async function saludoDeLaIa(env: Env, instrucciones: string): Promise<{ texto: string | null; tokens: Tokens }> {
  const modelo = modeloSaludo(env);
  const r = await pedir(env, 'chat/completions', {
    model: modelo,
    messages: [
      { role: 'system', content: instrucciones },
      { role: 'user', content: 'Escribe el renglón.' },
    ],
    // El modelo piensa antes de escribir: con 40 se gastaba todo pensando y regresaba vacío.
    max_completion_tokens: 400,
    store: false,
  });
  const uso = (r.usage ?? {}) as Record<string, unknown>;
  const detalle = (uso.prompt_tokens_details ?? {}) as Record<string, unknown>;
  const t = tokens(modelo, uso.prompt_tokens, detalle.cached_tokens, detalle.cache_write_tokens, uso.completion_tokens, r.usage);
  const eleccion = (Array.isArray(r.choices) ? r.choices[0] : null) as { message?: { content?: unknown }; finish_reason?: unknown } | null;
  const texto = typeof eleccion?.message?.content === 'string' ? eleccion.message.content : null;
  if (!texto) console.warn('[saludo] OpenAI no escribió nada', eleccion?.finish_reason, JSON.stringify(r.usage ?? null));
  return { texto, tokens: t };
}

// ─── El asistente del menú: Responses API con salida estructurada ─────────────

// Lo que regresa el modelo: su texto y los números de los productos que nombró, en ese orden.
const SALIDA_ASISTENTE = {
  type: 'json_schema',
  name: 'respuesta_del_asistente',
  strict: true,
  schema: {
    type: 'object',
    additionalProperties: false,
    required: ['respuesta', 'productos'],
    properties: {
      respuesta: { type: 'string' },
      productos: { type: 'array', items: { type: 'integer' } },
    },
  },
} as const;

// Una sola llamada por pregunta, con su razonamiento de siempre, como el saludo. Hasta 4,000
// tokens de salida: lo peor que cuesta una pregunta es medio centavo de dólar. Si OpenAI no la
// terminó, se negó o no trajo el JSON pedido, regresa null con lo que cobró, para anotarlo como
// menu_sin_respuesta. Nada de lo que escribió la clienta ni el modelo pasa al registro.
export async function respuestaDelAsistente(
  env: Env,
  peticion: { instrucciones: string; entrada: Item[]; cache: string },
): Promise<{ salida: { respuesta: string; productos: unknown[] } | null; tokens: Tokens }> {
  const modelo = modeloAsistente(env);
  const r = await pedir(
    env,
    'responses',
    {
      model: modelo,
      instructions: peticion.instrucciones,
      input: peticion.entrada,
      text: { format: SALIDA_ASISTENTE },
      store: false,
      max_output_tokens: 4_000,
      prompt_cache_key: peticion.cache,
    },
    { soloCodigo: true, espera: 45_000 },
  );

  const uso = (r.usage ?? {}) as Record<string, Record<string, unknown> | unknown>;
  const detalle = (uso.input_tokens_details ?? {}) as Record<string, unknown>;
  const t = tokens(modelo, uso.input_tokens, detalle.cached_tokens, detalle.cache_write_tokens, uso.output_tokens, r.usage);

  if (r.status !== 'completed') {
    const incompleta = (r.incomplete_details ?? {}) as { reason?: unknown };
    const error = (r.error ?? {}) as { code?: unknown };
    console.error('[asistente] OpenAI no terminó la respuesta', r.status, incompleta.reason ?? null, error.code ?? null);
    return { salida: null, tokens: t };
  }

  let texto = '';
  for (const item of Array.isArray(r.output) ? (r.output as Item[]) : []) {
    if (item.type !== 'message' || !Array.isArray(item.content)) continue;
    for (const parte of item.content as Record<string, unknown>[]) {
      if (parte.type === 'refusal') {
        console.warn('[asistente] OpenAI se negó a contestar');
        return { salida: null, tokens: t };
      }
      if (parte.type === 'output_text' && typeof parte.text === 'string') texto += parte.text;
    }
  }
  try {
    const salida = JSON.parse(texto) as { respuesta?: unknown; productos?: unknown };
    if (typeof salida.respuesta === 'string' && salida.respuesta.trim() && Array.isArray(salida.productos)) {
      return { salida: { respuesta: salida.respuesta.trim(), productos: salida.productos }, tokens: t };
    }
  } catch {
    // Abajo se registra igual que un JSON sin respuesta.
  }
  console.error('[asistente] OpenAI no regresó el JSON pedido', texto ? `(${texto.length} letras)` : '(vacío)');
  return { salida: null, tokens: t };
}

// ─── El paso de texto de los anuncios: Responses API con salida estructurada ──

// Una llamada con razonamiento bajo y 30 segundos de espera. Regresa el objeto que escribió el
// modelo (lo revisa anuncios/palabras.ts) o null si no lo terminó, se negó o no trajo JSON, con lo
// que cobró. Si OpenAI contesta con error, lanza Rechazo como las demás.
export async function palabrasDeLaIa(
  env: Env,
  peticion: { instrucciones: string; pregunta: string; esquema: unknown },
): Promise<{ salida: Record<string, unknown> | null; tokens: Tokens }> {
  const modelo = modeloPalabras(env);
  const r = await pedir(
    env,
    'responses',
    {
      model: modelo,
      instructions: peticion.instrucciones,
      input: [{ role: 'user', content: peticion.pregunta }],
      text: { format: peticion.esquema },
      reasoning: { effort: 'low' },
      store: false,
      max_output_tokens: 2_000,
    },
    { soloCodigo: true, espera: 30_000 },
  );

  const uso = (r.usage ?? {}) as Record<string, Record<string, unknown> | unknown>;
  const detalle = (uso.input_tokens_details ?? {}) as Record<string, unknown>;
  const t = tokens(modelo, uso.input_tokens, detalle.cached_tokens, detalle.cache_write_tokens, uso.output_tokens, r.usage);

  if (r.status !== 'completed') {
    const incompleta = (r.incomplete_details ?? {}) as { reason?: unknown };
    console.error('[anuncios] OpenAI no terminó las palabras', r.status, incompleta.reason ?? null);
    return { salida: null, tokens: t };
  }
  let texto = '';
  for (const item of Array.isArray(r.output) ? (r.output as Item[]) : []) {
    if (item.type !== 'message' || !Array.isArray(item.content)) continue;
    for (const parte of item.content as Record<string, unknown>[]) {
      if (parte.type === 'refusal') {
        console.warn('[anuncios] OpenAI se negó a escoger las palabras');
        return { salida: null, tokens: t };
      }
      if (parte.type === 'output_text' && typeof parte.text === 'string') texto += parte.text;
    }
  }
  try {
    const salida: unknown = JSON.parse(texto);
    if (salida && typeof salida === 'object' && !Array.isArray(salida)) return { salida: salida as Record<string, unknown>, tokens: t };
  } catch {
    // Abajo se registra igual que un JSON que no es objeto.
  }
  console.error('[anuncios] OpenAI no regresó el JSON de las palabras', texto ? `(${texto.length} letras)` : '(vacío)');
  return { salida: null, tokens: t };
}

// ─── La imagen del anuncio: la API de imágenes ────────────────────────────────

// Los tokens que reporta la API de imágenes, como los piden terminar_anuncio y fallar_anuncio.
export type TokensImagen = { texto: number; imagen: number; salida: number };
export const SIN_TOKENS_IMAGEN: TokensImagen = { texto: 0, imagen: 0, salida: 0 };

export type Foto = { nombre: string; tipo: string; bytes: ArrayBuffer };
export type ImagenHecha =
  | { ok: true; jpg: Uint8Array; tokens: TokensImagen }
  | { ok: false; motivo: 'rechazado' | 'no_salio'; tokens: TokensImagen };

// Hasta 10 minutos de espera: después cuenta como que no salió (Postgres lo suelta a los 15).
const ESPERA_IMAGEN = 10 * 60 * 1000;

// Una imagen en calidad high, JPG 92, del tamaño de su formato: con fotos por images/edits (en el
// orden de sus productos), sin fotos por images/generations. Lleva el restaurante con hash en
// `user`, para que OpenAI pueda frenar a uno sin cortar la llave de todos. Nunca lanza: cada falla
// queda en el registro con su código, sin el prompt. «rechazado» es el moderation_blocked de
// OpenAI; todo lo demás, «no_salio».
export async function imagenDelAnuncio(
  env: Env,
  peticion: { prompt: string; fotos: Foto[]; tamano: string; usuario: string },
): Promise<ImagenHecha> {
  const modelo = modeloImagen(env);
  const campos = { model: modelo, prompt: peticion.prompt, size: peticion.tamano, quality: 'high', output_format: 'jpeg', n: 1, user: peticion.usuario };
  let respuesta: Response;
  try {
    let cuerpo: BodyInit;
    const encabezados: Record<string, string> = { Authorization: `Bearer ${llave(env)}` };
    if (peticion.fotos.length) {
      const forma = new FormData();
      for (const [campo, valor] of Object.entries(campos)) forma.append(campo, String(valor));
      forma.append('output_compression', '92');
      for (const foto of peticion.fotos) forma.append('image[]', new File([foto.bytes], foto.nombre, { type: foto.tipo }));
      cuerpo = forma;
    } else {
      cuerpo = JSON.stringify({ ...campos, output_compression: 92 });
      encabezados['Content-Type'] = 'application/json';
    }
    respuesta = await fetch(`https://api.openai.com/v1/images/${peticion.fotos.length ? 'edits' : 'generations'}`, {
      method: 'POST',
      headers: encabezados,
      body: cuerpo,
      signal: AbortSignal.timeout(ESPERA_IMAGEN),
    });
  } catch (e) {
    if (e instanceof DOMException && e.name === 'TimeoutError') {
      console.error(`[anuncios] OpenAI no entregó la imagen en ${ESPERA_IMAGEN / 60000} minutos; si cobró algo, no quedó anotado`);
    } else {
      console.error('[anuncios] no se pudo llamar a OpenAI para la imagen', e);
    }
    return { ok: false, motivo: 'no_salio', tokens: SIN_TOKENS_IMAGEN };
  }

  const texto = await respuesta.text();
  if (!respuesta.ok) {
    const codigo = codigoDeError(texto);
    console.error(`[anuncios] la imagen falló con ${respuesta.status}`, codigo);
    const rechazada = codigo.includes('"moderation_blocked"');
    return { ok: false, motivo: rechazada ? 'rechazado' : 'no_salio', tokens: SIN_TOKENS_IMAGEN };
  }

  let r: { data?: { b64_json?: unknown }[]; usage?: Record<string, unknown> };
  try {
    r = JSON.parse(texto) as typeof r;
  } catch {
    console.error('[anuncios] OpenAI contestó la imagen sin JSON', `(${texto.length} letras)`);
    return { ok: false, motivo: 'no_salio', tokens: SIN_TOKENS_IMAGEN };
  }
  const uso = r.usage ?? {};
  const detalle = (uso.input_tokens_details ?? {}) as Record<string, unknown>;
  const t: TokensImagen = { texto: numero(detalle.text_tokens), imagen: numero(detalle.image_tokens), salida: numero(uso.output_tokens) };
  if (!uso.input_tokens_details) console.warn('[anuncios] OpenAI no dijo los tokens de entrada de la imagen', JSON.stringify(uso));

  const base64 = r.data?.[0]?.b64_json;
  if (typeof base64 !== 'string' || !base64) {
    console.error('[anuncios] OpenAI no trajo la imagen', JSON.stringify(uso));
    return { ok: false, motivo: 'no_salio', tokens: t };
  }
  // atob y un ciclo: lo que se midió en 1–2 ms para un JPG de 350 KB (los 10 ms del paso alcanzan).
  const binario = atob(base64);
  const jpg = new Uint8Array(binario.length);
  for (let i = 0; i < binario.length; i++) jpg[i] = binario.charCodeAt(i);
  if (jpg.byteLength < 3 || jpg[0] !== 0xff || jpg[1] !== 0xd8 || jpg[2] !== 0xff) {
    console.error('[anuncios] lo que trajo OpenAI no es un JPG', jpg.byteLength);
    return { ok: false, motivo: 'no_salio', tokens: t };
  }
  return { ok: true, jpg, tokens: t };
}
