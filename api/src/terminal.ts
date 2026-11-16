// La terminal conectada (libreta 5, «La terminal conectada»; libreta 3, «Mercado Pago»). Cada sucursal conecta su
// cuenta de Mercado Pago y su Point, y el monto de la cuenta llega solo a la terminal. El Worker nunca decide: antes de
// cada trabajo le pregunta a Postgres con la sesión de quien llama, y lo que dice Mercado Pago lo guarda Postgres
// (resultado_cobro), que mueve cada cobro una sola vez.
//
// Con la sesión del gerente (Ajustes):
//  - POST /mp/conectar {restaurante}: con la contraseña puesta hace 5 minutos o menos, un pase de un solo uso y la
//    dirección de Mercado Pago para dar el permiso (OAuth con PKCE). Mercado Pago regresa a GET /mp/regreso, que cambia
//    el código por las llaves, las guarda cifradas, liga la Point si es una y regresa a la app (?mp=conectado).
//  - POST /mp/terminales {restaurante}: las Point de la cuenta y en qué otra sucursal está cada una.
//  - POST /mp/terminal {restaurante, terminal_id}: liga una Point y la pone en modo de punto de venta.
// Con la sesión de quien cobra (mesero, caja o gerente):
//  - POST /terminal/mandar {venta, clave, monto, propina_porcentaje | propina}: aparta el cobro y lo manda a la Point.
//  - POST /terminal/revisar {cobro}: le pregunta a Mercado Pago cómo va (a los 5 segundos y con «Revisar»).
//  - POST /terminal/cancelar {cobro}: lo cancela antes de que se pague.
//  - POST /terminal/devolver {pago, motivo, autoriza?, pin?}: cancela un pago de la terminal devolviendo el dinero.
// De Mercado Pago:
//  - POST /mp/aviso: sus avisos, con tres revisiones (la firma, la orden pedida otra vez con la llave de esa cuenta, y
//    que apunte a un cobro de una sucursal conectada a esa cuenta con su monto).
// Y cada día, en el Cron: renovar las llaves a las que les faltan 30 días o menos.
import type { Env } from './index';
import { entero, hmacHex, leerCuerpo, mezclar, revisarPin } from './equipo';
import {
  base64url, cifrar, codigoDeError, descifrar, imprimirTicket, leerOrden, type Lectura, type Llaves, montoDevuelto, mp,
  MP_AUTORIZAR, pedirLlaves, ponerEnPdv, regreso, SinRespuesta, terminalesDeLaCuenta, type Ticket, versionDeCifrado,
} from './mercadoPago';
import { json, origenPermitido, Rechazo } from './respuestas';
import { leerSesion, llamar } from './supabase';

type CobroWorker = {
  cobro_id: number;
  restaurante_id: string;
  estado: string;
  motivo: string | null;
  orden_id: string | null;
  monto: number;
  terminal_id: string;
  tomado: boolean;
  vence_at: string;
  llaves?: Llaves | null;
};

type Resultado = {
  cambio: boolean;
  estado: string;
  motivo: string | null;
  tomado?: boolean;
  venta_id: number;
  cerrada?: boolean;
  folio?: number | null;
  ticket?: Ticket | null;
};

const ACTIVOS = ['mandando', 'esperando', 'revisar'];
const NO_CONTESTO = 'Mercado Pago no contestó. Intenta de nuevo.';

// ─── Las rutas de la app ──────────────────────────────────────────────────────

