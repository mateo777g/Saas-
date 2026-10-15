// Lo que lee y escribe Mi menú (migración menu): las categorías y los productos del restaurante.
// El gerente escribe directo en las tablas, solo las columnas que Postgres le deja; el orden, el
// archivado y el borrado los deciden las funciones de la base (mover_categoria,
// eliminar_producto, eliminar_categoria). Se leen solo los que no están archivados: los
// archivados ya no salen en ningún lado del panel.
import { esDeRed, Fallo, mensajeDeError, SIN_CONEXION } from './errores';
import { supabase } from './supabase';

export type Categoria = { id: number; nombre: string; icono: string };

export type Producto = {
  id: number;
  categoria_id: number;
  nombre: string;
  descripcion: string | null;
  precio: number;
  imagen_ruta: string | null;
  visible: boolean;
};

// Las categorías en su orden (el del menú en línea) y los productos en el de la tabla: por el
// lugar de su categoría y, dentro de ella, por el suyo.
export type Menu = { categorias: Categoria[]; productos: Producto[] };

export async function leerMenu(restauranteId: string): Promise<Menu> {
  const [categorias, productos] = await Promise.all([
    supabase
      .from('categorias')
      .select('id, nombre, icono')
      .eq('restaurante_id', restauranteId)
      .is('archivado_at', null)
      .order('orden')
      .order('id'),
    supabase
      .from('productos')
      .select('id, categoria_id, nombre, descripcion, precio, imagen_ruta, visible')
      .eq('restaurante_id', restauranteId)
      .is('archivado_at', null)
      .order('orden')
      .order('id'),
  ]);
  if (categorias.error) throw categorias.error;
  if (productos.error) throw productos.error;

  const lista = productos.data.map((p) => ({ ...p, precio: Number(p.precio) }));
  return { categorias: categorias.data, productos: ordenarProductos(categorias.data, lista) };
}

// Los productos (ya en su orden dentro de cada categoría) acomodados por el lugar de su
// categoría. También al mover una categoría con las flechas, sin volver a leer.
export function ordenarProductos(categorias: Categoria[], productos: Producto[]): Producto[] {
  const lugar = new Map(categorias.map((c, i) => [c.id, i]));
  return productos
    .map((p, i) => ({ p, i }))
    .sort((a, b) => (lugar.get(a.p.categoria_id) ?? 0) - (lugar.get(b.p.categoria_id) ?? 0) || a.i - b.i)
    .map(({ p }) => p);
}

// El error de una escritura, ya en español para la caja; el error completo queda en la consola.
function fallo(contexto: string, error: unknown): Fallo {
  console.error(`[menu] ${contexto}:`, error);
  return new Fallo(esDeRed(error) ? SIN_CONEXION : mensajeDeError(error));
}

// Un UPDATE que RLS no deja pasar no da error: regresa 0 filas (la regla de siempre). Se revisa.
function revisarFilas(contexto: string, filas: unknown[] | null, esperadas: number, mensaje: string) {
  if ((filas?.length ?? 0) !== esperadas) {
    console.error(`[menu] ${contexto}: se esperaban ${esperadas} filas y cambiaron ${filas?.length ?? 0}`);
    throw new Fallo(mensaje);
  }
}

// ─── Productos ──────────────────────────────────────────────────────────────

// Lo que se escribe en la ventana del producto. La foto va aparte (fotos.ts): aquí solo su ruta.
export type DatosProducto = {
  categoria_id: number;
  nombre: string;
  descripcion: string;
  precio: number;
  imagen_ruta?: string;
};

export async function crearProducto(restauranteId: string, datos: DatosProducto): Promise<void> {
  const { data, error } = await supabase
    .from('productos')
    .insert({ restaurante_id: restauranteId, ...datos })
    .select('id');
  if (error) throw fallo('no se pudo crear el producto', error);
  revisarFilas('crear producto', data, 1, 'No se pudo guardar el producto. Intenta de nuevo.');
}

export async function editarProducto(id: number, datos: DatosProducto): Promise<void> {
  const { data, error } = await supabase.from('productos').update(datos).eq('id', id).select('id');
  if (error) throw fallo('no se pudo guardar el producto', error);
  revisarFilas('editar producto', data, 1, 'No se pudo guardar el producto. Intenta de nuevo.');
}

// El ojito y Ocultar varios: cambia la visibilidad de esos productos de una vez. Regresa cuántos
// cambiaron de verdad (RLS puede dejar fuera algunos sin decir nada).
export async function cambiarVisibilidad(ids: number[], visible: boolean): Promise<number> {
  const { data, error } = await supabase.from('productos').update({ visible }).in('id', ids).select('id');
  if (error) throw fallo('no se pudo cambiar la visibilidad', error);
  return data.length;
}

// «Eliminar producto»: Postgres lo borra si nunca se vendió y regresa la ruta de su foto para
// borrarla; si ya se vendió, lo archiva y su foto se queda.
export async function eliminarProducto(id: number): Promise<{ resultado: 'borrado' | 'archivado'; imagen_ruta: string | null }> {
  const { data, error } = await supabase.rpc('eliminar_producto', { p_producto_id: id });
  if (error) throw fallo('eliminar_producto no se pudo', error);
  const fila = (data as { resultado: 'borrado' | 'archivado'; imagen_ruta: string | null }[])[0];
  if (!fila) throw fallo('eliminar_producto no regresó nada', data);
  return fila;
}

// ─── Categorías ─────────────────────────────────────────────────────────────

export async function crearCategoria(restauranteId: string, nombre: string, icono: string): Promise<void> {
  const { data, error } = await supabase
    .from('categorias')
    .insert({ restaurante_id: restauranteId, nombre, icono })
    .select('id');
  if (error) throw fallo('no se pudo crear la categoría', error);
  revisarFilas('crear categoría', data, 1, 'No se pudo guardar la categoría. Intenta de nuevo.');
}

export async function editarCategoria(id: number, nombre: string, icono: string): Promise<void> {
  const { data, error } = await supabase.from('categorias').update({ nombre, icono }).eq('id', id).select('id');
  if (error) throw fallo('no se pudo guardar la categoría', error);
  revisarFilas('editar categoría', data, 1, 'No se pudo guardar la categoría. Intenta de nuevo.');
}

// Las flechas: la sube o la baja un lugar; Postgres renumera las demás.
export async function moverCategoria(id: number, hacia: 'arriba' | 'abajo'): Promise<void> {
  const { error } = await supabase.rpc('mover_categoria', { p_categoria_id: id, p_hacia: hacia });
  if (error) throw fallo('mover_categoria no se pudo', error);
}

// Postgres la borra, o la archiva si solo le quedan productos archivados; con productos, no deja.
export async function eliminarCategoria(id: number): Promise<void> {
  const { error } = await supabase.rpc('eliminar_categoria', { p_categoria_id: id });
  if (error) throw fallo('eliminar_categoria no se pudo', error);
}
