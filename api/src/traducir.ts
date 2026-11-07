// Mi menú (decidido el 6 y el 7 de noviembre de 2026; planes/trabajo/rediseno/mi-menu.md). Dos trabajos:
//  - POST /menu/traducir {restaurante}, con la sesión de Don Chuy: el inglés de su menú. La app lo pide al
//    abrir Mi menú y después de cada «Guardar», sin esperarlo. Postgres dice qué falta y si el sobre del
//    asistente alcanza (pendientes_de_traducir); si no falta nada o no alcanza, no se llama a OpenAI. Si
//    sí: una llamada a gpt-5.6-luna con hasta 20 renglones, guardar_traducciones con la llave secreta
//    (que nunca pisa lo que él cambió o escribió mientras) y el gasto en el sobre del menú, sin contar
//    una pregunta. Regresa {quedan}: la app vuelve a pedir mientras baje.
//  - El dólar del día, en el Cron diario (index.ts): Frankfurter → fijar_tipo_de_cambio. Si no contesta
//    o contesta algo raro, se queda el último y se anota.
import { anotar } from './agente';
import { leerCuerpo } from './equipo';
import type { Env } from './index';
import { modeloTraduccion, traduccionDeLaIa } from './openai';
import { json, Rechazo } from './respuestas';
import { leerSesion, llamar } from './supabase';

const ETIQUETA = '[traducir]';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const TIPOS = new Set(['categoria', 'producto', 'grupo', 'opcion']);

type Pendiente = { tipo: string; id: number; nombre: string; descripcion?: string; grupo?: string };
type Pendientes = { puede: boolean; motivo: string | null; quedan: number; pendientes: Pendiente[] };

// La regla 4 de mi-menu.md: los nombres mexicanos no se inventan, la descripción sí se traduce completa.
export const REGLAS_TRADUCCION = `Traduces al inglés americano el menú de un restaurante mexicano: categorías, productos con su descripción, grupos de opciones y sus opciones. Lo lee un turista en su celular.

REGLAS:
- Los nombres de platillos y bebidas mexicanos no se inventan: se quedan como se dicen en México, en el orden natural del inglés. "Taco al pastor" sale "Al pastor taco", "Tacos de suadero" sale "Suadero tacos", "Horchata" se queda "Horchata", "Gringa", "Quesadilla", "Tlayuda", "Pozole" y "Chilaquiles" se quedan igual. "Agua de horchata" sale "Horchata"; "Agua de jamaica", "Hibiscus water".
- Lo que tiene una palabra común en inglés se traduce: "Bebidas" sale "Drinks", "Postres" sale "Desserts", "Refresco" sale "Soda", "Verde" sale "Green", "Roja" sale "Red", "Maíz" sale "Corn", "Harina" sale "Flour", "Chico" sale "Small".
- Las descripciones se traducen completas, con lo que dicen y nada más: no agregues ingredientes, sabores ni adjetivos. Las medidas y los números se quedan igual ("500 ml", "3 piezas" sale "3 pieces").
- Cada opción trae el grupo al que pertenece, para que sepas de qué es ("Verde" en "Salsa" es "Green").
- Escribe como en un menú: corto, con mayúscula al principio y sin punto al final de un nombre.
- Regresa cada renglón con su mismo tipo y su mismo número. descripcion_en va en null cuando el renglón no trae descripción.`;

export async function traducirMenu(request: Request, env: Env, url: URL): Promise<Response> {
  if (request.method !== 'POST') throw new Rechazo(405, 'Ese trabajo solo acepta POST.');
  if (url.pathname !== '/menu/traducir') throw new Rechazo(404, 'Ese trabajo no existe.');
  const sesion = leerSesion(request);
  const cuerpo = await leerCuerpo(request);
  const restaurante = typeof cuerpo.restaurante === 'string' ? cuerpo.restaurante : '';
  if (!UUID.test(restaurante)) throw new Rechazo(400, 'Falta el restaurante.');

  const lista = await llamar<Pendientes>(env, { sesion }, 'pendientes_de_traducir', { p_restaurante_id: restaurante });
  const pendientes = (Array.isArray(lista.pendientes) ? lista.pendientes : []).filter(
    (p) => p && TIPOS.has(p.tipo) && Number.isSafeInteger(p.id) && typeof p.nombre === 'string' && p.nombre.trim(),
  );
  if (!lista.puede || !pendientes.length) return json({ quedan: lista.quedan, puede: lista.puede, motivo: lista.motivo });

  const modelo = modeloTraduccion(env);
  const { salida, tokens } = await traduccionDeLaIa(env, { instrucciones: REGLAS_TRADUCCION, renglones: renglonesParaTraducir(pendientes) });
  // Lo que OpenAI cobró se anota siempre, en el sobre del menú y sin contar una pregunta.
  if (tokens.entrada || tokens.salida) await anotar(env, restaurante, 'menu_sin_respuesta', modelo, tokens);
  if (!salida) throw new Rechazo(502, 'No pudimos traducir tu menú. Se intenta otra vez al abrirlo.');

  const traducciones = juntar(pendientes, salida);
  let escritas = 0;
  if (traducciones.length) {
    escritas = await llamar<number>(env, 'worker', 'guardar_traducciones', {
      p_restaurante_id: restaurante,
      p_traducciones: traducciones,
    });
  }
  if (escritas < pendientes.length) {
    // Normal si Don Chuy cambió algo mientras; si pasa siempre, el modelo está regresando de menos.
    console.warn(ETIQUETA, `se escribieron ${escritas} de ${pendientes.length}`, restaurante);
  }
  return json({ quedan: Math.max(0, lista.quedan - escritas), escritas });
}

