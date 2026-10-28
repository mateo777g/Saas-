// El asistente del menú en línea (libreta 6, parte 6c; sus decisiones en planes/trabajo/6c). Un solo
// trabajo:
//  - POST /menu/pregunta, desde pidemenu.mx, sin sesión: la señora Ramírez le pregunta al asistente.
// Como en los pedidos, en orden: revisa cada campo, pasa la revisión de Cloudflare (una por plática:
// con ella el Worker da un pase de una hora, amarrado a ese celular y a ese menú), saca las dos
// marcas y llama a preguntar_al_asistente con la llave secreta, que decide si se puede y ya cuenta
// la pregunta. Después, una sola llamada a OpenAI con el menú entero en el prompt, y anotar_uso_ia.
// El texto de la pregunta y el de la respuesta nunca se guardan ni pasan al registro.
import { anotar } from './agente';
import type { Env } from './index';
import { hmacHex, leerCuerpo } from './equipo';
import { respuestaDelAsistente, modeloAsistente } from './openai';
import type { Item } from './openai';
import { conexionDelLimite, MARCA_CELULAR, pimientaMarcas, revisarTurnstile } from './pedidos';
import { ahoraParaElPrompt, REGLAS_ASISTENTE, restauranteParaElPrompt } from './promptAsistente';
import type { MenuPublico } from './promptAsistente';
import { json, Rechazo } from './respuestas';
import { llamar } from './supabase';

const ETIQUETA = '[asistente]';
// El texto no lo ve ella: el menú escribe su aviso, en español o en inglés.
const NO_CONTESTO = 'No pude contestar. Vuelve a intentarlo.';
const LARGO_PREGUNTA = 300;
const LARGO_RESPUESTA = 2_000;
// Sus últimas 3 preguntas con sus 3 respuestas.
const MENSAJES_DE_PLATICA = 6;
const PRODUCTOS_POR_RESPUESTA = 4;
const VIGENCIA_PASE = 60 * 60;
const PASE = /^(\d{10})\.([0-9a-f]{64})$/;

type Respuesta = { ok: true; restaurante_id: string; menu: MenuPublico } | { ok: false; motivo: string };

export async function preguntaDelMenu(request: Request, env: Env, url: URL): Promise<Response> {
  if (request.method !== 'POST') throw new Rechazo(405, 'Ese trabajo solo acepta POST.');
  if (url.pathname !== '/menu/pregunta') throw new Rechazo(404, 'Ese trabajo no existe.');
  const cuerpo = await leerCuerpo(request);
  const slug = typeof cuerpo.slug === 'string' ? cuerpo.slug.trim().toLowerCase() : '';
  if (!slug || slug.length > 100) throw new Rechazo(400, 'Faltan los datos.');
  const pregunta = typeof cuerpo.pregunta === 'string' ? cuerpo.pregunta.trim() : '';
  if (!pregunta) throw new Rechazo(400, 'Escribe tu pregunta.');
  if (pregunta.length > LARGO_PREGUNTA) throw new Rechazo(400, 'La pregunta es muy larga. Hazla más corta.');
  const platica = leerPlatica(cuerpo.conversacion);
  const lengua = cuerpo.lengua === 'en' ? 'en' : 'es';
  const moneda = cuerpo.moneda === 'usd' ? 'usd' : 'mxn';
  const marca = typeof cuerpo.marca === 'string' && MARCA_CELULAR.test(cuerpo.marca) ? cuerpo.marca : null;
  if (!marca) throw new Rechazo(400, 'Faltan las marcas de la pregunta');

  const ip = request.headers.get('CF-Connecting-IP');
  if (!ip) {
    console.error(`${ETIQUETA} llegó sin CF-Connecting-IP`);
    throw new Rechazo(503, NO_CONTESTO);
  }

  // El pase de la plática, o la revisión de Cloudflare y un pase nuevo. Sin ninguno de los dos, el
  // menú hace la revisión y vuelve a mandar la pregunta.
  const llave = pimientaMarcas(env, ETIQUETA, NO_CONTESTO);
  let paseNuevo: { pase: string; pase_vence: string } | null = null;
  if (!(typeof cuerpo.pase === 'string' && (await paseValido(llave, cuerpo.pase, slug, marca)))) {
    if (typeof cuerpo.turnstile !== 'string') return json({ ok: false, motivo: 'pase' });
    await revisarTurnstile(env, cuerpo.turnstile, ip, ETIQUETA, NO_CONTESTO);
    paseNuevo = await darPase(llave, slug, marca);
  }

  const respuesta = await llamar<Respuesta>(env, 'worker', 'preguntar_al_asistente', {
    p_slug: slug,
    p_marca_celular: await hmacHex(llave, `celular:${marca}`),
    p_marca_conexion: await hmacHex(llave, `conexion:${conexionDelLimite(ip)}`),
  });
  if (!respuesta.ok) return json({ ...respuesta, ...paseNuevo });
  if (!respuesta.menu) {
    console.error(`${ETIQUETA} preguntar_al_asistente no trajo el menú`, slug);
    throw new Rechazo(502, NO_CONTESTO);
  }

  const entrada: Item[] = [
    { role: 'developer', content: ahoraParaElPrompt(respuesta.menu, lengua, moneda) },
    ...platica,
    { role: 'user', content: pregunta },
  ];
  const { salida, tokens } = await respuestaDelAsistente(env, {
    instrucciones: `${REGLAS_ASISTENTE}\n\n${restauranteParaElPrompt(respuesta.menu)}`,
    entrada,
    cache: respuesta.restaurante_id,
  });
  // Lo que OpenAI cobró se anota siempre; solo las contestadas cuentan en consultas_menu.
  await anotar(env, respuesta.restaurante_id, salida ? 'menu' : 'menu_sin_respuesta', modeloAsistente(env), tokens);
  if (!salida) throw new Rechazo(502, NO_CONTESTO);

  return json({
    ok: true,
    respuesta: salida.respuesta,
    productos: productosDelMenu(salida.productos, respuesta.menu),
    ...paseNuevo,
  });
}

