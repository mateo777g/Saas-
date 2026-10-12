// Lo que lee el panel del distribuidor (libreta 8, paso 2). Su nombre y si está de baja salen de
// su fila en distribuidores, la única que su RLS le deja leer; sus 3 cifras y su lista, de
// distribuidor_resumen() y distribuidor_clientes() (migración distribuidor_lectura), que solo le
// responden mientras esté activo. Nada cambia datos y la app no cuenta nada.
import { esDeRed, mensajeDeError } from './errores';
import type { Cliente, Lectura, Resumen } from './panel';
import { supabase } from './supabase';

// Su fila en distribuidores: lo que sale al pie de su barra y si ve su panel o la pantalla de baja.
export type Cuenta = { nombre: string; activo: boolean };

// Una fila de distribuidor_clientes(): la de Clientes de Fragmentless sin su distribuidor.
export type ClienteDistribuidor = Omit<Cliente, 'distribuidor_id' | 'distribuidor_nombre'>;

export type DatosDistribuidor = {
  resumen: Lectura<Resumen>;
  clientes: Lectura<ClienteDistribuidor[]>;
};

// Su fila, o nada si la cuenta no está ligada a ningún distribuidor. Si no se pudo leer, lanza el
// error tal cual (quien llama decide).
export async function leerCuenta(usuarioId: string): Promise<Cuenta | null> {
  const { data, error } = await supabase.from('distribuidores').select('nombre, activo').eq('usuario_id', usuarioId);
  if (error) throw error;
  return data[0] ?? null;
}

async function leer<T>(funcion: string): Promise<Lectura<T>> {
  const { data, error } = await supabase.rpc(funcion);
  if (error) {
    console.error(`[distribuidor] no se pudo leer ${funcion}:`, error);
    return { ok: false, mensaje: mensajeDeError(error), deRed: esDeRed(error) };
  }
  return { ok: true, datos: data as T };
}

// Todo lo que muestran Inicio y Clientes, de una vez: al abrir, con Actualizar y cada vez que
// regresa a la pestaña. Cada parte por separado: si una falla, la otra se ve igual.
export async function leerPanelDistribuidor(): Promise<DatosDistribuidor> {
  const [resumen, clientes] = await Promise.all([
    leer<Resumen[]>('distribuidor_resumen'),
    leer<ClienteDistribuidor[]>('distribuidor_clientes'),
  ]);
  return { resumen: resumen.ok ? { ok: true, datos: resumen.datos[0] } : resumen, clientes };
}