export async function mercadoPago(request: Request, env: Env, url: URL): Promise<Response> {
  if (request.method !== 'POST') throw new Rechazo(405, 'Ese trabajo solo acepta POST.');
  const sesion = leerSesion(request);
  const cuerpo = await leerCuerpo(request);
  const restaurante = uuid(cuerpo.restaurante);

  if (url.pathname === '/mp/conectar') {
    const usuario = await llamar<string>(env, { sesion }, 'puedo_conectar_mercado_pago', { p_restaurante_id: restaurante });
    const pase = base64url(crypto.getRandomValues(new Uint8Array(32)));
    const verificador = base64url(crypto.getRandomValues(new Uint8Array(32)));
    await llamar(env, 'worker', 'guardar_pase_mercado_pago', {
      p_huella: await sha256Hex(pase),
      p_usuario_id: usuario,
      p_restaurante_id: restaurante,
      p_verificador: verificador,
      p_origen: request.headers.get('Origin'),
    });
    if (!env.MP_CLIENT_ID) {
      console.error('[mp] falta el secreto MP_CLIENT_ID en Cloudflare');
      throw new Rechazo(500, 'Algo salió mal. Intenta de nuevo.');
    }
    const destino = new URL(MP_AUTORIZAR);
    destino.searchParams.set('client_id', env.MP_CLIENT_ID);
    destino.searchParams.set('response_type', 'code');
    destino.searchParams.set('platform_id', 'mp');
    destino.searchParams.set('state', pase);
    destino.searchParams.set('redirect_uri', regreso(env));
    destino.searchParams.set('code_challenge', base64url(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verificador)))));
    destino.searchParams.set('code_challenge_method', 'S256');
    return json({ url: destino.toString() });
  }

  if (url.pathname === '/mp/terminales') {
    await llamar(env, { sesion }, 'puedo_ver_terminales', { p_restaurante_id: restaurante });
    const { llaves, acceso } = await accesoDe(env, restaurante);
    const lista = await terminalesDeLaCuenta(acceso);
    if (!lista) {
      await llamar(env, 'worker', 'mercado_pago_se_desconecto', { p_restaurante_id: restaurante });
      throw new Rechazo(409, 'Tu Mercado Pago se desconectó.');
    }
    const enOtra = await llamar<Record<string, string>>(env, 'worker', 'terminales_en_otra_sucursal', {
      p_restaurante_id: restaurante,
      p_terminales: lista.map((t) => t.id),
    });
    let desligada: string | null = null;
    if (llaves.terminal_id && !lista.some((t) => t.id === llaves.terminal_id)) {
      desligada = llaves.terminal_id;
      await llamar(env, 'worker', 'ligar_terminal', { p_restaurante_id: restaurante, p_terminal_id: null });
    }
    return json({
      terminales: lista.map((t) => ({ id: t.id, en: enOtra[t.id] ?? null })),
      ligada: desligada ? null : llaves.terminal_id,
      desligada,
    });
  }

  if (url.pathname === '/mp/terminal') {
    const terminalId = typeof cuerpo.terminal_id === 'string' ? cuerpo.terminal_id : '';
    if (!terminalId) throw new Rechazo(400, 'Elige tu Point.');
    await llamar(env, { sesion }, 'puedo_ver_terminales', { p_restaurante_id: restaurante });
    const { acceso } = await accesoDe(env, restaurante);
    const lista = await terminalesDeLaCuenta(acceso);
    if (!lista) {
      await llamar(env, 'worker', 'mercado_pago_se_desconecto', { p_restaurante_id: restaurante });
      throw new Rechazo(409, 'Tu Mercado Pago se desconectó.');
    }
    const point = lista.find((t) => t.id === terminalId);
    if (!point) throw new Rechazo(400, 'Esa Point ya no está en tu cuenta de Mercado Pago.');
    const reinicia = await sinCorte(() => ponerEnPdv(acceso, point));
    await llamar(env, 'worker', 'ligar_terminal', { p_restaurante_id: restaurante, p_terminal_id: terminalId });
    console.log('[mp] Point ligada', restaurante);
    return json({ ok: true, reinicia });
  }

  throw new Rechazo(404, 'Ese trabajo no existe.');
}

