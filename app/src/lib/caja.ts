// Lo que leen y llaman la caja y la hoja de cobro (parte 4b, migración caja; libreta 5; maqueta
// La caja FKj5RPPYE1tz6dcaU6F4kX). Como lib/pos.ts, cada función recibe la conexión y este archivo
// nunca importa lib/supabase.ts: lo usan el aparato del equipo y el panel del gerente. El punto de
// venta nunca cobra: solo anota cómo se pagó. Los números (la propina, el cambio, las partes, lo
// esperado del corte) los calcula Postgres; aquí solo se piden y se pintan.
import type { SupabaseClient } from '@supabase/supabase-js';
import { esDeRed, mensajeDeError, SIN_CONEXION } from './errores';
import { FalloPos } from './pos';

export type Metodo = 'efectivo' | 'tarjeta' | 'transferencia';
export const NOMBRE_METODO: Record<Metodo, string> = { efectivo: 'Efectivo', tarjeta: 'Tarjeta', transferencia: 'Transferencia' };

function fallo(contexto: string, error: unknown): FalloPos {
  console.error(`[caja] ${contexto}:`, error);
  const sinRed = esDeRed(error);
  return new FalloPos(sinRed ? SIN_CONEXION : mensajeDeError(error), sinRed);
}

// Lo que falta de una cuenta, solo para verlo en la lista (en centavos, sin redondeos de más). Al
// anotar, quien decide cuánto falta es Postgres.
export function faltaDe(v: { total: number; pagado: number }): number {
  return (Math.round(v.total * 100) - Math.round(v.pagado * 100)) / 100;
}

// ─── El turno ───────────────────────────────────────────────────────────────────────────────

export type Turno = { id: number; abierto_por: number; fondo_inicial: number; created_at: string };

// El turno abierto del restaurante (hay uno o ninguno), y el fondo del último, para proponerlo.
export async function leerTurno(
  cliente: SupabaseClient,
  restauranteId: string,
): Promise<{ abierto: Turno | null; ultimoFondo: number | null }> {
  const { data, error } = await cliente
    .from('turnos')
    .select('id, abierto_por, fondo_inicial, estado, created_at')
    .eq('restaurante_id', restauranteId)
    .order('created_at', { ascending: false })
    .order('id', { ascending: false })
    .limit(1);
  if (error) throw error;
  const t = data[0];
  if (!t) return { abierto: null, ultimoFondo: null };
  const turno = { id: t.id, abierto_por: t.abierto_por, fondo_inicial: Number(t.fondo_inicial), created_at: t.created_at };
  return { abierto: t.estado === 'abierto' ? turno : null, ultimoFondo: turno.fondo_inicial };
}

export async function abrirTurno(cliente: SupabaseClient, restauranteId: string, fondo: number): Promise<number> {
  const { data, error } = await cliente.rpc('abrir_turno', { p_restaurante_id: restauranteId, p_fondo: fondo });
  if (error) throw fallo('abrir_turno no se pudo', error);
  return data as number;
}

// Lo que quien llama cobró en efectivo en el turno abierto, con propinas.
export async function miEfectivo(cliente: SupabaseClient, restauranteId: string): Promise<number> {
  const { data, error } = await cliente.rpc('mi_efectivo', { p_restaurante_id: restauranteId });
  if (error) throw error;
  return Number(data);
}

// ─── La hoja de cobro ───────────────────────────────────────────────────────────────────────

export type Propina = { porcentaje: 10 | 15 } | { cantidad: number } | null;

export type Resumen = {
  estado: 'abierta' | 'cerrada' | 'cancelada';
  total: number;
  pagado: number;
  falta: number;
  partes: number[];
  monto: number;
  cabe: boolean;
  propina_10: number;
  propina_15: number;
  propina: number;
  cobrar: number;
  cambio: number | null;
};

function numeros(r: Record<string, unknown>): Resumen {
  const n = (x: unknown) => (x === null || x === undefined ? null : Number(x));
  return {
    estado: r.estado as Resumen['estado'],
    total: n(r.total)!,
    pagado: n(r.pagado)!,
    falta: n(r.falta)!,
    partes: (r.partes as unknown[]).map(Number),
    monto: n(r.monto)!,
    cabe: r.cabe as boolean,
    propina_10: n(r.propina_10)!,
    propina_15: n(r.propina_15)!,
    propina: n(r.propina)!,
    cobrar: n(r.cobrar)!,
    cambio: n(r.cambio),
  };
}

