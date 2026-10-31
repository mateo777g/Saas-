// Lo que usa la vista del Agente IA (libreta 1, «Cómo las usa el modelo» y «Qué cambia alrededor»;
// libreta 3, «El gasto de IA»; maqueta Agente IA KznKZdgQbLTZGs1EwVMvga):
//  - preguntar al Worker (/agente/pregunta) y pedirle el saludo (/agente/saludo), con la sesión;
//  - estado_ia, para saber al abrir si hay tope y, si no, qué aviso va en la caja;
//  - el Historial, guardado en este navegador por sucursal (las últimas 30), que «Cerrar sesión»
//    borra (cerrarSesion en supabase.ts borra todo lo que empieza con PREFIJO);
//  - el saludo de reserva, uno por sucursal, para que la bienvenida salga al instante.
// El Markdown de cada respuesta vive en markdown.ts. Ningún número sale de aquí: las cuentas las
// hace Postgres y el modelo solo redacta.
import { diaYMes } from './formato';
import { supabase } from './supabase';
import { llamarWorker } from './worker';

export const PREFIJO = 'fragmentless-agente-';
const MAX_CONVERSACIONES = 30;

export type Leido = { icono: string; texto: string };
export type Periodo = 'hoy' | 'semana' | 'mes';

export type SinTope = {
  puede: false;
  motivo: 'sin_ia' | 'limite';
  con_distribuidor: boolean;
  vuelve: string | null;
};
export type EstadoIa = { puede: true } | SinTope;

// El aviso de la libreta de Seguridad, según por qué no puede y quién le vende. Lo dicen igual el
// Agente IA y Crear contenido.
export function textoSinTope(e: SinTope): string {
  if (e.motivo === 'sin_ia') {
    return e.con_distribuidor
      ? 'La IA todavía no está activa en tu restaurante. Pídele a tu distribuidor que la active.'
      : 'La IA todavía no está activa en tu restaurante. Escríbele a Fragmentless para que la active.';
  }
  const vuelve = e.vuelve ? `Vuelve el ${diaYMes(e.vuelve)}` : 'Vuelve el próximo mes';
  return e.con_distribuidor
    ? `Llegaste al límite de IA de este mes. ${vuelve} o pídele a tu distribuidor que lo suba.`
    : `Llegaste al límite de IA de este mes. ${vuelve} o escríbele a Fragmentless para que lo suba.`;
}

// ─── Las ideas (las tres de Flet, con sus dos seguimientos cada una) ───────────────────────────

// Las tres piden el desglose por producto y que el total vaya debajo de la tabla, nunca como
// renglón: con el total adentro, el modelo suma la columna él solo (medido en Flet, ver
// agenteIA_view.py). Lo que va en MAYÚSCULAS es el periodo, lo único que cambia.
const FORMA =
  'en tabla y con el total al final. Ponme el producto, cuántas unidades se vendieron y cuánto ' +
  'dinero representa cada uno, de mayor a menor. El total no va dentro de la tabla: va debajo, ' +
  'en un renglón de texto. No lo desgloses por mesa.';

export type Idea = {
  icono: string;
  titulo: string;
  texto: string;
  prompt: string;
  seguimiento: { etiqueta: string; pregunta: string }[];
};

export const IDEAS: Idea[] = [
  {
    icono: 'hoy',
    titulo: 'Qué se vendió hoy',
    texto: 'Por producto, con el total al final.',
    prompt: `Ventas de HOY por producto, ${FORMA}`,
    seguimiento: [
      { etiqueta: 'Compárala con ayer', pregunta: 'Compara lo de hoy con lo de ayer, por producto.' },
      { etiqueta: 'Ver la semana', pregunta: `Ventas de ESTA SEMANA por producto, ${FORMA}` },
    ],
  },
  {
    icono: 'semana',
    titulo: 'Reporte de la semana',
    texto: 'Lunes a hoy, producto por producto.',
    prompt: `Ventas de ESTA SEMANA por producto, ${FORMA}`,
    seguimiento: [
      { etiqueta: 'Compárala con la pasada', pregunta: 'Compara esta semana con la semana pasada, por producto.' },
      { etiqueta: 'Ver el mes', pregunta: `Ventas de ESTE MES por producto, ${FORMA}` },
    ],
  },
  {
    icono: 'mes',
    titulo: 'Reporte del mes',
    texto: 'Lo que más dejó este mes.',
    prompt: `Ventas de ESTE MES por producto, ${FORMA}`,
    seguimiento: [
      { etiqueta: 'Compáralo con el pasado', pregunta: 'Compara este mes con el mes pasado, por producto.' },
      { etiqueta: 'Ver hoy', pregunta: `Ventas de HOY por producto, ${FORMA}` },
    ],
  },
];

