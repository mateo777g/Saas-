// Los estilos de los anuncios (libreta 7, parte 7a): sus muestras en R2, tres por estilo (post,
// historia y cartel), en estilos/<clave>/. Solo Fragmentless las sube y las borra, desde «Estilos»
// en su panel. Tres trabajos:
//  - POST /estilos/muestra?clave=<clave>&formato=<post|historia|cartel>, con la muestra WebP como
//    cuerpo: si Postgres dice que quien llama puede subirla (puedo_subir_muestra), la guarda con un
//    nombre al azar y contesta su ruta. La clave puede ser de un estilo que todavía no se guarda,
//    porque sus muestras se suben antes de guardarlo. La forma de cada formato la revisa el navegador.
//  - DELETE /estilos/muestra?ruta=<ruta>: si Postgres dice que puede borrarla (es de estilos/ y
//    ningún estilo la usa), la borra.
//  - GET /estilos: las claves de los estilos que ya tienen su prompt en este código, para que el
//    panel diga «Falta su prompt». Solo para Fragmentless.
// La app guarda la ruta con guardar_estilo; el nombre lo pone siempre el Worker.
import { esWebp, MAXIMO_BYTES, nombreAlAzar } from './fotos';
import type { Env } from './index';
import { json, Rechazo, SIN_PERMISO } from './respuestas';
import { esFragmentless, leerSesion, preguntar } from './supabase';

// Las claves de los estilos cuyo prompt ya vive en el Worker. En la 7a todavía no hay ninguno; en
// la 7b esta lista sale de los prompts.
const CLAVES_CON_PROMPT: string[] = [];

const FORMATOS = ['post', 'historia', 'cartel'];
// Las mismas reglas que exige la base (estilos.clave, puedo_subir_muestra y puedo_borrar_muestra).
// Se revisan aquí también porque la clave se vuelve el nombre de una carpeta.
const CLAVE = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const CLAVE_MAXIMO = 40;
const RUTA = /^estilos\/[a-z0-9]+(-[a-z0-9]+)*\/[0-9a-f]{32}\.webp$/;

export async function muestraDeEstilo(request: Request, env: Env, url: URL): Promise<Response> {
  if (request.method === 'POST') return subir(request, env, url);
  if (request.method === 'DELETE') return borrar(request, env, url);
  throw new Rechazo(405, 'Las muestras solo se suben o se borran.');
}

export async function listaDeEstilos(request: Request, env: Env): Promise<Response> {
  if (request.method !== 'GET') throw new Rechazo(405, 'La lista de estilos solo se lee.');
  const sesion = leerSesion(request);
  if (!(await esFragmentless(env, sesion))) {
    console.warn('[estilos] la lista la pidió alguien que no es Fragmentless');
    throw new Rechazo(403, SIN_PERMISO);
  }
  return json({ claves: CLAVES_CON_PROMPT });
}

async function subir(request: Request, env: Env, url: URL): Promise<Response> {
  const sesion = leerSesion(request);
  const clave = url.searchParams.get('clave') ?? '';
  if (!CLAVE.test(clave) || clave.length > CLAVE_MAXIMO) throw new Rechazo(400, 'Esa clave no es válida.');
  const formato = url.searchParams.get('formato') ?? '';
  if (!FORMATOS.includes(formato)) throw new Rechazo(400, 'Ese formato no existe.');

  // Antes de leer la muestra: el tamaño que dice el navegador.
  const largo = Number(request.headers.get('Content-Length'));
  if (!Number.isFinite(largo) || largo <= 0) throw new Rechazo(411, 'Falta la muestra.');
  if (largo > MAXIMO_BYTES) throw new Rechazo(413, 'La muestra pesa más de 2 MB.');

  if (!(await preguntar(env, sesion, 'puedo_subir_muestra', { p_clave: clave }))) {
    console.warn('[estilos] subida rechazada por Postgres', clave, formato);
    throw new Rechazo(403, SIN_PERMISO);
  }

  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.byteLength > MAXIMO_BYTES) throw new Rechazo(413, 'La muestra pesa más de 2 MB.');
  if (!esWebp(bytes)) throw new Rechazo(415, 'La muestra tiene que ser WebP.');

  const ruta = `estilos/${clave}/${nombreAlAzar()}.webp`;
  await env.BUCKET.put(ruta, bytes, {
    // El nombre nunca se repite, así que el archivo nunca cambia: se puede guardar en caché un año.
    httpMetadata: { contentType: 'image/webp', cacheControl: 'public, max-age=31536000, immutable' },
  });
  console.log('[estilos] muestra subida', formato, ruta, bytes.byteLength);
  return json({ ruta }, 201);
}

async function borrar(request: Request, env: Env, url: URL): Promise<Response> {
  const sesion = leerSesion(request);
  const ruta = url.searchParams.get('ruta') ?? '';
  if (!RUTA.test(ruta)) throw new Rechazo(400, 'Esa no es una muestra de un estilo.');

  if (!(await preguntar(env, sesion, 'puedo_borrar_muestra', { p_ruta: ruta }))) {
    console.warn('[estilos] borrado rechazado por Postgres', ruta);
    throw new Rechazo(403, SIN_PERMISO);
  }

  await env.BUCKET.delete(ruta);
  console.log('[estilos] muestra borrada', ruta);
  return json({ ruta });
}