export async function terminal(request: Request, env: Env, url: URL): Promise<Response> {
  if (request.method !== 'POST') throw new Rechazo(405, 'Ese trabajo solo acepta POST.');
  const sesion = leerSesion(request);
  const cuerpo = await leerCuerpo(request);

  if (url.pathname === '/terminal/mandar') {
    const apartado = await llamar<{ ok: boolean; motivo?: string; cobro_id?: number; estado?: string }>(env, { sesion }, 'apartar_cobro_terminal', {
      p_venta_id: entero(cuerpo.venta),
      p_clave: uuid(cuerpo.clave),
      p_monto: cuerpo.monto ?? null,
      p_propina_porcentaje: cuerpo.propina_porcentaje ?? null,
      p_propina: cuerpo.propina ?? null,
    });
    if (!apartado.ok || !apartado.cobro_id) return json({ ok: false, motivo: apartado.motivo ?? 'ocupada' });
    const cobro = await cobroDelWorker(env, apartado.cobro_id);
    if (cobro.estado !== 'mandando') return json(paraLaApp(cobro));
    return json(await mandarOrden(env, cobro));
  }

  if (url.pathname === '/terminal/revisar' || url.pathname === '/terminal/cancelar') {
    const cancelar = url.pathname === '/terminal/cancelar';
    const cobroId = entero(cuerpo.cobro);
    await llamar(env, { sesion }, 'puedo_tocar_cobro', { p_cobro_id: cobroId, p_para: cancelar ? 'cancelar' : 'revisar' });
    let cobro = await cobroDelWorker(env, cobroId);
    if (!ACTIVOS.includes(cobro.estado)) return json(paraLaApp(cobro));
    if (cobro.estado === 'mandando') {
      // Sin orden todavía: se manda otra vez con la misma clave y Mercado Pago regresa la misma orden.
      const mandado = await mandarOrden(env, cobro);
      if (!cancelar || mandado.error || !ACTIVOS.includes(mandado.estado)) return json(mandado);
      cobro = await cobroDelWorker(env, cobroId);
    }
    return json(cancelar ? await cancelarOrden(env, cobro) : await revisarOrden(env, cobro));
  }

  if (url.pathname === '/terminal/devolver') {
    const pin = typeof cuerpo.pin === 'string' ? cuerpo.pin : '';
    if (pin) revisarPin(pin);
    const revisado = await llamar<{ ok: boolean; cobro_id?: number; miembro?: number; autoriza?: number; motivo?: string; orden_id?: string }>(
      env, { sesion }, 'revisar_devolucion', {
        p_pago_id: entero(cuerpo.pago),
        p_motivo: typeof cuerpo.motivo === 'string' ? cuerpo.motivo : null,
        p_autoriza_id: cuerpo.autoriza == null ? null : entero(cuerpo.autoriza),
        p_pin_mezclado: pin ? await mezclar(env, pin) : null,
      });
    if (!revisado.ok || !revisado.cobro_id) return json(revisado);
    const cobro = await cobroDelWorker(env, revisado.cobro_id);
    const acceso = await accesoDelCobro(env, cobro);
    let respuesta;
    try {
      respuesta = await mp('POST', `/v1/orders/${encodeURIComponent(cobro.orden_id ?? '')}/refund`, acceso, { clave: `devolver-${cobro.cobro_id}` });
    } catch (e) {
      // Sin respuesta: la devolución se queda apartada y «Cancelar pago» otra vez la pide con la misma clave.
      if (e instanceof SinRespuesta) throw new Rechazo(502, 'Mercado Pago no contestó. Vuelve a intentar la cancelación.');
      throw e;
    }
    if (respuesta.estado < 200 || respuesta.estado >= 300) {
      await llamar(env, 'worker', 'devolucion_no_salio', { p_cobro_id: cobro.cobro_id });
      if (respuesta.estado === 401 || respuesta.estado === 403) {
        await llamar(env, 'worker', 'mercado_pago_se_desconecto', { p_restaurante_id: cobro.restaurante_id });
      }
      throw new Rechazo(502, 'Mercado Pago no devolvió el dinero. Intenta de nuevo.');
    }
    const hecho = await llamar<{ ok: boolean; reabierta: boolean }>(env, 'worker', 'pago_devuelto', {
      p_cobro_id: cobro.cobro_id,
      p_miembro: revisado.miembro,
      p_autoriza: revisado.autoriza,
      p_motivo: revisado.motivo,
    });
    console.log('[mp] pago devuelto', cobro.cobro_id);
    return json({ ok: true, autoriza: revisado.autoriza, reabierta: hecho.reabierta });
  }

  throw new Rechazo(404, 'Ese trabajo no existe.');
}

// ─── El regreso de Mercado Pago al conectar ───────────────────────────────────
// Una página del navegador, sin Origin y sin sesión: el pase de un solo uso dice quién la pidió y a dónde regresa.

