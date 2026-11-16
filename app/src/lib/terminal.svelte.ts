// La terminal conectada en el punto de venta (libreta 5, «La terminal conectada»; maqueta 8aJ1RUKVd2xA5kgawVpDkQ v2):
// mandar el monto de una cuenta a la Point, revisar cómo va, cancelarlo, «Sí se pagó / No se pagó» y devolver un pago.
// Como lib/pos.ts, cada función recibe la conexión y este archivo nunca importa lib/supabase.ts: lo usan el aparato
// del equipo y el panel. Lo que pasa con cada cobro lo guarda Postgres (resultado_cobro); aquí solo se lee y se pide.
import type { SupabaseClient } from '@supabase/supabase-js';
import { ALGO_SALIO_PANEL, esDeRed, mensajeDeError, SIN_CONEXION } from './errores';
import { escuchar, FalloPos } from './pos';

export const MINIMO_TERMINAL = 5;

export type EstadoCobro = 'mandando' | 'esperando' | 'pagado' | 'no_se_cobro' | 'revisar';
export type MotivoCobro = 'rechazada' | 'vencida' | 'cancelada' | 'cancelada_terminal' | 'ocupada' | 'sin_conexion';

export type CobroTerminal = {
  id: number;
  venta_id: number;
  estado: EstadoCobro;
  motivo: MotivoCobro | null;
  monto: number;
  propina: number;
  terminal_id: string;
  mandado_por: number;
  confirmado_por: number | null;
  pago_id: number | null;
  tomado_at: string | null;
  vence_at: string;
  created_at: string;
};

export const ACTIVO: EstadoCobro[] = ['mandando', 'esperando', 'revisar'];
export const esActivo = (c: { estado: EstadoCobro } | null | undefined) => !!c && ACTIVO.includes(c.estado);

// La Point se enseña por sus últimos 4: «Point ••4821».
export const nombrePoint = (id: string | null) => (id ? `Point ••${id.slice(-4)}` : 'Point');

function fallo(contexto: string, error: unknown): FalloPos {
  console.error(`[terminal] ${contexto}:`, error);
  const sinRed = esDeRed(error);
  return new FalloPos(sinRed ? SIN_CONEXION : mensajeDeError(error), sinRed);
}

// ─── El Worker ────────────────────────────────────────────────────────────────

async function alWorker(cliente: SupabaseClient, camino: string, cuerpo: Record<string, unknown>): Promise<Record<string, unknown>> {
  const { data, error } = await cliente.auth.getSession();
  if (error || !data.session) {
    console.error('[terminal] no hay sesión para hablar con el Worker:', error);
    throw new FalloPos('Tu sesión venció. Vuelve a entrar.');
  }
  let respuesta: Response;
  try {
    respuesta = await fetch(`${import.meta.env.VITE_API_URL}${camino}`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${data.session.access_token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(cuerpo),
    });
  } catch (falla) {
    console.error(`[terminal] ${camino}: no se pudo hablar con el Worker:`, falla);
    throw new FalloPos(SIN_CONEXION, true);
  }
  const datos = await respuesta.json().catch(() => null);
  if (!respuesta.ok) {
    console.error(`[terminal] ${camino}: el Worker dijo ${respuesta.status}:`, datos);
    throw new FalloPos(typeof datos?.error === 'string' ? datos.error : ALGO_SALIO_PANEL);
  }
  return (datos ?? {}) as Record<string, unknown>;
}

// Lo que contesta el Worker de un cobro. ok:false = no se mandó nada porque otro cobro de la sucursal espera.
export type RespuestaCobro =
  | { ok: false; motivo: 'ocupada' }
  | {
      ok: true;
      cobro_id: number;
      estado: EstadoCobro;
      motivo: MotivoCobro | null;
      tomado: boolean;
      cerrada?: boolean;
      folio?: number | null;
      cancelando?: boolean;
      error?: string; // Mercado Pago no contestó: el cobro se queda «mandando» y se reintenta con la misma clave
    };

export async function mandarATerminal(
  cliente: SupabaseClient,
  pedido: { ventaId: number; clave: string; monto: number | null; propina: { porcentaje: 10 | 15 } | { cantidad: number } | null },
): Promise<RespuestaCobro> {
  return (await alWorker(cliente, '/terminal/mandar', {
    venta: pedido.ventaId,
    clave: pedido.clave,
    monto: pedido.monto,
    propina_porcentaje: pedido.propina && 'porcentaje' in pedido.propina ? pedido.propina.porcentaje : null,
    propina: pedido.propina && 'cantidad' in pedido.propina ? pedido.propina.cantidad : null,
  })) as RespuestaCobro;
}

export async function revisarCobro(cliente: SupabaseClient, cobroId: number): Promise<RespuestaCobro> {
  return (await alWorker(cliente, '/terminal/revisar', { cobro: cobroId })) as RespuestaCobro;
}

export async function cancelarCobro(cliente: SupabaseClient, cobroId: number): Promise<RespuestaCobro> {
  return (await alWorker(cliente, '/terminal/cancelar', { cobro: cobroId })) as RespuestaCobro;
}

// «Sí se pagó / No se pagó»: lo resuelve quien lo mandó, directo en Postgres.
export async function confirmarCobro(cliente: SupabaseClient, cobroId: number, pagado: boolean): Promise<{ cerrada: boolean; folio: number | null }> {
  const { data, error } = await cliente.rpc('confirmar_cobro_terminal', { p_cobro_id: cobroId, p_pagado: pagado });
  if (error) throw fallo('confirmar_cobro_terminal no se pudo', error);
  const d = data as { cerrada: boolean; folio: number | null };
  return { cerrada: !!d.cerrada, folio: d.folio ?? null };
}