// ─── Preguntar ──────────────────────────────────────────────────────────────────────────────

// Una vuelta de la conversación: lo que se ve en la burbuja (el título de la idea o lo escrito),
// lo que se le mandó al agente (el prompt de la idea o lo escrito), su respuesta en Markdown, lo
// que leyó para responder y de qué idea salió (para sus seguimientos).
export type Turno = {
  visible: string;
  pregunta: string;
  respuesta: string;
  leido: Leido[];
  idea: number | null;
};

export type Contestacion =
  | { tipo: 'respuesta'; respuesta: string; leido: Leido[]; puede: boolean; ahora: { fecha: string; hora: string } | null }
  | { tipo: 'sin_tope'; estado: SinTope };

// Errores del Worker ya en español (Fallo de worker.ts); la vista los pinta en su caja.
export async function preguntar(
  restauranteId: string,
  pregunta: string,
  turnos: Turno[],
  periodo: Periodo,
): Promise<Contestacion> {
  const conversacion = turnos.flatMap((t) => [
    { rol: 'gerente', texto: t.pregunta },
    { rol: 'agente', texto: t.respuesta },
  ]);
  const r = await llamarWorker('agente', 'POST', '/agente/pregunta', {
    restaurante: restauranteId,
    pregunta,
    conversacion,
    periodo,
  });
  if (r?.puede === false && typeof r.respuesta !== 'string') return { tipo: 'sin_tope', estado: r as unknown as SinTope };
  if (typeof r?.respuesta !== 'string') {
    console.error('[agente] el Worker contestó algo que no se entiende:', r);
    throw new Error('El Worker no mandó la respuesta');
  }
  const leido = Array.isArray(r.leido)
    ? (r.leido as Leido[]).filter((l) => typeof l?.texto === 'string' && typeof l?.icono === 'string')
    : [];
  const ahora = r.ahora as { fecha?: unknown; hora?: unknown } | null;
  return {
    tipo: 'respuesta',
    respuesta: r.respuesta,
    leido,
    puede: r.puede !== false,
    ahora: typeof ahora?.fecha === 'string' && typeof ahora.hora === 'string' ? { fecha: ahora.fecha, hora: ahora.hora } : null,
  };
}

// Si este gerente puede preguntar en esta sucursal, y si no, por qué (lo cuenta Postgres).
export async function leerEstadoIa(restauranteId: string): Promise<EstadoIa> {
  const { data, error } = await supabase.rpc('estado_ia', { p_restaurante_id: restauranteId });
  if (error) throw error;
  return data as EstadoIa;
}

// La zona y la hora de corte de la sucursal: para la nota de «Lo que leí para responder» y para
// decir en qué día se guardó cada conversación.
export async function leerZonaYCorte(restauranteId: string): Promise<{ zona: string; corte: number }> {
  const { data, error } = await supabase
    .from('restaurantes')
    .select('zona_horaria, hora_corte')
    .eq('id', restauranteId)
    .single();
  if (error) throw error;
  return { zona: data.zona_horaria, corte: data.hora_corte };
}

// ─── El Historial, en este navegador ────────────────────────────────────────────────────────

// Cada conversación se llama como su primera pregunta (o su idea), con el día y la hora del
// restaurante en que empezó (los dio el Worker). La más nueva va primero.
export type Conversacion = { id: string; titulo: string; fecha: string; hora: string; turnos: Turno[] };

const llaveConversaciones = (restauranteId: string) => `${PREFIJO}conversaciones-${restauranteId}`;

function esConversacion(c: unknown): c is Conversacion {
  const x = c as Conversacion;
  return (
    typeof x?.id === 'string' &&
    typeof x.titulo === 'string' &&
    typeof x.fecha === 'string' &&
    typeof x.hora === 'string' &&
    Array.isArray(x.turnos) &&
    x.turnos.every((t) => typeof t?.visible === 'string' && typeof t.pregunta === 'string' && typeof t.respuesta === 'string')
  );
}