export async function regresoDeMercadoPago(env: Env, url: URL): Promise<Response> {
  const pase = url.searchParams.get('state') ?? '';
  if (!/^[A-Za-z0-9_-]{43}$/.test(pase)) return pagina('Este enlace ya no sirve. Regresa a Ajustes y toca «Conectar Mercado Pago» otra vez.');
  const datos = await llamar<{ restaurante_id: string; usuario_id: string; verificador: string; origen: string } | null>(
    env, 'worker', 'usar_pase_mercado_pago', { p_huella: await sha256Hex(pase) });
  if (!datos) return pagina('Este enlace ya no sirve. Regresa a Ajustes y toca «Conectar Mercado Pago» otra vez.');
  if (!origenPermitido(datos.origen, env.ORIGENES)) {
    console.error('[mp] un pase con un origen que ya no está en la lista');
    return pagina('No pudimos conectar tu Mercado Pago. Regresa a Ajustes e intenta otra vez.');
  }
  const volver = (resultado: string) => Response.redirect(`${datos.origen}/?mp=${resultado}`, 302);

  const codigo = url.searchParams.get('code');
  if (!codigo) return volver('cancelado');

  try {
    const llaves = await pedirLlaves(env, { grant_type: 'authorization_code', code: codigo, code_verifier: datos.verificador });
    if ('no' in llaves) return volver('error');
    const yo = await mp('GET', '/users/me', llaves.acceso);
    if (yo.estado !== 200 || !yo.datos || String(yo.datos.id) !== llaves.cuentaId) {
      console.error('[mp] /users/me no contestó la cuenta de las llaves', yo.estado);
      return volver('error');
    }
    const nombre = [yo.datos.first_name, yo.datos.last_name].filter((p) => typeof p === 'string' && p.trim()).join(' ').trim()
      || (typeof yo.datos.nickname === 'string' ? yo.datos.nickname : '') || 'Tu cuenta';
    const lista = (await terminalesDeLaCuenta(llaves.acceso)) ?? [];
    const conexion = await llamar<{ terminal_id: string | null; ligada: boolean }>(env, 'worker', 'conectar_mercado_pago', {
      p_usuario_id: datos.usuario_id,
      p_restaurante_id: datos.restaurante_id,
      p_cuenta_id: llaves.cuentaId,
      p_cuenta_nombre: nombre.slice(0, 120),
      p_acceso: await cifrar(env, llaves.acceso),
      p_renovar: await cifrar(env, llaves.renovar),
      p_version: versionDeCifrado(env),
      p_vence_at: new Date(Date.now() + llaves.venceEn * 1000).toISOString(),
      p_terminales: lista.map((t) => t.id),
    });
    let reinicia = false;
    const point = conexion.ligada ? lista.find((t) => t.id === conexion.terminal_id) : undefined;
    if (point) {
      try {
        reinicia = await ponerEnPdv(llaves.acceso, point);
      } catch (e) {
        console.error('[mp] la Point se ligó pero no se pudo poner en modo de punto de venta', e instanceof Error ? e.message : '');
      }
    }
    console.log('[mp] conectado', datos.restaurante_id, lista.length, 'Point');
    return volver(`conectado${reinicia ? '&reinicia=1' : ''}`);
  } catch (e) {
    console.error('[mp] no se pudo conectar', e instanceof Rechazo ? e.message : e);
    return volver('error');
  }
}

function pagina(texto: string): Response {
  const html = `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">`
    + `<title>Mercado Pago</title></head><body style="font-family:system-ui,sans-serif;max-width:28rem;margin:4rem auto;padding:0 1rem;`
    + `color:#0a0a0b"><p>${texto}</p></body></html>`;
  return new Response(html, { status: 400, headers: { 'Content-Type': 'text/html; charset=utf-8' } });
}

// ─── Los avisos de Mercado Pago ───────────────────────────────────────────────

