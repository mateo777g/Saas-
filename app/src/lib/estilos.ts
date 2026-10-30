// Lo que lee y escribe «Estilos» en el panel de Fragmentless (parte 7a de la libreta 7, migración
// estilos): los estilos de los anuncios de Crear contenido. Postgres los lee y los cambia con sus
// funciones, que primero revisan que quien llama sea Fragmentless; el Worker sube y borra sus
// muestras en R2 (estilos/<clave>/) y dice qué claves ya tienen su prompt en su código
// (GET /estilos). Lo que le falta a cada uno lo junta el panel con esas dos lecturas.
import { ALGO_SALIO_PANEL, esDeRed, Fallo, mensajeDeError, SIN_CONEXION } from './errores';
import { MESES, MESES_LARGOS } from './formato';
import { convertirAWebp, revisarFoto } from './fotos';
import type { Lectura } from './panel';
import { supabase } from './supabase';
import { llamarWorker } from './worker';

// La lista fija de grupos, en el orden de la ventana de Don Chuy (un grupo nuevo es una migración).
export type Grupo = 'temporada' | 'para_todos';
export const GRUPOS: { valor: Grupo; texto: string }[] = [
  { valor: 'temporada', texto: 'De temporada' },
  { valor: 'para_todos', texto: 'Para todos' },
];

// Las tres muestras de cada estilo, cada una en su forma. `proporcion` es ancho / alto.
export type Formato = 'post' | 'historia' | 'cartel';
export const FORMATOS: { valor: Formato; texto: string; forma: string; tamano: string; proporcion: number }[] = [
  { valor: 'post', texto: 'Post', forma: '4:5', tamano: '1152 × 1440', proporcion: 4 / 5 },
  { valor: 'historia', texto: 'Historia', forma: '9:16', tamano: '1152 × 2048', proporcion: 9 / 16 },
  { valor: 'cartel', texto: 'Cartel', forma: '16:9', tamano: '2048 × 1152', proporcion: 16 / 9 },
];

// Una fila de panel_estilos, ya en el orden de la ventana de Don Chuy. en_fechas dice si hoy
// (el día de México) cae en sus fechas; sin fechas, true.
export type Estilo = {
  id: number;
  clave: string;
  nombre: string;
  descripcion: string;
  grupo: Grupo;
  orden: number;
  desde_mes: number | null;
  desde_dia: number | null;
  hasta_mes: number | null;
  hasta_dia: number | null;
  prendido: boolean;
  muestra_post_ruta: string | null;
  muestra_historia_ruta: string | null;
  muestra_cartel_ruta: string | null;
  en_fechas: boolean;
};

// Cuándo sale cada año: día y mes, sin año. El rango puede cruzar el año.
export type Fechas = { desde_mes: number; desde_dia: number; hasta_mes: number; hasta_dia: number };

// Los días de cada mes en un año cualquiera: el 29 de febrero no existe todos los años.
export const DIAS_DEL_MES = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

export function fechasDe(e: Estilo): Fechas | null {
  if (e.desde_mes === null || e.desde_dia === null || e.hasta_mes === null || e.hasta_dia === null) return null;
  return { desde_mes: e.desde_mes, desde_dia: e.desde_dia, hasta_mes: e.hasta_mes, hasta_dia: e.hasta_dia };
}

export function rutaMuestra(e: Estilo, formato: Formato): string | null {
  return e[`muestra_${formato}_ruta` as const];
}

// En un mismo mes, el mes una sola vez: «1 al 25 de diciembre», «10–31 oct».
function mismoMes(f: Fechas) {
  return f.desde_mes === f.hasta_mes && f.desde_dia <= f.hasta_dia;
}

// «15 de octubre al 2 de noviembre» (el porqué de un renglón: «Sale del …»).
export function rango(f: Fechas): string {
  const hasta = `${f.hasta_dia} de ${MESES_LARGOS[f.hasta_mes - 1]}`;
  return mismoMes(f) ? `${f.desde_dia} al ${hasta}` : `${f.desde_dia} de ${MESES_LARGOS[f.desde_mes - 1]} al ${hasta}`;
}

// «15 oct–2 nov» (junto a la clave, en el renglón).
export function rangoCorto(f: Fechas): string {
  const hasta = `${f.hasta_dia} ${MESES[f.hasta_mes - 1]}`;
  return mismoMes(f) ? `${f.desde_dia}–${hasta}` : `${f.desde_dia} ${MESES[f.desde_mes - 1]}–${hasta}`;
}

// «31 de octubre» (uno de temporada que sí sale: «Hasta el …»).
export function ultimoDia(f: Fechas): string {
  return `${f.hasta_dia} de ${MESES_LARGOS[f.hasta_mes - 1]}`;
}

