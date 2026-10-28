// El agente IA (libreta 1, «Cómo las usa el modelo»; libreta 3, «El gasto de IA»). Dos trabajos,
// los dos con la sesión del gerente:
//  - POST /agente/pregunta {restaurante, pregunta, conversacion, periodo}: Don Chuy pregunta, el
//    modelo pide herramientas y el Worker se las pasa a Postgres (agente_herramienta) con la sesión
//    de Don Chuy, hasta que el modelo contesta con texto. Regresa la respuesta en Markdown, lo que
//    leyó para responder, si todavía queda tope y la fecha y la hora del restaurante.
//  - POST /agente/saludo {restaurante}: el segundo renglón de la bienvenida. Si falla o no hay
//    tope, regresa null y la app pone el suyo, sin aviso.
// El Worker no decide nada: estado_ia dice si se puede, las herramientas hacen las cuentas y
// anotar_uso_ia saca el costo con los tokens que reportó OpenAI.
import type { Env } from './index';
import { leerCuerpo } from './equipo';
import { modeloAgente, modeloSaludo, rondaDelAgente, RondaFallida, saludoDeLaIa, SIN_TOKENS, sumar } from './openai';
import type { Item, Llamada, Tokens } from './openai';
import { conPeriodo, contextoParaElPrompt, HERRAMIENTAS, limpiarSaludo, PERIODOS, promptSaludo, REGLAS_AGENTE, ULTIMA_RONDA } from './prompt';
import { json, Rechazo } from './respuestas';
import { leerSesion, llamar } from './supabase';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
// Hasta 6 rondas con el modelo por pregunta; en la sexta ya no puede pedir herramientas.
const RONDAS = 6;
// Las herramientas que puede pedir una pregunta en total, para no pasar del límite de llamadas
// de un Worker gratis (50 por petición).
const HERRAMIENTAS_POR_PREGUNTA = 24;
const LARGO_PREGUNTA = 2_000;
// De la conversación solo van los últimos mensajes, cada uno recortado.
const MENSAJES_DE_CONVERSACION = 20;
const LARGO_MENSAJE = 8_000;
const NO_CONTESTO = 'El agente no pudo contestar. Intenta de nuevo.';

type Estado = { puede: boolean; motivo?: string; con_distribuidor?: boolean; vuelve?: string };
type Leido = { icono: string; texto: string };

export async function agente(request: Request, env: Env, url: URL): Promise<Response> {
  if (request.method !== 'POST') throw new Rechazo(405, 'Ese trabajo solo acepta POST.');
  const sesion = leerSesion(request);
  const cuerpo = await leerCuerpo(request);
  const restaurante = typeof cuerpo.restaurante === 'string' ? cuerpo.restaurante : '';
  if (!UUID.test(restaurante)) throw new Rechazo(400, 'Falta el restaurante.');

  if (url.pathname === '/agente/pregunta') return pregunta(env, sesion, restaurante, cuerpo);
  if (url.pathname === '/agente/saludo') return saludo(env, sesion, restaurante);
  throw new Rechazo(404, 'Ese trabajo no existe.');
}