export async function avisoDeMercadoPago(request: Request, env: Env, url: URL): Promise<Response> {
  if (request.method !== 'POST') return new Response('Solo POST', { status: 405 });
  const texto = await request.text();
  let cuerpo: Record<string, unknown>;
  try {
    cuerpo = JSON.parse(texto) as Record<string, unknown>;
  } catch {
    console.error('[mp] aviso sin JSON', texto.length);
    return new Response('JSON inválido', { status: 400 });
  }
  const datos = (cuerpo.data && typeof cuerpo.data === 'object' ? cuerpo.data : {}) as Record<string, unknown>;
  const ordenId = url.searchParams.get('data.id') ?? (typeof datos.id === 'string' ? datos.id : '');

  // 1 · La firma: el id en minúsculas, el request-id y el ts, con el secreto de los avisos, en tiempo constante.
  if (!(await firmaBuena(request, env, ordenId))) {
    console.error('[mp] aviso con firma mala', cuerpo.action);
    return new Response('Firma inválida', { status: 401 });
  }
  if (cuerpo.type !== 'order' || !/^[A-Za-z0-9]+$/.test(ordenId)) return new Response('ok');
  const cuenta = typeof cuerpo.user_id === 'string' || typeof cuerpo.user_id === 'number' ? String(cuerpo.user_id) : '';
  if (!cuenta) return new Response('ok');

  try {
    // 2 · La orden, pedida otra vez a Mercado Pago con la llave de esa cuenta.
    const llaves = await llamar<Llaves | null>(env, 'worker', 'llaves_por_cuenta', { p_cuenta_id: cuenta });
    if (!llaves) {
      console.warn('[mp] aviso de una cuenta sin sucursal conectada');
      return new Response('ok');
    }
    const acceso = await descifrar(env, llaves.acceso, llaves.version);
    const { estado, datos: orden } = await mp('GET', `/v1/orders/${encodeURIComponent(ordenId)}`, acceso);
    if (estado !== 200 || !orden) {
      console.error('[mp] la orden del aviso no se pudo leer', estado);
      return new Response('ok');
    }
    const lectura = leerOrden(orden);
    if (!lectura.referencia || !/^\d{1,18}$/.test(lectura.referencia)) return new Response('ok');
    const cobroId = Number(lectura.referencia);

    // 3 · Postgres revisa que el cobro sea de una sucursal conectada a esa cuenta y que la orden y el monto coincidan.
    if (orden.status === 'refunded' || orden.status === 'partially_refunded' || String(cuerpo.action).includes('refund')) {
      const anotado = await llamar<boolean>(env, 'worker', 'devuelto_desde_mercado_pago', {
        p_cobro_id: cobroId, p_cuenta_id: cuenta, p_orden_id: ordenId, p_monto: montoDevuelto(orden),
      });
      if (anotado) console.log('[mp] devuelto desde Mercado Pago', cobroId);
      return new Response('ok');
    }
    const cobro = await cobroDelWorker(env, cobroId);
    await aplicar(env, cobro, cuenta, ordenId, lectura, acceso);
    return new Response('ok');
  } catch (e) {
    if (e instanceof SinRespuesta) return new Response('Sin respuesta', { status: 503 });
    console.error('[mp] el aviso no se pudo procesar', cuerpo.action, e instanceof Rechazo ? e.message : e);
    return new Response('ok');
  }
}

async function firmaBuena(request: Request, env: Env, ordenId: string): Promise<boolean> {
  if (!env.MP_SECRETO_AVISOS) {
    console.error('[mp] falta el secreto MP_SECRETO_AVISOS en Cloudflare');
    return false;
  }
  const cabecera = request.headers.get('x-signature') ?? '';
  const partes = Object.fromEntries(cabecera.split(',').map((p) => p.trim().split('=', 2) as [string, string]));
  if (!partes.ts || !partes.v1) return false;
  const requestId = request.headers.get('x-request-id') ?? '';
  const plantilla = `${ordenId ? `id:${ordenId.toLowerCase()};` : ''}${requestId ? `request-id:${requestId};` : ''}ts:${partes.ts};`;
  return igualesEnTiempoConstante(await hmacHex(env.MP_SECRETO_AVISOS, plantilla), partes.v1);
}

function igualesEnTiempoConstante(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diferencia = 0;
  for (let i = 0; i < a.length; i += 1) diferencia |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diferencia === 0;
}

// ─── La renovación diaria ─────────────────────────────────────────────────────
// Cada conexión a la que le faltan 30 días o menos, una por una, guardando las llaves nuevas en el mismo paso. Si
// Mercado Pago ya no acepta la de renovar (quitaron el permiso), o la llave ya venció: «Se desconectó». Si falla de
// otro modo, queda en el registro y se intenta al día siguiente.

