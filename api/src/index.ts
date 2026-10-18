// El Worker de Fragmentless (libreta 3, Seguridad). Hoy hace tres cosas: subir y borrar las fotos
// del menú en R2 (fotos.ts), las cuentas, los PIN y los aparatos del equipo (equipo.ts), y lo que
// pide el PIN de otra persona en el punto de venta (pos.ts). Nunca decide solo: antes de cada
// trabajo le pregunta a Postgres si se puede.
import { equipo } from './equipo';
import { fotoDelMenu } from './fotos';
import { pos } from './pos';
import { conCors, error, origenPermitido, preflight, Rechazo } from './respuestas';

// Lo que le da wrangler.jsonc: el bucket por binding (sin llave) y tres valores que no son
// secretos (la URL de Supabase, su llave publicable y las páginas que pueden llamar). Los dos
// secretos los pega Fragmentless en el dashboard de Cloudflare (Settings → Variables and Secrets).
export interface Env {
  BUCKET: R2Bucket;
  SUPABASE_URL: string;
  SUPABASE_LLAVE_PUBLICABLE: string;
  ORIGENES: string;
  SUPABASE_LLAVE_SECRETA?: string;
  PIMIENTA_PIN?: string;
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
      else if (url.pathname.startsWith('/equipo/')) respuesta = await equipo(request, env, url);
      else if (url.pathname.startsWith('/pos/')) respuesta = await pos(request, env, url);
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