async function pregunta(env: Env, sesion: string, restaurante: string, cuerpo: Record<string, unknown>): Promise<Response> {
  const texto = typeof cuerpo.pregunta === 'string' ? cuerpo.pregunta.trim() : '';
  if (!texto) throw new Rechazo(400, 'Escribe tu pregunta.');
  if (texto.length > LARGO_PREGUNTA) throw new Rechazo(400, 'La pregunta es muy larga. Hazla más corta.');
  const periodo = typeof cuerpo.periodo === 'string' && cuerpo.periodo in PERIODOS ? cuerpo.periodo : undefined;
  const conversacion = leerConversacion(cuerpo.conversacion);

  // Sin tope no se llama a OpenAI: la app pone el aviso con lo que dice estado_ia.
  const estado = await llamar<Estado>(env, { sesion }, 'estado_ia', { p_restaurante_id: restaurante });
  if (!estado.puede) return json(estado);

  const contexto = await llamar<{ ahora?: { fecha?: string; hora?: string } } | null>(
    env, { sesion }, 'contexto_agente', { p_restaurante_id: restaurante },
  );
  const instrucciones = `${REGLAS_AGENTE}\n\n${contextoParaElPrompt(contexto)}`;
  // La fecha y la hora del restaurante, para el Historial de la app (nunca el reloj del aparato).
  const ahora = contexto?.ahora?.fecha && contexto.ahora.hora ? { fecha: contexto.ahora.fecha, hora: contexto.ahora.hora } : null;
  const entrada: Item[] = [...conversacion, { role: 'user', content: conPeriodo(texto, periodo) }];
  const leido: Leido[] = [];
  let gastado = SIN_TOKENS;
  let pedidas = 0;

  try {
    for (let ronda = 1; ronda <= RONDAS; ronda++) {
      const ultima = ronda === RONDAS;
      if (ultima) entrada.push({ role: 'developer', content: ULTIMA_RONDA });
      const r = await rondaDelAgente(env, {
        instrucciones,
        entrada,
        herramientas: HERRAMIENTAS,
        sinHerramientas: ultima,
        cache: restaurante,
      });
      gastado = sumar(gastado, r.tokens);

      if (!r.llamadas.length) {
        if (!r.texto) {
          console.error('[agente] OpenAI contestó sin texto ni herramientas', JSON.stringify(r.items).slice(0, 2000));
          throw new Rechazo(502, NO_CONTESTO);
        }
        const puede = await anotar(env, restaurante, 'pregunta', modeloAgente(env), gastado);
        return json({ respuesta: r.texto, leido, puede: puede !== false, ahora });
      }

      // Lo que salió de esta ronda vuelve tal cual, y después lo que regresó cada herramienta.
      entrada.push(...r.items);
      for (const llamada of r.llamadas) {
        pedidas++;
        const salida =
          pedidas > HERRAMIENTAS_POR_PREGUNTA
            ? { error: 'Ya pediste demasiadas herramientas para esta pregunta: contesta con lo que ya tienes.' }
            : await usarHerramienta(env, sesion, restaurante, llamada, leido);
        entrada.push({ type: 'function_call_output', call_id: llamada.call_id, output: JSON.stringify(salida) });
      }
    }
    console.error('[agente] se acabaron las rondas sin respuesta', restaurante);
    throw new Rechazo(502, NO_CONTESTO);
  } catch (e) {
    // Lo que OpenAI ya cobró se anota aunque la pregunta no se haya contestado.
    if (e instanceof RondaFallida) gastado = sumar(gastado, e.tokens);
    if (gastado.entrada || gastado.salida) await anotar(env, restaurante, 'pregunta', modeloAgente(env), gastado);
    if (e instanceof RondaFallida) throw new Rechazo(502, NO_CONTESTO);
    throw e;
  }
}

// La conversación que guarda el navegador: solo el texto de Don Chuy y del agente.
function leerConversacion(valor: unknown): Item[] {
  if (valor === undefined || valor === null) return [];
  if (!Array.isArray(valor)) throw new Rechazo(400, 'No pudimos leer la conversación.');
  return valor.slice(-MENSAJES_DE_CONVERSACION).map((mensaje: unknown) => {
    const { rol, texto } = (mensaje ?? {}) as { rol?: unknown; texto?: unknown };
    if ((rol !== 'gerente' && rol !== 'agente') || typeof texto !== 'string' || !texto.trim()) {
      throw new Rechazo(400, 'No pudimos leer la conversación.');
    }
    return { role: rol === 'gerente' ? 'user' : 'assistant', content: texto.slice(0, LARGO_MENSAJE) };
  });
}

