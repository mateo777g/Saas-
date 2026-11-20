// Las fotos sueltas del recetario (19 nov 2026; planes/trabajo/recetario/, migración 20261119220000_recetario). Las
// fotos del recetario se suben con POST /menu/foto?carpeta=recetario (fotos.ts) y se guardan con guardar_recetario; la
// que se quita o se cambia, o las de un platillo o una preparación que se borra, las anota un disparador en
// fotos_por_borrar. Este trabajo, en el Cron Trigger diario de las 9:00 UTC (wrangler.jsonc), las borra como el de los
// anuncios vencidos (biblioteca.ts): las sueltas de todos los restaurantes (fotos_sueltas, hasta 1,000, las más viejas
// primero), sus archivos en una sola llamada a R2 y luego sus renglones de la fila (borrar_fotos_sueltas, que deja las
// que alguien volvió a usar). Lo que falle queda en el registro y se reintenta al otro día: borrar dos veces da lo mismo.
import type { Env } from './index';
import { llamar } from './supabase';

const ETIQUETA = '[recetario]';
// La forma de las fotos del recetario (la misma que exigen sus tablas): antes de borrar en R2 se revisa la ruta.
const RUTA = /^restaurantes\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\/recetario\/[0-9a-f]{32}\.webp$/;
// Las que regresa fotos_sueltas, como mucho; el resto se va al otro día.
const TANDA = 1000;

type Suelta = { id: number; ruta: string };

export async function borrarFotosSueltas(env: Env): Promise<void> {
  let sueltas: Suelta[];
  try {
    sueltas = await llamar<Suelta[]>(env, 'worker', 'fotos_sueltas', {});
  } catch (e) {
    console.error(ETIQUETA, 'no se pudieron pedir las fotos sueltas: se reintenta mañana', e);
    throw e;
  }
  if (!sueltas.length) {
    console.log(ETIQUETA, 'las fotos sueltas: no hay');
    return;
  }

  // Una ruta sin la forma del recetario no se borra, ni su renglón: se queda para que alguien la vea.
  const raras = sueltas.filter((s) => !RUTA.test(s.ruta));
  for (const s of raras) console.error(ETIQUETA, 'una foto suelta con una ruta que no es del recetario: no se borró', s.id, s.ruta);
  const aBorrar = sueltas.filter((s) => !raras.includes(s));
  if (!aBorrar.length) return;

  try {
    await env.BUCKET.delete(aBorrar.map((s) => s.ruta));
  } catch (e) {
    console.error(ETIQUETA, 'R2 no borró las fotos sueltas: ningún renglón se sacó, se reintenta mañana', aBorrar.length, e);
    throw e;
  }
  let sacadas: number;
  try {
    sacadas = await llamar<number>(env, 'worker', 'borrar_fotos_sueltas', { p_ids: aBorrar.map((s) => s.id) });
  } catch (e) {
    console.error(ETIQUETA, 'R2 ya borró las fotos sueltas pero sus renglones no: se terminan mañana', aBorrar.length, e);
    throw e;
  }
  console.log(ETIQUETA, 'las fotos sueltas:', `${sueltas.length} sueltas, ${aBorrar.length} archivos borrados y ${sacadas} renglones sacados`);
  if (sacadas < aBorrar.length) {
    // Alguien volvió a usar una foto entre la lista y el borrado: su archivo ya no está. Se avisa para verlo.
    console.warn(ETIQUETA, `${aBorrar.length - sacadas} se volvieron a usar después de pedir la lista: su archivo ya se borró`);
  }
  if (sueltas.length >= TANDA) console.warn(ETIQUETA, `llegaron ${TANDA}: el resto se va mañana`);
}
