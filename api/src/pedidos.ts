// El pedido del menú en línea por WhatsApp (libreta 6, parte 6b). Un solo trabajo:
//  - POST /menu/pedido, desde pidemenu.mx, sin sesión: la señora Ramírez toca «Hacer pedido».
// Primero la revisión de Cloudflare (Turnstile): si no pasa, no se toca la base. Después las dos
// marcas que cuentan el límite (3 pedidos por hora por celular, 10 por conexión), hechas aquí con
// la llave de las marcas: la conexión nunca se guarda, solo su marca, que no se puede revertir.
// Al final hacer_pedido como el Worker (la llave secreta). Postgres decide todo lo demás (horario,
// pausa, precios, agotados, el límite) y lo que contesta pasa tal cual, también sus «no».
import type { Env } from './index';
import { hmacHex, leerCuerpo } from './equipo';
import { json, Rechazo } from './respuestas';
import { llamar } from './supabase';

const SITEVERIFY = 'https://challenges.cloudflare.com/turnstile/v0/siteverify';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
// La marca del celular: 32 bytes al azar en base64url, guardados por el menú en pidemenu-marca.
const MARCA_CELULAR = /^[A-Za-z0-9_-]{43}$/;
const NO_ERES_TU = 'No pudimos revisar que eres tú. Intenta otra vez.';
const NO_SE_MANDO = 'No pudimos mandar tu pedido. Intenta otra vez.';
// Lo que dice Turnstile cuando el token no sirve (un robot, uno vencido o ya usado): es un «no»
// esperado. Cualquier otro código es nuestro (la llave secreta mal puesta) o suyo, y se registra.
const TOKEN_MALO = ['missing-input-response', 'invalid-input-response', 'timeout-or-duplicate'];

export async function pedidoDelMenu(request: Request, env: Env, url: URL): Promise<Response> {
  if (request.method !== 'POST') throw new Rechazo(405, 'Ese trabajo solo acepta POST.');
  if (url.pathname !== '/menu/pedido') throw new Rechazo(404, 'Ese trabajo no existe.');
  const cuerpo = await leerCuerpo(request);
  const argumentos = leerPedido(cuerpo);
  const marca = typeof cuerpo.marca === 'string' && MARCA_CELULAR.test(cuerpo.marca) ? cuerpo.marca : null;
  if (!marca) throw new Rechazo(400, 'Faltan las marcas del pedido');

  const ip = request.headers.get('CF-Connecting-IP');
  if (!ip) {
    console.error('[pedido] llegó sin CF-Connecting-IP');
    throw new Rechazo(503, NO_SE_MANDO);
  }
  await revisarTurnstile(env, typeof cuerpo.turnstile === 'string' ? cuerpo.turnstile : '', ip);

  const llave = pimientaMarcas(env);
  argumentos.p_marca_celular = await hmacHex(llave, `celular:${marca}`);
  argumentos.p_marca_conexion = await hmacHex(llave, `conexion:${ip}`);

  const respuesta = await llamar<{ ok?: boolean; numero?: number }>(env, 'worker', 'hacer_pedido', argumentos);
  if (respuesta?.ok) console.log('[pedido] guardado', argumentos.p_slug, respuesta.numero);
  return json(respuesta);
}

// Solo los campos de hacer_pedido, cada uno con su tipo, para que Postgres nunca reciba algo que no
// puede leer. Los límites (60 letras, 10 dígitos, 30 renglones…) los revisa Postgres con sus textos.
function leerPedido(cuerpo: Record<string, unknown>): Record<string, unknown> {
  const slug = cuerpo.slug;
  const clave = cuerpo.clave;
  if (typeof slug !== 'string' || !slug.trim() || slug.length > 100) throw new Rechazo(400, 'Faltan los datos.');
  if (typeof clave !== 'string' || !UUID.test(clave)) throw new Rechazo(400, 'Falta la clave del pedido');
  const pagaCon = cuerpo.paga_con ?? null;
  if (pagaCon !== null && (typeof pagaCon !== 'number' || !Number.isFinite(pagaCon))) {
    throw new Rechazo(400, 'Escribe con cuánto pagas, como 500');
  }
  const renglones = cuerpo.renglones;
  if (!Array.isArray(renglones) || !renglones.length) throw new Rechazo(400, 'Tu pedido está vacío');
  if (renglones.length > 30) throw new Rechazo(400, 'Un pedido lleva hasta 30 renglones');

  return {
    p_slug: slug,
    p_clave: clave,
    p_tipo: textoONulo(cuerpo.tipo),
    p_cliente_nombre: textoONulo(cuerpo.cliente_nombre),
    p_cliente_telefono: textoONulo(cuerpo.cliente_telefono),
    p_cliente_direccion: textoONulo(cuerpo.cliente_direccion),
    p_cliente_referencias: textoONulo(cuerpo.cliente_referencias),
    p_paga_con: pagaCon,
    p_renglones: renglones.map(leerRenglon),
  };
}

