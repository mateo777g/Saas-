// El Worker de Fragmentless (libreta 3, Seguridad). Hoy hace diez cosas: subir y borrar las
// fotos del menú en R2 (fotos.ts), las cuentas, los PIN y los aparatos del equipo (equipo.ts), lo
// que pide el PIN de otra persona en el punto de venta (pos.ts), el agente IA con su saludo
// (agente.ts) y «Armar mi menú con tu carta» (carta.ts), el pedido del menú en línea por WhatsApp (pedidos.ts), el asistente del menú
// (asistente.ts), las muestras de los estilos de los anuncios (estilos.ts), Crear contenido
// (crearContenido.ts, con su trabajo en segundo plano en hacerAnuncio.ts) y Mi biblioteca
// (biblioteca.ts: Eliminar y, cada día a las 9:00 UTC, el borrado de los 30 días) y Mi menú
// (traducir.ts: el inglés que traduce la IA y, en el mismo Cron, el dólar del día), y la terminal
// conectada (terminal.ts y mercadoPago.ts: conectar Mercado Pago, mandar cada cobro a la Point, sus
// avisos y, en el mismo Cron, renovar sus llaves), y en el mismo Cron borra las fotos sueltas del
// recetario (recetario.ts), y la tarjeta de lealtad del menú (tarjeta.ts). Nunca decide solo: antes
// de cada trabajo le pregunta a Postgres si se puede.
import { agente } from './agente';
import { preguntaDelMenu } from './asistente';
import { borrarVencidos } from './biblioteca';
import { crearContenido } from './crearContenido';
import { equipo } from './equipo';
import { listaDeEstilos, muestraDeEstilo } from './estilos';
import { fotoDelMenu } from './fotos';
import { pedidoDelMenu } from './pedidos';
import { tarjetaDelMenu } from './tarjeta';
import { pos } from './pos';
import { borrarFotosSueltas } from './recetario';
import { avisoDeMercadoPago, mercadoPago, regresoDeMercadoPago, renovarLlaves, terminal } from './terminal';
import { conCors, error, origenPermitido, preflight, Rechazo } from './respuestas';
import { dolarDelDia, traducirMenu } from './traducir';
import type { Parametros } from './hacerAnuncio';

// El trabajo en segundo plano de los anuncios: Cloudflare lo encuentra aquí por su nombre.
export { HacerAnuncio } from './hacerAnuncio';

// Lo que le da wrangler.jsonc: el bucket y el trabajo de los anuncios por binding (sin llave) y
// tres valores que no son secretos (la URL de Supabase, su llave publicable y las páginas que pueden
// llamar). Los cinco secretos los pega Fragmentless en el dashboard de Cloudflare (Settings →
// Variables and Secrets). Los OPENAI_MODEL… no existen hoy: solo sirven para cambiar de modelo sin
// publicar código.
export interface Env {
  BUCKET: R2Bucket;
  HACER_ANUNCIO: Workflow<Parametros>;
  SUPABASE_URL: string;
  SUPABASE_LLAVE_PUBLICABLE: string;
  ORIGENES: string;
  SUPABASE_LLAVE_SECRETA?: string;
  PIMIENTA_PIN?: string;
  OPENAI_LLAVE?: string;
  TURNSTILE_SECRETO?: string;
  PIMIENTA_MARCAS?: string;
  OPENAI_MODEL?: string;
  OPENAI_MODEL_SALUDO?: string;
  OPENAI_MODEL_MENU?: string;
  OPENAI_MODEL_IMAGEN?: string;
  OPENAI_MODEL_PALABRAS?: string;
  OPENAI_MODEL_TRADUCIR?: string;
  // La terminal: la dirección fija de regreso al conectar (wrangler.jsonc) y los secretos de la aplicación de
  // Mercado Pago, el de sus avisos y la llave que cifra las llaves de cada sucursal (32 bytes en base64), con su
  // versión y, mientras se cambia, la anterior.
  MP_REGRESO?: string;
  MP_CLIENT_ID?: string;
  MP_CLIENT_SECRET?: string;
  MP_SECRETO_AVISOS?: string;
  MP_LLAVE_CIFRADO?: string;
  MP_LLAVE_CIFRADO_ANTERIOR?: string;
  MP_LLAVE_VERSION?: string;
}

export default {
  async fetch(request, env, ctx): Promise<Response> {
    const url = new URL(request.url);
    // Lo único que llega sin Origin: los avisos de Mercado Pago (con su firma) y su regreso al conectar (una página
    // del navegador, con su pase de un solo uso).
    if (url.pathname === '/mp/aviso' || url.pathname === '/mp/regreso') {
      try {
        if (url.pathname === '/mp/aviso') return await avisoDeMercadoPago(request, env, url);
        if (request.method !== 'GET') return new Response('Solo GET', { status: 405 });
        return await regresoDeMercadoPago(env, url);
      } catch (e) {
        console.error('[api] falló', request.method, url.pathname, e);
        return new Response('Algo salió mal.', { status: 500 });
      }
    }
    const origen = request.headers.get('Origin');
    if (!origenPermitido(origen, env.ORIGENES)) {
      console.warn('[api] origen no permitido', origen, request.method, url.pathname);
      return error(403, 'Esta página no puede usar el servidor de Fragmentless.');
    }
    if (request.method === 'OPTIONS') return preflight(origen);

    let respuesta: Response;
    try {
      if (url.pathname === '/menu/foto') respuesta = await fotoDelMenu(request, env, url);
      else if (url.pathname === '/menu/pedido') respuesta = await pedidoDelMenu(request, env, url);
      else if (url.pathname === '/menu/tarjeta' || url.pathname.startsWith('/menu/tarjeta/')) respuesta = await tarjetaDelMenu(request, env, url);
      else if (url.pathname === '/menu/pregunta') respuesta = await preguntaDelMenu(request, env, url, ctx);
      else if (url.pathname === '/menu/traducir') respuesta = await traducirMenu(request, env, url);
      else if (url.pathname === '/estilos/muestra') respuesta = await muestraDeEstilo(request, env, url);
      else if (url.pathname === '/estilos') respuesta = await listaDeEstilos(request, env);
      else if (url.pathname === '/anuncios' || url.pathname.startsWith('/anuncios/')) respuesta = await crearContenido(request, env, url);
      else if (url.pathname.startsWith('/equipo/')) respuesta = await equipo(request, env, url);
      else if (url.pathname.startsWith('/pos/')) respuesta = await pos(request, env, url);
      else if (url.pathname.startsWith('/mp/')) respuesta = await mercadoPago(request, env, url);
      else if (url.pathname.startsWith('/terminal/')) respuesta = await terminal(request, env, url);
      else if (url.pathname.startsWith('/agente/')) respuesta = await agente(request, env, url, ctx);
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

  // El Cron Trigger diario (wrangler.jsonc): el borrado de los 30 días, el dólar del día, renovar las llaves de
  // Mercado Pago y las fotos sueltas del recetario, cada uno por su lado. Si el borrado, la renovación o las fotos
  // fallan, la corrida sale como fallida en Cloudflare; el dólar nunca la tumba.
  async scheduled(_controlador, env): Promise<void> {
    const [vencidos, , llaves, fotos] = await Promise.allSettled([
      borrarVencidos(env),
      dolarDelDia(env),
      renovarLlaves(env),
      borrarFotosSueltas(env),
    ]);
    if (vencidos.status === 'rejected') throw vencidos.reason;
    if (llaves.status === 'rejected') throw llaves.reason;
    if (fotos.status === 'rejected') throw fotos.reason;
  },
} satisfies ExportedHandler<Env>;
