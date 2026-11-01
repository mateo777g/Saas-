// nosotros.js — la página Nosotros de Fragmentless (nosotros.html).
// Cada bloque con .aparece entra (sube y aparece) la primera vez que asoma al bajar; ya no se vuelve a ir.
// La clase .ns-animada en <html> es la que los esconde al principio: sin este script, todo se ve desde el inicio.
(() => {
  const bloques = [...document.querySelectorAll('.aparece')];
  if (!('IntersectionObserver' in window) || matchMedia('(prefers-reduced-motion: reduce)').matches) return;

  document.documentElement.classList.add('ns-animada');
  const observador = new IntersectionObserver((entradas) => {
    for (const entrada of entradas) {
      if (!entrada.isIntersecting) continue;
      entrada.target.setAttribute('data-visto', '');
      observador.unobserve(entrada.target);
    }
  }, { rootMargin: '0px 0px -10% 0px' });
  for (const bloque of bloques) observador.observe(bloque);
})();

// La entrada del logo (components/logo-vidrio.tsx): mide cuánto tiene que subir el logo, del centro de la pantalla
// al lugar que le aparta .ns-logo-lugar arriba del texto, y lo vuelve a medir si cambia el tamaño.
(() => {
  const logo = document.getElementById('logo-vidrio');
  const lugar = document.querySelector('.ns-logo-lugar');
  if (!logo || !lugar) return;
  const medir = () => {
    const sube = lugar.offsetTop + lugar.offsetHeight / 2 - (logo.offsetTop + logo.offsetHeight / 2);
    logo.style.setProperty('--sube', `${sube}px`);
  };
  medir();
  new ResizeObserver(medir).observe(lugar.parentElement);

  // El titular, letra por letra, para el brillo azul que le pasa al terminar la entrada (nosotros.css)
  const titular = lugar.parentElement.querySelector('h1');
  let letra = 0;
  titular.replaceChildren(...[...titular.textContent].map((caracter) => {
    if (caracter === ' ') return ' ';
    const span = document.createElement('span');
    span.className = 'brilla';
    span.style.setProperty('--i', letra++);
    span.textContent = caracter;
    return span;
  }));

  // Si el bundle no llega a montar el logo, la entrada nunca terminaría y la página se quedaría trabada en gris
  setTimeout(() => {
    const raiz = document.documentElement;
    if (raiz.dataset.intro === 'logo' && !logo.childElementCount) raiz.dataset.intro = 'sube';
  }, 5000);
})();
