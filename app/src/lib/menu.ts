// Lo que lee y escribe Mi menú (migraciones menu y opciones): las categorías, los productos, los
// grupos de opciones y las áreas de preparación del restaurante. El gerente escribe directo en las
// tablas solo lo que Postgres le deja (las categorías, las áreas y el ojito de los productos); el
// orden, el archivado, el borrado, los grupos con sus opciones y el producto con sus grupos los
// deciden las funciones de la base. Se leen solo los que no están archivados: los archivados ya no
// salen en ningún lado del panel.
import { esDeRed, Fallo, mensajeDeError, SIN_CONEXION } from './errores';
import { supabase } from './supabase';

// area_preparacion_id vacía = «Lo sirve el mesero». Los _en son el inglés del menú en línea
// (opcional: vacío = sale el de español; migración menu_en_linea).
export type Categoria = {
  id: number;
  nombre: string;
  nombre_en: string | null;
  icono: string;
  area_preparacion_id: number | null;
};

export type Producto = {
  id: number;
  categoria_id: number;
  nombre: string;
  descripcion: string | null;
  nombre_en: string | null;
  descripcion_en: string | null;
  precio: number;
  imagen_ruta: string | null;
  visible: boolean;
  // «Es un costo de envío» (parte 6b): no sale en el menú en línea ni llega a la cocina, y no lleva
  // foto, inglés ni opciones.
  es_envio: boolean;
  // Los grupos que lleva, en el orden de Opciones.
  grupos: number[];
};

export type Opcion = { id: number; nombre: string; nombre_en: string | null; precio_extra: number; visible: boolean };

// Un grupo con sus opciones en su orden y los productos que lo llevan.
export type Grupo = {
  id: number;
  nombre: string;
  nombre_en: string | null;
  minimo: number;
  maximo: number;
  opciones: Opcion[];
  productos: number[];
};

export type Area = { id: number; nombre: string };

// Las categorías en su orden (el del menú en línea), los productos en el de la tabla (por el lugar
// de su categoría y, dentro de ella, por el suyo), los grupos en el orden en que Pepe elige y las
// áreas en el orden en que se crearon.
export type Menu = { categorias: Categoria[]; productos: Producto[]; grupos: Grupo[]; areas: Area[] };