export function leerConversaciones(restauranteId: string): Conversacion[] {
  try {
    const crudo = localStorage.getItem(llaveConversaciones(restauranteId));
    if (!crudo) return [];
    const lista: unknown = JSON.parse(crudo);
    if (!Array.isArray(lista)) throw new Error('no es una lista');
    return lista.filter(esConversacion).map((c) => ({
      ...c,
      turnos: c.turnos.map((t) => ({ ...t, leido: Array.isArray(t.leido) ? t.leido : [], idea: t.idea ?? null })),
    }));
  } catch (error) {
    console.error('[agente] no se pudo leer el Historial de este navegador:', error);
    return [];
  }
}

// Pone (o reemplaza) la conversación hasta arriba y deja las últimas 30. Si el navegador ya no
// tiene lugar, suelta las más viejas hasta que quepa. Regresa la lista como quedó.
export function guardarConversacion(restauranteId: string, conversacion: Conversacion): Conversacion[] {
  let lista = [conversacion, ...leerConversaciones(restauranteId).filter((c) => c.id !== conversacion.id)].slice(
    0,
    MAX_CONVERSACIONES,
  );
  for (;;) {
    try {
      localStorage.setItem(llaveConversaciones(restauranteId), JSON.stringify(lista));
      return lista;
    } catch (error) {
      if (lista.length <= 1) {
        console.error('[agente] no se pudo guardar la conversación en este navegador:', error);
        return lista;
      }
      console.error('[agente] el navegador no tiene lugar; se suelta la conversación más vieja:', error);
      lista = lista.slice(0, -1);
    }
  }
}

// ─── El saludo de reserva ───────────────────────────────────────────────────────────────────

// El segundo renglón de la bienvenida lo escribe la IA («¿Cómo va el sábado?»). Siempre hay a lo
// más uno guardado, para que salga al instante: la vista se lo lleva al abrir y pide el siguiente.
// Solo sirve el mismo día y en el mismo momento del día (días, tardes o noches): uno de la mañana
// no se pone en la noche. Si no hay, falla o no hay tope, sale el local, sin aviso.
export const SALUDO_LOCAL = '¿Qué revisamos hoy?';

type Reserva = { texto: string; dia: string; momento: string };
const llaveSaludo = (restauranteId: string) => `${PREFIJO}saludo-${restauranteId}`;

function leerReserva(restauranteId: string): Reserva | null {
  try {
    const crudo = localStorage.getItem(llaveSaludo(restauranteId));
    if (!crudo) return null;
    const r = JSON.parse(crudo) as Reserva;
    return typeof r?.texto === 'string' && typeof r.dia === 'string' && typeof r.momento === 'string' ? r : null;
  } catch (error) {
    console.error('[agente] no se pudo leer el saludo guardado:', error);
    return null;
  }
}

export function haySaludo(restauranteId: string, dia: string, momento: string): boolean {
  const r = leerReserva(restauranteId);
  return !!r && r.dia === dia && r.momento === momento;
}

// Se lleva el de reserva si todavía sirve; si no, nada.
export function tomarSaludo(restauranteId: string, dia: string, momento: string): string | null {
  const r = leerReserva(restauranteId);
  try {
    localStorage.removeItem(llaveSaludo(restauranteId));
  } catch (error) {
    console.error('[agente] no se pudo soltar el saludo guardado:', error);
  }
  return r && r.dia === dia && r.momento === momento ? r.texto : null;
}

// Pide uno nuevo y lo guarda para la próxima vez. Cuenta para el tope; sin tope, el Worker
// regresa null sin llamar a OpenAI. Si falla, solo se anota en la consola.
let pidiendo: Promise<void> | null = null;
export function prepararSaludo(restauranteId: string, dia: string, momento: string): Promise<void> {
  pidiendo ??= (async () => {
    try {
      const r = await llamarWorker('saludo', 'POST', '/agente/saludo', { restaurante: restauranteId });
      if (typeof r?.saludo !== 'string' || !r.saludo.trim()) return;
      localStorage.setItem(llaveSaludo(restauranteId), JSON.stringify({ texto: r.saludo.trim(), dia, momento }));
    } catch (error) {
      console.error('[agente] no se pudo preparar el saludo; saldrá el local:', error);
    } finally {
      pidiendo = null;
    }
  })();
  return pidiendo;
}
