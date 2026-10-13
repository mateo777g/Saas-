// Las preguntas a Postgres. Siempre con la sesión de quien llama y la llave publicable, como la
// app: Postgres contesta con sus reglas de siempre (quién es gerente de qué restaurante y si su
// licencia funciona hoy). La llave secreta no se usa aquí (libreta 3).
import type { Env } from './index';
import { Rechazo, SIN_PERMISO } from './respuestas';

// La sesión que manda la app: «Authorization: Bearer <token de Supabase>».
export function leerSesion(request: Request): string {
  const encabezado = request.headers.get('Authorization') ?? '';
  const sesion = /^Bearer\s+(\S+)$/i.exec(encabezado)?.[1];
  if (!sesion) throw new Rechazo(401, 'Tu sesión venció. Vuelve a entrar.');
  return sesion;
}

// Llama a una función de Postgres que contesta sí o no (puedo_subir_foto, puedo_borrar_foto).
export async function preguntar(
  env: Env,
  sesion: string,
  funcion: string,
  argumentos: Record<string, unknown>,
): Promise<boolean> {
  const respuesta = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/${funcion}`, {
    method: 'POST',
    headers: {
      apikey: env.SUPABASE_LLAVE_PUBLICABLE,
      Authorization: `Bearer ${sesion}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(argumentos),
  });

  if (respuesta.status === 401) {
    console.warn(`[supabase] ${funcion}: sesión rechazada`, await respuesta.text());
    throw new Rechazo(401, 'Tu sesión venció. Vuelve a entrar.');
  }
  if (respuesta.status === 403) {
    console.warn(`[supabase] ${funcion}: sin permiso de ejecutarla`, await respuesta.text());
    throw new Rechazo(403, SIN_PERMISO);
  }
  if (!respuesta.ok) {
    console.error(`[supabase] ${funcion} falló con ${respuesta.status}`, await respuesta.text());
    throw new Rechazo(502, 'No pudimos revisar tu permiso. Intenta de nuevo.');
  }

  const valor: unknown = await respuesta.json();
  if (typeof valor !== 'boolean') {
    console.error(`[supabase] ${funcion} no contestó sí o no`, valor);
    throw new Rechazo(502, 'No pudimos revisar tu permiso. Intenta de nuevo.');
  }
  return valor;
}
