// El equipo y sus aparatos (libreta 3, «El personal: aparato y PIN»; libreta 5, pieza 2). Cinco
// trabajos:
//  - POST /equipo/empleado, con la sesión del gerente: le crea su cuenta a Pepe (un correo interno
//    que nunca recibe nada y una contraseña al azar que nadie conoce) y lo anota en su equipo.
//  - POST /equipo/pin, con la sesión del gerente: le pone un PIN nuevo a alguien de su equipo, o
//    el suyo.
//  - POST /equipo/vincular, desde el aparato: Pepe escribe el código de 6 letras y el aparato
//    recibe su secreto.
//  - POST /equipo/nombres, desde el aparato: «¿Quién eres?».
//  - POST /equipo/entrar, desde el aparato: Pepe toca su nombre y pone su PIN; si Postgres dice
//    que sí, recibe su sesión de Supabase.
// El PIN nunca sale de aquí tal cual: se mezcla con la llave de los PIN (la pimienta) y Postgres
// guarda la huella. La llave secreta de Supabase se usa solo después de que Postgres dijo que sí,
// o para las funciones del aparato, que no tiene sesión y que solo el Worker puede llamar.
import type { Env } from './index';
import { json, Rechazo, SIN_PERMISO } from './respuestas';
import { admin, leerSesion, llamar, preguntar, verificar } from './supabase';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const ROLES = ['mesero', 'caja', 'cocina'];
// El secreto del aparato: 32 bytes al azar en base64url (lo mismo que exige la base).
const SECRETO_APARATO = /^[A-Za-z0-9_-]{43}$/;
// Los correos del personal nunca reciben nada: Supabase exige un correo para cada cuenta.
const DOMINIO_PERSONAL = 'personal.fragmentless.com';

export async function equipo(request: Request, env: Env, url: URL): Promise<Response> {
  if (request.method !== 'POST') throw new Rechazo(405, 'Ese trabajo solo acepta POST.');
  const cuerpo = await leerCuerpo(request);
  switch (url.pathname) {
    case '/equipo/empleado':
      return altaEmpleado(request, env, cuerpo);
    case '/equipo/pin':
      return asignarPin(request, env, cuerpo);
    case '/equipo/vincular':
      return vincular(env, cuerpo);
    case '/equipo/nombres':
      return nombres(env, cuerpo);
    case '/equipo/entrar':
      return entrar(env, cuerpo);
    default:
      throw new Rechazo(404, 'Ese trabajo no existe.');
  }
}

// «Agregar empleado»: primero Postgres dice si quien llama es gerente de ese restaurante; solo
// entonces se crea la cuenta con la llave secreta. Si anotarlo falla (un nombre repetido), la
// cuenta se borra para no dejarla suelta.
async function altaEmpleado(request: Request, env: Env, cuerpo: Record<string, unknown>): Promise<Response> {
  const sesion = leerSesion(request);
  const restaurante = texto(cuerpo.restaurante);
  const nombre = texto(cuerpo.nombre).trim();
  const roles = cuerpo.roles;
  const pin = texto(cuerpo.pin);
  if (!UUID.test(restaurante)) throw new Rechazo(400, 'Falta el restaurante.');
  if (!nombre) throw new Rechazo(400, 'Escribe el nombre.');
  if (!Array.isArray(roles) || !roles.length || !roles.every((r) => typeof r === 'string' && ROLES.includes(r))) {
    throw new Rechazo(400, 'Elige al menos un rol: mesero, caja o cocina.');
  }
  revisarPin(pin);

  if (!(await preguntar(env, sesion, 'puedo_cambiar_equipo', { p_restaurante_id: restaurante }))) {
    console.warn('[equipo] alta rechazada por Postgres', restaurante);
    throw new Rechazo(403, SIN_PERMISO);
  }

  const usuario = await admin<{ id?: string }>(env, 'POST', '/admin/users', {
    email: `${crypto.randomUUID()}@${DOMINIO_PERSONAL}`,
    password: alAzar(32),
    email_confirm: true,
    app_metadata: { personal: true },
  });
  if (!usuario.id) {
    console.error('[equipo] Supabase creó la cuenta sin id', usuario);
    throw new Rechazo(502, 'No pudimos crear la cuenta. Intenta de nuevo.');
  }

  try {
    const miembro = await llamar<number>(env, { sesion }, 'alta_empleado', {
      p_restaurante_id: restaurante,
      p_usuario_id: usuario.id,
      p_nombre: nombre,
      p_roles: roles,
      p_pin_mezclado: await mezclar(env, pin),
    });
    console.log('[equipo] alta', restaurante, miembro);
    return json({ miembro }, 201);
  } catch (e) {
    try {
      await admin(env, 'DELETE', `/admin/users/${usuario.id}`);
    } catch (borrado) {
      console.error('[equipo] no se pudo borrar la cuenta que quedó suelta', usuario.id, borrado);
    }
    throw e;
  }
}

