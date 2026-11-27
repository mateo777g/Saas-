// El inglés de Mi menú, que traduce la IA sola (decidido el 6 de noviembre de 2026;
// planes/trabajo/rediseno/mi-menu.md). Don Chuy escribe en español y no hace nada más: al abrir Mi menú y
// después de guardar un producto, una categoría o un grupo, la app le pide al Worker POST /menu/traducir,
// sin esperarlo. Cada vuelta traduce hasta 20 renglones y contesta cuántos quedan; se vuelve a pedir
// mientras queden y bajen. Se para si ya no avanza, si no hay saldo en el sobre del asistente
// (`puede: false`, con tope 0 por ejemplo) o si falla, y eso se anota. Si escribió algo, la vista vuelve a
// leer el menú. Al salir de la vista se detiene: lo que falte se traduce la próxima vez que se abra.
// En el panel no sale nada mientras traduce.
import { llamarWorker } from './worker';

export type Traductor = { correr: () => void; parar: () => void };

// Una sola traducción a la vez por restaurante, aunque la pidan dos vistas (la ventana de revisión del
// menú con IA al subir y Mi menú al abrirse con «Ver Mi menú»): la que llega después espera a la que va
// y luego pide lo que falte; si ya no falta nada, el Worker no llama a OpenAI. Sin esto las dos traducían
// los mismos renglones a la vez y se pagaba una vuelta de más (la prueba del 27 nov 2026). Cada una
// resuelve si escribió algo, también lo de la anterior, para que la vista que esperó vuelva a leer.
const enCurso = new Map<string, Promise<boolean>>();

export function traductor(restauranteId: string, alEscribir: () => void): Traductor {
  let vivo = true;
  let corriendo = false;
  let otraVez = false;

  async function vueltas(): Promise<boolean> {
    let escribio = false;
    let antes = Infinity;
    try {
      while (vivo) {
        const r = await llamarWorker('traducir', 'POST', '/menu/traducir', { restaurante: restauranteId });
        const quedan = typeof r?.quedan === 'number' ? r.quedan : 0;
        const escritas = typeof r?.escritas === 'number' ? r.escritas : 0;
        if (escritas > 0) escribio = true;
        if (r?.puede === false || quedan <= 0) break;
        if (escritas === 0 || quedan >= antes) {
          console.warn('[traducir] la traducción ya no avanza; quedan', quedan, 'renglones');
          break;
        }
        antes = quedan;
      }
    } catch (falla) {
      console.error('[traducir] no se pudo traducir el menú:', falla);
    }
    return escribio;
  }

  async function correr() {
    if (!vivo) return;
    // Si ya está traduciendo, da otra vuelta al terminar: lo recién guardado pudo quedar fuera.
    if (corriendo) {
      otraVez = true;
      return;
    }
    corriendo = true;
    const anterior = enCurso.get(restauranteId) ?? Promise.resolve(false);
    const esta = anterior.then(async (laAnteriorEscribio) => (await vueltas()) || laAnteriorEscribio);
    enCurso.set(restauranteId, esta);
    const escribio = await esta;
    if (enCurso.get(restauranteId) === esta) enCurso.delete(restauranteId);
    corriendo = false;
    if (escribio && vivo) alEscribir();
    if (otraVez && vivo) {
      otraVez = false;
      void correr();
    }
  }

  return {
    correr: () => void correr(),
    parar: () => {
      vivo = false;
    },
  };
}
