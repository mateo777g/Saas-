// El movimiento de lo que se abre en el menú («Tu menú en línea», maqueta UDArhiEZceT7rmSKxqRA5r), como
// transiciones de Svelte: las hojas y Ajustes entran con cubic-bezier(0.32, 0.72, 0, 1) en 380 ms y salen
// con cubic-bezier(0.4, 0, 1, 1) en 240 ms; su velo aparece en 220 ms y se va en 200 ms. Con «reducir
// movimiento», nada se mueve.

// Una curva cubic-bezier como función de 0 a 1 (la misma cuenta que hace el navegador).
export function bezier(x1: number, y1: number, x2: number, y2: number): (t: number) => number {
  const cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx;
  const cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
  const x = (s: number) => ((ax * s + bx) * s + cx) * s;
  const dx = (s: number) => (3 * ax * s + 2 * bx) * s + cx;
  return (t: number) => {
    let s = t;
    for (let i = 0; i < 8; i++) {
      const d = dx(s);
      if (Math.abs(d) < 1e-6) break;
      s -= (x(s) - t) / d;
    }
    s = Math.min(1, Math.max(0, s));
    return ((ay * s + by) * s + cy) * s;
  };
}

const ENTRA = bezier(0.32, 0.72, 0, 1);
const SALE = bezier(0.4, 0, 1, 1);

export const quieto = () => matchMedia('(prefers-reduced-motion: reduce)').matches;

type Lado = 'derecha' | 'abajo';

// La hoja o el panel que entra de un lado; `intro` es si entra (true) o sale.
export function desliza(_el: Element, { lado, intro }: { lado: Lado; intro: boolean }) {
  if (quieto()) return { duration: 0 };
  const eje = lado === 'derecha' ? 'X' : 'Y';
  // Svelte corre la de salida de 1 a 0: la curva se voltea para que salga con la suya.
  return intro
    ? { duration: 380, easing: ENTRA, css: (t: number) => `transform: translate${eje}(${(1 - t) * 100}%)` }
    : { duration: 240, easing: (t: number) => 1 - SALE(1 - t), css: (t: number) => `transform: translate${eje}(${(1 - t) * 100}%)` };
}

export function velo(_el: Element, { intro }: { intro: boolean }) {
  if (quieto()) return { duration: 0 };
  return { duration: intro ? 220 : 200, css: (t: number) => `opacity: ${t}` };
}
