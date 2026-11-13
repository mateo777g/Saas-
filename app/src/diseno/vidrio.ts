// El vidrio del estilo Cristal se mueve como el Liquid Glass de iOS («Meet Liquid Glass», WWDC25; libreta 4, «El estilo
// Cristal»; maqueta FiHkjmT1meyTu7zuU3En2n, su sección 7): la luz sigue al mouse (un brillo suave por dentro y, en el
// canto, la línea de luz que se junta de ese lado), prende y se apaga despacio, y al picar se ilumina donde picaste. El
// contenido no brilla. Su CSS (cómo se ve cada tipo de vidrio) vive en cristal.css; en Simple nada de esto corre.
//
//   use:vidrio={'boton'}        la pieza es vidrio de ese tipo (menu, boton, control, busqueda, hoja, ventana); null = no es
//   use:pica={1.08}             al picarla crece con resorte a esa escala y regresa al soltar
//
// Un solo escucha para toda la página (no uno por pieza): busca el vidrio bajo el mouse con closest('[data-vidrio]') y
// le mueve sus variables cuadro por cuadro.
import { getContext, setContext } from 'svelte';

export type TipoVidrio = 'menu' | 'boton' | 'control' | 'busqueda' | 'hoja' | 'ventana';

type Luz = { x: number; y: number; a: number; r: number; metaA: number; metaR: number };

const luces = new Map<HTMLElement, Luz>();
let corriendo = false;
let instalado = false;
let picado: HTMLElement | null = null;

const enCristal = () => document.documentElement.dataset.estilo === 'cristal';
const quieto = () => window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ?? false;

// La pieza puede estar escalada (una ventana que sale de 97 %, «Agrandar»): la luz se mide en sus pixeles.
function escalaDe(el: HTMLElement) {
  const r = el.getBoundingClientRect();
  return r.width / el.offsetWidth || 1;
}

function radio(el: HTMLElement) {
  return Math.max(60, Math.min(220, Math.min(el.offsetWidth, el.offsetHeight) * 1.8));
}

function mover() {
  corriendo = false;
  const k = quieto() ? 1 : 0.16;
  luces.forEach((l, el) => {
    l.a += (l.metaA - l.a) * k;
    l.r += (l.metaR - l.r) * k;
    if (Math.abs(l.metaA - l.a) > 0.005 || Math.abs(l.metaR - l.r) > 0.5) corriendo = true;
    else {
      l.a = l.metaA;
      l.r = l.metaR;
    }
    el.style.setProperty('--luz-x', `${l.x.toFixed(1)}px`);
    el.style.setProperty('--luz-y', `${l.y.toFixed(1)}px`);
    el.style.setProperty('--luz-a', l.a.toFixed(3));
    el.style.setProperty('--luz-r', `${l.r.toFixed(1)}px`);
  });
  if (corriendo) requestAnimationFrame(mover);
}

function arrancar() {
  if (corriendo) return;
  corriendo = true;
  requestAnimationFrame(mover);
}

function apagarTodo(menos: HTMLElement | null) {
  luces.forEach((l, el) => {
    if (el === menos) return;
    l.metaA = 0;
    l.metaR = radio(el) * 0.6;
  });
  arrancar();
}

function vidrioBajo(e: PointerEvent): HTMLElement | null {
  const el = (e.target as Element | null)?.closest?.('[data-vidrio]');
  return el instanceof HTMLElement && luces.has(el) ? el : null;
}

function apuntar(el: HTMLElement, e: PointerEvent, fuerza: number) {
  const r = el.getBoundingClientRect();
  const s = escalaDe(el);
  const l = luces.get(el)!;
  l.x = (e.clientX - r.left) / s;
  l.y = (e.clientY - r.top) / s;
  l.metaA = fuerza;
  l.metaR = radio(el) * (fuerza > 1 ? 1.4 : 1);
  arrancar();
}

function soltar(e: PointerEvent | null) {
  if (!picado) return;
  delete picado.dataset.picado;
  picado = null;
  const vidrio = e && vidrioBajo(e);
  if (vidrio) apuntar(vidrio, e, 1);
}

// Al pasar de Cristal a Simple, la luz se borra de una vez (en Simple las variables no se usan, pero no se quedan).
function apagarDeGolpe() {
  luces.forEach((l, el) => {
    l.a = l.metaA = l.r = l.metaR = 0;
    for (const v of ['--luz-x', '--luz-y', '--luz-a', '--luz-r']) el.style.removeProperty(v);
  });
}

function instalar() {
  if (instalado) return;
  instalado = true;
  document.addEventListener(
    'pointermove',
    (e) => {
      if (!enCristal() || e.pointerType !== 'mouse') return;
      const el = vidrioBajo(e);
      apagarTodo(el);
      if (el) apuntar(el, e, picado ? 1.8 : 1);
    },
    { passive: true },
  );
  document.addEventListener(
    'pointerdown',
    (e) => {
      if (!enCristal()) return;
      const pica = (e.target as Element | null)?.closest?.('[data-pica]');
      if (pica instanceof HTMLElement) {
        picado = pica;
        pica.dataset.picado = '';
      }
      const vidrio = vidrioBajo(e);
      if (vidrio) apuntar(vidrio, e, 1.8);
    },
    { passive: true },
  );
  document.addEventListener('pointerup', soltar, { passive: true });
  document.addEventListener('pointercancel', soltar, { passive: true });
  document.documentElement.addEventListener('pointerleave', () => {
    soltar(null);
    apagarTodo(null);
  });
  new MutationObserver(() => {
    if (!enCristal()) apagarDeGolpe();
  }).observe(document.documentElement, { attributes: true, attributeFilter: ['data-estilo'] });
}

export function vidrio(el: HTMLElement, tipo: TipoVidrio | null) {
  function poner(t: TipoVidrio | null) {
    if (t) {
      el.dataset.vidrio = t;
      if (!luces.has(el)) luces.set(el, { x: 0, y: 0, a: 0, r: 0, metaA: 0, metaR: 0 });
      instalar();
    } else {
      delete el.dataset.vidrio;
      luces.delete(el);
    }
  }
  poner(tipo);
  return {
    update: poner,
    destroy() {
      luces.delete(el);
    },
  };
}

export function pica(el: HTMLElement, escala: number | null) {
  function poner(s: number | null) {
    if (s) {
      el.dataset.pica = '';
      el.style.setProperty('--pica', String(s));
      instalar();
    } else {
      delete el.dataset.pica;
      el.style.removeProperty('--pica');
    }
  }
  poner(escala);
  return {
    update: poner,
    destroy() {
      if (picado === el) picado = null;
    },
  };
}

// Dentro de la barra de arriba, lo que se pica es vidrio (los botones de solo ícono, la sucursal, «Ocultar varios»);
// en una fila de tabla o dentro de una ventana, el mismo botón no lo es. La barra lo dice a sus piezas con un contexto.
const EN_BARRA = Symbol('vidrio-en-barra');

export function ponerEnBarra() {
  setContext(EN_BARRA, true);
}

// Una ventana o una hoja que se abre desde la barra ya no es la barra: lo de adentro nunca es vidrio sobre vidrio.
export function quitarDeBarra() {
  setContext(EN_BARRA, false);
}

export function enBarra(): boolean {
  return getContext<boolean | undefined>(EN_BARRA) === true;
}
