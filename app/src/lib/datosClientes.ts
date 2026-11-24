// Los datos de los clientes del menú en Ajustes (migración datos_de_clientes, 21 nov 2026; planes/trabajo/datos-de-clientes/):
// Don Chuy busca un teléfono y borra lo de ese cliente en esta sucursal. Los dos los revisa Postgres (solo el gerente de
// la sucursal) y regresan cuántos pedidos: un pedido y la cuenta que salió de él cuentan como uno. Solo cuenta lo que se
// puede vaciar (sin los por confirmar ni las cuentas abiertas). Un teléfono que no son 10 dígitos lo dice Postgres.
// Con la tarjeta de lealtad (23 nov 2026): borrar_datos_cliente también borra su tarjeta, y tarjeta_del_cliente la dice
// antes (su nombre y lo que lleva), con la meta de la regla para escribir «8 de 10 sellos».
import { esDeRed, Fallo, mensajeDeError, SIN_CONEXION } from './errores';
import { supabase } from './supabase';

function fallo(contexto: string, error: unknown): Fallo {
  console.error(`[datos de clientes] ${contexto}:`, error);
  return new Fallo(esDeRed(error) ? SIN_CONEXION : mensajeDeError(error));
}

export async function buscarDatosCliente(restauranteId: string, telefono: string): Promise<number> {
  const { data, error } = await supabase.rpc('buscar_datos_cliente', { p_restaurante_id: restauranteId, p_telefono: telefono });
  if (error) throw fallo('buscar_datos_cliente no se pudo', error);
  return Number(data ?? 0);
}

export async function borrarDatosCliente(restauranteId: string, telefono: string): Promise<number> {
  const { data, error } = await supabase.rpc('borrar_datos_cliente', { p_restaurante_id: restauranteId, p_telefono: telefono });
  if (error) throw fallo('borrar_datos_cliente no se pudo', error);
  return Number(data ?? 0);
}

export type TarjetaDelCliente = { nombre: string; saldo: number; forma: 'sellos' | 'puntos'; meta: number | null };

export async function tarjetaDelCliente(restauranteId: string, telefono: string): Promise<TarjetaDelCliente | null> {
  const [t, l] = await Promise.all([
    supabase.rpc('tarjeta_del_cliente', { p_restaurante_id: restauranteId, p_telefono: telefono }),
    supabase.from('lealtad').select('meta').eq('restaurante_id', restauranteId).maybeSingle(),
  ]);
  if (t.error) throw fallo('tarjeta_del_cliente no se pudo', t.error);
  if (l.error) throw fallo('no se pudo leer la regla de la tarjeta', l.error);
  const d = t.data as { nombre: string; saldo: number; forma: 'sellos' | 'puntos' | null } | null;
  if (!d) return null;
  const meta = l.data?.meta;
  return { nombre: d.nombre, saldo: Number(d.saldo), forma: d.forma ?? 'sellos', meta: meta === null || meta === undefined ? null : Number(meta) };
}
