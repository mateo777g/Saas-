// Hablar con Mercado Pago (libreta 3, «Mercado Pago»; libreta 5, «La terminal conectada»). Aquí viven las llamadas a su
// API, el cifrado de las llaves de cada sucursal, cómo se lee una orden de la Point y el ticket que imprime. Las rutas
// están en terminal.ts.
//
// Las llaves nunca salen: ni ellas, ni el código de la conexión, ni los secretos, ni lo que Mercado Pago contesta con
// ellas van al registro, a la app o al navegador. Un error de Mercado Pago se anota solo con su número y su código.
import type { Env } from './index';
import { Rechazo } from './respuestas';

export const MP_API = 'https://api.mercadopago.com';
export const MP_AUTORIZAR = 'https://auth.mercadopago.com/authorization';

// Mercado Pago no contestó (sin internet, se cortó): el cobro se queda como estaba y se puede reintentar.
export class SinRespuesta extends Error {}

export type Llaves = {
  restaurante_id: string;
  cuenta_id: string;
  terminal_id: string | null;
  acceso: string;
  renovar: string;
  version: number;
  vence_at: string;
};

// ─── El cifrado ───────────────────────────────────────────────────────────────
// AES-256-GCM, con un número al azar de 12 bytes adelante: base64(número ‖ cifrado). La llave es secreto del Worker
// (MP_LLAVE_CIFRADO, 32 bytes en base64). Si se filtra, se cambia: la nueva va en MP_LLAVE_CIFRADO con
// MP_LLAVE_VERSION un número más, y la vieja en MP_LLAVE_CIFRADO_ANTERIOR mientras el Cron renueva todas.

function bytesDeBase64(texto: string): Uint8Array {
  return Uint8Array.from(atob(texto), (c) => c.charCodeAt(0));
}

function base64DeBytes(bytes: Uint8Array): string {
  let texto = '';
  for (const b of bytes) texto += String.fromCharCode(b);
  return btoa(texto);
}

export function base64url(bytes: Uint8Array): string {
  return base64DeBytes(bytes).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}

export function versionDeCifrado(env: Env): number {
  const version = Number(env.MP_LLAVE_VERSION ?? '1');
  return Number.isInteger(version) && version > 0 && version < 32000 ? version : 1;
}

async function llaveDeCifrado(env: Env, version: number): Promise<CryptoKey> {
  const actual = versionDeCifrado(env);
  const texto = version === actual ? env.MP_LLAVE_CIFRADO : version === actual - 1 ? env.MP_LLAVE_CIFRADO_ANTERIOR : undefined;
  if (!texto) {
    console.error('[mp] falta la llave de cifrado de la versión', version);
    throw new Rechazo(500, 'Algo salió mal. Intenta de nuevo.');
  }
  const bytes = bytesDeBase64(texto.trim());
  if (bytes.length !== 32) {
    console.error('[mp] la llave de cifrado no mide 32 bytes', version);
    throw new Rechazo(500, 'Algo salió mal. Intenta de nuevo.');
  }
  return crypto.subtle.importKey('raw', bytes, 'AES-GCM', false, ['encrypt', 'decrypt']);
}

export async function cifrar(env: Env, texto: string): Promise<string> {
  const llave = await llaveDeCifrado(env, versionDeCifrado(env));
  const numero = crypto.getRandomValues(new Uint8Array(12));
  const cifrado = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv: numero }, llave, new TextEncoder().encode(texto)));
  const junto = new Uint8Array(12 + cifrado.length);
  junto.set(numero);
  junto.set(cifrado, 12);
  return base64DeBytes(junto);
}

export async function descifrar(env: Env, cifrado: string, version: number): Promise<string> {
  const llave = await llaveDeCifrado(env, version);
  const bytes = bytesDeBase64(cifrado);
  try {
    const claro = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: bytes.slice(0, 12) }, llave, bytes.slice(12));
    return new TextDecoder().decode(claro);
  } catch {
    console.error('[mp] una llave no se pudo descifrar', version);
    throw new Rechazo(500, 'Algo salió mal. Intenta de nuevo.');
  }
}

// ─── Las llamadas ─────────────────────────────────────────────────────────────

