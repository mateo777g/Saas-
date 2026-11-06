// Lo que usa la vista del Agente IA (libreta 1, «Cómo las usa el modelo» y «Qué cambia alrededor»;
// libreta 3, «El gasto de IA»; maqueta Agente IA KznKZdgQbLTZGs1EwVMvga):
//  - preguntar al Worker (/agente/pregunta) y pedirle el saludo (/agente/saludo), con la sesión;
//  - estado_ia, para saber al abrir si hay tope y, si no, qué aviso va en la caja;
//  - el Historial, guardado en este navegador por sucursal (las últimas 30), que «Cerrar sesión»
//    borra (cerrarSesion en supabase.ts borra todo lo que empieza con PREFIJO);
//  - el saludo de reserva, uno por sucursal, para que la bienvenida salga al instante.
// El Markdown de cada respuesta vive en markdown.ts. Ningún número sale de aquí: las cuentas las
// hace Postgres y el modelo solo redacta.
import { ALGO_SALIO_PANEL, Fallo, SIN_CONEXION } from './errores';
import { diaYMes } from './formato';
import { Compas, leerRenglones, vienePorPartes, type Aviso, type Paso } from './pasos';
import type { ReporteGuardado } from './reporte';
import { supabase } from './supabase';
import { abrirWorker, llamarWorker } from './worker';

export const PREFIJO = 'fragmentless-agente-';
const MAX_CONVERSACIONES = 30;

export type Leido = { icono: string; texto: string };

export type SinTope = {
  puede: false;
  motivo: 'sin_ia' | 'limite';
  con_distribuidor: boolean;
  vuelve: string | null;
};
export type EstadoIa = { puede: true } | SinTope;

// El aviso de la libreta de Seguridad, según por qué no puede y quién le vende.
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

// `frase` es lo que se ve en la caja y en la burbuja; `prompt`, lo que se le manda al agente.
export type Idea = {
  icono: string;
  titulo: string;
  texto: string;
  frase: string;
  prompt: string;
  seguimiento: { etiqueta: string; pregunta: string }[];
};

export const IDEAS: Idea[] = [
  {
    icono: 'r-hoy',
    titulo: 'Qué se vendió hoy',
    texto: 'Por producto, con el total al final.',
    frase: '¿Qué se vendió hoy? Por producto, con el total al final.',
    prompt: `Ventas de HOY por producto, ${FORMA}`,
    seguimiento: [
      { etiqueta: 'Compárala con ayer', pregunta: 'Compara lo de hoy con lo de ayer, por producto.' },
      { etiqueta: 'Ver la semana', pregunta: `Ventas de ESTA SEMANA por producto, ${FORMA}` },
    ],
  },
  {
    icono: 'r-semana',
    titulo: 'Reporte de la semana',
    texto: 'Lunes a hoy, producto por producto.',
    frase: 'Dame el reporte de la semana: de lunes a hoy, producto por producto.',
    prompt: `Ventas de ESTA SEMANA por producto, ${FORMA}`,
    seguimiento: [
      { etiqueta: 'Compárala con la pasada', pregunta: 'Compara esta semana con la semana pasada, por producto.' },
      { etiqueta: 'Ver el mes', pregunta: `Ventas de ESTE MES por producto, ${FORMA}` },
    ],
  },
  {
    icono: 'r-mes',
    titulo: 'Reporte del mes',
    texto: 'Lo que más dejó este mes.',
    frase: 'Dame el reporte del mes: lo que más dejó este mes.',
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
// También cuánto tardó y lo que hizo («Pensé 6 s», planes/trabajo/estrella/vista.md; las conversaciones
// de antes no lo traen). Una pregunta detenida es un turno sin respuesta que no se le manda al agente, y
// un «Reporte en PDF» tampoco: lo arma el sistema, sin IA (reporte.ts).
export type Turno = {
  visible: string;
  pregunta: string;
  respuesta: string;
  leido: Leido[];
  idea: number | null;
  segundos?: number;
  pasos?: string[];
  detenida?: boolean;
  reporte?: ReporteGuardado;
};

export type Contestacion =
  | {
      tipo: 'respuesta';
      respuesta: string;
      leido: Leido[];
      puede: boolean;
      ahora: { fecha: string; hora: string } | null;
      pasos: string[];
    }
  | { tipo: 'sin_tope'; estado: SinTope };

// Un paso del agente es de lo que encontró si trae `dato`: es lo que alcanzó a leer si se detiene.
export type PasoAgente = Paso & { dato?: boolean };

type Oyentes = {
  senal: AbortSignal;
  alPasos: (pasos: PasoAgente[]) => void;
  alLlegar: () => void; // la respuesta ya llegó (los segundos son hasta aquí), aunque falte enseñar pasos
};

// El Worker contesta por partes (worker.md): cada paso, y al final la respuesta. Lo que rechaza antes de
// empezar llega en JSON normal. Si se detiene (`senal`), esto lanza el error de la señal, sin esperar.
// Errores del Worker ya en español (Fallo de worker.ts); la vista los pinta en su caja.
export async function preguntar(
  restauranteId: string,
  pregunta: string,
  turnos: Turno[],
  { senal, alPasos, alLlegar }: Oyentes,
): Promise<Contestacion> {
  const conversacion = turnos
    .filter((t) => !t.detenida && !t.reporte)
    .flatMap((t) => [
      { rol: 'gerente', texto: t.pregunta },
      { rol: 'agente', texto: t.respuesta },
    ]);
  const respuesta = await abrirWorker(
    'agente',
    '/agente/pregunta',
    { restaurante: restauranteId, pregunta, conversacion },
    senal,
  );
  if (!vienePorPartes(respuesta)) {
    const r = await respuesta.json().catch((error) => {
      if (senal.aborted) throw error;
      return null;
    });
    if (r?.puede === false) return { tipo: 'sin_tope', estado: r as SinTope };
    console.error('[agente] el Worker contestó algo que no se entiende:', r);
    throw new Error('El Worker no mandó la respuesta');
  }

  const compas = new Compas();
  const parar = () => compas.parar();
  senal.addEventListener('abort', parar);
  let pasos: PasoAgente[] = [];
  const poner = (nuevos: PasoAgente[]) => {
    pasos = nuevos;
    alPasos(pasos);
  };
  let datos = 0;
  let fin: Aviso | null = null;
  try {
    await leerRenglones(respuesta, (a) => {
      if (a.tipo === 'paso') {
        const paso = { clave: a.id as number, icono: a.icono as string, texto: a.texto as string, listo: a.listo as string, hecho: false };
        compas.entra(() => poner([...pasos, paso]));
      } else if (a.tipo === 'hecho') {
        compas.sale(() => poner(pasos.map((p) => (p.clave === a.id ? { ...p, hecho: true } : p))));
      } else if (a.tipo === 'quita') {
        compas.sale(() => poner(pasos.filter((p) => p.clave !== a.id)));
      } else if (a.tipo === 'dato') {
        const paso = { clave: `dato-${datos++}`, icono: a.icono as string, texto: a.texto as string, listo: a.texto as string, hecho: true, dato: true };
        compas.ahora(() => poner([...pasos, paso]));
      } else if (a.tipo === 'fin') {
        fin = a;
        alLlegar();
      } else if (a.tipo === 'error') {
        throw new Fallo(typeof a.mensaje === 'string' ? a.mensaje : ALGO_SALIO_PANEL);
      }
    });
    if (!fin) throw new Error('la respuesta se acabó sin su final');
    // La respuesta espera a que el último paso se deje leer.
    compas.sale(() => {});
    await compas.termina();
    senal.throwIfAborted();
  } catch (error) {
    if (senal.aborted || error instanceof Fallo) throw error;
    console.error('[agente] la lectura de la respuesta se cortó:', error);
    throw new Fallo(SIN_CONEXION);
  } finally {
    senal.removeEventListener('abort', parar);
    compas.parar();
  }

  const r = fin as Aviso;
  if (typeof r.respuesta !== 'string') {
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
    pasos: pasos.map((p) => p.listo),
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
// restaurante en que empezó (los dio el Worker). La más nueva va primero. Las guardadas antes del
// 6 de noviembre de 2026 no traen `fijada`.
export type Conversacion = { id: string; titulo: string; fecha: string; hora: string; turnos: Turno[]; fijada?: boolean };

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
      fijada: c.fijada === true,
      turnos: c.turnos.map((t) => ({ ...t, leido: Array.isArray(t.leido) ? t.leido : [], idea: t.idea ?? null })),
    }));
  } catch (error) {
    console.error('[agente] no se pudo leer el Historial de este navegador:', error);
    return [];
  }
}

