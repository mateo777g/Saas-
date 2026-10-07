// barra.js — la barra de la página de Fragmentless (index.html).
// Al pasar el mouse o tocar un atajo, la barra crece y muestra su menú. Al bajar se esconde.
(() => {
  const barra = document.querySelector('.barra');
  const nav = barra.querySelector('.atajos');
  const atajos = [...barra.querySelectorAll('.atajo')];
  const velo = document.querySelector('.velo');
  const conMouse = matchMedia('(hover: hover)');

  // Cada letra de los submenús va en su propio <span> para que ruede al pasar
  // el mouse (ver .rueda en style.css). El enlace conserva su texto en aria-label.
  for (const enlace of barra.querySelectorAll('.submenu a')) {
    const texto = enlace.textContent.trim();
    const rueda = document.createElement('span');
    rueda.className = 'rueda';
    rueda.setAttribute('aria-hidden', 'true');
    [...texto].forEach((letra, i) => {
      if (letra === ' ') { rueda.append(' '); return; }
      const span = document.createElement('span');
      span.textContent = letra;
      span.style.setProperty('--i', i);
      rueda.append(span);
    });
    enlace.setAttribute('aria-label', texto);
    enlace.replaceChildren(rueda);
  }

  // Los submenús empiezan donde empiezan los atajos.
  function alinear() {
    barra.style.setProperty('--inicio-atajos', nav.getBoundingClientRect().left + 'px');
  }

  // Mientras la barra está abierta la página no se mueve: ni con la rueda del mouse (salvo Ctrl + rueda, que
  // es el zoom), ni con el dedo, ni con las teclas de bajar. No se le quita el scroll a la página para que su
  // barra de scroll no desaparezca y nada brinque de lado. Con el mouse, la barra se cierra al salir de ella,
  // así que tampoco se alcanza a arrastrar la barra de scroll.
  const TECLAS_SCROLL = new Set([' ', 'PageUp', 'PageDown', 'Home', 'End', 'ArrowUp', 'ArrowDown']);

  function frenar(e) {
    if (!e.ctrlKey) e.preventDefault();
  }

  function frenarTeclas(e) {
    if (!TECLAS_SCROLL.has(e.key)) return;
    if (e.key === ' ' && e.target.closest('button')) return; // con la barra de espacio se pica el botón
    e.preventDefault();
  }

  function bloquearScroll(bloquear) {
    if (bloquear) {
      addEventListener('wheel', frenar, { passive: false });
      addEventListener('touchmove', frenar, { passive: false });
      addEventListener('keydown', frenarTeclas);
    } else {
      removeEventListener('wheel', frenar);
      removeEventListener('touchmove', frenar);
      removeEventListener('keydown', frenarTeclas);
    }
  }

  function abrir(atajo) {
    for (const a of atajos) {
      const activo = a === atajo;
      a.setAttribute('aria-expanded', String(activo));
      document.getElementById(a.getAttribute('aria-controls')).hidden = !activo;
    }
    alinear();
    barra.dataset.abierto = '';
    bloquearScroll(true);
  }

  function cerrar() {
    delete barra.dataset.abierto;
    for (const a of atajos) a.setAttribute('aria-expanded', 'false');
    bloquearScroll(false);
  }

  for (const a of atajos) {
    a.addEventListener('mouseenter', () => { if (conMouse.matches) abrir(a); });
    a.addEventListener('click', (e) => {
      // Con mouse el clic solo abre; con dedo o teclado abre y cierra.
      const yaAbierto = a.getAttribute('aria-expanded') === 'true';
      if (yaAbierto && !(conMouse.matches && e.detail > 0)) cerrar();
      else abrir(a);
    });
  }

  barra.addEventListener('mouseleave', () => { if (conMouse.matches) cerrar(); });
  barra.addEventListener('focusout', (e) => { if (!barra.contains(e.relatedTarget)) cerrar(); });
  velo.addEventListener('click', cerrar);
  document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape' || !('abierto' in barra.dataset)) return;
    const activo = atajos.find((a) => a.getAttribute('aria-expanded') === 'true');
    cerrar();
    if (activo) activo.focus();
  });
  addEventListener('resize', alinear);

  // Al bajar, la barra se esconde hacia arriba; al subir, regresa. Abierta o con el foco
  // del teclado adentro, se queda. Los saltitos de menos de 4 px no cuentan.
  let ultimaY = scrollY;
  addEventListener('scroll', () => {
    const y = scrollY;
    if (Math.abs(y - ultimaY) < 4) return;
    const bajando = y > ultimaY;
    ultimaY = y;
    if (bajando && y > barra.offsetHeight && !('abierto' in barra.dataset) && !barra.contains(document.activeElement)) {
      barra.dataset.escondida = '';
    } else if (!bajando) {
      delete barra.dataset.escondida;
    }
  }, { passive: true });
  barra.addEventListener('focusin', () => { delete barra.dataset.escondida; });
})();
