// Lo que leen y escriben «Tu restaurante» y «Tu menú en línea» (migración menu_en_linea; libreta 6,
// decidido el 20 de octubre de 2026). Se leen las tablas directo (restaurantes, horarios, carteles);
// se escribe solo con las funciones de la base, que revisan que quien llama sea el gerente.
import type { TemaMenu } from './color';
import { esDeRed, Fallo, mensajeDeError, SIN_CONEXION } from './errores';
import { leerFormas, type Formas } from './formasMenu';
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
  hace_envios: boolean; // «Hago envíos» (parte 6b): sus clientes también piden a domicilio
  horario: Horario[];
};

// Un cartel es una imagen que subió o un producto de Mi menú con foto (migración tu_menu_en_linea): uno de los dos.
export type Cartel = { id: number; imagen_ruta: string | null; producto_id: number | null };

// '09:00:00' (como lo da Postgres) → '9:00'.
function hora(t: string): string {
  const [h, m] = t.split(':');
  return `${Number(h)}:${m}`;
}

export async function leerRestaurante(restauranteId: string): Promise<Restaurante> {
  const [fila, dias] = await Promise.all([
    supabase
      .from('restaurantes')
      .select('nombre, slug, telefono, direccion, logo_ruta, menu_tema, menu_color, hace_envios')
      .eq('id', restauranteId)
      .single(),
    supabase.from('horarios').select('dia, abre, cierra').eq('restaurante_id', restauranteId).order('dia'),
  ]);
  if (fila.error) throw fila.error;
  if (dias.error) throw dias.error;
  return {
    ...fila.data,
    menu_tema: fila.data.menu_tema as TemaMenu,
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
  // «Hago envíos» (desde el 12 nov 2026 vive aquí y no en Tu menú en línea).
  hace_envios: boolean;
};

// «Guardar»: los datos, el horario y «Hago envíos» juntos (guardar_restaurante). Regresa la ruta del logo
// anterior si cambió, para borrarla de R2 después.
export async function guardarRestaurante(restauranteId: string, datos: DatosRestaurante): Promise<string | null> {
  const { data, error } = await supabase.rpc('guardar_restaurante', {
    p_restaurante_id: restauranteId,
    p_nombre: datos.nombre,
    p_telefono: datos.telefono,
    p_direccion: datos.direccion,
    p_logo_ruta: datos.logo_ruta,
    p_horario: datos.horario,
    p_hace_envios: datos.hace_envios,
  });
  if (error) throw fallo('guardar_restaurante no se pudo', error);
  return (data as string | null) ?? null;
}

// ─── Tu menú en línea ───────────────────────────────────────────────────────

// Cómo se ve su menú (migración tu_menu_en_linea): el tema, los tres colores (vacío = el de siempre) y las 18
// formas. El dólar ya no lo escribe nadie: es uno para todos y lo pone el Worker cada día (Mi menú, 6 nov 2026).
export type DisenoMenu = {
  tema: TemaMenu;
  color: string | null;
  colorBarra: string | null;
  fondo: string | null;
  formas: Formas;
};

export async function leerDisenoMenu(restauranteId: string): Promise<DisenoMenu> {
  const { data, error } = await supabase
    .from('restaurantes')
    .select(
      'menu_tema, menu_color, menu_color_barra, menu_fondo, menu_barra, menu_con_nombre, menu_idioma, menu_moneda, ' +
        'menu_busqueda, menu_carteles, menu_info, menu_info_lugar, menu_carteles_producto, menu_categorias, menu_orden, ' +
        'menu_titulos, menu_productos, menu_abajo, menu_abajo_con_nombres, menu_producto_ventana, menu_producto_titulo, ' +
        'menu_producto_opciones',
    )
    .eq('id', restauranteId)
    .single();
  if (error) throw error;
  const fila = data as unknown as Record<string, unknown>;
  // Las columnas sin «menu_», como las manda menu_publico.
  const sinMenu = Object.fromEntries(Object.entries(fila).map(([k, v]) => [k.replace(/^menu_/, ''), v]));
  return {
    tema: fila.menu_tema === 'oscuro' ? 'oscuro' : 'claro',
    color: (fila.menu_color as string | null) ?? null,
    colorBarra: (fila.menu_color_barra as string | null) ?? null,
    fondo: (fila.menu_fondo as string | null) ?? null,
    formas: leerFormas(sinMenu),
  };
}

// La barra de guardar: el tema, los colores y las formas, todo junto (guardar_menu_en_linea). Cada forma la revisa
// su regla de la tabla.
export async function guardarDisenoMenu(restauranteId: string, d: DisenoMenu): Promise<void> {
  const f = d.formas;
  const { error } = await supabase.rpc('guardar_menu_en_linea', {
    p_restaurante_id: restauranteId,
    p_tema: d.tema,
    p_color: d.color,
    p_color_barra: d.colorBarra,
    p_fondo: d.fondo,
    p_barra: f.barra,
    p_con_nombre: f.con_nombre,
    p_idioma: f.idioma,
    p_moneda: f.moneda,
    p_busqueda: f.busqueda,
    p_carteles: f.carteles,
    p_info: f.info,
    p_info_lugar: f.info_lugar,
    p_carteles_producto: f.carteles_producto,
    p_categorias: f.categorias,
    p_orden: f.orden,
    p_titulos: f.titulos,
    p_productos: f.productos,
    p_abajo: f.abajo,
    p_abajo_con_nombres: f.abajo_con_nombres,
    p_producto_ventana: f.producto_ventana,
    p_producto_titulo: f.producto_titulo,
    p_producto_opciones: f.producto_opciones,
  });
  if (error) throw fallo('guardar_menu_en_linea no se pudo', error);
}

// El chip de arriba: si está abierto (null = sin horario) y cuántos productos ven sus clientes de
// los que tiene, contados por Postgres igual que el menú. Con la 6c, si el asistente del menú
// contesta y, si no, por qué (sin IA o en su límite), si tiene distribuidor y cuándo vuelve: Don
// Chuy no ve números, solo el aviso.
export type EstadoMenu = {
  estado: { abierto: true; cierra: string } | { abierto: false; abre: { dia: number; hora: string; en_dias: number } } | null;
  a_la_vista: number;
  productos: number;
  asistente: { puede: true } | { puede: false; motivo: 'sin_ia' | 'limite'; con_distribuidor: boolean; vuelve: string };
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
    .select('id, imagen_ruta, producto_id')
    .eq('restaurante_id', restauranteId)
    .order('orden')
    .order('id');
  if (error) throw error;
  return data;
}

// Lo que lleva un cartel: la imagen que ya subió el Worker, o un producto de Mi menú con foto.
export type LoDelCartel = { imagen: string } | { producto: number };

const argumentos = (lo: LoDelCartel) =>
  'imagen' in lo ? { p_imagen_ruta: lo.imagen, p_producto_id: null } : { p_imagen_ruta: null, p_producto_id: lo.producto };

// Va al final.
export async function agregarCartel(restauranteId: string, lo: LoDelCartel): Promise<void> {
  const { error } = await supabase.rpc('agregar_cartel', { p_restaurante_id: restauranteId, ...argumentos(lo) });
  if (error) throw fallo('agregar_cartel no se pudo', error);
}

// En su mismo lugar. Regresa la ruta de la imagen anterior si se fue, para borrarla de R2.
export async function cambiarCartel(id: number, lo: LoDelCartel): Promise<string | null> {
  const { data, error } = await supabase.rpc('cambiar_cartel', { p_cartel_id: id, ...argumentos(lo) });
  if (error) throw fallo('cambiar_cartel no se pudo', error);
  return (data as string | null) ?? null;
}

export async function moverCartel(id: number, hacia: 'arriba' | 'abajo'): Promise<void> {
  const { error } = await supabase.rpc('mover_cartel', { p_cartel_id: id, p_hacia: hacia });
  if (error) throw fallo('mover_cartel no se pudo', error);
}

// Regresa la ruta de su imagen, para borrarla de R2 (vacío si era un producto: no hay imagen que borrar).
export async function quitarCartel(id: number): Promise<string | null> {
  const { data, error } = await supabase.rpc('quitar_cartel', { p_cartel_id: id });
  if (error) throw fallo('quitar_cartel no se pudo', error);
  return (data as string | null) ?? null;
}
