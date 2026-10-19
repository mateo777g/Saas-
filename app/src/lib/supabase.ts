// La conexión de la app con Supabase (proyecto Saas-Restaurantes), con la llave publicable.
// La secreta nunca va aquí: vive solo en el Worker. Las dos llegan de app/.env, fuera de git.
import { createClient } from '@supabase/supabase-js';

const URL_PROYECTO = import.meta.env.VITE_SUPABASE_URL;
const LLAVE_PUBLICABLE = import.meta.env.VITE_SUPABASE_LLAVE_PUBLICABLE;
if (!URL_PROYECTO || !LLAVE_PUBLICABLE) {
  throw new Error('Faltan VITE_SUPABASE_URL o VITE_SUPABASE_LLAVE_PUBLICABLE en app/.env');
}

// La sesión es la que da Supabase (libreta 4, decidido el 11 de octubre de 2026): se entra una
// vez, el navegador la guarda con este nombre y se renueva sola mientras no se cierre.
export const supabase = createClient(URL_PROYECTO, LLAVE_PUBLICABLE, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: false,
    storageKey: 'fragmentless-sesion',
  },
});

// "Cerrar sesión" solo saca de este aparato: si Don Chuy cierra sesión en su celular, su compu
// sigue dentro. Sin internet Supabase no alcanza a avisarle al servidor, pero la sesión se borra
// de este navegador igual. También se borra lo que el Agente IA guardó aquí: el Historial de cada
// sucursal y su saludo de reserva (todo lo que empieza con PREFIJO de agente.ts; libreta 1,
// decidido el 19 de octubre de 2026).
export async function cerrarSesion(): Promise<void> {
  const { error } = await supabase.auth.signOut({ scope: 'local' });
  if (error) console.error('[sesion] el servidor no se enteró del cierre; se borró solo aquí:', error);
  try {
    const llaves = Object.keys(localStorage).filter((k) => k.startsWith('fragmentless-agente-'));
    for (const k of llaves) localStorage.removeItem(k);
  } catch (e) {
    console.error('[sesion] no se pudo borrar el Historial del agente de este navegador:', e);
  }
}
