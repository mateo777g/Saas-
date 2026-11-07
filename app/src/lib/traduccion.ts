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

export function traductor(restauranteId: string, alEscribir: () => void): Traductor {
  let vivo = true;
  let corriendo = false;
  let otraVez = false;

  async function correr() {
    if (!vivo) return;
    // Si ya está traduciendo, da otra vuelta al terminar: lo recién guardado pudo quedar fuera.
    if (corriendo) {
      otraVez = true;
      return;
    }
    corriendo = true;
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
