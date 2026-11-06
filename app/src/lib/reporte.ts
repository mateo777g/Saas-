// El «Reporte en PDF» del Agente IA (libreta 4, «El rediseño del panel»; maqueta KhJcfGHEMiKoakTbNr9cgy;
// planes/trabajo/rediseno/encuestas-agente.md). Lo arma el navegador, sin IA y sin costo, con las mismas
// funciones de Postgres que usa el agente, que no gastan tope: aquí no se cuenta nada, solo se acomoda.
//  - prepararReporte, al elegir De hoy, De la semana o Del mes: las fechas las da Postgres y, si no hay
//    ventas cerradas, no hay reporte.
//  - bajarReporte, al picar «Descargar»: vuelve a leer con esas fechas y arma el archivo. pdf-lib y las
//    letras solo se bajan aquí.
import { diaAnterior, diaConNombre, enZona, plural } from './formato';
import { supabase } from './supabase';
import type { Fila, Tabla } from './reportePdf';

export type PeriodoReporte = 'hoy' | 'semana' | 'mes';

// Lo que se guarda en la plática: con estas fechas, «Descargar» lo vuelve a armar.
export type ReporteGuardado = {
  periodo: PeriodoReporte;
  desde: string;
  hasta: string;
  detalle: string; // «Del lunes 2 al jueves 5 de noviembre»
  sin_ventas?: boolean;
};

export const PERIODOS_REPORTE: { valor: PeriodoReporte; boton: string }[] = [
  { valor: 'hoy', boton: 'De hoy' },
  { valor: 'semana', boton: 'De la semana' },
  { valor: 'mes', boton: 'Del mes' },
];

const TEXTOS: Record<PeriodoReporte, { boton: string; de: string; sin: string }> = {
  hoy: { boton: 'De hoy', de: 'de hoy', sin: 'de hoy' },
  semana: { boton: 'De la semana', de: 'de la semana', sin: 'de esta semana' },
  mes: { boton: 'Del mes', de: 'del mes', sin: 'de este mes' },
};

export const tituloDelPedido = (p: PeriodoReporte) => `Reporte en PDF · ${TEXTOS[p].boton}`;
export const textoEntrega = (p: PeriodoReporte) => `Toma, aquí está tu reporte ${TEXTOS[p].de}.`;
export const textoSinVentas = (p: PeriodoReporte) =>
  `Todavía no hay ventas cerradas ${TEXTOS[p].sin}, así que no hay reporte que armar.`;
export const nombreDelArchivo = (p: PeriodoReporte, restaurante: string) =>
  `Reporte ${TEXTOS[p].de} · ${restaurante}.pdf`;

// ─── Lo que da Postgres ─────────────────────────────────────────────────────────────────────

type Ahora = { fecha: string; hora: string; zona: string; corte: number; hoy: string; lunes: string; primero: string };

// La hora y los días del restaurante: nunca el reloj del aparato.
async function leerAhora(restauranteId: string): Promise<Ahora> {
  const { data, error } = await supabase.rpc('contexto_agente', { p_restaurante_id: restauranteId });
  if (error) throw error;
  const a = data.ahora;
  return {
    fecha: a.fecha,
    hora: a.hora,
    zona: a.zona,
    corte: a.hora_corte,
    hoy: a.dia_de_negocio,
    lunes: a.lunes_de_esta_semana,
    primero: a.primer_dia_del_mes,
  };
}

async function herramienta<T>(restauranteId: string, nombre: string, argumentos: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc('agente_herramienta', {
    p_restaurante_id: restauranteId,
    p_herramienta: nombre,
    p_argumentos: argumentos,
  });
  if (error) throw error;
  return data as T;
}

