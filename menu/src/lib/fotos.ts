// Cada foto del menú (el logo, los carteles, los productos) late en su lugar mientras llega de R2, del tamaño y las
// esquinas de su caja y en el gris del menú, y luego aparece suave en 0.3 s («Los esqueletos del menú digital», 12 nov
// 2026; maqueta UDArhiEZceT7rmSKxqRA5r v59, fotosLlegan). Una que ya estaba en el celular sale de una vez. Una que no
// llega deja de latir y se apunta el error: nunca un esqueleto que no se acaba.
//
// Vigila todo lo que hay dentro de `raiz`: las fotos que van saliendo (la tarjeta del asistente, Tu pedido, el
// producto) y las que cambian de foto. El CSS de `.f-foto-espera` está en formas.css.
import { quieto } from './movimiento';

const ESPERA = 'f-foto-espera';

export function esperarFotos(raiz: HTMLElement): () => void {
  const pendientes = new Map<HTMLImageElement, AbortController>();

  function vigilar(img: HTMLImageElement) {
    pendientes.get(img)?.abort();
    pendientes.delete(img);
    if (!img.getAttribute('src')) return img.classList.remove(ESPERA);
    if (img.complete) {
      img.classList.remove(ESPERA);
      if (!img.naturalWidth) console.error('[menu] no llegó una foto:', img.currentSrc || img.src);
      return;
    }
    img.classList.add(ESPERA);
    const control = new AbortController();
    pendientes.set(img, control);
    const listo = (llego: boolean) => {
      control.abort();
      pendientes.delete(img);
      img.classList.remove(ESPERA);
      if (!llego) return console.error('[menu] no llegó una foto:', img.currentSrc || img.src);
      // Hasta la opacidad que le toca (lo agotado de Tu pedido va más clarito).
      if (!quieto()) img.animate([{ opacity: 0 }, { opacity: getComputedStyle(img).opacity }], { duration: 300, easing: 'ease-out' });
    };
    img.addEventListener('load', () => listo(true), { signal: control.signal });
    img.addEventListener('error', () => listo(false), { signal: control.signal });
  }

  const todas = (n: Node) => (n instanceof HTMLImageElement ? [n] : n instanceof Element ? [...n.querySelectorAll('img')] : []);
  todas(raiz).forEach(vigilar);
  const observador = new MutationObserver((cambios) => {
    for (const c of cambios) {
      if (c.type === 'attributes') {
        if (c.target instanceof HTMLImageElement) vigilar(c.target);
        continue;
      }
      for (const n of c.addedNodes) todas(n).forEach(vigilar);
      for (const n of c.removedNodes)
        for (const img of todas(n)) {
          pendientes.get(img)?.abort();
          pendientes.delete(img);
        }
    }
  });
  observador.observe(raiz, { childList: true, subtree: true, attributes: true, attributeFilter: ['src'] });
  return () => {
    observador.disconnect();
    for (const c of pendientes.values()) c.abort();
    pendientes.clear();
  };
}

// Espera a que lleguen (o fallen) las fotos que ya se ven arriba, hasta `tope` ms.
export function fotosDeArriba(raiz: HTMLElement, tope: number): Promise<void> {
  const fotos = [...raiz.querySelectorAll('img')].filter((i) => !i.complete && i.getBoundingClientRect().top < innerHeight);
  if (!fotos.length) return Promise.resolve();
  const una = (i: HTMLImageElement) =>
    new Promise<void>((listo) => {
      i.addEventListener('load', () => listo(), { once: true });
      i.addEventListener('error', () => listo(), { once: true });
    });
  return Promise.race([Promise.all(fotos.map(una)).then(() => {}), new Promise<void>((listo) => setTimeout(listo, tope))]);
}