// La plática que guarda su celular: solo el texto de ella y del asistente, lo último.
function leerPlatica(valor: unknown): Item[] {
  if (valor === undefined || valor === null) return [];
  if (!Array.isArray(valor)) throw new Rechazo(400, 'No pudimos leer la plática.');
  return valor.slice(-MENSAJES_DE_PLATICA).map((mensaje: unknown) => {
    const { rol, texto } = (mensaje ?? {}) as { rol?: unknown; texto?: unknown };
    if ((rol !== 'cliente' && rol !== 'asistente') || typeof texto !== 'string' || !texto.trim()) {
      throw new Rechazo(400, 'No pudimos leer la plática.');
    }
    return rol === 'cliente'
      ? { role: 'user', content: texto.trim().slice(0, LARGO_PREGUNTA) }
      : { role: 'assistant', content: texto.trim().slice(0, LARGO_RESPUESTA) };
  });
}

// Solo los productos que están en el menú, sin repetir, hasta 4, en el orden en que los nombró.
function productosDelMenu(nombrados: unknown[], menu: MenuPublico): number[] {
  const enElMenu = new Set(menu.categorias.flatMap((c) => c.productos.map((p) => p.id)));
  const productos: number[] = [];
  for (const id of nombrados) {
    if (typeof id === 'number' && enElMenu.has(id) && !productos.includes(id)) productos.push(id);
    if (productos.length === PRODUCTOS_POR_RESPUESTA) break;
  }
  return productos;
}

// El pase: hasta cuándo vale (en segundos) y su firma con la llave de las marcas, amarrada a ese
// menú y a la marca de ese celular. Pasar del wifi a los datos no lo cambia.
async function darPase(llave: string, slug: string, marca: string): Promise<{ pase: string; pase_vence: string }> {
  const vence = Math.floor(Date.now() / 1000) + VIGENCIA_PASE;
  return {
    pase: `${vence}.${await hmacHex(llave, `pase:${slug}:${marca}:${vence}`)}`,
    pase_vence: new Date(vence * 1000).toISOString(),
  };
}

async function paseValido(llave: string, pase: string, slug: string, marca: string): Promise<boolean> {
  const partes = PASE.exec(pase);
  if (!partes) return false;
  const vence = Number(partes[1]);
  const ahora = Math.floor(Date.now() / 1000);
  if (vence <= ahora || vence > ahora + VIGENCIA_PASE) return false;
  return mismoTexto(await hmacHex(llave, `pase:${slug}:${marca}:${vence}`), partes[2]);
}

// Compara las dos firmas sin salirse antes, para que el tiempo no diga cuántas letras atinó.
function mismoTexto(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diferencia = 0;
  for (let i = 0; i < a.length; i++) diferencia |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diferencia === 0;
}
