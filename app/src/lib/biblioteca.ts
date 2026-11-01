// Lo que usa «Mi biblioteca» (parte 7b-2 de la libreta 7; maqueta SMeWoa5ypbcVQmvBGyyytt, sus
// decisiones en planes/trabajo/7b/biblioteca-7b2.md):
//  - mi_biblioteca: en una sola lectura, hoy en el calendario del restaurante y sus anuncios (el que
//    se está haciendo, de quien sea, y los listos de todos sus gerentes, del más nuevo al más viejo),
//    cada uno con su día, su hora y los días que le quedan ya contados por Postgres.
//  - el Worker, con la sesión: Eliminar (DELETE /anuncios) y el JPG (GET /anuncios/archivo), que
//    «Descargar» baja y «Ponerlo en mi menú» convierte en un cartel más.
// Aquí no se cuenta nada: las fechas solo se pasan a palabras.
import { esDeRed, Fallo, mensajeDeError, SIN_CONEXION } from './errores';
import type { Formato } from './crearContenido';
import { diaAnterior, MESES_LARGOS } from './formato';
import { borrarFoto, convertirCartel, subirFoto } from './fotos';
import { agregarCartel, leerCarteles, MAXIMO_CARTELES } from './restaurante';
import { supabase } from './supabase';
import { bajarDelWorker, llamarWorker } from './worker';

export type AnuncioListo = {
  id: number;
  estado: 'listo';
  formato: Formato;
  // El nombre de su estilo hoy.
  estilo: string;
  productos: string[];
  ruta: string;
  // El día en que terminó, en el calendario del restaurante ('2026-10-31').
  dia: string;
  hora: string;
  // 0 = «Se borra hoy».
  dias_restantes: number;
};

export type AnuncioHaciendo = {
  id: number;
  estado: 'haciendo';
  formato: Formato;
  estilo: string;
  productos: string[];
  // Cuántos segundos lleva, con el reloj de Postgres.
  segundos: number;
};

export type DatosBiblioteca = { hoy: string; anuncios: (AnuncioListo | AnuncioHaciendo)[] };

export async function leerBiblioteca(restauranteId: string): Promise<DatosBiblioteca> {
  const { data, error } = await supabase.rpc('mi_biblioteca', { p_restaurante_id: restauranteId });
  if (error) {
    console.error('[biblioteca] no se pudo leer:', error);
    throw error;
  }
  return data as DatosBiblioteca;
}

// Lo borra el Worker: primero su JPG de R2 y luego su renglón. Si ya no estaba (la socia lo borró
// o el trabajo diario se lo llevó), también contesta que sí.
export async function eliminarAnuncio(id: number): Promise<void> {
  await llamarWorker('biblioteca', 'DELETE', `/anuncios?id=${id}`);
}

// «Ponerlo en mi menú»: el JPG del cartel (2048 × 1152, la misma forma) pasado a WebP de 1600 × 900
// y subido como cualquier cartel, al final de los suyos. Con 5 carteles no sube nada; si algo falla
// después de subirlo, se borra (la regla de las fotos del menú).
export const CINCO_CARTELES = 'Ya tienes 5 carteles. Quita uno para agregar otro.';

export async function ponerEnMiMenu(restauranteId: string, anuncioId: number): Promise<void> {
  let cuantos: number;
  try {
    cuantos = (await leerCarteles(restauranteId)).length;
  } catch (error) {
    console.error('[biblioteca] no se pudieron leer los carteles:', error);
    throw new Fallo(esDeRed(error) ? SIN_CONEXION : mensajeDeError(error));
  }
  if (cuantos >= MAXIMO_CARTELES) throw new Fallo(CINCO_CARTELES);

  const { archivo } = await bajarDelWorker('biblioteca', `/anuncios/archivo?id=${anuncioId}`);
  const cartel = await convertirCartel(new File([archivo], 'anuncio.jpg', { type: archivo.type || 'image/jpeg' }));
  const ruta = await subirFoto(restauranteId, cartel, 'carteles');
  try {
    await agregarCartel(restauranteId, ruta);
  } catch (error) {
    await borrarFoto(ruta);
    throw error;
  }
}

