// Los renglones de Cortes y reportes con la forma de la Caja a lo ancho (14 nov 2026; la Caja de la adaptabilidad,
// caja/caja/filas.ts): cada turno del día y cada cosa que pasó en sus cuentas (un descuento, una cancelación, otro
// cambio), ya en palabras (Qué · Tipo · Quién · Monto). Todo sale de reporte_del_dia: aquí no se suma nada, solo se
// escribe. La tabla solo los pinta; la tarjeta de la derecha enseña el detalle del que se toca.
import { pesos, enZona, plural } from '../../../lib/formato';
import type { Cancelacion, Descuento, OtroCambio, ReporteDia, TurnoDelDia } from '../../../lib/reportes';
import { quienLoHizo } from './quien';

export type FiltroCortes = 'todo' | 'turnos' | 'descuentos' | 'cancelaciones' | 'otros';

type Comun = {
  clave: string;
  icono: string;
  titulo: string; // «Turno de 08:00 a 16:10», «2 Taco al pastor»
  sub: string; // abajo del título: «Mesa 4 · Folio 1043»; vacío si no lleva
  tipo: string; // «Corte de caja», «Descuento · 10 %», «Cancelación»
  quien: string; // «Pepe · 14:05»
  autorizo: string; // abajo de quién, si otra persona lo autorizó: «Autorizó Lupita»
  buscar: string; // sin acentos, para la búsqueda
};

export type FilaCortes =
  | (Comun & { que: 'turno'; turno: TurnoDelDia; sello: Sello })
  | (Comun & { que: 'descuento'; descuento: Descuento })
  | (Comun & { que: 'cancelacion'; cancelacion: Cancelacion })
  | (Comun & { que: 'otro'; otro: OtroCambio });

// El sello de un turno: abierta; si todo cuadra, «Cuadra»; si solo un método no, lo que dice ese método; si son
// varios, cuántos. No se suman efectivo y tarjeta entre sí (como el Turno de la pieza 5).
export type Sello = { texto: string; clase: 'abierta' | 'cuadra' | 'falta' | 'sobra' };

export function diferencia(d: number): Sello {
  if (d === 0) return { texto: 'Cuadra', clase: 'cuadra' };
  return d < 0 ? { texto: `Faltan ${pesos(-d)}`, clase: 'falta' } : { texto: `Sobran ${pesos(d)}`, clase: 'sobra' };
}

function selloDe(t: TurnoDelDia): Sello {
  if (t.estado === 'abierto') return { texto: 'Abierta', clase: 'abierta' };
  const no = (t.cortes ?? []).filter((k) => k.diferencia !== 0);
  if (!no.length) return { texto: 'Cuadra', clase: 'cuadra' };
  if (no.length === 1) return diferencia(no[0].diferencia);
  return { texto: `No cuadran ${no.length} métodos`, clase: 'falta' };
}

// «Mesa 4», «Comer aquí · #23», «Para llevar · Sr. Ramírez», «Domicilio · Doña Mari».
export function cuentaDe(x: { tipo: string; cuenta: string }): string {
  if (x.tipo === 'comer_aqui') return `Comer aquí · ${x.cuenta}`;
  if (x.tipo === 'para_llevar') return `Para llevar · ${x.cuenta}`;
  if (x.tipo === 'domicilio') return `Domicilio · ${x.cuenta}`;
  return x.cuenta;
}

const valor = (tipo: 'porcentaje' | 'pesos', v: number) => (tipo === 'porcentaje' ? `${v} %` : pesos(v));

export function textoOtro(o: OtroCambio): string {
  const d = o.detalle as Record<string, string | number | null | undefined>;
  if (o.accion === 'cambiar_mesa') return `De ${d.de} a ${d.a}`;
  if (o.accion === 'juntar_mesas') return `${d.de} con ${d.a}`;
  if (o.accion === 'cambiar_hora_corte') return `De ${d.de}:00 a ${d.a}:00`;
  return d.nombre ? String(d.nombre) : 'Toda la cuenta';
}

export const TIPO_OTRO: Record<OtroCambio['accion'], string> = {
  cambiar_mesa: 'Cambio de mesa',
  juntar_mesas: 'Juntó mesas',
  quitar_descuento: 'Quitó un descuento',
  cambiar_hora_corte: 'Hora de corte',
};

const ICONO_OTRO: Record<OtroCambio['accion'], string> = {
  cambiar_mesa: 'cambiar',
  juntar_mesas: 'juntar',
  quitar_descuento: 'porcentaje',
  cambiar_hora_corte: 'reloj',
};

const sinAcentos = (texto: string) => texto.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
const juntos = (...partes: (string | number | null | undefined)[]) => partes.filter((p) => p !== null && p !== undefined && p !== '').join(' · ');

// El que lo pidió (o lo hizo) y, aparte, quién lo autorizó si fue otra persona.
function quienes(pidioId: number | null, pidio: string | null, autorizoId: number | null, autorizo: string | null) {
  const texto = quienLoHizo(pidioId, pidio, autorizoId, autorizo);
  if (texto.startsWith('Pidió ')) return { quien: pidio ?? '', autorizo: `Autorizó ${autorizo}` };
  if (texto.startsWith('Lo hizo ')) return { quien: pidio ?? '', autorizo: '' };
  return { quien: autorizo ?? '—', autorizo: '' };
}

