// Las ventanas del panel del gerente se mueven (9 nov 2026; maqueta 4NPDnXrWetC6yFYF7B1EXd, versión 2 «Suave», de la
// «Expandable Dialog» que mandó el developer): salen del centro, de 97 % a 100 % y de transparentes a sólidas en 0.35 s,
// y al cerrar hacen lo mismo al revés en 0.2 s; el velo de atrás aparece y se va en 0.2 s. Agrandar las hace 1.15 veces
// más anchas y más altas con el mismo resorte. Fragmentless y los distribuidores se quedan quietos: solo PanelGerente
// llama a ventanasQueSeMueven(), y Ventana y Confirmar preguntan con seMueven().
import { getContext, setContext } from 'svelte';
import { cubicOut } from 'svelte/easing';
import type { TransitionConfig } from 'svelte/transition';

const LLAVE = Symbol('ventanas-que-se-mueven');

export function ventanasQueSeMueven() {
  setContext(LLAVE, true);
}

export function seMueven(): boolean {
  return getContext<boolean | undefined>(LLAVE) === true;
}

export const ABRE = 350;
export const CIERRA = 200;
export const VELO = 200;
export const ESCALA = 0.97;
export const CRECE = 1.15;

// El resorte de la ventana del prompt (el de motion, rigidez 300, freno 30, masa 1: casi sin rebote, sube 0.4 %):
// sus 0.5 s de resorte apretados en lo que dure la animación.
function resorte(rigidez: number, freno: number, segundos: number) {
  const w0 = Math.sqrt(rigidez);
  const z = freno / (2 * w0);
  const wd = w0 * Math.sqrt(1 - z * z);
  return (u: number) => {
    if (u >= 1) return 1;
    const t = u * segundos;
    return 1 - Math.exp(-z * w0 * t) * (Math.cos(wd * t) + ((z * w0) / wd) * Math.sin(wd * t));
  };
}

export const RESORTE = resorte(300, 30, 0.5);

// El mismo resorte como curva de CSS, para lo que se anima con element.animate() (agrandar).
export const RESORTE_CSS = `linear(${Array.from({ length: 41 }, (_, i) => +RESORTE(i / 40).toFixed(4)).join(', ')})`;

export function quieto(): boolean {
  return matchMedia('(prefers-reduced-motion: reduce)').matches;
}

// La ventana: crece del centro y se aclara al abrir; al cerrar, al revés y más rápido.
export function ventanaSale(_nodo: Element, mueve: boolean, { direction }: { direction: 'in' | 'out' | 'both' }): TransitionConfig {
  if (!mueve || quieto()) return { duration: 0 };
  return {
    duration: direction === 'out' ? CIERRA : ABRE,
    easing: RESORTE,
    css: (t) => `opacity: ${Math.min(t, 1)}; transform: scale(${ESCALA + (1 - ESCALA) * t})`,
  };
}

// El velo oscuro de atrás: solo su color, para que la ventana no se aclare dos veces.
export function veloSale(_nodo: Element, mueve: boolean): TransitionConfig {
  if (!mueve || quieto()) return { duration: 0 };
  return {
    duration: VELO,
    easing: cubicOut,
    css: (t) => `background-color: color-mix(in srgb, var(--velo) ${(Math.min(t, 1) * 100).toFixed(1)}%, transparent)`,
  };
}
