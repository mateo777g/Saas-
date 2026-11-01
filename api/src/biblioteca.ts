// Mi biblioteca (libreta 7, parte 7b-2; sus decisiones en planes/trabajo/7b/worker-7b2.md). Dos
// trabajos que borran un anuncio, siempre primero su JPG de R2 y luego su renglón, así nunca queda
// un archivo sin su renglón:
//  - DELETE /anuncios?id=<id>, con la sesión de Don Chuy: Postgres dice si lo puede borrar y cuál es
//    su archivo (puedo_borrar_anuncio); el renglón lo borra el Worker con la llave secreta
//    (borrar_anuncio). Contesta {ok: true}, también si ya no estaba.
//  - El borrado de los 30 días, el Cron Trigger diario de las 9:00 UTC (wrangler.jsonc): los
//    vencidos de todos los restaurantes (anuncios_vencidos), sus archivos en una sola llamada a R2 y
//    luego sus renglones (borrar_vencidos). Lo que falle queda en el registro y se reintenta al otro
//    día: borrar dos veces da lo mismo.
import type { Env } from './index';
import { json, Rechazo } from './respuestas';
import { leerSesion, llamar } from './supabase';

const ETIQUETA = '[biblioteca]';
const NO_SE_BORRO = 'No pudimos borrar tu anuncio. Inténtalo otra vez.';
// La forma de los anuncios (hacerAnuncio.ts): antes de borrar en R2 se revisa la ruta que da Postgres.
const RUTA = /^restaurantes\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\/biblioteca\/[0-9a-f]{32}\.jpg$/;
// Los que regresa anuncios_vencidos, como mucho; el resto se va al otro día.
const TANDA = 1000;

// ─── DELETE /anuncios ─────────────────────────────────────────────────────────

export async function borrarAnuncio(request: Request, env: Env, url: URL): Promise<Response> {
  const sesion = leerSesion(request);
  const id = Number(url.searchParams.get('id'));
  if (!Number.isSafeInteger(id) || id <= 0) throw new Rechazo(400, 'Falta el anuncio.');

  // null: la socia ya lo borró, el trabajo diario se lo llevó o no es suyo. La app lo quita.
  const ruta = await llamar<string | null>(env, { sesion }, 'puedo_borrar_anuncio', { p_anuncio_id: id });
  if (ruta === null) return json({ ok: true });
  if (!RUTA.test(ruta)) {
    console.error(ETIQUETA, 'la ruta de un anuncio no tiene la forma de los anuncios: no se borró', id, ruta);
    throw new Rechazo(500, NO_SE_BORRO);
  }

  try {
    await env.BUCKET.delete(ruta);
  } catch (e) {
    console.error(ETIQUETA, 'R2 no borró el anuncio: el renglón se queda', id, ruta, e);
    throw new Rechazo(502, NO_SE_BORRO);
  }
  let borrado: boolean;
  try {
    borrado = await llamar<boolean>(env, 'worker', 'borrar_anuncio', { p_anuncio_id: id, p_ruta: ruta });
  } catch (e) {
    console.error(ETIQUETA, 'R2 ya lo borró pero el renglón no: se termina al intentarlo otra vez', id, e);
    throw new Rechazo(502, NO_SE_BORRO);
  }
  console.log(ETIQUETA, borrado ? 'borrado' : 'ya no estaba al borrar el renglón', id);
  return json({ ok: true });
}

// ─── El borrado de los 30 días ────────────────────────────────────────────────

type Vencido = { id: number; ruta: string | null };

export async function borrarVencidos(env: Env): Promise<void> {
  let vencidos: Vencido[];
  try {
    vencidos = await llamar<Vencido[]>(env, 'worker', 'anuncios_vencidos', {});
  } catch (e) {
    console.error(ETIQUETA, 'no se pudieron pedir los vencidos: se reintenta mañana', e);
    throw e;
  }
  if (!vencidos.length) {
    console.log(ETIQUETA, 'el borrado de los 30 días: no hay vencidos');
    return;
  }

  // Una ruta sin la forma de los anuncios no se borra, ni su renglón: se queda para que alguien la vea.
  const raros = vencidos.filter((v) => v.ruta !== null && !RUTA.test(v.ruta));
  for (const v of raros) console.error(ETIQUETA, 'un vencido con una ruta que no es de anuncio: no se borró', v.id, v.ruta);
  const aBorrar = vencidos.filter((v) => !raros.includes(v));
  const rutas = aBorrar.flatMap((v) => (v.ruta === null ? [] : [v.ruta]));

  if (rutas.length) {
    try {
      await env.BUCKET.delete(rutas);
    } catch (e) {
      console.error(ETIQUETA, 'R2 no borró los vencidos: ningún renglón se borró, se reintenta mañana', rutas.length, e);
      throw e;
    }
  }
  let borrados = 0;
  if (aBorrar.length) {
    try {
      borrados = await llamar<number>(env, 'worker', 'borrar_vencidos', { p_ids: aBorrar.map((v) => v.id) });
    } catch (e) {
      console.error(ETIQUETA, 'R2 ya borró los vencidos pero sus renglones no: se terminan mañana', aBorrar.length, e);
      throw e;
    }
  }
  console.log(ETIQUETA, 'el borrado de los 30 días:', `${vencidos.length} vencidos, ${rutas.length} archivos y ${borrados} renglones borrados`);
  if (vencidos.length >= TANDA) console.warn(ETIQUETA, `llegaron ${TANDA}: el resto se va mañana`);
}
