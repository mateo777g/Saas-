// Los textos fijos del menú en sus dos idiomas (libreta 6: los traduce Fragmentless una vez; lo que
// escribe Don Chuy lleva su propio inglés, y lo que no lo tiene sale en español). Los de la maqueta
// de la 6a (Qx4C5CbKJYpeAsJCfw4ghn), sección 1.
import type { Estado } from './datos';

export type Lengua = 'es' | 'en';

export const TEXTOS = {
  es: {
    buscar: 'Buscar en el menú',
    limpiar: 'Borrar la búsqueda',
    ordenar: 'Ordenar por',
    ordenes: ['Recomendado', 'Precio: menor a mayor', 'Precio: mayor a menor', 'Nombre: A a Z'],
    desde: 'Desde',
    aprox: 'aprox.',
    incluido: 'Incluido',
    resultado: 'resultado',
    resultados: 'resultados',
    nada: (q: string) => `No encontramos «${q}»`,
    nadaTexto: 'Prueba con otra palabra, como el nombre de un platillo o de una bebida.',
    info: 'Información del restaurante',
    direccion: 'Dirección',
    whatsapp: 'WhatsApp',
    escribir: 'Escribir por WhatsApp',
    horario: 'Horario',
    hoy: 'hoy',
    cerrado: 'Cerrado',
    a: 'a',
    dias: ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'],
    cerrar: 'Cerrar',
    verFoto: 'Ver la foto',
    idioma: 'Idioma',
    moneda: 'Moneda',
    categorias: 'Categorías',
    cartel: (n: number, de: number) => `Cartel ${n} de ${de}`,
    apagado: 'Este menú no está disponible',
    apagadoTexto: 'Revisa el link o pregúntale al restaurante.',
    sinRed: 'No se pudo abrir el menú',
    sinRedTexto: 'Revisa tu internet e inténtalo otra vez.',
    reintentar: 'Intentar otra vez',
  },
  en: {
    buscar: 'Search the menu',
    limpiar: 'Clear the search',
    ordenar: 'Sort by',
    ordenes: ['Recommended', 'Price: low to high', 'Price: high to low', 'Name: A to Z'],
    desde: 'From',
    aprox: 'approx.',
    incluido: 'Included',
    resultado: 'result',
    resultados: 'results',
    nada: (q: string) => `No results for «${q}»`,
    nadaTexto: 'Try another word, like the name of a dish or a drink.',
    info: 'About the restaurant',
    direccion: 'Address',
    whatsapp: 'WhatsApp',
    escribir: 'Message on WhatsApp',
    horario: 'Hours',
    hoy: 'today',
    cerrado: 'Closed',
    a: 'to',
    dias: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'],
    cerrar: 'Close',
    verFoto: 'See the photo',
    idioma: 'Language',
    moneda: 'Currency',
    categorias: 'Categories',
    cartel: (n: number, de: number) => `Banner ${n} of ${de}`,
    apagado: 'This menu is not available',
    apagadoTexto: 'Check the link or ask the restaurant.',
    sinRed: "We couldn't open the menu",
    sinRedTexto: 'Check your internet connection and try again.',
    reintentar: 'Try again',
  },
} as const;

export type Textos = (typeof TEXTOS)[Lengua];

// «Abierto · cierra a las 18:00», «Cerrado · abre mañana a las 9:00». Sin horario, nada. En
// español es «a la 1:00», no «a las 1:00».
export function textoEstado(estado: Estado, lengua: Lengua): string | null {
  if (!estado) return null;
  const alas = (hora: string) => (/^1:/.test(hora) ? `a la ${hora}` : `a las ${hora}`);
  if (lengua === 'en') {
    if (estado.abierto) return `Open · closes at ${estado.cierra}`;
    const { dia, hora, en_dias } = estado.abre;
    const cuando = en_dias === 0 ? 'today' : en_dias === 1 ? 'tomorrow' : TEXTOS.en.dias[dia - 1];
    return `Closed · opens ${cuando} at ${hora}`;
  }
  if (estado.abierto) return `Abierto · cierra ${alas(estado.cierra)}`;
  const { dia, hora, en_dias } = estado.abre;
  const cuando = en_dias === 0 ? 'hoy' : en_dias === 1 ? 'mañana' : `el ${TEXTOS.es.dias[dia - 1].toLowerCase()}`;
  return `Cerrado · abre ${cuando} ${alas(hora)}`;
}

// Cuántas opciones se eligen de un grupo, del mínimo y el máximo que guardó Postgres: «Elige 1»,
// «Hasta 3 · opcional». La misma regla que reglaCorta de app/src/lib/opciones.ts, dicha para la
// clienta y en sus dos idiomas.
export function textoRegla(minimo: number, maximo: number, lengua: Lengua): string {
  if (lengua === 'en') {
    if (minimo === 0) return maximo === 1 ? 'Optional' : `Up to ${maximo} · optional`;
    if (minimo === maximo) return `Choose ${minimo}`;
    return `Choose ${minimo} to ${maximo}`;
  }
  if (minimo === 0) return maximo === 1 ? 'Opcional' : `Hasta ${maximo} · opcional`;
  if (minimo === maximo) return `Elige ${minimo}`;
  return `Elige de ${minimo} a ${maximo}`;
}

// Lo que Don Chuy escribió en inglés, o su español si lo dejó vacío.
export function enSuLengua(es: string, en: string | null, lengua: Lengua): string;
export function enSuLengua(es: string | null, en: string | null, lengua: Lengua): string | null;
export function enSuLengua(es: string | null, en: string | null, lengua: Lengua): string | null {
  return lengua === 'en' && en ? en : es;
}