// «Guardar PIN»: Postgres revisa con la sesión del gerente de quién es el PIN y si se puede.
async function asignarPin(request: Request, env: Env, cuerpo: Record<string, unknown>): Promise<Response> {
  const sesion = leerSesion(request);
  const miembro = entero(cuerpo.miembro);
  const pin = texto(cuerpo.pin);
  revisarPin(pin);
  await llamar(env, { sesion }, 'asignar_pin', { p_miembro_id: miembro, p_pin_mezclado: await mezclar(env, pin) });
  console.log('[equipo] PIN nuevo', miembro);
  return json({ miembro });
}

// «Vincular»: el aparato manda el código; aquí nace su secreto, que solo él guarda.
async function vincular(env: Env, cuerpo: Record<string, unknown>): Promise<Response> {
  const codigo = texto(cuerpo.codigo).trim().toUpperCase();
  if (!/^[A-Z]{6}$/.test(codigo)) throw new Rechazo(400, 'El código son 6 letras.');
  const token = alAzar(32);
  const aparato = await llamar<{ aparato: string; compartido: boolean }>(env, 'worker', 'vincular_aparato', {
    p_codigo: codigo,
    p_token: token,
  });
  console.log('[equipo] aparato ligado', aparato.aparato);
  return json({ token, aparato: aparato.aparato, compartido: aparato.compartido }, 201);
}

// «¿Quién eres?»: el restaurante, el aparato y quiénes pueden entrar ahí.
async function nombres(env: Env, cuerpo: Record<string, unknown>): Promise<Response> {
  const token = secreto(cuerpo.token);
  return json(await llamar(env, 'worker', 'nombres_del_aparato', { p_token: token }));
}

type Entrada =
  | { ok: true; usuario_id: string; correo: string }
  | { ok: false; motivo: 'pin'; quedan: number }
  | { ok: false; motivo: 'bloqueado'; hasta: string | null };

// Pepe pone su PIN. Postgres revisa todo (el aparato, la persona, la licencia, el PIN y el
// bloqueo) y anota los intentos. Si dice que sí, se le crea su sesión con la llave secreta (un
// enlace mágico que nunca se manda por correo, canjeado aquí mismo) y se registra como la única
// de ese aparato.
async function entrar(env: Env, cuerpo: Record<string, unknown>): Promise<Response> {
  const token = secreto(cuerpo.token);
  const miembro = entero(cuerpo.miembro);
  const pin = texto(cuerpo.pin);
  revisarPin(pin);

  const entrada = await llamar<Entrada>(env, 'worker', 'entrar_con_pin', {
    p_token: token,
    p_miembro_id: miembro,
    p_pin_mezclado: await mezclar(env, pin),
  });
  if (!entrada.ok) return json(entrada);

  const enlace = await admin<{ hashed_token?: string; verification_type?: string }>(env, 'POST', '/admin/generate_link', {
    type: 'magiclink',
    email: entrada.correo,
  });
  if (!enlace.hashed_token) {
    console.error('[equipo] generate_link no regresó el token', Object.keys(enlace));
    throw new Rechazo(502, 'No pudimos abrir tu sesión. Intenta de nuevo.');
  }
  const sesion = await verificar(env, enlace.verification_type ?? 'magiclink', enlace.hashed_token);
  const sesionId = idDeSesion(sesion.access_token);

  try {
    await llamar(env, 'worker', 'registrar_sesion', { p_token: token, p_miembro_id: miembro, p_sesion_id: sesionId });
  } catch (e) {
    // El aparato se desligó en ese instante: la sesión recién creada no se entrega.
    await cerrarSesion(env, sesion.access_token);
    throw e;
  }
  console.log('[equipo] entró', miembro);
  return json({
    ok: true,
    sesion: {
      access_token: sesion.access_token,
      refresh_token: sesion.refresh_token,
      expires_in: sesion.expires_in,
      expires_at: sesion.expires_at,
      token_type: sesion.token_type,
    },
  });
}