function leerRenglon(valor: unknown): Record<string, unknown> {
  if (!valor || typeof valor !== 'object' || Array.isArray(valor)) {
    throw new Rechazo(400, 'Cada renglón va con su producto y su cantidad');
  }
  const r = valor as Record<string, unknown>;
  if (!esId(r.producto_id) || typeof r.cantidad !== 'number' || !Number.isSafeInteger(r.cantidad)) {
    throw new Rechazo(400, 'Cada renglón va con su producto y su cantidad');
  }
  const opciones = r.opciones ?? [];
  if (!Array.isArray(opciones) || opciones.length > 50 || !opciones.every(esId)) {
    throw new Rechazo(400, 'Las opciones de cada renglón van en una lista');
  }
  if (typeof r.precio !== 'number' || !Number.isFinite(r.precio)) throw new Rechazo(400, 'Falta el precio de un renglón');
  return { producto_id: r.producto_id, cantidad: r.cantidad, opciones, nota: textoONulo(r.nota), precio: r.precio };
}

function esId(valor: unknown): valor is number {
  return typeof valor === 'number' && Number.isSafeInteger(valor) && valor > 0;
}

function textoONulo(valor: unknown): string | null {
  return typeof valor === 'string' ? valor.slice(0, 1000) : null;
}

// La revisión de Cloudflare. Si dice que no, es un «no» esperado y no se registra. Si no contesta,
// falla o la llave está mal puesta, se registra y ningún pedido entra sin ella (decidido el 25 de
// octubre de 2026).
async function revisarTurnstile(env: Env, token: string, ip: string): Promise<void> {
  if (!token || token.length > 2048) throw new Rechazo(403, NO_ERES_TU);
  if (!env.TURNSTILE_SECRETO) {
    console.error('[pedido] falta el secreto TURNSTILE_SECRETO en Cloudflare');
    throw new Rechazo(503, NO_SE_MANDO);
  }
  let resultado: { success?: boolean; 'error-codes'?: string[] };
  try {
    const respuesta = await fetch(SITEVERIFY, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ secret: env.TURNSTILE_SECRETO, response: token, remoteip: ip }),
      signal: AbortSignal.timeout(10_000),
    });
    if (!respuesta.ok) {
      console.error('[pedido] Turnstile contestó', respuesta.status, await respuesta.text());
      throw new Rechazo(503, NO_SE_MANDO);
    }
    resultado = (await respuesta.json()) as typeof resultado;
  } catch (e) {
    if (e instanceof Rechazo) throw e;
    console.error('[pedido] Turnstile no contestó', e);
    throw new Rechazo(503, NO_SE_MANDO);
  }
  if (resultado.success === true) return;
  const codigos = resultado['error-codes'] ?? [];
  if (codigos.length && codigos.every((c) => TOKEN_MALO.includes(c))) throw new Rechazo(403, NO_ERES_TU);
  console.error('[pedido] Turnstile falló', codigos);
  throw new Rechazo(503, NO_SE_MANDO);
}

function pimientaMarcas(env: Env): string {
  if (!env.PIMIENTA_MARCAS) {
    console.error('[pedido] falta el secreto PIMIENTA_MARCAS en Cloudflare');
    throw new Rechazo(503, NO_SE_MANDO);
  }
  return env.PIMIENTA_MARCAS;
}