// Una herramienta, por la única puerta de Postgres y con la sesión del gerente: el modelo nunca
// elige el restaurante. Si la llamada viene mal, Postgres dice por qué y eso se le regresa al
// modelo para que corrija; si Supabase no contesta, un error genérico para que no invente.
async function usarHerramienta(env: Env, sesion: string, restaurante: string, llamada: Llamada, leido: Leido[]): Promise<unknown> {
  let argumentos: unknown;
  try {
    argumentos = llamada.arguments ? JSON.parse(llamada.arguments) : {};
  } catch {
    return { error: 'Los argumentos no son un JSON válido.' };
  }
  try {
    const resultado = await llamar<Record<string, unknown> | null>(env, { sesion }, 'agente_herramienta', {
      p_restaurante_id: restaurante,
      p_herramienta: llamada.name,
      p_argumentos: argumentos,
    });
    // «Lo que leí para responder» es para la app; al modelo le van solo los números.
    const { leido: renglon, ...numeros } = resultado ?? {};
    if (esLeido(renglon) && !leido.some((l) => l.texto === renglon.texto)) leido.push(renglon);
    return numeros;
  } catch (e) {
    if (e instanceof Rechazo && (e.estado === 400 || e.estado === 404)) return { error: e.message };
    if (e instanceof Rechazo && (e.estado === 401 || e.estado === 403)) throw e;
    if (!(e instanceof Rechazo)) console.error('[agente] la herramienta falló', llamada.name, e);
    return { error: 'No pude leer los datos en este momento.' };
  }
}

function esLeido(valor: unknown): valor is Leido {
  const l = valor as Leido | null;
  return !!l && typeof l.icono === 'string' && typeof l.texto === 'string';
}

async function saludo(env: Env, sesion: string, restaurante: string): Promise<Response> {
  const estado = await llamar<Estado>(env, { sesion }, 'estado_ia', { p_restaurante_id: restaurante });
  if (!estado.puede) return json({ saludo: null });

  const contexto = await llamar<{ ahora?: { hora?: string; dia_de_negocio_en_palabras?: string } } | null>(
    env,
    { sesion },
    'contexto_agente',
    { p_restaurante_id: restaurante },
  );
  const hora = Number.parseInt(contexto?.ahora?.hora ?? '', 10);
  const dia = (contexto?.ahora?.dia_de_negocio_en_palabras ?? '').split(' ')[0];
  if (!Number.isFinite(hora) || !dia) {
    console.error('[saludo] contexto_agente no trajo la hora', JSON.stringify(contexto?.ahora ?? null));
    return json({ saludo: null });
  }

  // Dos intentos, como en Flet: 1 de cada 3 se descartaba por colar un «¿listo para…?».
  let gastado = SIN_TOKENS;
  let texto: string | null = null;
  try {
    for (let intento = 0; intento < 2 && !texto; intento++) {
      const r = await saludoDeLaIa(env, promptSaludo(dia, hora));
      gastado = sumar(gastado, r.tokens);
      texto = limpiarSaludo(r.texto);
      if (!texto && r.texto) console.warn('[saludo] se descartó', JSON.stringify(r.texto));
    }
  } catch (e) {
    // Sin internet o sin cuota no tiene caso reintentar; lo de OpenAI ya quedó en el registro.
    if (!(e instanceof Rechazo)) console.error('[saludo] falló', e);
  }
  if (gastado.entrada || gastado.salida) await anotar(env, restaurante, 'saludo', modeloSaludo(env), gastado);
  return json({ saludo: texto });
}

// El gasto, con la llave secreta: Postgres saca el costo y dice si todavía queda tope. Nunca
// truena: si no se pudo anotar, queda en el registro con los tokens para anotarlo a mano. El
// asistente del menú la usa igual, con sus dos usos.
export async function anotar(
  env: Env,
  restaurante: string,
  uso: 'pregunta' | 'saludo' | 'menu' | 'menu_sin_respuesta',
  modelo: string,
  t: Tokens,
): Promise<boolean | null> {
  const etiqueta = uso === 'menu' || uso === 'menu_sin_respuesta' ? '[asistente]' : '[agente]';
  try {
    const r = await llamar<{ costo: unknown; puede: boolean }>(env, 'worker', 'anotar_uso_ia', {
      p_restaurante_id: restaurante,
      p_uso: uso,
      p_modelo: modelo,
      p_entrada: t.entrada,
      p_entrada_cache: t.entrada_cache,
      p_escritura_cache: t.escritura_cache,
      p_salida: t.salida,
    });
    console.log(`${etiqueta} gasto anotado`, uso, modelo, JSON.stringify(t), 'costo', r.costo);
    return r.puede;
  } catch (e) {
    console.error(`${etiqueta} no se pudo anotar el gasto`, uso, modelo, restaurante, JSON.stringify(t), e);
    return null;
  }
}
