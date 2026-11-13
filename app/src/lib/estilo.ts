// El estilo del panel en este navegador: «Simple» (el de siempre) o «Cristal» (el vidrio de iOS; libreta 4,
// «El estilo Cristal»). public/tema-inicial.js lo pone en <html data-estilo> antes de pintar; Ajustes lo
// cambia aquí, con la misma llave. Como el tema, se guarda en el navegador y no en la base: cada aparato
// tiene el suyo. Un estilo solo cambia materiales: el CSS de Cristal de cada pieza cuelga de
// :root[data-estilo='cristal'], así que cambiarlo se ve al momento.
export type Estilo = 'simple' | 'cristal';

const LLAVE = 'fragmentless-estilo';

export function estiloActual(): Estilo {
  return document.documentElement.dataset.estilo === 'cristal' ? 'cristal' : 'simple';
}

export function cambiarEstilo(estilo: Estilo): void {
  document.documentElement.dataset.estilo = estilo;
  try {
    localStorage.setItem(LLAVE, estilo);
  } catch (error) {
    console.error('[estilo] no se pudo guardar el estilo; se queda solo mientras la pestaña siga abierta:', error);
  }
}

// Para lo que dibuja con JavaScript (la luz del vidrio, la gota del menú): avisa cuando cambian el estilo
// o el tema, con lo que hay ahora. Devuelve cómo dejar de escuchar.
export function alCambiarEstilo(hacer: (estilo: Estilo, tema: 'claro' | 'oscuro') => void): () => void {
  const raiz = document.documentElement;
  const avisar = () => hacer(estiloActual(), raiz.dataset.tema === 'oscuro' ? 'oscuro' : 'claro');
  const vigia = new MutationObserver(avisar);
  vigia.observe(raiz, { attributes: true, attributeFilter: ['data-estilo', 'data-tema'] });
  return () => vigia.disconnect();
}