export async function renovarLlaves(env: Env): Promise<void> {
  const lista = await llamar<Llaves[]>(env, 'worker', 'llaves_por_renovar', {});
  for (const llaves of lista) {
    try {
      if (Date.parse(llaves.vence_at) <= Date.now()) {
        await llamar(env, 'worker', 'mercado_pago_se_desconecto', { p_restaurante_id: llaves.restaurante_id });
        console.error('[mp] una conexión venció sin renovarse', llaves.restaurante_id);
        continue;
      }
      const nuevas = await pedirLlaves(env, { grant_type: 'refresh_token', refresh_token: await descifrar(env, llaves.renovar, llaves.version) });
      if ('no' in nuevas) {
        if (nuevas.no === 'invalid_grant') {
          await llamar(env, 'worker', 'mercado_pago_se_desconecto', { p_restaurante_id: llaves.restaurante_id });
          console.warn('[mp] quitaron el permiso: se desconectó', llaves.restaurante_id);
        } else {
          console.error('[mp] no se pudo renovar', llaves.restaurante_id, nuevas.no);
        }
        continue;
      }
      await llamar(env, 'worker', 'guardar_llaves_mercado_pago', {
        p_restaurante_id: llaves.restaurante_id,
        p_acceso: await cifrar(env, nuevas.acceso),
        p_renovar: await cifrar(env, nuevas.renovar),
        p_version: versionDeCifrado(env),
        p_vence_at: new Date(Date.now() + nuevas.venceEn * 1000).toISOString(),
      });
      console.log('[mp] llaves renovadas', llaves.restaurante_id);
    } catch (e) {
      console.error('[mp] no se pudo renovar', llaves.restaurante_id, e instanceof Error ? e.message : e);
    }
  }
}

// ─── Lo que comparten las rutas ───────────────────────────────────────────────

async function cobroDelWorker(env: Env, cobroId: number): Promise<CobroWorker> {
  const cobro = await llamar<CobroWorker | null>(env, 'worker', 'cobro_para_el_worker', { p_cobro_id: cobroId });
  if (!cobro) throw new Rechazo(404, 'Ese cobro ya no está.');
  return cobro;
}

async function accesoDe(env: Env, restaurante: string): Promise<{ llaves: Llaves; acceso: string }> {
  const llaves = await llamar<Llaves | null>(env, 'worker', 'llaves_de_mercado_pago', { p_restaurante_id: restaurante });
  if (!llaves) throw new Rechazo(409, 'Mercado Pago no está conectado en esta sucursal.');
  return { llaves, acceso: await descifrar(env, llaves.acceso, llaves.version) };
}

async function accesoDelCobro(env: Env, cobro: CobroWorker): Promise<string> {
  if (!cobro.llaves) throw new Rechazo(409, 'Mercado Pago no está conectado en esta sucursal.');
  return descifrar(env, cobro.llaves.acceso, cobro.llaves.version);
}

function paraLaApp(cobro: { cobro_id: number; estado: string; motivo: string | null; tomado?: boolean }, extra: Record<string, unknown> = {}) {
  return { ok: true, cobro_id: cobro.cobro_id, estado: cobro.estado, motivo: cobro.motivo, tomado: cobro.tomado ?? false, ...extra };
}

// Manda la orden a la Point con el número del cobro como clave para no repetir y como referencia.
async function mandarOrden(env: Env, cobro: CobroWorker): Promise<ReturnType<typeof paraLaApp> & { error?: string }> {
  const acceso = await accesoDelCobro(env, cobro);
  let respuesta;
  try {
    respuesta = await mp('POST', '/v1/orders', acceso, {
      clave: `cobro-${cobro.cobro_id}`,
      cuerpo: {
        type: 'point',
        external_reference: String(cobro.cobro_id),
        expiration_time: 'PT5M',
        transactions: { payments: [{ amount: Number(cobro.monto).toFixed(2) }] },
        config: { point: { terminal_id: cobro.terminal_id, print_on_terminal: 'seller_ticket' } },
      },
    });
  } catch (e) {
    if (e instanceof SinRespuesta) return paraLaApp(cobro, { error: 'No pudimos mandarlo a la terminal. Intenta de nuevo.' });
    throw e;
  }
  const cuenta = cobro.llaves?.cuenta_id ?? '';
  if (respuesta.estado === 200 || respuesta.estado === 201) {
    const orden = respuesta.datos ?? {};
    const ordenId = typeof orden.id === 'string' ? orden.id : '';
    if (!ordenId) {
      console.error('[mp] la orden se creó sin número');
      return paraLaApp(cobro, { error: 'No pudimos mandarlo a la terminal. Intenta de nuevo.' });
    }
    return paraLaApp(cobro, await aplicar(env, cobro, cuenta, ordenId, leerOrden(orden), acceso));
  }
  const codigo = codigoDeError(respuesta.datos);
  if (respuesta.estado === 401 || respuesta.estado === 403) {
    await llamar(env, 'worker', 'mercado_pago_se_desconecto', { p_restaurante_id: cobro.restaurante_id });
  }
  const motivo = /already_queued_order_(for|on)_terminal/.test(codigo) || respuesta.estado === 409 ? 'ocupada' : 'sin_conexion';
  if (motivo === 'sin_conexion') console.error('[mp] la orden no se creó', respuesta.estado, codigo);
  return paraLaApp(cobro, await aplicar(env, cobro, cuenta, null, { estado: 'no_se_cobro', motivo, monto: null, referencia: null }, acceso));
}

