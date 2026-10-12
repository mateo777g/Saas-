// El tema claro u oscuro de este navegador. public/tema-inicial.js lo pone en <html data-tema>
// antes de pintar; Ajustes lo cambia aquí, con la misma llave. Se guarda en el navegador, no en
// la base: cada aparato tiene el suyo (libreta 4, «Qué cambia al dejar Flet»).
export type Tema = 'claro' | 'oscuro';

const LLAVE = 'fragmentless-tema';

export function temaActual(): Tema {
  return document.documentElement.dataset.tema === 'oscuro' ? 'oscuro' : 'claro';
}

// Se ve al momento: los colores son variables de CSS que dependen de data-tema.
export function cambiarTema(tema: Tema): void {
  document.documentElement.dataset.tema = tema;
  try {
    localStorage.setItem(LLAVE, tema);
  } catch (error) {
    console.error('[tema] no se pudo guardar el tema; se queda solo mientras la pestaña siga abierta:', error);
  }
}