// Todos los renglones de un día: primero los turnos (como se abrieron) y después lo que pasó, por hora.
export function filasDelDia(r: ReporteDia): FilaCortes[] {
  const hora = (momento: string | null) => (momento ? enZona(momento, r.zona).hora : '');

  const turnos: FilaCortes[] = r.turnos.map((t) => {
    const abierto = t.estado === 'abierto';
    const titulo = abierto ? `Turno desde las ${hora(t.abierto_at)}` : `Turno de ${hora(t.abierto_at)} a ${t.cerrado_at ? hora(t.cerrado_at) : '—'}`;
    const quien = abierto || !t.cerrado_por || t.abierto_por === t.cerrado_por ? t.abierto_por : `${t.abierto_por} y ${t.cerrado_por}`;
    const sub = `Fondo ${pesos(t.fondo_inicial)}`;
    return {
      que: 'turno',
      clave: `t${t.id}`,
      icono: abierto ? 'billete' : 'corte',
      titulo,
      sub,
      tipo: abierto ? 'Turno abierto' : 'Corte de caja',
      quien,
      autorizo: '',
      turno: t,
      sello: selloDe(t),
      buscar: sinAcentos(juntos(titulo, 'turno corte caja', quien)),
    };
  });

  const pasaron: { cuando: string | null; fila: FilaCortes }[] = [];

  for (const d of r.descuentos.lista) {
    const q = quienes(d.pidio_id, d.pidio, d.autorizo_id, d.autorizo);
    const titulo = d.renglon_id ? [d.cantidad, d.nombre].filter(Boolean).join(' ') : 'Toda la cuenta';
    const sub = juntos(d.cuenta, d.folio ? `Folio ${d.folio}` : '');
    const tipo = `Descuento · ${valor(d.descuento_tipo, d.descuento_valor)}`;
    pasaron.push({
      cuando: d.created_at,
      fila: {
        que: 'descuento',
        clave: `d${d.venta_id}-${d.renglon_id ?? 'cuenta'}`,
        icono: 'porcentaje',
        titulo,
        sub,
        tipo,
        quien: juntos(q.quien, hora(d.created_at)),
        autorizo: q.autorizo,
        descuento: d,
        buscar: sinAcentos(juntos(titulo, cuentaDe(d), sub, tipo, d.motivo, d.pidio, d.autorizo)),
      },
    });
  }

  for (const c of r.cancelaciones.lista) {
    const q = quienes(c.pidio_id, c.pidio, c.autorizo_id, c.autorizo);
    const titulo = c.que === 'cuenta' ? 'Toda la cuenta' : `${c.cantidad} ${c.nombre}`;
    const sub = juntos(c.cuenta, c.folio ? `Folio ${c.folio}` : '');
    pasaron.push({
      cuando: c.created_at,
      fila: {
        que: 'cancelacion',
        clave: `c${c.que}-${c.venta_id}-${c.renglon_id ?? ''}`,
        icono: 'eliminar',
        titulo,
        sub,
        tipo: 'Cancelación',
        quien: juntos(q.quien, hora(c.created_at)),
        autorizo: q.autorizo,
        cancelacion: c,
        buscar: sinAcentos(juntos(titulo, cuentaDe(c), sub, 'cancelacion', c.motivo, c.pidio, c.autorizo)),
      },
    });
  }

  r.otros.forEach((o, i) => {
    const titulo = textoOtro(o);
    const sub = o.accion === 'quitar_descuento' && o.cuenta ? o.cuenta : '';
    pasaron.push({
      cuando: o.created_at,
      fila: {
        que: 'otro',
        clave: `o${i}-${o.accion}-${o.created_at}`,
        icono: ICONO_OTRO[o.accion],
        titulo,
        sub,
        tipo: TIPO_OTRO[o.accion],
        quien: juntos(o.quien, hora(o.created_at)),
        autorizo: '',
        otro: o,
        buscar: sinAcentos(juntos(titulo, sub, TIPO_OTRO[o.accion], o.quien)),
      },
    });
  });

  // Por hora; lo que no trae hora (un descuento sin su renglón en la bitácora), al final.
  pasaron.sort((a, b) => (a.cuando === b.cuando ? 0 : a.cuando === null ? 1 : b.cuando === null ? -1 : a.cuando < b.cuando ? -1 : 1));
  return [...turnos, ...pasaron.map((p) => p.fila)];
}

export function cuantosDe(filas: FilaCortes[]): Record<FiltroCortes, number> {
  return {
    todo: filas.length,
    turnos: filas.filter((f) => f.que === 'turno').length,
    descuentos: filas.filter((f) => f.que === 'descuento').length,
    cancelaciones: filas.filter((f) => f.que === 'cancelacion').length,
    otros: filas.filter((f) => f.que === 'otro').length,
  };
}

const DEL_FILTRO: Record<FiltroCortes, FilaCortes['que'] | null> = {
  todo: null,
  turnos: 'turno',
  descuentos: 'descuento',
  cancelaciones: 'cancelacion',
  otros: 'otro',
};

export function filtrar(filas: FilaCortes[], filtro: FiltroCortes, busqueda: string): FilaCortes[] {
  const que = DEL_FILTRO[filtro];
  const q = sinAcentos(busqueda.trim()).replace(/^#/, '');
  return filas.filter((f) => (!que || f.que === que) && (!q || f.buscar.includes(q)));
}

// Lo que dice la barra de abajo sin nada elegido: los turnos y, aparte, lo descontado y lo cancelado (los suma Postgres).
export function resumenAbajo(r: ReporteDia): { fuerte: string; chico: string } {
  const fuerte = r.turnos.length ? plural(r.turnos.length, 'turno', 'turnos') : 'Este día no se abrió la caja';
  const chico = `Descuentos ${pesos(r.descuentos.total)} · Cancelaciones ${pesos(r.cancelaciones.total)}`;
  return { fuerte, chico };
}
