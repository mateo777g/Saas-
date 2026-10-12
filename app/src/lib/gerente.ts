// Lo que lee y guarda el panel del gerente en el paso 1. Sus restaurantes, con su estado, su
// fecha y su hora, vienen de mis_sucursales() (migración gerente_lectura); el apodo, de su fila
// en perfiles; el plan, de cada restaurante. La app no cuenta nada.
import { mensajeDeError } from './errores';
import { supabase } from './supabase';

// Una fila de mis_sucursales(): todo ya contado por Postgres.
export type Sucursal = {
  id: string;
  nombre: string;
  slug: string;
  estado: 'funciona' | 'vencida' | 'pausada';
  licencia_fin: string | null;
  hoy: string; // la fecha de hoy en la zona del restaurante, 'aaaa-mm-dd'
  hora: number; // la hora de ahora en esa zona, 0 a 23
  mi_nombre: string;
};

// Lo que el panel tiene a la mano: sus sucursales (por nombre, como las da Postgres), su apodo y
// el plan de cada sucursal por id. Si el apodo o los planes no se pudieron leer, van vacíos y el
// panel usa su nombre y no dice plan.
export type DatosGerente = {
  sucursales: Sucursal[];
  apodo: string | null;
  planes: Record<string, string>;
};

// La sucursal que eligió en este aparato, guardada en el navegador como el tema (libreta 4,
// decidido el 11 de octubre de 2026).
const LLAVE_SUCURSAL = 'fragmentless-sucursal';

const PLANES: Record<string, string> = { basico: 'Básico', pro: 'Pro' };

// Todo de una vez: al entrar y cada vez que regresa a la pestaña. Si la lista de sucursales no se
// pudo leer, lanza ese error tal cual (quien llama decide); sin sucursales, la cuenta ya no es
// gerente de ninguna.
export async function leerGerente(usuarioId: string): Promise<DatosGerente> {
  const sucursales = await supabase.rpc('mis_sucursales');
  if (sucursales.error) throw sucursales.error;
  const lista = sucursales.data as Sucursal[];
  const [apodo, planes] = await Promise.all([leerApodo(usuarioId), leerPlanes(lista.map((s) => s.id))]);
  return { sucursales: lista, apodo, planes };
}

// Su apodo ("¿Cómo quieres que te llamemos?"); sin fila o sin apodo, nada.
async function leerApodo(usuarioId: string): Promise<string | null> {
  const { data, error } = await supabase.from('perfiles').select('apodo').eq('usuario_id', usuarioId);
  if (error) {
    console.error('[gerente] no se pudo leer el apodo; se usa su nombre:', error);
    return null;
  }
  return data[0]?.apodo ?? null;
}

async function leerPlanes(ids: string[]): Promise<Record<string, string>> {
  if (!ids.length) return {};
  const { data, error } = await supabase.from('restaurantes').select('id, plan').in('id', ids);
  if (error) {
    console.error('[gerente] no se pudo leer el plan de sus sucursales:', error);
    return {};
  }
  return Object.fromEntries(data.map((r: { id: string; plan: string }) => [r.id, PLANES[r.plan] ?? r.plan]));
}

// El botón Guardar de Perfil: guardar_perfil (migración perfiles) corrige su nombre en todas sus
// sucursales y guarda su apodo. Postgres quita los espacios de sobra, deja sin apodo si va vacío y
// revisa los 20 de máximo; sus errores ya vienen en español y salen tal cual.
export async function guardarPerfil(
  nombre: string,
  apodo: string,
): Promise<{ ok: true } | { ok: false; mensaje: string }> {
  const { error } = await supabase.rpc('guardar_perfil', { p_nombre: nombre, p_apodo: apodo });
  if (error) {
    console.error('[gerente] guardar_perfil no se pudo:', error);
    return { ok: false, mensaje: mensajeDeError(error) };
  }
  return { ok: true };
}

// Cuál sale al abrir: la última que eligió en este aparato, si sigue en su lista (funcione o no);
// si no, la primera que funciona por orden alfabético; si ninguna funciona, la primera.
export function sucursalInicial(sucursales: Sucursal[]): Sucursal {
  let recordada: string | null = null;
  try {
    recordada = localStorage.getItem(LLAVE_SUCURSAL);
  } catch (error) {
    console.error('[gerente] no se pudo leer la sucursal guardada:', error);
  }
  return (
    sucursales.find((s) => s.id === recordada) ??
    sucursales.find((s) => s.estado === 'funciona') ??
    sucursales[0]
  );
}

export function recordarSucursal(id: string): void {
  try {
    localStorage.setItem(LLAVE_SUCURSAL, id);
  } catch (error) {
    console.error('[gerente] no se pudo guardar la sucursal elegida:', error);
  }
}
