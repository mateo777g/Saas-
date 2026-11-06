// Los números del eje derecho de las gráficas de Inicio: 0, un paso y dos pasos, con un tope redondo.
import type { Marca } from '../diseno/GraficaLinea.svelte';

// El tope es el primer número de esta lista que alcanza lo más alto; la rayita de en medio, su pareja.
const ESCALA: [number, number][] = [
  [1, 0.5], [1.2, 0.6], [1.4, 0.7], [1.6, 0.8], [2, 1], [2.4, 1.2], [3, 1.5], [3.2, 1.5],
  [4, 2], [5, 2.5], [6, 3], [8, 4], [10, 5],
];

export function escala(alto: number): { tope: number; paso: number } {
  if (alto <= 0) return { tope: 1, paso: 0.5 };
  const orden = 10 ** Math.floor(Math.log10(alto));
  const [t, p] = ESCALA.find(([t]) => t * orden >= alto) ?? [10, 5];
  return { tope: t * orden, paso: p * orden };
}

// Lo que se cuenta en enteros (piezas, altas, restaurantes): de 1 a 9, el par que alcanza, desde `minimo`.
export function ejeEntero(alto: number, minimo = 4): { tope: number; marcas: Marca[] } {
  let { tope, paso } = escala(alto);
  if (alto < 10) {
    tope = Math.max(minimo, Math.ceil(alto / 2) * 2);
    paso = tope / 2;
  }
  return { tope, marcas: [0, paso, paso * 2].map((valor) => ({ valor, texto: String(valor) })) };
}

// La rejilla sin números, mientras lee o si no pudo.
export const SIN_MARCAS: Marca[] = [
  { valor: 0, texto: '' },
  { valor: 0.5, texto: '' },
  { valor: 1, texto: '' },
];
