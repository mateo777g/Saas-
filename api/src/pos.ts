// Lo que pide PIN en el punto de venta (libreta 5, «Propinas, descuentos y cancelaciones»; parte
// 4c). Un solo trabajo:
//  - POST /pos/autorizar, con la sesión de quien pide (Pepe, en su celular): cancelar un renglón,
//    una cuenta o un pago, o hacer un descuento, con el PIN de Lupita o de Don Chuy puesto en el
//    celular de Pepe.
// El Worker no decide nada: mezcla el PIN con la llave de los PIN y llama a la función de Postgres
// con la sesión de Pepe. Postgres revisa quién pide, quién autoriza, el PIN y el bloqueo, y aplica
// el cambio en el mismo paso. Un PIN equivocado no es un error: llega como {ok:false} con los
// intentos que quedan, y se contesta igual. Si quien pide ya es de la caja o gerente, la app llama
// a Postgres directo, sin pasar por aquí.
import type { Env } from './index';
import { entero, leerCuerpo, mezclar, revisarPin } from './equipo';
import { json, Rechazo } from './respuestas';
import { leerSesion, llamar } from './supabase';

// Qué datos lleva cada función. El PIN mezclado y quién autoriza los pone el Worker, nunca la app.
const FUNCIONES: Record<string, string[]> = {
  cancelar_renglon: ['p_renglon_id', 'p_cantidad', 'p_motivo'],
  cancelar_cuenta: ['p_venta_id', 'p_motivo'],
  cancelar_pago: ['p_pago_id', 'p_motivo'],
  descontar: ['p_venta_id', 'p_renglon_id', 'p_tipo', 'p_valor', 'p_motivo'],
};

export async function pos(request: Request, env: Env, url: URL): Promise<Response> {
  if (request.method !== 'POST') throw new Rechazo(405, 'Ese trabajo solo acepta POST.');
  if (url.pathname !== '/pos/autorizar') throw new Rechazo(404, 'Ese trabajo no existe.');
  const sesion = leerSesion(request);
  const cuerpo = await leerCuerpo(request);

  const funcion = typeof cuerpo.funcion === 'string' ? cuerpo.funcion : '';
  const llaves = FUNCIONES[funcion];
  if (!llaves) throw new Rechazo(400, 'Eso no se autoriza con PIN.');
  const datos = cuerpo.datos;
  if (!datos || typeof datos !== 'object' || Array.isArray(datos)) throw new Rechazo(400, 'Faltan los datos.');
  const autoriza = entero(cuerpo.autoriza);
  const pin = typeof cuerpo.pin === 'string' ? cuerpo.pin : '';
  revisarPin(pin);

  const argumentos: Record<string, unknown> = {};
  for (const llave of llaves) argumentos[llave] = (datos as Record<string, unknown>)[llave] ?? null;
  argumentos.p_autoriza_id = autoriza;
  argumentos.p_pin_mezclado = await mezclar(env, pin);

  const respuesta = await llamar<{ ok?: boolean }>(env, { sesion }, funcion, argumentos);
  if (respuesta?.ok) console.log('[pos] autorizado', funcion, autoriza);
  return json(respuesta);
}