// Cancelar un pago de la terminal devuelve el dinero: siempre por el Worker, con el PIN de otra persona o sin PIN si
// quien cancela es de la caja o gerente.
export async function devolverPago(
  cliente: SupabaseClient,
  pedido: { pagoId: number; motivo: string; autoriza: number | null; pin: string | null },
): Promise<{ ok: true; autoriza: number; reabierta: boolean } | { ok: false; motivo: string; quedan?: number; hasta?: string | null }> {
  const r = await alWorker(cliente, '/terminal/devolver', {
    pago: pedido.pagoId,
    motivo: pedido.motivo,
    ...(pedido.autoriza !== null ? { autoriza: pedido.autoriza } : {}),
    ...(pedido.pin ? { pin: pedido.pin } : {}),
  });
  if (r.ok) return { ok: true, autoriza: Number(r.autoriza), reabierta: !!r.reabierta };
  return { ok: false, motivo: String(r.motivo ?? 'pin'), quedan: r.quedan === undefined ? undefined : Number(r.quedan), hasta: (r.hasta as string | null) ?? null };
}

// ─── La vigía: la conexión de la sucursal y sus cobros ────────────────────────
// La tienen el punto de venta y la caja. Lee la conexión (para saber si sale «Mandar a la terminal») y los cobros de
// la sucursal de los últimos 15 minutos, y los vuelve a leer con el tiempo real de cobros_terminal. La conexión no está
// en tiempo real: se vuelve a leer al regresar a la pestaña y cada minuto.

const COLUMNAS =
  'id, venta_id, estado, motivo, monto, propina, terminal_id, mandado_por, confirmado_por, pago_id, tomado_at, vence_at, created_at';

export class VigiaTerminal {
  conexion = $state<{ terminalId: string | null; desconectada: boolean } | null>(null);
  cobros = $state<CobroTerminal[]>([]);
  leida = $state(false);
  // Sale «Mandar a la terminal»: la sucursal está conectada y tiene su Point.
  puedeMandar = $derived(!!this.conexion && !this.conexion.desconectada && !!this.conexion.terminalId);
  point = $derived(nombrePoint(this.conexion?.terminalId ?? null));

  constructor(
    private readonly cliente: SupabaseClient,
    private readonly restauranteId: string,
  ) {}

  // El cobro que espera de una cuenta, o el último que tuvo (para el «No se cobró» y su porqué).
  activo(ventaId: number): CobroTerminal | null {
    return this.cobros.find((c) => c.venta_id === ventaId && esActivo(c)) ?? null;
  }
  ultimo(ventaId: number): CobroTerminal | null {
    return this.cobros.find((c) => c.venta_id === ventaId) ?? null;
  }

  // Lo que la marca de la mesa o de la cuenta dice: esperando, revisa o no se cobró (el último, si no se ha vuelto a
  // mandar ni anotar nada). null = nada que marcar.
  marca(ventaId: number): { tipo: 'terminal' | 'revisa' | 'no-cobro'; monto: number } | null {
    const c = this.ultimo(ventaId);
    if (!c) return null;
    if (c.estado === 'mandando' || c.estado === 'esperando') return { tipo: 'terminal', monto: c.monto };
    if (c.estado === 'revisar') return { tipo: 'revisa', monto: c.monto };
    if (c.estado === 'no_se_cobro' && c.motivo !== 'cancelada' && c.confirmado_por === null) return { tipo: 'no-cobro', monto: c.monto };
    return null;
  }

  // Un cobro que la hoja acaba de saber por el Worker, antes de que llegue el tiempo real.
  anotar(cobro: Partial<CobroTerminal> & { id: number }) {
    const i = this.cobros.findIndex((c) => c.id === cobro.id);
    if (i >= 0) this.cobros[i] = { ...this.cobros[i], ...cobro };
  }

  async leer(): Promise<void> {
    const desde = new Date(Date.now() - 15 * 60 * 1000).toISOString();
    const [conexion, cobros] = await Promise.all([
      this.cliente.from('mercado_pago').select('terminal_id, desconectada_at').eq('restaurante_id', this.restauranteId).maybeSingle(),
      this.cliente
        .from('cobros_terminal')
        .select(COLUMNAS)
        .eq('restaurante_id', this.restauranteId)
        .or(`created_at.gte.${desde},estado.in.(mandando,esperando,revisar)`)
        .order('id', { ascending: false })
        .limit(50),
    ]);
    if (conexion.error) throw fallo('no se pudo leer la conexión de Mercado Pago', conexion.error);
    if (cobros.error) throw fallo('no se pudieron leer los cobros de la terminal', cobros.error);
    this.conexion = conexion.data
      ? { terminalId: conexion.data.terminal_id, desconectada: conexion.data.desconectada_at !== null }
      : null;
    this.cobros = (cobros.data ?? []).map((c) => ({ ...c, monto: Number(c.monto), propina: Number(c.propina) }) as CobroTerminal);
    this.leida = true;
  }

  // Empieza a vigilar; regresa con qué se deja de vigilar.
  iniciar(): () => void {
    const leer = () => this.leer().catch(() => {});
    leer();
    const dejar = escuchar(this.cliente, this.restauranteId, ['cobros_terminal'], leer);
    const reloj = setInterval(leer, 60 * 1000);
    const alVolver = () => {
      if (document.visibilityState === 'visible') leer();
    };
    document.addEventListener('visibilitychange', alVolver);
    return () => {
      dejar();
      clearInterval(reloj);
      document.removeEventListener('visibilitychange', alVolver);
    };
  }
}
