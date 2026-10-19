// Lo que lee el panel del gerente en la pieza 5 (migración reportes; libreta 5; maqueta Cortes y
// reportes 7J6LvYWiktRnGxNugbuaoe): Mesas ahora y Tus meseros en Inicio, las columnas de Mesas, el
// reporte de un día en Cortes y reportes, y la hora de corte en Ajustes. Todo lo cuenta Postgres
// (lo que falta por cobrar, lo vendido, los descuentos, lo cancelado); aquí solo se pide y se
// convierte a números. Solo el gerente lo usa.
import type { ResumenTurno } from './caja';
import { esDeRed, Fallo, mensajeDeError, SIN_CONEXION } from './errores';
import { supabase } from './supabase';

const n = (x: unknown) => Number(x);

// ─── Mesas ahora ────────────────────────────────────────────────────────────────────────────

// Cada mesa en su orden; venta_id, total y abierta_at vienen vacíos si está libre.
export type MesaAhora = {
  id: number;
  nombre: string;
  venta_id: number | null;
  total: number | null;
  abierta_at: string | null;
};
export type MesasAhora = { hora: string; mesas: MesaAhora[]; ocupadas: number; por_cobrar: number };

export async function leerMesasAhora(restauranteId: string): Promise<MesasAhora> {
  const { data, error } = await supabase.rpc('mesas_ahora', { p_restaurante_id: restauranteId });
  if (error) throw error;
  const r = data as MesasAhora;
  return {
    ...r,
    mesas: r.mesas.map((m) => ({ ...m, total: m.total === null ? null : n(m.total) })),
    por_cobrar: n(r.por_cobrar),
  };
}

// ─── Tus meseros ────────────────────────────────────────────────────────────────────────────

export type Persona = {
  miembro_id: number;
  nombre: string;
  roles: string[];
  abiertas: number;
  ventas: number;
  vendido: number;
};
export type TusMeseros = {
  hoy: string;
  hora: string;
  equipo: { meseros: number; caja: number; cocina: number };
  personas: Persona[];
};

export async function leerTusMeseros(restauranteId: string): Promise<TusMeseros> {
  const { data, error } = await supabase.rpc('tus_meseros', { p_restaurante_id: restauranteId });
  if (error) throw error;
  const r = data as TusMeseros;
  return { ...r, personas: r.personas.map((p) => ({ ...p, vendido: n(p.vendido) })) };
}

// ─── Cortes y reportes ──────────────────────────────────────────────────────────────────────

export type PagoCancelado = {
  pago_id: number;
  folio: number | null;
  cuenta: string;
  metodo: 'efectivo' | 'tarjeta' | 'transferencia';
  monto: number;
  propina: number;
  motivo: string;
  pidio_id: number;
  pidio: string;
  autorizo_id: number;
  autorizo: string;
  cancelado_at: string;
};

// El corte de un turno (resumen_turno: con la caja abierta no trae lo esperado ni quién cobró),
// con sus entradas y salidas y sus pagos cancelados.
export type TurnoDelDia = ResumenTurno & {
  movimientos: NonNullable<ResumenTurno['movimientos']>;
  pagos_cancelados: PagoCancelado[];
};

export type Descuento = {
  venta_id: number;
  folio: number | null;
  tipo: 'mesa' | 'para_llevar' | 'domicilio';
  cuenta: string;
  renglon_id: number | null; // vacío: el descuento es de toda la cuenta
  nombre: string | null;
  cantidad: number | null;
  descuento_tipo: 'porcentaje' | 'pesos';
  descuento_valor: number;
  descuento: number;
  motivo: string;
  pidio_id: number | null;
  pidio: string | null;
  autorizo_id: number | null;
  autorizo: string | null;
  created_at: string | null;
};

export type Cancelacion = {
  que: 'renglon' | 'cuenta';
  venta_id: number;
  folio: number | null;
  tipo: 'mesa' | 'para_llevar' | 'domicilio';
  cuenta: string;
  estado: 'abierta' | 'cerrada' | 'cancelada';
  renglon_id: number | null;
  nombre: string | null;
  cantidad: number | null;
  importe: number;
  motivo: string;
  pidio_id: number;
  pidio: string;
  autorizo_id: number;
  autorizo: string;
  created_at: string;
};

export type OtroCambio = {
  accion: 'cambiar_mesa' | 'juntar_mesas' | 'quitar_descuento' | 'cambiar_hora_corte';
  detalle: Record<string, unknown>;
  cuenta: string | null; // la cuenta a la que se le hizo («Mesa 1»); vacía en la hora de corte
  quien: string | null;
  created_at: string;
};

export type ReporteDia = {
  dia: string;
  hoy: string;
  zona: string;
  hora_corte: number;
  turnos: TurnoDelDia[];
  descuentos: { total: number; cuentas: number; lista: Descuento[] };
  cancelaciones: { total: number; renglones: number; cuentas: number; lista: Cancelacion[] };
  otros: OtroCambio[];
};

// El reporte de un día de negocio ('aaaa-mm-dd'); sin día, el de hoy.
export async function leerReporte(restauranteId: string, dia: string | null): Promise<ReporteDia> {
  const { data, error } = await supabase.rpc('reporte_del_dia', { p_restaurante_id: restauranteId, p_dia: dia });
  if (error) throw error;
  const r = data as ReporteDia;
  return {
    ...r,
    turnos: r.turnos.map((t) => ({
      ...t,
      fondo_inicial: n(t.fondo_inicial),
      propinas: t.propinas.map((p) => ({ ...p, total: n(p.total), pagado: n(p.pagado), falta: n(p.falta) })),
      cortes: t.cortes?.map((k) => ({ ...k, esperado: n(k.esperado), contado: n(k.contado), diferencia: n(k.diferencia) })),
      por_persona: t.por_persona?.map((q) => ({
        ...q,
        total: n(q.total),
        efectivo: n(q.efectivo),
        tarjeta: n(q.tarjeta),
        transferencia: n(q.transferencia),
      })),
      movimientos: t.movimientos.map((m) => ({ ...m, monto: n(m.monto) })),
      pagos_cancelados: t.pagos_cancelados.map((p) => ({ ...p, monto: n(p.monto), propina: n(p.propina) })),
    })),
    descuentos: {
      ...r.descuentos,
      total: n(r.descuentos.total),
      lista: r.descuentos.lista.map((d) => ({ ...d, descuento_valor: n(d.descuento_valor), descuento: n(d.descuento) })),
    },
    cancelaciones: {
      ...r.cancelaciones,
      total: n(r.cancelaciones.total),
      lista: r.cancelaciones.lista.map((c) => ({ ...c, importe: n(c.importe) })),
    },
  };
}

// ─── La hora de corte ───────────────────────────────────────────────────────────────────────

export async function leerHoraCorte(restauranteId: string): Promise<number> {
  const { data, error } = await supabase.from('restaurantes').select('hora_corte').eq('id', restauranteId).single();
  if (error) throw error;
  return data.hora_corte;
}

// Postgres revisa que sea gerente y que vaya de 0 a 23; sus errores vienen en español.
export async function fijarHoraCorte(restauranteId: string, hora: number): Promise<void> {
  const { error } = await supabase.rpc('fijar_hora_corte', { p_restaurante_id: restauranteId, p_hora: hora });
  if (error) {
    console.error('[reportes] fijar_hora_corte no se pudo:', error);
    throw new Fallo(esDeRed(error) ? SIN_CONEXION : mensajeDeError(error));
  }
}