// ─── Ayudantes ────────────────────────────────────────────────────────────────

export async function leerCuerpo(request: Request): Promise<Record<string, unknown>> {
  try {
    const cuerpo: unknown = await request.json();
    if (cuerpo && typeof cuerpo === 'object' && !Array.isArray(cuerpo)) return cuerpo as Record<string, unknown>;
  } catch {
    // Abajo se contesta igual que un cuerpo que no es objeto.
  }
  throw new Rechazo(400, 'Faltan los datos.');
}

function texto(valor: unknown): string {
  return typeof valor === 'string' ? valor : '';
}

export function entero(valor: unknown): number {
  if (typeof valor !== 'number' || !Number.isSafeInteger(valor) || valor <= 0) throw new Rechazo(400, 'Falta la persona.');
  return valor;
}

function secreto(valor: unknown): string {
  const token = texto(valor);
  if (!SECRETO_APARATO.test(token)) throw new Rechazo(400, 'Este aparato no está ligado.');
  return token;
}

export function revisarPin(pin: string): void {
  if (!/^\d{4}$/.test(pin)) throw new Rechazo(400, 'El PIN son 4 números.');
}

// El PIN mezclado con la llave de los PIN: HMAC-SHA256 en hexadecimal. Con solo una copia de la
// base no se puede sacar ningún PIN.
export async function mezclar(env: Env, pin: string): Promise<string> {
  if (!env.PIMIENTA_PIN) {
    console.error('[equipo] falta el secreto PIMIENTA_PIN en Cloudflare');
    throw new Rechazo(500, 'Algo salió mal. Intenta de nuevo.');
  }
  const codificar = new TextEncoder();
  const llave = await crypto.subtle.importKey('raw', codificar.encode(env.PIMIENTA_PIN), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const firma = new Uint8Array(await crypto.subtle.sign('HMAC', llave, codificar.encode(pin)));
  return Array.from(firma, (b) => b.toString(16).padStart(2, '0')).join('');
}

// Bytes al azar en base64url, sin relleno: 32 bytes son 43 caracteres.
function alAzar(bytes: number): string {
  const azar = crypto.getRandomValues(new Uint8Array(bytes));
  return btoa(String.fromCharCode(...azar)).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}

// El session_id que trae el token de acceso: es el que se registra en el aparato.
function idDeSesion(tokenAcceso: string): string {
  try {
    const parte = tokenAcceso.split('.')[1].replaceAll('-', '+').replaceAll('_', '/');
    const datos = JSON.parse(atob(parte.padEnd(Math.ceil(parte.length / 4) * 4, '='))) as { session_id?: unknown };
    if (typeof datos.session_id === 'string' && UUID.test(datos.session_id)) return datos.session_id;
  } catch (e) {
    console.error('[equipo] no se pudo leer el token de acceso', e);
  }
  throw new Rechazo(502, 'No pudimos abrir tu sesión. Intenta de nuevo.');
}

async function cerrarSesion(env: Env, tokenAcceso: string): Promise<void> {
  const respuesta = await fetch(`${env.SUPABASE_URL}/auth/v1/logout?scope=local`, {
    method: 'POST',
    headers: { apikey: env.SUPABASE_LLAVE_PUBLICABLE, Authorization: `Bearer ${tokenAcceso}` },
  });
  if (!respuesta.ok) console.error('[equipo] no se pudo cerrar la sesión sobrante', respuesta.status, await respuesta.text());
}