// Si el navegador ya no tiene lugar, suelta las más viejas hasta que quepa: primero las que no
// están fijadas. Regresa la lista como quedó.
function escribirConversaciones(restauranteId: string, lista: Conversacion[]): Conversacion[] {
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
      const sinFijar = lista.map((c) => !c.fijada).lastIndexOf(true);
      const sale = sinFijar >= 0 ? sinFijar : lista.length - 1;
      lista = lista.filter((_, i) => i !== sale);
    }
  }
}

// Pone (o reemplaza) la conversación hasta arriba y deja las últimas 30. Las fijadas no se cuentan:
// no se caen por más conversaciones que lleguen.
export function guardarConversacion(restauranteId: string, conversacion: Conversacion): Conversacion[] {
  let sueltas = 0;
  const lista = [conversacion, ...leerConversaciones(restauranteId).filter((c) => c.id !== conversacion.id)].filter(
    (c) => c.fijada || ++sueltas <= MAX_CONVERSACIONES,
  );
  return escribirConversaciones(restauranteId, lista);
}

// Fijar y cambiar el nombre no la mueven de su lugar: al desfijarla, regresa adonde estaba.
export function cambiarConversacion(
  restauranteId: string,
  id: string,
  cambios: Partial<Pick<Conversacion, 'titulo' | 'fijada'>>,
): Conversacion[] {
  const lista = leerConversaciones(restauranteId).map((c) => (c.id === id ? { ...c, ...cambios } : c));
  return escribirConversaciones(restauranteId, lista);
}

export function eliminarConversacion(restauranteId: string, id: string): Conversacion[] {
  return escribirConversaciones(
    restauranteId,
    leerConversaciones(restauranteId).filter((c) => c.id !== id),
  );
}

// Si la barra de chats se cerró a mano, no se vuelve a abrir sola. Como el resto de lo que el agente
// guarda aquí, «Cerrar sesión» lo borra.
const LLAVE_BARRA_CERRADA = `${PREFIJO}barra-cerrada`;

export function leerBarraCerrada(): boolean {
  try {
    return localStorage.getItem(LLAVE_BARRA_CERRADA) === '1';
  } catch (error) {
    console.error('[agente] no se pudo leer si la barra de chats iba cerrada; se abre:', error);
    return false;
  }
}

export function guardarBarraCerrada(cerrada: boolean) {
  try {
    if (cerrada) localStorage.setItem(LLAVE_BARRA_CERRADA, '1');
    else localStorage.removeItem(LLAVE_BARRA_CERRADA);
  } catch (error) {
    console.error('[agente] no se pudo recordar la barra de chats cerrada:', error);
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
