// Lo que la clienta eligió arriba del menú (ES / EN, MXN / USD), recordado en su celular para la
// próxima vez. Si el navegador no deja guardar (modo privado), el menú funciona igual: abre en el
// idioma del celular y en pesos.
import type { Lengua } from './textos';

export type Moneda = 'mxn' | 'usd';
export type Preferencias = { lengua?: Lengua; moneda?: Moneda };

const CLAVE = 'pidemenu-preferencias';

export function leerPreferencias(): Preferencias {
  try {
    const p = JSON.parse(localStorage.getItem(CLAVE) ?? '{}') as Preferencias;
    return {
      lengua: p.lengua === 'es' || p.lengua === 'en' ? p.lengua : undefined,
      moneda: p.moneda === 'mxn' || p.moneda === 'usd' ? p.moneda : undefined,
    };
  } catch (error) {
    console.warn('[menu] no se pudieron leer las preferencias:', error);
    return {};
  }
}

export function guardarPreferencias(p: Preferencias) {
  try {
    localStorage.setItem(CLAVE, JSON.stringify(p));
  } catch (error) {
    console.warn('[menu] no se pudieron recordar las preferencias:', error);
  }
}

// Abre en inglés si el celular está en inglés (libreta 6); si no, en español.
export function lenguaDelCelular(): Lengua {
  const idioma = (navigator.languages?.[0] ?? navigator.language ?? '').toLowerCase();
  return idioma.startsWith('en') ? 'en' : 'es';
}