type Resumen = {
  sin_ventas?: boolean;
  cuentas: number;
  unidades: number;
  total: string;
  ticket_promedio: string;
  promedio_por_dia_abierto: string;
};
type Ranking = {
  sin_ventas?: boolean;
  grupos?: { clave: string; nombre: string; importe: string; unidades: number; cuentas: number }[];
  resto?: { grupos: number; importe: string; unidades: number };
  total?: { cuentas: number; unidades: number; importe: string };
  descuento_a_la_cuenta?: { importe: string };
};
type Propinas = {
  grupos: { nombre: string; propinas: string; pagado: string; falta: string }[];
  total: { propinas: string; pagado: string; falta: string };
};
type ConMotivo = {
  grupos: {
    nombre: string;
    veces: number;
    importe: string;
    motivos?: string[];
    autorizo?: { nombre: string; veces: number }[];
  }[];
  total: { veces: number; importe: string };
};

// ─── Cómo se escribe ────────────────────────────────────────────────────────────────────────

const sinCero = (hora: string) => hora.replace(/^0(\d)/, '$1');
const minuscula = (s: string) => s.charAt(0).toLowerCase() + s.slice(1);
const sinMes = (s: string) => s.replace(/ de .*$/, '');

// «Jueves 5 de noviembre, hasta las 14:32», «Del lunes 2 al jueves 5 de noviembre», «Del 1 al 5 de noviembre».
function detalleDe(p: PeriodoReporte, desde: string, hasta: string, hoy: string, hora: string): string {
  if (desde === hasta) return hasta === hoy ? `${diaConNombre(hasta)}, hasta las ${sinCero(hora)}` : diaConNombre(hasta);
  const ultimo = minuscula(diaConNombre(hasta));
  const mismoMes = desde.slice(0, 7) === hasta.slice(0, 7);
  if (p === 'mes') return `Del ${Number(desde.slice(8))} al ${ultimo.replace(/^\S+ /, '')}`;
  const primero = minuscula(diaConNombre(desde));
  return `Del ${mismoMes ? sinMes(primero) : primero} al ${ultimo}`;
}

// Postgres escribe $10,120 y $22.50; el reporte lleva centavos siempre, como el corte.
const conCentavos = (dinero: string) => (dinero.includes('.') ? dinero : `${dinero}.00`);
const pieza = (n: number) => n.toLocaleString('en-US');

// «Lo hizo Lupita» si la misma persona pidió y autorizó, como en Cortes.
function quienAutorizo(nombre: string, autorizo: { nombre: string; veces: number }[] | undefined): string {
  if (!autorizo?.length) return '';
  if (autorizo.length > 1) return `Autorizó ${autorizo.map((a) => `${a.nombre} (${a.veces})`).join(', ')}`;
  return autorizo[0].nombre === nombre ? `Lo hizo ${nombre}` : `Autorizó ${autorizo[0].nombre}`;
}

function filasConMotivo(r: ConMotivo): Fila[] {
  return r.grupos.map((g) => ({
    celdas: [g.nombre, pieza(g.veces), conCentavos(g.importe)],
    nota:
      [(g.motivos ?? []).map((m) => `«${m}»`).join(', '), quienAutorizo(g.nombre, g.autorizo)]
        .filter(Boolean)
        .join(' · ') || undefined,
  }));
}

const totalConMotivo = (r: ConMotivo) => ['Total', pieza(r.total.veces), conCentavos(r.total.importe)];

// ¿La caja que sigue abierta entra en estas fechas? Es de su día de negocio, el de cuando se abrió.
async function hayCajaAbierta(restauranteId: string, ahora: Ahora, desde: string, hasta: string): Promise<boolean> {
  const { data, error } = await supabase
    .from('turnos')
    .select('created_at')
    .eq('restaurante_id', restauranteId)
    .eq('estado', 'abierto')
    .maybeSingle();
  if (error) throw error;
  if (!data) return false;
  const { dia, hora } = enZona(data.created_at, ahora.zona);
  const negocio = Number(hora.slice(0, 2)) < ahora.corte ? diaAnterior(dia) : dia;
  return negocio >= desde && negocio <= hasta;
}

