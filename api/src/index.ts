// El Worker de Fragmentless (libreta 3, Seguridad). Hoy hace dos trabajos: subir y borrar las
// fotos del menú en R2 (fotos.ts). Nunca decide solo: antes de tocar el bucket le pregunta a
// Postgres, con la sesión de quien llama, si se puede.
import { fotoDelMenu } from './fotos';
import { conCors, error, origenPermitido, preflight, Rechazo } from './respuestas';

// Lo que le da wrangler.jsonc: el bucket por binding (sin llave) y tres valores que no son
// secretos (la URL de Supabase, su llave publicable y las páginas que pueden llamar).
export interface Env {
  BUCKET: R2Bucket;
  SUPABASE_URL: string;
  SUPABASE_LLAVE_PUBLICABLE: string;
  ORIGENES: string;
}

export default {
  async fetch(request, env): Promise<Response> {
    const url = new URL(request.url);
    const origen = request.headers.get('Origin');
    if (!origenPermitido(origen, env.ORIGENES)) {
      console.warn('[api] origen no permitido', origen, request.method, url.pathname);
      return error(403, 'Esta página no puede usar el servidor de Fragmentless.');
    }
    if (request.method === 'OPTIONS') return preflight(origen);

    let respuesta: Response;
    try {
      if (url.pathname === '/menu/foto') respuesta = await fotoDelMenu(request, env, url);
      else respuesta = error(404, 'Ese trabajo no existe.');
    } catch (e) {
      if (e instanceof Rechazo) {
        respuesta = error(e.estado, e.message);
      } else {
        console.error('[api] falló', request.method, url.pathname, e);
        respuesta = error(500, 'Algo salió mal. Intenta de nuevo.');
      }
    }
    return conCors(respuesta, origen);
  },
} satisfies ExportedHandler<Env>;