// Lo que le falta a un estilo para salirles a los clientes, en el orden en que se arregla:
// «Apagado · Falta la muestra de historia · Falta su prompt · Sale del 1 al 25 de diciembre».
// Vacío = les sale.
export function porQueNoSale(e: Estilo, claves: string[]): string[] {
  const razones: string[] = [];
  if (!e.prendido) razones.push('Apagado');
  const faltan = FORMATOS.filter((f) => !rutaMuestra(e, f.valor)).map((f) => f.valor);
  if (faltan.length === 3) razones.push('Faltan sus 3 muestras');
  else if (faltan.length === 2) razones.push(`Faltan las muestras de ${faltan[0]} y ${faltan[1]}`);
  else if (faltan.length === 1) razones.push(`Falta la muestra de ${faltan[0]}`);
  if (!claves.includes(e.clave)) razones.push('Falta su prompt');
  const fechas = fechasDe(e);
  if (fechas && !e.en_fechas) razones.push(`Sale del ${rango(fechas)}`);
  return razones;
}

// La clave que sale sola del nombre: «Día de Muertos» → dia-de-muertos.
export function claveDe(nombre: string): string {
  return nombre
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 40)
    .replace(/-+$/, '');
}

// La misma regla que Postgres y el Worker: letras sin acento, números y guiones sueltos.
export const CLAVE_VALIDA = /^[a-z0-9]+(-[a-z0-9]+)*$/;

// ─── Leer ───────────────────────────────────────────────────────────────────

export type DatosEstilos = { estilos: Estilo[]; claves: string[] };

async function leerTabla(): Promise<Lectura<Estilo[]>> {
  const { data, error } = await supabase.rpc('panel_estilos');
  if (error) {
    console.error('[estilos] no se pudo leer panel_estilos:', error);
    return { ok: false, mensaje: mensajeDeError(error), deRed: esDeRed(error) };
  }
  return { ok: true, datos: data as Estilo[] };
}

// Las claves cuyo prompt ya vive en el Worker. llamarWorker ya dejó en la consola lo que falló.
async function leerClaves(): Promise<Lectura<string[]>> {
  try {
    const respuesta = await llamarWorker('estilos', 'GET', '/estilos');
    const claves = respuesta?.claves;
    if (!Array.isArray(claves) || !claves.every((c) => typeof c === 'string')) {
      console.error('[estilos] el Worker no regresó la lista de claves:', respuesta);
      return { ok: false, mensaje: ALGO_SALIO_PANEL, deRed: false };
    }
    return { ok: true, datos: claves };
  } catch (falla) {
    if (!(falla instanceof Fallo)) console.error('[estilos] no se pudo leer GET /estilos:', falla);
    const mensaje = falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL;
    return { ok: false, mensaje, deRed: mensaje === SIN_CONEXION };
  }
}

// Las dos lecturas a la vez. Si una falla, falla todo: sin la lista del Worker no se sabe a quién
// le falta su prompt, y no se adivina.
export async function leerEstilos(): Promise<Lectura<DatosEstilos>> {
  const [tabla, claves] = await Promise.all([leerTabla(), leerClaves()]);
  if (tabla.ok && claves.ok) return { ok: true, datos: { estilos: tabla.datos, claves: claves.datos } };
  const falla = !tabla.ok ? tabla : (claves as { ok: false; mensaje: string; deRed: boolean });
  return { ok: false, mensaje: falla.mensaje, deRed: (!tabla.ok && tabla.deRed) || (!claves.ok && claves.deRed) };
}

// ─── Escribir ───────────────────────────────────────────────────────────────

// El error de una escritura, ya en español para la caja; el error completo queda en la consola.
function fallo(contexto: string, error: unknown): Fallo {
  console.error(`[estilos] ${contexto}:`, error);
  return new Fallo(esDeRed(error) ? SIN_CONEXION : mensajeDeError(error));
}

// Lo que se escribe en la ventana. Cada muestra es la que debe quedar: la misma, una nueva que ya
// subió el Worker, o ninguna.
export type DatosEstilo = {
  clave: string;
  nombre: string;
  descripcion: string;
  grupo: Grupo;
  fechas: Fechas | null;
  muestras: Record<Formato, string | null>;
};