async function revisarOrden(env: Env, cobro: CobroWorker) {
  const acceso = await accesoDelCobro(env, cobro);
  const { estado, datos } = await sinCorte(() => mp('GET', `/v1/orders/${encodeURIComponent(cobro.orden_id ?? '')}`, acceso));
  if (estado !== 200 || !datos) {
    console.error('[mp] la orden no se pudo leer', estado, codigoDeError(datos));
    throw new Rechazo(502, NO_CONTESTO);
  }
  return paraLaApp(cobro, await aplicar(env, cobro, cobro.llaves?.cuenta_id ?? '', cobro.orden_id, leerOrden(datos), acceso));
}

async function cancelarOrden(env: Env, cobro: CobroWorker) {
  const acceso = await accesoDelCobro(env, cobro);
  const ruta = `/v1/orders/${encodeURIComponent(cobro.orden_id ?? '')}/cancel`;
  const { estado, datos } = await sinCorte(() => mp('POST', ruta, acceso, {
    clave: `cancelar-${cobro.cobro_id}`,
    cabeceras: { 'x-allow-cancelable-status': 'at_terminal' },
  }));
  if (estado === 200 || estado === 201) {
    const lectura = leerOrden(datos ?? {});
    // En la Point todavía: la cancelación está pedida y la confirma el aviso.
    if (lectura.estado === 'tomado' || lectura.estado === 'esperando') return paraLaApp(cobro, { cancelando: true });
    return paraLaApp(cobro, await aplicar(env, cobro, cobro.llaves?.cuenta_id ?? '', cobro.orden_id, lectura, acceso));
  }
  // Ya no se puede cancelar (ya se pagó, venció…): lo que diga la orden.
  console.warn('[mp] no se canceló', estado, codigoDeError(datos));
  return revisarOrden(env, cobro);
}

// Guarda en Postgres lo que dijo Mercado Pago y, si la cuenta se cerró con el ticket prendido, lo imprime.
async function aplicar(env: Env, cobro: CobroWorker, cuenta: string, ordenId: string | null, lectura: Lectura, acceso: string) {
  const resultado = await llamar<Resultado>(env, 'worker', 'resultado_cobro', {
    p_cobro_id: cobro.cobro_id,
    p_cuenta_id: cuenta,
    p_orden_id: ordenId,
    p_estado: lectura.estado,
    p_motivo: lectura.motivo,
    p_monto: lectura.estado === 'pagado' ? lectura.monto : null,
  });
  if (resultado.cambio) console.log('[mp] cobro', cobro.cobro_id, resultado.estado, resultado.motivo ?? '');
  if (resultado.ticket && resultado.cerrada) await imprimirTicket(acceso, cobro.terminal_id, resultado.venta_id, resultado.ticket);
  return { estado: resultado.estado, motivo: resultado.motivo, tomado: resultado.tomado ?? cobro.tomado, cerrada: resultado.cerrada ?? false, folio: resultado.folio ?? null };
}

// Mercado Pago sin respuesta, para las rutas que no tienen nada que dejar apartado.
async function sinCorte<T>(trabajo: () => Promise<T>): Promise<T> {
  try {
    return await trabajo();
  } catch (e) {
    if (e instanceof SinRespuesta) throw new Rechazo(502, NO_CONTESTO);
    throw e;
  }
}

function uuid(valor: unknown): string {
  if (typeof valor !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(valor)) {
    throw new Rechazo(400, 'Faltan los datos.');
  }
  return valor;
}

async function sha256Hex(texto: string): Promise<string> {
  const huella = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(texto)));
  return Array.from(huella, (b) => b.toString(16).padStart(2, '0')).join('');
}
