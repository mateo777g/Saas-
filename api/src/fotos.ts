// Las fotos del menú en R2 (libreta 3, «Las fotos en R2»). Dos trabajos:
//  - POST /menu/foto?restaurante=<id>, con la foto WebP como cuerpo: si Postgres dice que quien
//    llama puede subir fotos a ese restaurante, la guarda con un nombre al azar y contesta su ruta.
//  - DELETE /menu/foto?ruta=<ruta>: si Postgres dice que puede borrarla (es de su menú y ningún
//    producto la usa), la borra.
// La app guarda la ruta en productos.imagen_ruta; el nombre lo pone siempre el Worker.
import type { Env } from './index';
import { json, Rechazo, SIN_PERMISO } from './respuestas';
import { leerSesion, preguntar } from './supabase';

// El navegador ya la manda en WebP de 1600 px (unos 200 KB); 2 MB deja de sobra.
const MAXIMO_BYTES = 2 * 1024 * 1024;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
// El mismo formato que exige la base (productos_imagen_ruta_formato y puedo_borrar_foto).
const RUTA = /^restaurantes\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\/menu\/[0-9a-f]{32}\.webp$/;

export async function fotoDelMenu(request: Request, env: Env, url: URL): Promise<Response> {
  if (request.method === 'POST') return subir(request, env, url);
  if (request.method === 'DELETE') return borrar(request, env, url);
  throw new Rechazo(405, 'Las fotos solo se suben o se borran.');
}

async function subir(request: Request, env: Env, url: URL): Promise<Response> {
  const sesion = leerSesion(request);
  const restaurante = url.searchParams.get('restaurante') ?? '';
  if (!UUID.test(restaurante)) throw new Rechazo(400, 'Falta el restaurante.');

  // Antes de leer la foto: el tamaño que dice el navegador.
  const largo = Number(request.headers.get('Content-Length'));
  if (!Number.isFinite(largo) || largo <= 0) throw new Rechazo(411, 'Falta la foto.');
  if (largo > MAXIMO_BYTES) throw new Rechazo(413, 'La foto pesa más de 2 MB.');

  if (!(await preguntar(env, sesion, 'puedo_subir_foto', { p_restaurante_id: restaurante }))) {
    console.warn('[fotos] subida rechazada por Postgres', restaurante);
    throw new Rechazo(403, SIN_PERMISO);
  }

  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.byteLength > MAXIMO_BYTES) throw new Rechazo(413, 'La foto pesa más de 2 MB.');
  if (!esWebp(bytes)) throw new Rechazo(415, 'La foto tiene que ser WebP.');

  const ruta = `restaurantes/${restaurante}/menu/${nombreAlAzar()}.webp`;
  await env.BUCKET.put(ruta, bytes, {
    // El nombre nunca se repite, así que el archivo nunca cambia: se puede guardar en caché un año.
    httpMetadata: { contentType: 'image/webp', cacheControl: 'public, max-age=31536000, immutable' },
  });
  console.log('[fotos] subida', ruta, bytes.byteLength);
  return json({ ruta }, 201);
}

async function borrar(request: Request, env: Env, url: URL): Promise<Response> {
  const sesion = leerSesion(request);
  const ruta = url.searchParams.get('ruta') ?? '';
  if (!RUTA.test(ruta)) throw new Rechazo(400, 'Esa no es una foto del menú.');

  if (!(await preguntar(env, sesion, 'puedo_borrar_foto', { p_ruta: ruta }))) {
    console.warn('[fotos] borrado rechazado por Postgres', ruta);
    throw new Rechazo(403, SIN_PERMISO);
  }

  await env.BUCKET.delete(ruta);
  console.log('[fotos] borrada', ruta);
  return json({ ruta });
}

// Un archivo WebP empieza con «RIFF», su tamaño menos 8 (4 bytes, al revés) y «WEBP».
function esWebp(bytes: Uint8Array): boolean {
  if (bytes.byteLength < 16) return false;
  const texto = (desde: number) => String.fromCharCode(...bytes.subarray(desde, desde + 4));
  const tamano = new DataView(bytes.buffer, bytes.byteOffset).getUint32(4, true);
  return texto(0) === 'RIFF' && texto(8) === 'WEBP' && tamano + 8 === bytes.byteLength;
}

// 32 caracteres hexadecimales al azar: imposible de adivinar, así nadie pisa la foto de otro.
function nombreAlAzar(): string {
  const azar = crypto.getRandomValues(new Uint8Array(16));
  return Array.from(azar, (b) => b.toString(16).padStart(2, '0')).join('');
}