// Los números de la hoja para lo que lleva escrito: no anota nada.
export async function resumenCuenta(
  cliente: SupabaseClient,
  ventaId: number,
  pedido: { monto: number | null; partes: number; propina: Propina; recibido: number | null },
): Promise<Resumen> {
  const { data, error } = await cliente.rpc('resumen_cuenta', {
    p_venta_id: ventaId,
    p_monto: pedido.monto,
    p_partes: pedido.partes,
    p_propina_porcentaje: pedido.propina && 'porcentaje' in pedido.propina ? pedido.propina.porcentaje : null,
    p_propina: pedido.propina && 'cantidad' in pedido.propina ? pedido.propina.cantidad : null,
    p_recibido: pedido.recibido,
  });
  if (error) throw fallo('resumen_cuenta no se pudo', error);
  return numeros(data as Record<string, unknown>);
}

export type Cobro = { pago_id: number | null; cerrada: boolean; folio: number | null; cambio: number; falta: number };

// Anota un pago. Con la misma clave Postgres no lo anota dos veces. Sin método ni monto, cierra una
// cuenta de $0.
export async function cobrar(
  cliente: SupabaseClient,
  pago: {
    ventaId: number;
    clave: string;
    metodo: Metodo | null;
    monto: number | null;
    propina: Propina;
    recibido: number | null;
    referencia: string;
  },
): Promise<Cobro> {
  const { data, error } = await cliente.rpc('cobrar', {
    p_venta_id: pago.ventaId,
    p_clave: pago.clave,
    p_metodo: pago.metodo,
    p_monto: pago.monto,
    p_propina_porcentaje: pago.propina && 'porcentaje' in pago.propina ? pago.propina.porcentaje : null,
    p_propina: pago.propina && 'cantidad' in pago.propina ? pago.propina.cantidad : null,
    p_recibido: pago.metodo === 'efectivo' ? pago.recibido : null,
    p_referencia: pago.metodo === 'efectivo' ? null : pago.referencia,
  });
  if (error) throw fallo('cobrar no se pudo', error);
  const r = data as Record<string, unknown>;
  return {
    pago_id: (r.pago_id as number | null) ?? null,
    cerrada: r.cerrada as boolean,
    folio: (r.folio as number | null) ?? null,
    cambio: Number(r.cambio),
    falta: Number(r.falta),
  };
}

export type Pago = {
  id: number;
  venta_id: number;
  metodo: Metodo;
  monto: number;
  propina: number;
  cobrado_por: number | null;
  turno_id: number | null;
  created_at: string;
  // Un pago cancelado se queda en la lista, tachado, y ya no cuenta (parte 4c).
  cancelado_at: string | null;
  cancelado_por: number | null;
  cancelado_motivo: string | null;
};

// Los pagos ya anotados de unas cuentas, también los cancelados.
export async function leerPagos(cliente: SupabaseClient, restauranteId: string, ventas: number[]): Promise<Pago[]> {
  if (ventas.length === 0) return [];
  const { data, error } = await cliente
    .from('pagos')
    .select('id, venta_id, metodo, monto, propina, cobrado_por, turno_id, created_at, cancelado_at, cancelado_por, cancelado_motivo')
    .eq('restaurante_id', restauranteId)
    .in('venta_id', ventas)
    .order('id');
  if (error) throw error;
  return (data as Pago[]).map((p) => ({ ...p, monto: Number(p.monto), propina: Number(p.propina) }));
}

// ─── Lo cobrado en el turno ─────────────────────────────────────────────────────────────────

export type Cobrada = {
  id: number;
  folio: number;
  titulo: string;
  tipo: 'mesa' | 'para_llevar' | 'domicilio';
  total: number;
  abierta_por: number | null;
  cerrada_at: string;
  metodos: Metodo[]; // sin los pagos cancelados
};

// Las cuentas que se cerraron en este turno, la más reciente arriba, con cómo se pagaron.
export async function leerCobradas(cliente: SupabaseClient, restauranteId: string, turnoId: number): Promise<Cobrada[]> {
  const { data, error } = await cliente
    .from('ventas')
    .select('id, folio, tipo, mesa_nombre, cliente_nombre, total, abierta_por, cerrada_at')
    .eq('restaurante_id', restauranteId)
    .eq('estado', 'cerrada')
    .eq('turno_id', turnoId)
    .order('cerrada_at', { ascending: false })
    .order('id', { ascending: false });
  if (error) throw error;
  const pagos = await leerPagos(
    cliente,
    restauranteId,
    data.map((v) => v.id),
  );
  return data.map((v) => {
    const metodos: Metodo[] = [];
    for (const p of pagos) if (p.venta_id === v.id && !p.cancelado_at && !metodos.includes(p.metodo)) metodos.push(p.metodo);
    return {
      id: v.id,
      folio: v.folio,
      titulo: (v.tipo === 'mesa' ? v.mesa_nombre : v.cliente_nombre) ?? '—',
      tipo: v.tipo,
      total: Number(v.total),
      abierta_por: v.abierta_por,
      cerrada_at: v.cerrada_at,
      metodos,
    };
  });
}

