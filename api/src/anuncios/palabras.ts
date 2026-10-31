// El paso de texto (worker-7b1.md, 22 a 25): las palabras que no escribe Don Chuy («PASTOR», «ESTO NO
// ES / UN TACO», las banderitas) las escoge gpt-5.6-luna antes de la imagen, con un esquema JSON por
// estilo. Solo recibe los nombres y las descripciones de los productos: ni precios ni datos del
// restaurante. Lo que regresa la IA y lo que manda la app (las de la IA o las que él cambió) se
// revisan con la misma pieza: sus lugares, nada vacío, dentro del tope y en mayúsculas donde van.
import { enMayusculas, lugaresDe } from './comun';
import type { Estilo, LugarListo } from './comun';

export type ProductoParaPalabras = { nombre: string; descripcion: string | null };

export const REGLAS_PALABRAS = [
  'Escoges las palabras de un anuncio de un restaurante mexicano: unas pocas palabras que van escritas en la imagen.',
  'Escribes en español de México, con sus acentos.',
  'Las sacas solo del nombre y la descripción de los productos que te dan: no inventes ingredientes, precios, promociones, premios ni frases de venta.',
  'Cada lugar dice cuántas letras caben como máximo (contando espacios) y si va en mayúsculas. Nunca te pases de ese tope.',
  'Contesta solo con el JSON que se te pide.',
].join('\n');

// Lo que se le pregunta: los productos en orden y cada lugar con su tope.
export function preguntaDePalabras(estilo: Estilo, productos: ProductoParaPalabras[]): string {
  const lista = productos.map((p, i) => `${i + 1}. «${p.nombre}»${p.descripcion ? `: ${p.descripcion}` : ''}`);
  const lugares = lugaresDe(estilo, productos.length).map((l) => {
    const deQuien = l.producto ? ` (del producto ${l.producto}, «${productos[l.producto - 1].nombre}»)` : '';
    const forma = l.forma ? ` Forma: ${l.forma.explica}` : '';
    return `- ${l.llave}${deQuien}: ${l.pide}${forma} Hasta ${l.tope} letras${l.mayusculas ? ', en MAYÚSCULAS' : ''}.`;
  });
  return `Los productos del anuncio, en orden:\n${lista.join('\n')}\n\nLos lugares:\n${lugares.join('\n')}`;
}

// El esquema que pide la Responses API: un texto por lugar, todos obligatorios.
export function esquemaDePalabras(estilo: Estilo, productos: number) {
  const lugares = lugaresDe(estilo, productos);
  return {
    type: 'json_schema',
    name: 'palabras_del_anuncio',
    strict: true,
    schema: {
      type: 'object',
      additionalProperties: false,
      required: lugares.map((l) => l.llave),
      properties: Object.fromEntries(
        lugares.map((l) => [l.llave, { type: 'string', description: `Hasta ${l.tope} letras${l.mayusculas ? ', en mayúsculas' : ''}.` }]),
      ),
    },
  } as const;
}

// Revisa unas palabras contra los lugares del estilo con tantos productos. Regresa las palabras
// limpias o, si algo no cabe, lo que está mal en palabras de Don Chuy.
export function revisarPalabras(
  estilo: Estilo,
  productos: number,
  palabras: unknown,
): { ok: true; palabras: Record<string, string> } | { ok: false; falta: string } {
  const lugares = lugaresDe(estilo, productos);
  if (!lugares.length) {
    if (palabras === undefined || palabras === null) return { ok: true, palabras: {} };
    if (typeof palabras === 'object' && !Array.isArray(palabras) && Object.keys(palabras).length === 0) return { ok: true, palabras: {} };
    return { ok: false, falta: 'Este estilo no lleva palabras.' };
  }
  if (!palabras || typeof palabras !== 'object' || Array.isArray(palabras)) return { ok: false, falta: 'Faltan las palabras del anuncio.' };
  const dadas = palabras as Record<string, unknown>;
  const llaves = new Set(lugares.map((l) => l.llave));
  if (Object.keys(dadas).some((llave) => !llaves.has(llave))) return { ok: false, falta: 'Esas palabras no van en este estilo.' };

  const limpias: Record<string, string> = {};
  for (const lugar of lugares) {
    const valor = dadas[lugar.llave];
    const texto = typeof valor === 'string' ? valor.trim().replace(/\s+/g, ' ') : '';
    const falta = faltaEn(lugar, texto);
    if (falta) return { ok: false, falta };
    limpias[lugar.llave] = texto;
  }
  return { ok: true, palabras: limpias };
}

function faltaEn(lugar: LugarListo, texto: string): string | null {
  const nombre = lugar.producto ? `${lugar.nombre} ${lugar.producto}` : lugar.nombre;
  if (!texto) return `Falta ${minuscula(nombre)}.`;
  if ([...texto].length > lugar.tope) return `${nombre} puede tener hasta ${lugar.tope} letras.`;
  if (lugar.mayusculas && !enMayusculas(texto)) return `${nombre} va en mayúsculas.`;
  if (lugar.forma && !lugar.forma.regla.test(texto)) return `${nombre} ${lugar.forma.explica}`;
  return null;
}

function minuscula(texto: string): string {
  return texto.charAt(0).toLowerCase() + texto.slice(1);
}
