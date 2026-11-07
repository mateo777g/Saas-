// La cajita de los botones (regla de diseño del 7 de noviembre de 2026, reglas-diseno.md, «Las cajitas
// de los botones»; maqueta de Mi menú U9YqpsSb2PeB5pFXTPvh1C, versión 23). Ningún botón usa el `title`
// del navegador: los de solo ícono y la barra lateral llevan esta, la misma del dock. Hay una sola para
// toda la app, colgada de <body> (su estilo, .pista-flotante, vive en base.css).
//
// Sale tras medio segundo con el mouse encima; si ya hay una abierta, o se acaba de cerrar, la de al
// lado sale al instante. Con el teclado sale en cuanto llegas. Se va al picarle, al salirte, al mover la
// página o con Escape. Sin mouse (celular) no sale. Abajo del botón, centrada y a 8 px; si no cabe,
// arriba, y nunca se sale por los lados. Con `lado: 'derecha'` (la barra lateral plegada) va a su
// derecha, centrada. Un texto vacío no pone nada: así la barra lateral abierta no la lleva.
import type { Action } from 'svelte/action';

export type Pista = string | null | undefined | { texto: string | null | undefined; lado?: 'abajo' | 'derecha' };

const ESPERA = 500;
const AL_INSTANTE = 300;
const SEPARACION = 8;
const ORILLA = 8;

let caja: HTMLDivElement | null = null;
let de: HTMLElement | null = null;
let espera: ReturnType<typeof setTimeout> | undefined;
let cerradaEn = -Infinity;
const datos = new WeakMap<HTMLElement, { texto: string; lado: 'abajo' | 'derecha' }>();
let escuchando = false;

function laCaja(): HTMLDivElement {
  if (caja?.isConnected) return caja;
  caja = document.createElement('div');
  caja.className = 'pista-flotante';
  caja.setAttribute('aria-hidden', 'true');
  document.body.append(caja);
  return caja;
}

function poner(el: HTMLElement) {
  const d = datos.get(el);
  if (!d || !el.isConnected) return;
  const c = laCaja();
  // Una ventana abierta (<dialog>) va encima de todo lo de <body>: ahí adentro va la cajita de sus botones.
  const padre = el.closest('dialog[open]') ?? document.body;
  if (c.parentElement !== padre) padre.append(c);
  c.textContent = d.texto;
  const r = el.getBoundingClientRect();
  const t = c.getBoundingClientRect();
  const ancho = document.documentElement.clientWidth;
  const alto = document.documentElement.clientHeight;
  let x: number;
  let y: number;
  if (d.lado === 'derecha') {
    x = r.right + SEPARACION;
    y = r.top + r.height / 2 - t.height / 2;
  } else {
    x = Math.min(Math.max(ORILLA, r.left + r.width / 2 - t.width / 2), ancho - ORILLA - t.width);
    y = r.bottom + SEPARACION;
    if (y + t.height > alto - ORILLA) y = r.top - SEPARACION - t.height;
  }
  c.style.left = `${x}px`;
  c.style.top = `${y}px`;
  c.classList.add('visible');
}

function mostrar(el: HTMLElement, ya = false) {
  clearTimeout(espera);
  de = el;
  if (ya || caja?.classList.contains('visible') || performance.now() - cerradaEn < AL_INSTANTE) poner(el);
  else espera = setTimeout(() => de === el && poner(el), ESPERA);
}

export function esconderPista() {
  clearTimeout(espera);
  if (caja?.classList.contains('visible')) cerradaEn = performance.now();
  caja?.classList.remove('visible');
  de = null;
}

// Al picar se va sin contar como «recién cerrada»: el siguiente botón espera su medio segundo.
function alPicar() {
  clearTimeout(espera);
  caja?.classList.remove('visible');
  de = null;
}

function escucharUnaVez() {
  if (escuchando) return;
  escuchando = true;
  document.addEventListener('pointerdown', alPicar, true);
  document.addEventListener('keydown', (e) => e.key === 'Escape' && esconderPista());
  addEventListener('scroll', esconderPista, true);
}

function leer(valor: Pista): { texto: string; lado: 'abajo' | 'derecha' } | null {
  const texto = typeof valor === 'object' && valor ? valor.texto : valor;
  if (!texto) return null;
  return { texto, lado: typeof valor === 'object' && valor?.lado ? valor.lado : 'abajo' };
}

export const pista: Action<HTMLElement, Pista> = (el, valor) => {
  escucharUnaVez();
  const guardar = (v: Pista) => {
    const d = leer(v);
    if (d) datos.set(el, d);
    else datos.delete(el);
    if (de === el) {
      if (d) poner(el);
      else esconderPista();
    }
  };
  guardar(valor);

  const entra = (e: PointerEvent) => {
    if (e.pointerType !== 'mouse' || !datos.has(el) || de === el) return;
    mostrar(el);
  };
  const sale = (e: PointerEvent) => {
    if (de !== el) return;
    const destino = e.relatedTarget as Node | null;
    if (destino && el.contains(destino)) return;
    esconderPista();
  };
  const foco = () => {
    if (datos.has(el) && el.matches(':focus-visible')) mostrar(el, true);
  };
  const sinFoco = () => de === el && esconderPista();
  el.addEventListener('pointerenter', entra);
  el.addEventListener('pointerleave', sale);
  el.addEventListener('focus', foco);
  el.addEventListener('blur', sinFoco);
  return {
    update: guardar,
    destroy() {
      el.removeEventListener('pointerenter', entra);
      el.removeEventListener('pointerleave', sale);
      el.removeEventListener('focus', foco);
      el.removeEventListener('blur', sinFoco);
      datos.delete(el);
      if (de === el) esconderPista();
    },
  };
};
