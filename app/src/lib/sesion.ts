// Quién entró y qué panel le toca. La app no decide nada por su cuenta: le pregunta a Postgres.
//   Fragmentless   tiene su fila en plataforma_admins (solo Fragmentless la ve, por RLS)
//   gerente        mis_sucursales() le regresa al menos un restaurante
//   nadie          ni lo uno ni lo otro (Juanito, o Don Chuy antes de ligarlo): se le cierra la
//                  sesión y el login se lo dice (libreta 4, decidido el 11 de octubre de 2026)
import type { User } from '@supabase/supabase-js';
import { cerrarSesion, supabase } from './supabase';
import { ALGO_SALIO, SIN_CONEXION, esDeRed } from './errores';

export const SIN_PANEL =
  'Esta cuenta no tiene acceso a ningún panel. Si crees que es un error, escríbele a Fragmentless.';

// Una fila de mis_sucursales() (migración gerente_lectura): todo ya contado por Postgres.
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

// Fragmentless lleva el correo de su sesión, que sale al pie de su barra lateral.
export type Panel =
  | { tipo: 'fragmentless'; correo: string }
  | { tipo: 'gerente'; sucursales: Sucursal[] };

async function averiguar(usuario: User): Promise<Panel | null> {
  const admins = await supabase
    .from('plataforma_admins')
    .select('usuario_id')
    .eq('usuario_id', usuario.id);
  if (admins.error) throw admins.error;
  if (admins.data.length > 0) return { tipo: 'fragmentless', correo: usuario.email ?? '' };

  const sucursales = await supabase.rpc('mis_sucursales');
  if (sucursales.error) throw sucursales.error;
  if (sucursales.data.length > 0) return { tipo: 'gerente', sucursales: sucursales.data };
  return null;
}

// Al entrar y al abrir la app con la sesión guardada. Si no le toca ningún panel, o no se pudo
// averiguar, cierra la sesión y regresa el mensaje para el login (como el candado de Flet: si no
// se sabe, no se deja pasar).
export async function abrirPanel(usuario: User): Promise<{ panel: Panel } | { mensaje: string }> {
  try {
    const panel = await averiguar(usuario);
    if (panel) return { panel };
    await cerrarSesion();
    return { mensaje: SIN_PANEL };
  } catch (error) {
    console.error('[sesion] no se pudo averiguar qué panel abrir:', error);
    await cerrarSesion();
    return { mensaje: esDeRed(error) ? SIN_CONEXION : ALGO_SALIO };
  }
}
