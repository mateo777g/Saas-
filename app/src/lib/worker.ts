// Las llamadas del panel al Worker (api-pruebas), con la sesión de quien está adentro: las fotos
// del menú (fotos.ts), el alta y los PIN del equipo (equipo.ts) y las muestras de los estilos y
// la lista de sus prompts (estilos.ts, el único GET). El Worker le pregunta a
// Postgres con esa sesión antes de hacer nada (libreta 3) y contesta sus errores en español,
// listos para la caja de error.
import { ALGO_SALIO_PANEL, Fallo, SIN_CONEXION } from './errores';
import { supabase } from './supabase';

const API = import.meta.env.VITE_API_URL;
if (!API) throw new Error('Falta VITE_API_URL en app/.env');

// `contexto` va al principio de cada registro de la consola ('fotos', 'equipo'). El cuerpo es la
// foto en WebP tal cual o un objeto que se manda como JSON.
export async function llamarWorker(
  contexto: string,
  metodo: 'GET' | 'POST' | 'DELETE',
  camino: string,
  cuerpo?: Blob | Record<string, unknown>,
): Promise<Record<string, unknown> | null> {
  const { data, error } = await supabase.auth.getSession();
  if (error || !data.session) {
    console.error(`[${contexto}] no hay sesión para hablar con el Worker:`, error);
    throw new Fallo('Tu sesión venció. Vuelve a entrar.');
  }

  const esFoto = cuerpo instanceof Blob;
  let respuesta: Response;
  try {
    respuesta = await fetch(`${API}${camino}`, {
      method: metodo,
      headers: {
        Authorization: `Bearer ${data.session.access_token}`,
        ...(cuerpo ? { 'Content-Type': esFoto ? 'image/webp' : 'application/json' } : {}),
      },
      body: cuerpo === undefined ? undefined : esFoto ? cuerpo : JSON.stringify(cuerpo),
    });
  } catch (falla) {
    console.error(`[${contexto}] ${metodo} ${camino}: no se pudo hablar con el Worker:`, falla);
    throw new Fallo(SIN_CONEXION);
  }

  const respuestaJson = await respuesta.json().catch(() => null);
  if (!respuesta.ok) {
    console.error(`[${contexto}] ${metodo} ${camino}: el Worker dijo ${respuesta.status}:`, respuestaJson);
    throw new Fallo(typeof respuestaJson?.error === 'string' ? respuestaJson.error : ALGO_SALIO_PANEL);
  }
  return respuestaJson;
}