// ─── Entradas, salidas y propinas ───────────────────────────────────────────────────────────

// Efectivo que entra o sale del cajón. Con `mesero`, el pago de sus propinas (el motivo lo pone
// Postgres). Con la misma clave no se anota dos veces.
export async function movimientoCaja(
  cliente: SupabaseClient,
  restauranteId: string,
  mov: { clave: string; tipo: 'retiro' | 'ingreso'; monto: number; motivo: string; mesero: number | null },
): Promise<number> {
  const { data, error } = await cliente.rpc('movimiento_caja', {
    p_restaurante_id: restauranteId,
    p_clave: mov.clave,
    p_tipo: mov.tipo,
    p_monto: mov.monto,
    p_motivo: mov.mesero === null ? mov.motivo : null,
    p_mesero_id: mov.mesero,
  });
  if (error) throw fallo('movimiento_caja no se pudo', error);
  return data as number;
}

// ─── El corte ───────────────────────────────────────────────────────────────────────────────

export async function cerrarTurno(
  cliente: SupabaseClient,
  restauranteId: string,
  contado: Record<Metodo, number>,
): Promise<number> {
  const { data, error } = await cliente.rpc('cerrar_turno', {
    p_restaurante_id: restauranteId,
    p_efectivo: contado.efectivo,
    p_tarjeta: contado.tarjeta,
    p_transferencia: contado.transferencia,
  });
  if (error) throw fallo('cerrar_turno no se pudo', error);
  return data as number;
}

export type PropinaDe = { miembro_id: number; nombre: string; total: number; pagado: number; falta: number };
export type Corte = { metodo: Metodo; esperado: number; contado: number; diferencia: number };
export type PorPersona = { miembro_id: number; nombre: string; total: number } & Record<Metodo, number>;
export type Movimiento = { tipo: 'retiro' | 'ingreso'; monto: number; motivo: string; registrado_por: string; created_at: string };

export type ResumenTurno = {
  id: number;
  estado: 'abierto' | 'cerrado';
  fondo_inicial: number;
  abierto_por: string;
  abierto_at: string;
  cerrado_por: string | null;
  cerrado_at: string | null;
  cuentas_abiertas: number;
  propinas: PropinaDe[];
  // Solo con la caja cerrada: el corte es a ciegas.
  cortes?: Corte[];
  por_persona?: PorPersona[];
  movimientos?: Movimiento[];
};

export async function resumenTurno(cliente: SupabaseClient, turnoId: number): Promise<ResumenTurno> {
  const { data, error } = await cliente.rpc('resumen_turno', { p_turno_id: turnoId });
  if (error) throw fallo('resumen_turno no se pudo', error);
  const r = data as ResumenTurno;
  const n = (x: unknown) => Number(x);
  return {
    ...r,
    fondo_inicial: n(r.fondo_inicial),
    propinas: r.propinas.map((p) => ({ ...p, total: n(p.total), pagado: n(p.pagado), falta: n(p.falta) })),
    cortes: r.cortes?.map((k) => ({ ...k, esperado: n(k.esperado), contado: n(k.contado), diferencia: n(k.diferencia) })),
    por_persona: r.por_persona?.map((q) => ({
      ...q,
      total: n(q.total),
      efectivo: n(q.efectivo),
      tarjeta: n(q.tarjeta),
      transferencia: n(q.transferencia),
    })),
    movimientos: r.movimientos?.map((m) => ({ ...m, monto: n(m.monto) })),
  };
}

// Un monto escrito a mano («$1,240.50», «500»): el número, o null si no se entiende. Solo lee lo
// escrito; las cuentas las hace Postgres.
export function leerMonto(texto: string): number | null {
  const limpio = texto.replace(/[$,\s]/g, '');
  if (!/^\d+(\.\d{0,2})?$/.test(limpio)) return null;
  return Number(limpio);
}
