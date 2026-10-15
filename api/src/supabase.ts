// Las preguntas a Postgres y a Supabase Auth. Casi siempre con la sesión de quien llama y la llave
// publicable, como la app: Postgres contesta con sus reglas de siempre (quién es gerente de qué
// restaurante y si su licencia funciona hoy). La llave secreta solo la usan admin() (crear la
// cuenta de un empleado y su sesión) y llamar(…, 'worker', …) para las funciones del aparato, que
// no tiene sesión y que ningún usuario puede ejecutar (libreta 3).
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

// Llama a una función de Postgres y regresa lo que contesta: con la sesión de quien llama, o
// como el Worker (service_role, con la llave secreta) para las funciones del aparato. Los «no» de
// Postgres llegan como Rechazo con su texto en español, listo para la caja de error de la app.
export async function llamar<T = unknown>(
  env: Env,
  quien: { sesion: string } | 'worker',
  funcion: string,
  argumentos: Record<string, unknown>,
): Promise<T> {
  const respuesta = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/${funcion}`, {
    method: 'POST',
    headers:
      quien === 'worker'
        ? { apikey: llaveSecreta(env), 'Content-Type': 'application/json' }
        : { apikey: env.SUPABASE_LLAVE_PUBLICABLE, Authorization: `Bearer ${quien.sesion}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(argumentos),
  });
  if (respuesta.ok) {
    const texto = await respuesta.text();
    return (texto ? JSON.parse(texto) : null) as T;
  }
  if (respuesta.status === 401) {
    console.warn(`[supabase] ${funcion}: sesión rechazada`, await respuesta.text());
    throw new Rechazo(401, 'Tu sesión venció. Vuelve a entrar.');
  }
  throw await rechazoDePostgres(funcion, respuesta);
}

// Lo que Postgres contestó con error, en español. Los mensajes de nuestras funciones ya vienen en
// español; los de Postgres se traducen por su código, y lo inesperado queda en el registro.
async function rechazoDePostgres(funcion: string, respuesta: Response): Promise<Rechazo> {
  const crudo = await respuesta.text();
  let error: { code?: string; message?: string } = {};
  try {
    error = JSON.parse(crudo) as typeof error;
  } catch {
    // Se queda vacío y cae en «Algo salió mal».
  }
  const mensaje = error.message ?? '';
  switch (error.code) {
    case '42501':
      console.warn(`[supabase] ${funcion}: sin permiso`, mensaje);
      return new Rechazo(403, mensaje.startsWith('permission denied') ? SIN_PERMISO : mensaje);
    case 'P0002':
      return new Rechazo(404, mensaje);
    case '22023':
      return new Rechazo(400, mensaje);
    case '23505':
      if (mensaje.includes('miembros_nombre_unico')) return new Rechazo(400, 'Ya hay alguien en tu equipo con ese nombre.');
      if (mensaje.includes('dispositivos_nombre_unico')) return new Rechazo(400, 'Ya hay un aparato con ese nombre. Pídele a tu gerente otro código.');
      if (!mensaje.startsWith('duplicate key')) return new Rechazo(400, mensaje);
  }
  console.error(`[supabase] ${funcion} falló con ${respuesta.status}`, crudo);
  return new Rechazo(502, 'Algo salió mal. Intenta de nuevo.');
}

// Supabase Auth como administrador, con la llave secreta: crear y borrar la cuenta de un empleado,
// y el enlace mágico de su sesión (generate_link nunca manda correos).
export async function admin<T = unknown>(env: Env, metodo: 'POST' | 'DELETE', ruta: string, cuerpo?: unknown): Promise<T> {
  const respuesta = await fetch(`${env.SUPABASE_URL}/auth/v1${ruta}`, {
    method: metodo,
    headers: { apikey: llaveSecreta(env), 'Content-Type': 'application/json' },
    body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo),
  });
  const texto = await respuesta.text();
  if (!respuesta.ok) {
    console.error(`[auth] ${metodo} ${ruta} falló con ${respuesta.status}`, texto);
    throw new Rechazo(502, 'Algo salió mal. Intenta de nuevo.');
  }
  return (texto ? JSON.parse(texto) : null) as T;
}

export type Sesion = {
  access_token: string;
  refresh_token: string;
  expires_in: number;
  expires_at?: number;
  token_type: string;
};

// Canjea el enlace mágico por una sesión, como lo haría el navegador al abrirlo.
export async function verificar(env: Env, tipo: string, tokenHash: string): Promise<Sesion> {
  const respuesta = await fetch(`${env.SUPABASE_URL}/auth/v1/verify`, {
    method: 'POST',
    headers: { apikey: env.SUPABASE_LLAVE_PUBLICABLE, 'Content-Type': 'application/json' },
    body: JSON.stringify({ type: tipo, token_hash: tokenHash }),
  });
  const texto = await respuesta.text();
  if (!respuesta.ok) {
    console.error(`[auth] verify falló con ${respuesta.status}`, texto);
    throw new Rechazo(502, 'No pudimos abrir tu sesión. Intenta de nuevo.');
  }
  const sesion = JSON.parse(texto) as Partial<Sesion>;
  if (!sesion.access_token || !sesion.refresh_token) {
    console.error('[auth] verify no regresó la sesión', Object.keys(sesion));
    throw new Rechazo(502, 'No pudimos abrir tu sesión. Intenta de nuevo.');
  }
  return sesion as Sesion;
}

function llaveSecreta(env: Env): string {
  if (!env.SUPABASE_LLAVE_SECRETA) {
    console.error('[supabase] falta el secreto SUPABASE_LLAVE_SECRETA en Cloudflare');
    throw new Rechazo(500, 'Algo salió mal. Intenta de nuevo.');
  }
  return env.SUPABASE_LLAVE_SECRETA;
}
