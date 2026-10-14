// Lo que lee y escribe Mesas (migración mesas): el catálogo de mesas del restaurante. El gerente
// agrega y renombra directo en la tabla, solo las columnas que Postgres le deja; el orden, el
// archivado y el borrado los deciden las funciones de la base (mover_mesa y eliminar_mesa). Se
// leen solo las que no están archivadas: las archivadas ya no salen en ningún lado del panel.
import { esDeRed, mensajeDeError, SIN_CONEXION } from './errores';
import { Fallo } from './fotos';
import { supabase } from './supabase';

export type Mesa = { id: number; nombre: string };

// Las mesas en su orden: el de la tabla y el de las tarjetas del punto de venta.
export async function leerMesas(restauranteId: string): Promise<Mesa[]> {
  const { data, error } = await supabase
    .from('mesas')
    .select('id, nombre')
    .eq('restaurante_id', restauranteId)
    .is('archivado_at', null)
    .order('orden')
    .order('id');
  if (error) throw error;
  return data;
}

// El error de una escritura, ya en español para la caja; el error completo queda en la consola.
function fallo(contexto: string, error: unknown): Fallo {
  console.error(`[mesas] ${contexto}:`, error);
  return new Fallo(esDeRed(error) ? SIN_CONEXION : mensajeDeError(error));
}

// Un UPDATE que RLS no deja pasar no da error: regresa 0 filas (la regla de siempre). Se revisa.
function revisarFilas(contexto: string, filas: unknown[] | null) {
  if ((filas?.length ?? 0) !== 1) {
    console.error(`[mesas] ${contexto}: se esperaba 1 fila y cambiaron ${filas?.length ?? 0}`);
    throw new Fallo('No se pudo guardar la mesa. Intenta de nuevo.');
  }
}

export async function crearMesa(restauranteId: string, nombre: string): Promise<void> {
  const { data, error } = await supabase
    .from('mesas')
    .insert({ restaurante_id: restauranteId, nombre })
    .select('id');
  if (error) throw fallo('no se pudo crear la mesa', error);
  revisarFilas('crear mesa', data);
}

export async function renombrarMesa(id: number, nombre: string): Promise<void> {
  const { data, error } = await supabase.from('mesas').update({ nombre }).eq('id', id).select('id');
  if (error) throw fallo('no se pudo renombrar la mesa', error);
  revisarFilas('renombrar mesa', data);
}

// Las flechas: la sube o la baja un lugar; Postgres renumera las demás.
export async function moverMesa(id: number, hacia: 'arriba' | 'abajo'): Promise<void> {
  const { error } = await supabase.rpc('mover_mesa', { p_mesa_id: id, p_hacia: hacia });
  if (error) throw fallo('mover_mesa no se pudo', error);
}

// «Eliminar mesa»: Postgres la borra si nunca tuvo cuentas y la archiva si ya tuvo.
export async function eliminarMesa(id: number): Promise<'borrado' | 'archivado'> {
  const { data, error } = await supabase.rpc('eliminar_mesa', { p_mesa_id: id });
  if (error) throw fallo('eliminar_mesa no se pudo', error);
  return data as 'borrado' | 'archivado';
}
