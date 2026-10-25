// Lo que leen y escriben «Tu restaurante» y «Tu menú en línea» (migración menu_en_linea; libreta 6,
// decidido el 20 de octubre de 2026). Se leen las tablas directo (restaurantes, horarios, carteles);
// se escribe solo con las funciones de la base, que revisan que quien llama sea el gerente.
import type { TemaMenu } from './color';
import { esDeRed, Fallo, mensajeDeError, SIN_CONEXION } from './errores';
import { supabase } from './supabase';

// Un día que abre, con las horas como '9:00'. Si cierra antes de la hora en que abre, cierra al día
// siguiente. dia va de 1 (lunes) a 7 (domingo), como isodow; un día sin renglón está cerrado.
export type Horario = { dia: number; abre: string; cierra: string };

export type Restaurante = {
  nombre: string;
  slug: string;
  telefono: string | null;
  direccion: string | null;
  logo_ruta: string | null;
  menu_tema: TemaMenu;
  menu_color: string | null;
  tipo_cambio_usd: number | null;
  horario: Horario[];
};

export type Cartel = { id: number; imagen_ruta: string };

// '09:00:00' (como lo da Postgres) → '9:00'.
function hora(t: string): string {
  const [h, m] = t.split(':');
  return `${Number(h)}:${m}`;
}

export async function leerRestaurante(restauranteId: string): Promise<Restaurante> {
  const [fila, dias] = await Promise.all([
    supabase
      .from('restaurantes')
      .select('nombre, slug, telefono, direccion, logo_ruta, menu_tema, menu_color, tipo_cambio_usd')
      .eq('id', restauranteId)
      .single(),
    supabase.from('horarios').select('dia, abre, cierra').eq('restaurante_id', restauranteId).order('dia'),
  ]);
  if (fila.error) throw fila.error;
  if (dias.error) throw dias.error;
  return {
    ...fila.data,
    menu_tema: fila.data.menu_tema as TemaMenu,
    tipo_cambio_usd: fila.data.tipo_cambio_usd === null ? null : Number(fila.data.tipo_cambio_usd),
    horario: dias.data.map((d) => ({ dia: d.dia, abre: hora(d.abre), cierra: hora(d.cierra) })),
  };
}

// El error de una escritura, ya en español para la caja; el error completo queda en la consola.
function fallo(contexto: string, error: unknown): Fallo {
  console.error(`[restaurante] ${contexto}:`, error);
  return new Fallo(esDeRed(error) ? SIN_CONEXION : mensajeDeError(error));
}

// ─── Tu restaurante ─────────────────────────────────────────────────────────

export type DatosRestaurante = {
  nombre: string;
  telefono: string;
  direccion: string;
  logo_ruta: string | null;
  horario: Horario[];
};

// «Guardar»: los datos y el horario juntos (guardar_restaurante). Regresa la ruta del logo anterior
// si cambió, para borrarla de R2 después.
export async function guardarRestaurante(restauranteId: string, datos: DatosRestaurante): Promise<string | null> {
  const { data, error } = await supabase.rpc('guardar_restaurante', {
    p_restaurante_id: restauranteId,
    p_nombre: datos.nombre,
    p_telefono: datos.telefono,
    p_direccion: datos.direccion,
    p_logo_ruta: datos.logo_ruta,
    p_horario: datos.horario,
  });
  if (error) throw fallo('guardar_restaurante no se pudo', error);
  return (data as string | null) ?? null;
}

// ─── Tu menú en línea ───────────────────────────────────────────────────────

// «Guardar» de Cómo se ve: el tema, el color (vacío = el neutro) y el tipo de cambio (vacío = solo
// pesos).
export async function guardarMenuEnLinea(
  restauranteId: string,
  tema: TemaMenu,
  color: string | null,
  tipoCambio: number | null,
): Promise<void> {
  const { error } = await supabase.rpc('guardar_menu_en_linea', {
    p_restaurante_id: restauranteId,
    p_tema: tema,
    p_color: color,
    p_tipo_cambio_usd: tipoCambio,
  });
  if (error) throw fallo('guardar_menu_en_linea no se pudo', error);
}

// El chip de arriba: si está abierto (null = sin horario) y cuántos productos ven sus clientes de
// los que tiene, contados por Postgres igual que el menú.
export type EstadoMenu = {
  estado: { abierto: true; cierra: string } | { abierto: false; abre: { dia: number; hora: string; en_dias: number } } | null;
  a_la_vista: number;
  productos: number;
};

export async function leerEstadoMenu(restauranteId: string): Promise<EstadoMenu> {
  const { data, error } = await supabase.rpc('estado_menu_en_linea', { p_restaurante_id: restauranteId });
  if (error) throw error;
  return data as EstadoMenu;
}

// ─── Carteles ───────────────────────────────────────────────────────────────

export const MAXIMO_CARTELES = 5;

export async function leerCarteles(restauranteId: string): Promise<Cartel[]> {
  const { data, error } = await supabase
    .from('carteles')
    .select('id, imagen_ruta')
    .eq('restaurante_id', restauranteId)
    .order('orden')
    .order('id');
  if (error) throw error;
  return data;
}

// La imagen ya la subió el Worker; va al final.
export async function agregarCartel(restauranteId: string, ruta: string): Promise<void> {
  const { error } = await supabase.rpc('agregar_cartel', { p_restaurante_id: restauranteId, p_imagen_ruta: ruta });
  if (error) throw fallo('agregar_cartel no se pudo', error);
}

// Regresa la ruta de la imagen anterior, para borrarla de R2.
export async function cambiarCartel(id: number, ruta: string): Promise<string | null> {
  const { data, error } = await supabase.rpc('cambiar_cartel', { p_cartel_id: id, p_imagen_ruta: ruta });
  if (error) throw fallo('cambiar_cartel no se pudo', error);
  return (data as string | null) ?? null;
}

export async function moverCartel(id: number, hacia: 'arriba' | 'abajo'): Promise<void> {
  const { error } = await supabase.rpc('mover_cartel', { p_cartel_id: id, p_hacia: hacia });
  if (error) throw fallo('mover_cartel no se pudo', error);
}

// Regresa la ruta de su imagen, para borrarla de R2.
export async function quitarCartel(id: number): Promise<string> {
  const { data, error } = await supabase.rpc('quitar_cartel', { p_cartel_id: id });
  if (error) throw fallo('quitar_cartel no se pudo', error);
  return data as string;
}