// ─── Pedir y bajar ──────────────────────────────────────────────────────────────────────────

// Al elegir una opción del «+». `ahora` es para el Historial, como el que manda el Worker.
export async function prepararReporte(
  restauranteId: string,
  periodo: PeriodoReporte,
): Promise<{ reporte: ReporteGuardado; ahora: { fecha: string; hora: string } }> {
  const a = await leerAhora(restauranteId);
  const desde = periodo === 'hoy' ? a.hoy : periodo === 'semana' ? a.lunes : a.primero;
  const r = await herramienta<Resumen>(restauranteId, 'resumen', { desde, hasta: a.hoy });
  const reporte: ReporteGuardado = {
    periodo,
    desde,
    hasta: a.hoy,
    detalle: detalleDe(periodo, desde, a.hoy, a.hoy, a.hora),
  };
  if (r.sin_ventas) reporte.sin_ventas = true;
  return { reporte, ahora: { fecha: a.fecha, hora: a.hora } };
}

// Lee todo con las fechas guardadas, arma el archivo y lo baja.
export async function bajarReporte(restauranteId: string, restaurante: string, g: ReporteGuardado): Promise<void> {
  const { desde, hasta, periodo } = g;
  const rango = { desde, hasta };
  const ahora = await leerAhora(restauranteId);
  const ver = (ver: string) =>
    herramienta<ConMotivo>(restauranteId, 'cancelaciones_descuentos_propinas', { ...rango, ver, agrupar_por: 'persona', limite: 50 });

  const [resumen, dias, productos, meseros, propinas, descuentos, cancelaciones, pagos, cajaAbierta] = await Promise.all([
    herramienta<Resumen>(restauranteId, 'resumen', rango),
    periodo === 'hoy' ? null : herramienta<Ranking>(restauranteId, 'ranking', { ...rango, agrupar_por: 'dia', limite: 50 }),
    herramienta<Ranking>(restauranteId, 'ranking', { ...rango, agrupar_por: 'producto', limite: 50 }),
    herramienta<Ranking>(restauranteId, 'ranking', { ...rango, agrupar_por: 'mesero', limite: 50 }),
    herramienta<Propinas>(restauranteId, 'cancelaciones_descuentos_propinas', { ...rango, ver: 'propinas', agrupar_por: 'persona', limite: 50 }),
    ver('descuentos'),
    ver('cancelaciones'),
    ver('pagos_cancelados'),
    hayCajaAbierta(restauranteId, ahora, desde, hasta),
  ]);

  const tablas: Tabla[] = [];

  if (dias) {
    const mismoMes = desde.slice(0, 7) === hasta.slice(0, 7);
    tablas.push({
      titulo: 'Día por día',
      columnas: ['Día', 'Cuentas', 'Piezas', 'Vendido'],
      filas: (dias.grupos ?? []).map((d) => ({
        celdas: [
          mismoMes ? sinMes(diaConNombre(d.clave)) : diaConNombre(d.clave),
          pieza(d.cuentas),
          pieza(d.unidades),
          conCentavos(d.importe),
        ],
      })),
      vacio: 'Sin ventas en estas fechas.',
    });
  }

  const filasProductos: Fila[] = (productos.grupos ?? [])
    .filter((p) => p.unidades > 0)
    .map((p) => ({ celdas: [p.nombre, pieza(p.unidades), conCentavos(p.importe)] }));
  // Pasando de 50, el resto se dice junto; los que no se vendieron no salen.
  if (productos.resto && productos.resto.unidades > 0) {
    filasProductos.push({
      celdas: [`Otros ${plural(productos.resto.grupos, 'producto', 'productos')}`, pieza(productos.resto.unidades), conCentavos(productos.resto.importe)],
      suave: true,
    });
  }
  if (productos.descuento_a_la_cuenta) {
    filasProductos.push({ celdas: ['Descuentos a toda la cuenta', '', conCentavos(productos.descuento_a_la_cuenta.importe)], suave: true });
  }
  tablas.push({
    titulo: 'Por producto',
    columnas: ['Producto', 'Piezas', 'Vendido'],
    filas: filasProductos,
    total: ['Total', pieza(resumen.unidades ?? 0), conCentavos(resumen.total ?? '$0')],
    vacio: 'Sin ventas en estas fechas.',
  });

  tablas.push({
    titulo: 'Por mesero',
    columnas: ['Mesero', 'Cuentas', 'Vendido'],
    filas: (meseros.grupos ?? [])
      .filter((m) => m.cuentas > 0)
      .map((m) => ({ celdas: [m.nombre, pieza(m.cuentas), conCentavos(m.importe)] })),
    total: ['Total', pieza(resumen.cuentas ?? 0), conCentavos(resumen.total ?? '$0')],
    vacio: 'Sin ventas en estas fechas.',
  });

  tablas.push({
    titulo: 'Propinas',
    columnas: ['Mesero', 'Propinas', 'Pagado', 'Falta'],
    filas: propinas.grupos.map((p) => ({
      celdas: [p.nombre, conCentavos(p.propinas), conCentavos(p.pagado), conCentavos(p.falta)],
    })),
    total: ['Total', conCentavos(propinas.total.propinas), conCentavos(propinas.total.pagado), conCentavos(propinas.total.falta)],
    nota: cajaAbierta ? 'Incluye la caja que sigue abierta: puede cambiar.' : undefined,
    vacio: 'Ninguna propina en estas fechas.',
  });

  tablas.push({
    titulo: 'Descuentos',
    columnas: ['Quién lo hizo', 'Veces', 'Importe'],
    filas: filasConMotivo(descuentos),
    total: totalConMotivo(descuentos),
    vacio: 'Ningún descuento en estas fechas.',
  });
  tablas.push({
    titulo: 'Cancelaciones',
    columnas: ['Quién la pidió', 'Veces', 'Importe'],
    filas: filasConMotivo(cancelaciones),
    total: totalConMotivo(cancelaciones),
    vacio: 'Ninguna cancelación en estas fechas.',
  });
  // Los pagos cancelados, solo si hubo.
  if (pagos.grupos.length) {
    tablas.push({
      titulo: 'Pagos cancelados',
      columnas: ['Quién lo pidió', 'Veces', 'Importe'],
      filas: filasConMotivo(pagos),
      total: totalConMotivo(pagos),
    });
  }

  const cifras = [
    { etiqueta: 'Vendido', valor: conCentavos(resumen.total ?? '$0') },
    { etiqueta: 'Cuentas', valor: pieza(resumen.cuentas ?? 0) },
    { etiqueta: 'Piezas', valor: pieza(resumen.unidades ?? 0) },
    { etiqueta: 'Promedio por cuenta', valor: conCentavos(resumen.ticket_promedio ?? '$0') },
  ];
  if (periodo !== 'hoy') {
    cifras.push({ etiqueta: 'Promedio por día abierto', valor: conCentavos(resumen.promedio_por_dia_abierto ?? '$0') });
  }

  const archivo = nombreDelArchivo(periodo, restaurante);
  const { armarPdf } = await import('./reportePdf');
  const pdf = await armarPdf({
    restaurante,
    titulo: `Reporte ${TEXTOS[periodo].de}`,
    fechas: detalleDe(periodo, desde, hasta, ahora.hoy, ahora.hora),
    armado: `Armado el ${minuscula(diaConNombre(ahora.fecha))} a las ${sinCero(ahora.hora)}`,
    archivo,
    cifras,
    tablas,
  });

  const enlace = document.createElement('a');
  enlace.href = URL.createObjectURL(pdf);
  enlace.download = archivo;
  enlace.click();
  setTimeout(() => URL.revokeObjectURL(enlace.href), 10_000);
}