export type RespuestaMp = { estado: number; datos: Record<string, unknown> | null };

// Una llamada a la API de Mercado Pago con la llave de una sucursal. clave: la de «no repetir» (X-Idempotency-Key):
// la misma clave regresa lo mismo. Sin respuesta: SinRespuesta.
export async function mp(
  metodo: 'GET' | 'POST' | 'PATCH',
  ruta: string,
  acceso: string,
  opciones: { cuerpo?: unknown; clave?: string; cabeceras?: Record<string, string> } = {},
): Promise<RespuestaMp> {
  const headers: Record<string, string> = { Authorization: `Bearer ${acceso}`, ...opciones.cabeceras };
  if (metodo !== 'GET') headers['Content-Type'] = 'application/json';
  if (opciones.clave) headers['X-Idempotency-Key'] = opciones.clave;
  let respuesta: Response;
  try {
    respuesta = await fetch(`${MP_API}${ruta}`, {
      method: metodo,
      headers,
      body: opciones.cuerpo === undefined ? undefined : JSON.stringify(opciones.cuerpo),
    });
  } catch (e) {
    console.error('[mp] sin respuesta', metodo, ruta.split('?')[0], e instanceof Error ? e.message : '');
    throw new SinRespuesta();
  }
  const texto = await respuesta.text();
  let datos: Record<string, unknown> | null = null;
  try {
    const valor: unknown = texto ? JSON.parse(texto) : null;
    if (valor && typeof valor === 'object' && !Array.isArray(valor)) datos = valor as Record<string, unknown>;
  } catch {
    // Sin JSON: se queda null.
  }
  if (!respuesta.ok) console.warn('[mp] respondió', respuesta.status, metodo, ruta.split('?')[0], codigoDeError(datos));
  if (respuesta.status >= 500) throw new SinRespuesta();
  return { estado: respuesta.status, datos };
}

// El código de un error de Mercado Pago, sin nada más de lo que contestó.
export function codigoDeError(datos: Record<string, unknown> | null): string {
  if (!datos) return '';
  const errores = datos.errors;
  if (Array.isArray(errores) && errores[0] && typeof errores[0] === 'object') {
    const codigo = (errores[0] as Record<string, unknown>).code;
    if (typeof codigo === 'string') return codigo;
  }
  for (const llave of ['error', 'code', 'status']) {
    const valor = datos[llave];
    if (typeof valor === 'string' || typeof valor === 'number') return String(valor);
  }
  return '';
}

// ─── Las llaves de la aplicación ──────────────────────────────────────────────

export type LlavesNuevas = { acceso: string; renovar: string; cuentaId: string; venceEn: number };

