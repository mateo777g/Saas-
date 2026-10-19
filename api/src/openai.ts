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

async function pedir(env: Env, ruta: string, cuerpo: unknown): Promise<Record<string, unknown>> {
  const respuesta = await fetch(`https://api.openai.com/v1/${ruta}`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${llave(env)}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(cuerpo),
  });
  const texto = await respuesta.text();
  if (!respuesta.ok) {
    // El cuerpo de error de OpenAI no trae la llave: dice qué pasó (cuota, modelo, argumentos).
    console.error(`[openai] ${ruta} falló con ${respuesta.status}`, texto.slice(0, 2000));
    throw new Rechazo(502, 'El agente no pudo contestar. Intenta de nuevo.');
  }
  return JSON.parse(texto) as Record<string, unknown>;
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
    max_completion_tokens: 40,
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