// «Agregar estilo» y «Guardar cambios». id vacío = estilo nuevo, apagado y al final de su grupo.
// Regresa las muestras viejas que cambiaron, para borrarlas de R2.
export async function guardarEstilo(id: number | null, d: DatosEstilo): Promise<string[]> {
  const { data, error } = await supabase.rpc('guardar_estilo', {
    p_estilo_id: id,
    p_clave: d.clave,
    p_nombre: d.nombre,
    p_descripcion: d.descripcion,
    p_grupo: d.grupo,
    p_desde_mes: d.fechas?.desde_mes ?? null,
    p_desde_dia: d.fechas?.desde_dia ?? null,
    p_hasta_mes: d.fechas?.hasta_mes ?? null,
    p_hasta_dia: d.fechas?.hasta_dia ?? null,
    p_muestra_post_ruta: d.muestras.post,
    p_muestra_historia_ruta: d.muestras.historia,
    p_muestra_cartel_ruta: d.muestras.cartel,
  });
  if (error) throw fallo('guardar_estilo no se pudo', error);
  return (data as { id: number; borrar: string[] }).borrar;
}

// El interruptor del renglón: se puede prender aunque le falte algo.
export async function prenderEstilo(id: number, prendido: boolean): Promise<void> {
  const { error } = await supabase.rpc('prender_estilo', { p_estilo_id: id, p_prendido: prendido });
  if (error) throw fallo('prender_estilo no se pudo', error);
}

// Las flechas: un lugar arriba o abajo, dentro de su grupo.
export async function moverEstilo(id: number, hacia: 'arriba' | 'abajo'): Promise<void> {
  const { error } = await supabase.rpc('mover_estilo', { p_estilo_id: id, p_hacia: hacia });
  if (error) throw fallo('mover_estilo no se pudo', error);
}

// «Eliminar estilo»: Postgres lo borra si nunca se usó y regresa las rutas de sus muestras para
// borrarlas; si ya se usó, dice «Este estilo ya se usó: apágalo.».
export async function eliminarEstilo(id: number): Promise<string[]> {
  const { data, error } = await supabase.rpc('eliminar_estilo', { p_estilo_id: id });
  if (error) throw fallo('eliminar_estilo no se pudo', error);
  return (data as string[] | null) ?? [];
}

// ─── Las muestras ───────────────────────────────────────────────────────────

// Al elegir una muestra: las revisiones de siempre de una foto (hasta 15 MB y que el navegador la
// pueda abrir) y su forma, con 1 % de margen para que pasen tanto la de las pruebas (1152 × 1440)
// como la ya achicada (1080 × 1350). Regresa el error para la caja, o nada si está bien.
export async function revisarMuestra(archivo: File, formato: Formato): Promise<string | null> {
  const problema = await revisarFoto(archivo);
  if (problema) return problema;
  const f = FORMATOS.find((x) => x.valor === formato)!;
  let ancho: number;
  let alto: number;
  try {
    // Derecha aunque se haya guardado de lado, como la convierte convertirAWebp.
    const imagen = await createImageBitmap(archivo, { imageOrientation: 'from-image' });
    ancho = imagen.width;
    alto = imagen.height;
    imagen.close();
  } catch (error) {
    console.error('[estilos] no se pudo medir la muestra elegida:', error);
    return 'El archivo seleccionado no es una imagen válida.';
  }
  if (Math.abs(ancho / alto / f.proporcion - 1) > 0.01) return `La muestra de ${formato} va en ${f.forma} (${f.tamano}).`;
  return null;
}

// La pasa a WebP de 1600 px de lado mayor, calidad 80, y la sube a estilos/<clave>/. Regresa su
// ruta en R2, que es lo que se guarda en la tabla.
export async function subirMuestra(clave: string, formato: Formato, archivo: File): Promise<string> {
  const muestra = await convertirAWebp(archivo);
  const respuesta = await llamarWorker(
    'estilos',
    'POST',
    `/estilos/muestra?clave=${encodeURIComponent(clave)}&formato=${formato}`,
    muestra,
  );
  if (typeof respuesta?.ruta !== 'string') {
    console.error('[estilos] el Worker no regresó la ruta de la muestra:', respuesta);
    throw new Fallo(ALGO_SALIO_PANEL);
  }
  return respuesta.ruta;
}

// Borra una muestra que ya nada usa (la vieja al cambiarla, las de un estilo eliminado o las de
// uno que no se pudo guardar). Si falla, lo demás ya salió bien: no se le muestra a nadie, pero
// queda en la consola, nunca se traga.
export async function borrarMuestra(ruta: string): Promise<void> {
  try {
    await llamarWorker('estilos', 'DELETE', `/estilos/muestra?ruta=${encodeURIComponent(ruta)}`);
  } catch (error) {
    console.error(`[estilos] no se pudo borrar la muestra ${ruta}; queda en R2:`, error);
  }
}
