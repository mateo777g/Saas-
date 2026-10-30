// Cómo contesta el Worker: siempre JSON, con el permiso del navegador (CORS) solo para las páginas
// de la lista ORIGENES, y los errores en español, listos para la caja de error de la app.

// Un «no» con su código HTTP y el texto que ve Don Chuy. Se lanza desde cualquier trabajo y
// index.ts lo convierte en respuesta.
export class Rechazo extends Error {
  constructor(
    readonly estado: number,
    mensaje: string,
  ) {
    super(mensaje);
  }
}

export const SIN_PERMISO = 'No tienes permiso';

export function json(cuerpo: unknown, estado = 200): Response {
  return new Response(JSON.stringify(cuerpo), {
    status: estado,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  });
}

export function error(estado: number, mensaje: string): Response {
  return json({ error: mensaje }, estado);
}

// ¿Esta página puede llamar al Worker? Solo las de la app (y el localhost mientras se
// desarrolla). Una llamada sin Origin no viene de una página, así que tampoco se atiende.
export function origenPermitido(origen: string | null, origenes: string): origen is string {
  if (!origen) return false;
  return origenes.split(',').some((permitido) => permitido.trim() === origen);
}

// La respuesta del navegador antes de un GET, un POST o un DELETE con sesión: qué se permite mandar.
export function preflight(origen: string): Response {
  return new Response(null, {
    status: 204,
    headers: {
      'Access-Control-Allow-Origin': origen,
      'Access-Control-Allow-Methods': 'GET, POST, DELETE',
      'Access-Control-Allow-Headers': 'Authorization, Content-Type',
      'Access-Control-Max-Age': '86400',
      Vary: 'Origin',
    },
  });
}

export function conCors(respuesta: Response, origen: string): Response {
  const nueva = new Response(respuesta.body, respuesta);
  nueva.headers.set('Access-Control-Allow-Origin', origen);
  nueva.headers.append('Vary', 'Origin');
  return nueva;
}