// Realtime con cada cambio de sus anuncios. Los DELETE no se filtran (ni por RLS ni por filtro) y
// solo traen el id: llegan los de todos los restaurantes, así que solo se vuelve a leer si era uno
// de los que se ven.
export function escucharBiblioteca(restauranteId: string, alCambiar: () => void, seVe: (id: number) => boolean): () => void {
  const filtro = `restaurante_id=eq.${restauranteId}`;
  const canal = supabase
    .channel(`biblioteca-${restauranteId}-${crypto.randomUUID()}`)
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'anuncios', filter: filtro }, alCambiar)
    .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'anuncios', filter: filtro }, alCambiar)
    .on('postgres_changes', { event: 'DELETE', schema: 'public', table: 'anuncios' }, (cambio) => {
      if (seVe(Number(cambio.old?.id))) alCambiar();
    });
  canal.subscribe((estado, error) => {
    if (estado === 'SUBSCRIBED') alCambiar();
    else if (estado === 'CHANNEL_ERROR' || estado === 'TIMED_OUT') {
      console.error(`[biblioteca] el tiempo real se cortó (${estado}); se reconecta solo:`, error);
    }
  });
  return () => {
    supabase.removeChannel(canal).catch((e) => console.error('[biblioteca] no se pudo cerrar el tiempo real:', e));
  };
}

// ─── Las palabras ─────────────────────────────────────────────────────────────────────────────

const DIAS = ['DOMINGO', 'LUNES', 'MARTES', 'MIÉRCOLES', 'JUEVES', 'VIERNES', 'SÁBADO'];

function partes(iso: string) {
  const [anio, mes, dia] = iso.split('-').map(Number);
  return { anio, mes, dia };
}

// '2026-10-31' → 'SÁBADO 31 DE OCTUBRE'. El día de la semana sale de la misma fecha.
function diaLargo(iso: string): string {
  const { anio, mes, dia } = partes(iso);
  return `${DIAS[new Date(Date.UTC(anio, mes - 1, dia)).getUTCDay()]} ${dia} DE ${MESES_LARGOS[mes - 1].toUpperCase()}`;
}

// La cabecera de cada día: ['HOY', 'SÁBADO 31 DE OCTUBRE'], ['AYER', …] o, más atrás, solo la fecha.
export function cabeceraDelDia(dia: string, hoy: string): [string, string] {
  if (dia === hoy) return ['HOY', diaLargo(dia)];
  if (dia === diaAnterior(hoy)) return ['AYER', diaLargo(dia)];
  return [diaLargo(dia), ''];
}

// «Hoy, 13:25», «Ayer, 19:05» o «27 de octubre, 12:30».
export function creado(a: AnuncioListo, hoy: string): string {
  const { mes, dia } = partes(a.dia);
  const cuando = a.dia === hoy ? 'Hoy' : a.dia === diaAnterior(hoy) ? 'Ayer' : `${dia} de ${MESES_LARGOS[mes - 1]}`;
  return `${cuando}, ${a.hora}`;
}

export function seBorra(dias: number): string {
  if (dias <= 0) return 'Se borra hoy';
  return dias === 1 ? 'Se borra en 1 día' : `Se borra en ${dias} días`;
}

// «Gringa, Torta y Jamaica».
export function listaDe(nombres: string[]): string {
  return nombres.length < 2 ? (nombres[0] ?? '') : `${nombres.slice(0, -1).join(', ')} y ${nombres[nombres.length - 1]}`;
}

export function anuncios(n: number): string {
  return n === 1 ? '1 anuncio' : `${n.toLocaleString('en-US')} anuncios`;
}

// Cada formato: su nombre en la tarjeta y en grande, su tamaño y su forma.
export const FORMA: Record<Formato, { corto: string; largo: string; plural: string; medida: string; razon: string; alto: number }> = {
  post: { corto: 'POST', largo: 'Post de Instagram', plural: 'posts', medida: '1152 × 1440', razon: '4 / 5', alto: 1440 / 1152 },
  historia: { corto: 'HISTORIA', largo: 'Historia de Instagram', plural: 'historias', medida: '1152 × 2048', razon: '9 / 16', alto: 2048 / 1152 },
  cartel: { corto: 'CARTEL', largo: 'Cartel del menú', plural: 'carteles', medida: '2048 × 1152', razon: '16 / 9', alto: 1152 / 2048 },
};
