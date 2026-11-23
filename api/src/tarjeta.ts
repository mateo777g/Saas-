// La tarjeta de lealtad del menú en línea (libreta 6, parte B). Cuatro trabajos, desde abremenu.com y sin sesión:
//  - POST /menu/tarjeta: «Sacar mi tarjeta» (nombre, teléfono y la casilla del aviso).
//  - POST /menu/tarjeta/codigo: «Recupera tu tarjeta» (su número; sale el código que confirma quien cobra).
//  - POST /menu/tarjeta/ver: la tarjeta del celular, con su historial, por su llave.
//  - POST /menu/tarjeta/borrar: «Borrar mi tarjeta», por su llave.
// Sacarla y pedir el código van como el pedido: primero Turnstile y después las dos marcas que cuentan el límite (3 por
// hora por celular, 10 por conexión, en Postgres). Ver y borrar no llevan Turnstile: la llave (32 bytes al azar que
// solo tiene ese celular) ya es la prueba. Postgres saca la llave y los códigos y decide todo; lo que contesta pasa tal
// cual, también sus «no». Nunca se registran el nombre, el teléfono ni la llave.
import type { Env } from './index';
import { hmacHex, leerCuerpo } from './equipo';
import { conexionDelLimite, MARCA_CELULAR, pimientaMarcas, revisarTurnstile } from './pedidos';
import { json, Rechazo } from './respuestas';
import { llamar } from './supabase';

// La llave de la tarjeta tiene la misma forma que la marca del celular: 32 bytes en base64url, 43 caracteres.
export const LLAVE_TARJETA = MARCA_CELULAR;
const NO_SE_SACO = 'No pudimos sacar tu tarjeta. Intenta otra vez.';
const SIN_CODIGO = 'No pudimos pedir tu código. Intenta otra vez.';

export async function tarjetaDelMenu(request: Request, env: Env, url: URL): Promise<Response> {
  if (request.method !== 'POST') throw new Rechazo(405, 'Ese trabajo solo acepta POST.');
  const trabajo = url.pathname.slice('/menu/tarjeta'.length);
  if (!['', '/codigo', '/ver', '/borrar'].includes(trabajo)) throw new Rechazo(404, 'Ese trabajo no existe.');
  const cuerpo = await leerCuerpo(request);
  const slug = cuerpo.slug;
  if (typeof slug !== 'string' || !slug.trim() || slug.length > 100) throw new Rechazo(400, 'Faltan los datos.');

  if (trabajo === '/ver' || trabajo === '/borrar') {
    const llave = typeof cuerpo.llave === 'string' && LLAVE_TARJETA.test(cuerpo.llave) ? cuerpo.llave : null;
    if (!llave) throw new Rechazo(400, 'Falta la llave de tu tarjeta');
    const funcion = trabajo === '/ver' ? 'mi_tarjeta' : 'borrar_mi_tarjeta';
    const respuesta = await llamar<{ ok?: boolean }>(env, 'worker', funcion, { p_slug: slug, p_llave: llave });
    if (trabajo === '/borrar' && respuesta?.ok) console.log('[tarjeta] borrada', slug);
    return json(respuesta);
  }

  const etiqueta = '[tarjeta]';
  const falla = trabajo === '' ? NO_SE_SACO : SIN_CODIGO;
  const marca = typeof cuerpo.marca === 'string' && MARCA_CELULAR.test(cuerpo.marca) ? cuerpo.marca : null;
  if (!marca) throw new Rechazo(400, 'Faltan las marcas');
  const telefono = typeof cuerpo.telefono === 'string' ? cuerpo.telefono.slice(0, 40) : '';
  const argumentos: Record<string, unknown> = { p_slug: slug, p_telefono: telefono };
  if (trabajo === '') {
    argumentos.p_nombre = typeof cuerpo.nombre === 'string' ? cuerpo.nombre.slice(0, 200) : '';
    argumentos.p_acepta = cuerpo.acepta === true;
  }

  const ip = request.headers.get('CF-Connecting-IP');
  if (!ip) {
    console.error(`${etiqueta} llegó sin CF-Connecting-IP`);
    throw new Rechazo(503, falla);
  }
  await revisarTurnstile(env, typeof cuerpo.turnstile === 'string' ? cuerpo.turnstile : '', ip, etiqueta, falla);

  const pimienta = pimientaMarcas(env, etiqueta, falla);
  argumentos.p_marca_celular = await hmacHex(pimienta, `celular:${marca}`);
  argumentos.p_marca_conexion = await hmacHex(pimienta, `conexion:${conexionDelLimite(ip)}`);

  const funcion = trabajo === '' ? 'sacar_tarjeta' : 'pedir_codigo_tarjeta';
  const respuesta = await llamar<{ ok?: boolean }>(env, 'worker', funcion, argumentos);
  if (respuesta?.ok) console.log(etiqueta, trabajo === '' ? 'sacada' : 'código pedido', slug);
  return json(respuesta);
}