export async function leerMenu(restauranteId: string): Promise<Menu> {
  const [categorias, productos, grupos, opciones, ligas, areas] = await Promise.all([
    supabase
      .from('categorias')
      .select('id, nombre, nombre_en, icono, area_preparacion_id')
      .eq('restaurante_id', restauranteId)
      .is('archivado_at', null)
      .order('orden')
      .order('id'),
    supabase
      .from('productos')
      .select('id, categoria_id, nombre, descripcion, nombre_en, descripcion_en, precio, imagen_ruta, visible, es_envio')
      .eq('restaurante_id', restauranteId)
      .is('archivado_at', null)
      .order('orden')
      .order('id'),
    supabase
      .from('grupos_opciones')
      .select('id, nombre, nombre_en, minimo, maximo')
      .eq('restaurante_id', restauranteId)
      .order('orden')
      .order('id'),
    supabase
      .from('opciones')
      .select('id, grupo_id, nombre, nombre_en, precio_extra, visible')
      .eq('restaurante_id', restauranteId)
      .order('orden')
      .order('id'),
    supabase.from('producto_grupos').select('producto_id, grupo_id').eq('restaurante_id', restauranteId),
    supabase
      .from('areas_preparacion')
      .select('id, nombre')
      .eq('restaurante_id', restauranteId)
      .is('archivado_at', null)
      .order('id'),
  ]);
  for (const r of [categorias, productos, grupos, opciones, ligas, areas]) if (r.error) throw r.error;

  const vivos = new Set(productos.data!.map((p) => p.id));
  const listaGrupos: Grupo[] = grupos.data!.map((g) => ({
    ...g,
    opciones: opciones.data!
      .filter((o) => o.grupo_id === g.id)
      .map(({ id, nombre, nombre_en, precio_extra, visible }) => ({
        id,
        nombre,
        nombre_en,
        precio_extra: Number(precio_extra),
        visible,
      })),
    productos: ligas.data!.filter((l) => l.grupo_id === g.id && vivos.has(l.producto_id)).map((l) => l.producto_id),
  }));
  const lista = productos.data!.map((p) => ({
    ...p,
    precio: Number(p.precio),
    grupos: listaGrupos.filter((g) => g.productos.includes(p.id)).map((g) => g.id),
  }));
  return {
    categorias: categorias.data!,
    productos: ordenarProductos(categorias.data!, lista),
    grupos: listaGrupos,
    areas: areas.data!,
  };
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

// Lo que se escribe en la ventana del producto. La foto va aparte (fotos.ts): aquí solo su ruta,
// y sin ruta al editar la foto se queda como estaba.
export type DatosProducto = {
  categoria_id: number;
  nombre: string;
  descripcion: string;
  nombre_en: string;
  descripcion_en: string;
  precio: number;
  imagen_ruta?: string;
  grupos: number[];
  es_envio: boolean;
};

// «Agregar producto» y «Guardar cambios»: Postgres guarda el producto y sus grupos juntos
// (guardar_producto); si algo falla, no queda nada a medias. id vacío = producto nuevo.
export async function guardarProducto(restauranteId: string, id: number | null, datos: DatosProducto): Promise<void> {
  const { error } = await supabase.rpc('guardar_producto', {
    p_restaurante_id: restauranteId,
    p_producto_id: id,
    p_categoria_id: datos.categoria_id,
    p_nombre: datos.nombre,
    p_descripcion: datos.descripcion,
    p_precio: datos.precio,
    p_imagen_ruta: datos.imagen_ruta ?? null,
    p_grupos: datos.grupos,
    // Un envío no lleva inglés: vacío no basta, Postgres pide que no vaya.
    p_nombre_en: datos.es_envio ? null : datos.nombre_en,
    p_descripcion_en: datos.es_envio ? null : datos.descripcion_en,
    p_es_envio: datos.es_envio,
  });
  if (error) throw fallo('guardar_producto no se pudo', error);
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

// Lo que se escribe en la ventana de la categoría. area vacía = «Lo sirve el mesero»; el inglés en
// blanco queda vacío (lo limpia la base).
export type DatosCategoria = { nombre: string; nombre_en: string; icono: string; area_preparacion_id: number | null };

export async function crearCategoria(restauranteId: string, datos: DatosCategoria): Promise<void> {
  const { data, error } = await supabase
    .from('categorias')
    .insert({ restaurante_id: restauranteId, ...datos })
    .select('id');
  if (error) throw fallo('no se pudo crear la categoría', error);
  revisarFilas('crear categoría', data, 1, 'No se pudo guardar la categoría. Intenta de nuevo.');
}

export async function editarCategoria(id: number, datos: DatosCategoria): Promise<void> {
  const { data, error } = await supabase.from('categorias').update(datos).eq('id', id).select('id');
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

// ─── Grupos de opciones ─────────────────────────────────────────────────────

// Lo que manda la ventana del grupo: sus opciones en su orden (con id las que ya existían) y los
// productos que lo llevan.
export type DatosGrupo = {
  nombre: string;
  nombre_en: string;
  minimo: number;
  maximo: number;
  opciones: { id: number | null; nombre: string; nombre_en: string; precio_extra: number; visible: boolean }[];
  productos: number[];
};

// «Agregar grupo» y «Guardar cambios»: Postgres guarda todo junto (guardar_grupo) y borra las
// opciones que ya no llegaron. id vacío = grupo nuevo, al final.
export async function guardarGrupo(restauranteId: string, id: number | null, datos: DatosGrupo): Promise<void> {
  const { error } = await supabase.rpc('guardar_grupo', {
    p_restaurante_id: restauranteId,
    p_grupo_id: id,
    p_nombre: datos.nombre,
    p_minimo: datos.minimo,
    p_maximo: datos.maximo,
    p_opciones: datos.opciones,
    p_productos: datos.productos,
    p_nombre_en: datos.nombre_en,
  });
  if (error) throw fallo('guardar_grupo no se pudo', error);
}

// Las flechas de Opciones: lo sube o lo baja un lugar; Postgres renumera los demás.
export async function moverGrupo(id: number, hacia: 'arriba' | 'abajo'): Promise<void> {
  const { error } = await supabase.rpc('mover_grupo', { p_grupo_id: id, p_hacia: hacia });
  if (error) throw fallo('mover_grupo no se pudo', error);
}

// Lo borra con sus opciones y lo quita de sus productos; las ventas pasadas no cambian.
export async function eliminarGrupo(id: number): Promise<void> {
  const { error } = await supabase.rpc('eliminar_grupo', { p_grupo_id: id });
  if (error) throw fallo('eliminar_grupo no se pudo', error);
}

// ─── Áreas de preparación ───────────────────────────────────────────────────

export async function crearArea(restauranteId: string, nombre: string): Promise<void> {
  const { data, error } = await supabase
    .from('areas_preparacion')
    .insert({ restaurante_id: restauranteId, nombre })
    .select('id');
  if (error) throw fallo('no se pudo crear el área', error);
  revisarFilas('crear área', data, 1, 'No se pudo guardar el área. Intenta de nuevo.');
}

export async function renombrarArea(id: number, nombre: string): Promise<void> {
  const { data, error } = await supabase.from('areas_preparacion').update({ nombre }).eq('id', id).select('id');
  if (error) throw fallo('no se pudo guardar el área', error);
  revisarFilas('renombrar área', data, 1, 'No se pudo guardar el área. Intenta de nuevo.');
}

// Postgres no deja si alguna categoría va a ella o si es la última; la borra, o la archiva si ya
// recibió comandas.
export async function eliminarArea(id: number): Promise<void> {
  const { error } = await supabase.rpc('eliminar_area', { p_area_id: id });
  if (error) throw fallo('eliminar_area no se pudo', error);
}