// El intercambio con OAuth: el código de la conexión (con su verificador de PKCE) o la llave de renovar. Un «no» de
// Mercado Pago regresa null con su código; sin respuesta, SinRespuesta.
export async function pedirLlaves(
  env: Env,
  datos: { grant_type: 'authorization_code'; code: string; code_verifier: string } | { grant_type: 'refresh_token'; refresh_token: string },
): Promise<LlavesNuevas | { no: string }> {
  if (!env.MP_CLIENT_ID || !env.MP_CLIENT_SECRET) {
    console.error('[mp] faltan los secretos MP_CLIENT_ID o MP_CLIENT_SECRET en Cloudflare');
    throw new Rechazo(500, 'Algo salió mal. Intenta de nuevo.');
  }
  let respuesta: Response;
  try {
    respuesta = await fetch(`${MP_API}/oauth/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({
        client_id: env.MP_CLIENT_ID,
        client_secret: env.MP_CLIENT_SECRET,
        ...(datos.grant_type === 'authorization_code' ? { redirect_uri: regreso(env) } : {}),
        ...datos,
      }),
    });
  } catch (e) {
    console.error('[mp] oauth sin respuesta', e instanceof Error ? e.message : '');
    throw new SinRespuesta();
  }
  let cuerpo: Record<string, unknown> | null = null;
  try {
    cuerpo = (await respuesta.json()) as Record<string, unknown>;
  } catch {
    // Se queda null.
  }
  if (respuesta.status >= 500) {
    console.error('[mp] oauth respondió', respuesta.status);
    throw new SinRespuesta();
  }
  if (!respuesta.ok || !cuerpo) {
    const codigo = codigoDeError(cuerpo);
    console.warn('[mp] oauth no dio las llaves', respuesta.status, datos.grant_type, codigo);
    return { no: codigo || String(respuesta.status) };
  }
  const acceso = cuerpo.access_token;
  const renovar = cuerpo.refresh_token;
  const cuenta = cuerpo.user_id;
  const venceEn = Number(cuerpo.expires_in);
  if (typeof acceso !== 'string' || typeof renovar !== 'string' || (typeof cuenta !== 'string' && typeof cuenta !== 'number')
      || !Number.isFinite(venceEn) || venceEn <= 0) {
    console.error('[mp] oauth contestó sin las llaves completas', Object.keys(cuerpo));
    return { no: 'incompleta' };
  }
  return { acceso, renovar, cuentaId: String(cuenta), venceEn };
}

// La dirección fija del Worker a la que Mercado Pago regresa al conectar.
export function regreso(env: Env): string {
  if (!env.MP_REGRESO) {
    console.error('[mp] falta MP_REGRESO en wrangler.jsonc');
    throw new Rechazo(500, 'Algo salió mal. Intenta de nuevo.');
  }
  return env.MP_REGRESO;
}

// ─── Las Point ────────────────────────────────────────────────────────────────

export type Point = { id: string; modo: string };

export async function terminalesDeLaCuenta(acceso: string): Promise<Point[] | null> {
  const { estado, datos } = await mp('GET', '/terminals/v1/list?limit=50', acceso);
  if (estado === 401 || estado === 403) return null;
  if (estado !== 200) throw new Rechazo(502, 'Mercado Pago no contestó. Intenta de nuevo.');
  const lista = (datos?.data as Record<string, unknown> | undefined)?.terminals;
  if (!Array.isArray(lista)) return [];
  return lista
    .filter((t): t is Record<string, unknown> => !!t && typeof t === 'object' && typeof (t as Record<string, unknown>).id === 'string')
    .map((t) => ({ id: String(t.id), modo: typeof t.operating_mode === 'string' ? t.operating_mode : '' }));
}

// Pone una Point en modo de punto de venta. Regresa si hubo que cambiarla (entonces se reinicia una vez).
export async function ponerEnPdv(acceso: string, terminal: Point): Promise<boolean> {
  if (terminal.modo === 'PDV') return false;
  const { estado } = await mp('PATCH', '/terminals/v1/setup', acceso, {
    cuerpo: { terminals: [{ id: terminal.id, operating_mode: 'PDV' }] },
  });
  if (estado < 200 || estado >= 300) throw new Rechazo(502, 'Mercado Pago no pudo preparar tu Point. Intenta de nuevo.');
  return true;
}

// ─── Leer una orden ───────────────────────────────────────────────────────────

export type Lectura = {
  estado: 'esperando' | 'tomado' | 'pagado' | 'no_se_cobro' | 'revisar';
  motivo: string | null;
  monto: number | null;
  referencia: string | null;
};

// Lo que dice una orden de la Point, en las palabras del cobro: created = esperando (la Point no la ha tomado),
// at_terminal = tomado, processed = pagado (con su monto), canceled = no se cobró (cancelada, o cancelada en la
// terminal), expired = vencida, failed = rechazada. Lo demás (action_required, refunded…): revisar.
export function leerOrden(orden: Record<string, unknown>): Lectura {
  const pagos = (orden.transactions as Record<string, unknown> | undefined)?.payments;
  const pago = Array.isArray(pagos) && pagos[0] && typeof pagos[0] === 'object' ? (pagos[0] as Record<string, unknown>) : {};
  const monto = Number(pago.amount ?? orden.total_amount);
  const referencia = typeof orden.external_reference === 'string' ? orden.external_reference : null;
  const base = { monto: Number.isFinite(monto) ? monto : null, referencia };
  switch (orden.status) {
    case 'created':
      return { ...base, estado: 'esperando', motivo: null };
    case 'at_terminal':
      return { ...base, estado: 'tomado', motivo: null };
    case 'processed':
      return { ...base, estado: 'pagado', motivo: null };
    case 'canceled':
      return { ...base, estado: 'no_se_cobro', motivo: pago.status_detail === 'cancel_by_terminal' ? 'cancelada_terminal' : 'cancelada' };
    case 'expired':
      return { ...base, estado: 'no_se_cobro', motivo: 'vencida' };
    case 'failed':
      return { ...base, estado: 'no_se_cobro', motivo: 'rechazada' };
    default:
      return { ...base, estado: 'revisar', motivo: null };
  }
}

// Cuánto se devolvió de una orden: lo que dicen sus devoluciones, o todo si no las enumera.
export function montoDevuelto(orden: Record<string, unknown>): number | null {
  const devoluciones = (orden.transactions as Record<string, unknown> | undefined)?.refunds;
  if (Array.isArray(devoluciones) && devoluciones.length > 0) {
    let suma = 0;
    for (const d of devoluciones) {
      const monto = Number((d as Record<string, unknown> | null)?.amount);
      if (!Number.isFinite(monto)) return null;
      suma += Math.round(monto * 100);
    }
    return suma / 100;
  }
  return leerOrden(orden).monto;
}

// ─── El ticket ────────────────────────────────────────────────────────────────

export type Ticket = {
  restaurante: string;
  cuenta: string;
  atendio: string | null;
  renglones: { cantidad: number; nombre: string; importe: number }[];
  descuento: number;
  propina: number;
  total: number;
  folio: number;
  cerrada_at: string;
  zona: string;
};

const pesos = (monto: number) => `$${Number(monto).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
// Las llaves del formato de la Point no pueden salir del texto del restaurante.
const limpio = (texto: string) => texto.replace(/[{}]/g, '').slice(0, 60);

// Lo que imprime la Point al cerrarse la cuenta. Sin {left}: en la prueba los renglones con {left} salieron a la
// derecha, y los que no llevan etiqueta salen a la izquierda.
export function textoDelTicket(t: Ticket): string {
  const cuando = new Date(t.cerrada_at).toLocaleString('es-MX', {
    timeZone: t.zona, day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false,
  });
  const renglones = t.renglones.map((r) => `${r.cantidad} ${limpio(r.nombre)}  ${pesos(r.importe)}{br}`);
  return [
    `{center}{b}${limpio(t.restaurante)}{/b}{/center}{br}`,
    `{center}{s}Folio ${t.folio} · ${cuando}{/s}{/center}{br}{br}`,
    `${limpio(t.cuenta)}${t.atendio ? ` · Atendió: ${limpio(t.atendio)}` : ''}{br}{br}`,
    ...renglones,
    '{br}',
    ...(Number(t.descuento) > 0 ? [`Descuento  -${pesos(t.descuento)}{br}`] : []),
    `{w}{b}Total ${pesos(t.total)}{/b}{/w}{br}`,
    ...(Number(t.propina) > 0 ? [`Propina  ${pesos(t.propina)}{br}`] : []),
    '{br}{center}{s}Gracias por su visita{/s}{/center}{br}',
  ].join('');
}

// Manda el ticket a la Point. Imprimir y cobrar comparten su fila: si falla, solo queda en el registro (la cuenta ya
// se cerró y el comprobante de la tarjeta ya salió).
export async function imprimirTicket(acceso: string, terminalId: string, ventaId: number, ticket: Ticket): Promise<void> {
  try {
    const { estado, datos } = await mp('POST', '/terminals/v1/actions', acceso, {
      clave: `ticket-${ventaId}-${ticket.folio}`,
      cuerpo: {
        type: 'print',
        external_reference: `ticket-${ventaId}`,
        config: { point: { terminal_id: terminalId, subtype: 'custom' } },
        content: textoDelTicket(ticket),
      },
    });
    if (estado < 200 || estado >= 300) console.error('[mp] el ticket no se mandó', estado, codigoDeError(datos), ventaId);
  } catch (e) {
    console.error('[mp] el ticket no se mandó', ventaId, e instanceof Error ? e.message : '');
  }
}
