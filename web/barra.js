// barra.js — la barra de la página de Fragmentless (index.html).
// Al pasar el mouse o tocar un atajo, la barra crece y muestra su menú. Al bajar se esconde.
// En celular y en tablet no caben los atajos: la hamburguesa abre la barra con los tres submenús, uno debajo del otro,
// cada uno un renglón que se abre al tocarlo, como el footer en celular.
(() => {
  const barra = document.querySelector('.barra');
  const nav = barra.querySelector('.atajos');
  const atajos = [...barra.querySelectorAll('.atajo')];
  const hamburguesa = barra.querySelector('.hamburguesa');
  const submenus = [...barra.querySelectorAll('.submenu')];
  const velo = document.querySelector('.velo');
  const conMouse = matchMedia('(hover: hover)');
  // Hasta este ancho no caben los atajos y va la hamburguesa (el mismo de style.css)
  const conHamburguesa = matchMedia('(max-width: 900px)');

  // Con la hamburguesa cada submenú es un renglón: un botón con el nombre de su atajo y una flechita, y debajo el
  // submenú, que se abre con la altura (style.css). En escritorio el botón no se ve y el submenú queda como siempre.
  const grupos = atajos.map((a) => {
    const submenu = document.getElementById(a.getAttribute('aria-controls'));
    const grupo = document.createElement('div');
    grupo.className = 'submenu-grupo';
    const titulo = document.createElement('button');
    titulo.type = 'button';
    titulo.className = 'submenu-titulo';
    titulo.setAttribute('aria-controls', submenu.id);
    const flecha = document.createElement('span');
    flecha.className = 'submenu-flecha';
    flecha.setAttribute('aria-hidden', 'true');
    titulo.append(a.textContent.trim(), flecha);
    const cuerpo = document.createElement('div');
    cuerpo.className = 'submenu-cuerpo';
    submenu.replaceWith(grupo);
    cuerpo.append(submenu);
    grupo.append(titulo, cuerpo);
    return { grupo, titulo, cuerpo };
  });

  function abrirGrupo({ grupo, titulo, cuerpo }, abierto) {
    titulo.setAttribute('aria-expanded', String(abierto));
    grupo.toggleAttribute('data-abierto', abierto);
    // Cerrado, sus enlaces no se pueden tabular; en escritorio no se cierra nunca
    cuerpo.inert = conHamburguesa.matches && !abierto;
  }

  // Todos cerrados: al abrir la hamburguesa y al cambiar entre la hamburguesa y los atajos
  function cerrarGrupos() {
    for (const g of grupos) abrirGrupo(g, false);
  }

  // Al abrirse, a sus enlaces les pasa el brillo, como al pasarles el mouse
  for (const g of grupos) {
    g.titulo.addEventListener('click', () => {
      const abrir = g.titulo.getAttribute('aria-expanded') !== 'true';
      abrirGrupo(g, abrir);
      if (abrir) g.cuerpo.querySelectorAll('a').forEach(encender);
    });
  }
  cerrarGrupos();

  // El brillo de un enlace (style.css, .brillando). Reinicia el barrido al volver a entrar, aunque el anterior no
  // haya terminado.
  function encender(enlace) {
    enlace.classList.remove('brillando');
    void enlace.offsetWidth;
    enlace.classList.add('brillando');
  }

  // El brillo recorre cada enlace de izquierda a derecha, también si tiene una sola palabra.
  for (const enlace of barra.querySelectorAll('.submenu a')) {
    const texto = enlace.textContent.trim();
    const brillo = document.createElement('span');
    brillo.className = 'submenu-brillo';
    brillo.setAttribute('aria-hidden', 'true');
    [...texto].forEach((letra, i) => {
      if (letra === ' ') { brillo.append(' '); return; }
      const span = document.createElement('span');
      span.textContent = letra;
      span.style.setProperty('--i', i);
      brillo.append(span);
    });
    enlace.setAttribute('aria-label', texto);
    enlace.replaceChildren(brillo);
    enlace.addEventListener('pointerenter', () => { if (conMouse.matches) encender(enlace); });
    enlace.addEventListener('focus', () => encender(enlace));
    enlace.addEventListener('pointerleave', () => enlace.classList.remove('brillando'));
    enlace.addEventListener('blur', () => enlace.classList.remove('brillando'));
    brillo.addEventListener('animationend', (e) => {
      if (e.target === brillo.lastElementChild) enlace.classList.remove('brillando');
    });
  }

  // Los submenús empiezan donde empiezan los atajos.
  function alinear() {
    barra.style.setProperty('--inicio-atajos', nav.getBoundingClientRect().left + 'px');
  }

  // Abierta con el dedo o el teclado, la página no se mueve: ni con el dedo, ni con la rueda (salvo Ctrl + rueda,
  // que es el zoom), ni con las teclas de bajar. No se le quita el scroll a la página para que su barra de scroll
  // no desaparezca y nada brinque de lado. Abierta con el mouse no se frena nada: basta pasar el cursor por los
  // atajos para abrirla, y la página no debe atorarse; si se baja con ella abierta, se cierra.
  const TECLAS_SCROLL = new Set([' ', 'PageUp', 'PageDown', 'Home', 'End', 'ArrowUp', 'ArrowDown']);
  let frenada = false;

  function frenar(e) {
    if (!e.ctrlKey) e.preventDefault();
  }

  function frenarTeclas(e) {
    if (!TECLAS_SCROLL.has(e.key)) return;
    if (e.key === ' ' && e.target.closest('button')) return; // con la barra de espacio se pica el botón
    e.preventDefault();
  }

  function bloquearScroll(bloquear) {
    frenada = bloquear;
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

  function abrir(atajo, frenar) {
    for (const a of atajos) {
      const activo = a === atajo;
      a.setAttribute('aria-expanded', String(activo));
      document.getElementById(a.getAttribute('aria-controls')).hidden = !activo;
    }
    alinear();
    barra.dataset.abierto = '';
    bloquearScroll(frenar);
  }

  // La hamburguesa muestra los tres renglones, cerrados. Se abre con el dedo, así que la página no se mueve.
  function abrirMenu() {
    for (const a of atajos) a.setAttribute('aria-expanded', 'false');
    for (const s of submenus) s.hidden = false;
    cerrarGrupos();
    hamburguesa.setAttribute('aria-expanded', 'true');
    barra.dataset.abierto = '';
    bloquearScroll(true);
  }

  function cerrar() {
    delete barra.dataset.abierto;
    for (const a of atajos) a.setAttribute('aria-expanded', 'false');
    hamburguesa.setAttribute('aria-expanded', 'false');
    bloquearScroll(false);
  }

  for (const a of atajos) {
    a.addEventListener('mouseenter', () => { if (conMouse.matches) abrir(a, false); });
    a.addEventListener('click', (e) => {
      // Con mouse el clic solo abre; con dedo o teclado abre y cierra.
      const conClic = conMouse.matches && e.detail > 0;
      const yaAbierto = a.getAttribute('aria-expanded') === 'true';
      if (yaAbierto && !conClic) cerrar();
      else abrir(a, !conClic);
    });
  }

  hamburguesa.addEventListener('click', () => {
    if ('abierto' in barra.dataset) cerrar();
    else abrirMenu();
  });

  barra.addEventListener('mouseleave', () => { if (conMouse.matches) cerrar(); });
  barra.addEventListener('focusout', (e) => { if (!barra.contains(e.relatedTarget)) cerrar(); });
  // Abierta con la hamburguesa la página está frenada: un enlace a la misma página (como #sistema) la movería con
  // la barra abierta encima
  barra.querySelector('.despliegue').addEventListener('click', (e) => {
    if (conHamburguesa.matches && e.target.closest('a')) cerrar();
  });
  velo.addEventListener('click', cerrar);
  document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape' || !('abierto' in barra.dataset)) return;
    const activo = [...atajos, hamburguesa].find((a) => a.getAttribute('aria-expanded') === 'true');
    cerrar();
    if (activo) activo.focus();
  });
  addEventListener('resize', alinear);
  // Al cambiar de la hamburguesa a los atajos (o al revés) abierta, se quedaría con el menú del otro
  conHamburguesa.addEventListener('change', () => {
    cerrar();
    cerrarGrupos();
  });

  // Al bajar, la barra se esconde hacia arriba; al subir, regresa. Abierta o con el foco
  // del teclado adentro, se queda. Los saltitos de menos de 4 px no cuentan.
  let ultimaY = scrollY;
  addEventListener('scroll', () => {
    if ('abierto' in barra.dataset && !frenada) cerrar();
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