// Los renglones como los lee el modelo: uno por línea, en JSON, con solo lo que hace falta.
export function renglonesParaTraducir(pendientes: Pendiente[]): string {
  return pendientes
    .map((p) =>
      JSON.stringify({
        tipo: p.tipo,
        id: p.id,
        nombre: p.nombre,
        ...(p.descripcion ? { descripcion: p.descripcion } : {}),
        ...(p.grupo ? { grupo: p.grupo } : {}),
      }),
    )
    .join('\n');
}

// Lo que tradujo el modelo, con el español que se le mandó (nunca el que él diga): así Postgres compara
// contra lo que de verdad se tradujo. Lo que no pidió, lo repetido o un inglés vacío no pasa.
export function juntar(pendientes: Pendiente[], salida: unknown[]): Record<string, unknown>[] {
  const porClave = new Map(pendientes.map((p) => [`${p.tipo}:${p.id}`, p]));
  const vistas = new Set<string>();
  const juntas: Record<string, unknown>[] = [];
  for (const t of salida) {
    if (!t || typeof t !== 'object') continue;
    const { tipo, id, nombre_en, descripcion_en } = t as Record<string, unknown>;
    const clave = `${String(tipo)}:${String(id)}`;
    const p = porClave.get(clave);
    if (!p || vistas.has(clave) || typeof nombre_en !== 'string' || !nombre_en.trim()) continue;
    vistas.add(clave);
    juntas.push({
      tipo: p.tipo,
      id: p.id,
      nombre: p.nombre,
      descripcion: p.descripcion ?? null,
      nombre_en: nombre_en.trim(),
      descripcion_en: p.descripcion && typeof descripcion_en === 'string' && descripcion_en.trim() ? descripcion_en.trim() : null,
    });
  }
  return juntas;
}

// ─── El dólar del día ─────────────────────────────────────────────────────────

const FRANKFURTER = 'https://api.frankfurter.dev/v1/latest?base=USD&symbols=MXN';

// Nunca lanza: si algo falla se anota y se queda el último dólar, y el Cron sigue con lo suyo. Un
// número fuera de 5 a 100 pesos se toma como respuesta rara.
export async function dolarDelDia(env: Env): Promise<void> {
  let pesos: unknown;
  try {
    const respuesta = await fetch(FRANKFURTER, { signal: AbortSignal.timeout(10_000) });
    if (!respuesta.ok) {
      console.error(ETIQUETA, `Frankfurter contestó ${respuesta.status}: se queda el dólar de ayer`);
      return;
    }
    const datos = (await respuesta.json()) as { rates?: { MXN?: unknown } };
    pesos = datos.rates?.MXN;
  } catch (e) {
    console.error(ETIQUETA, 'Frankfurter no contestó: se queda el dólar de ayer', e);
    return;
  }
  if (typeof pesos !== 'number' || !Number.isFinite(pesos) || pesos < 5 || pesos > 100) {
    console.error(ETIQUETA, 'Frankfurter dio un dólar raro: se queda el de ayer', JSON.stringify(pesos));
    return;
  }
  try {
    const quedo = await llamar<number>(env, 'worker', 'fijar_tipo_de_cambio', { p_pesos: pesos });
    console.log(ETIQUETA, 'el dólar del día:', quedo);
  } catch (e) {
    console.error(ETIQUETA, 'no se pudo guardar el dólar del día: se queda el de ayer', pesos, e);
  }
}
