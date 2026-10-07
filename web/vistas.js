// vistas.js — las vistas del panel en la sección 3 de la página de Fragmentless (index.html).
// Como la página del iPhone: unas manos sostienen una tablet y en su pantalla se ve una vista del panel;
// arriba, su título, su descripción y los botones. Las capturas van en fila dentro de la pantalla y la
// pista se corre una pantalla por vista. Lo demás sale del carrusel "Coverflow Carousel" (React + Motion)
// que había antes aquí: botones, flechas del teclado, arrastre con su mismo elástico y sus resortes
// (--resorte y --resorte-regreso en style.css). Como en él, no da la vuelta por dentro: de la última se
// pasa a la primera regresando toda la fila.
(() => {
  const vistas = document.querySelector('.vistas');
  const pantalla = vistas.querySelector('.vistas-pantalla');
  const pista = vistas.querySelector('.vistas-pista');
  const capturas = [...pista.children];
  const cajaNombres = vistas.querySelector('.vistas-nombres');
  const nombres = [...cajaNombres.children];
  const descripciones = [...vistas.querySelectorAll('.vistas-descripcion')];
  const aviso = vistas.querySelector('.solo-lector');
  const sinMovimiento = matchMedia('(prefers-reduced-motion: reduce)');
  const n = capturas.length;

  // Al arrastrar, la pista sigue al dedo solo un 12 %; se pasa de vista si se arrastró más de 80 px
  // o se soltó a más de 500 px por segundo.
  const ELASTICO = 0.12;
  const DISTANCIA_PASAR = 80;
  const VELOCIDAD_PASAR = 500;
  const EMPEZAR_ARRASTRE = 3;   // px que hay que mover antes de que cuente como arrastre

  let actual = 0;

  // Corre la pista a la vista actual, más lo que se lleve arrastrado (px)
  function correr(arrastrado = 0) {
    pista.style.transform = `translateX(calc(${-actual * 100}% + ${arrastrado}px))`;
  }

  // La caja de los nombres mide lo que el de la vista del frente, para que el título quede centrado
  // (style.css). El ancho de cada nombre lo da el ResizeObserver de abajo, sin la escala de la hoja (que
  // arranca al 90 %), y cambia al cargar la letra y al cambiar el ancho de la pantalla (la letra crece con él).
  const anchos = nombres.map((nombre) => nombre.offsetWidth);

  function medirNombre() {
    cajaNombres.style.setProperty('--ancho-nombre', `${anchos[actual]}px`);
  }

  function acomodar() {
    correr();
    capturas.forEach((captura, i) => {
      if (i === actual) captura.removeAttribute('aria-hidden');
      else captura.setAttribute('aria-hidden', 'true');
    });
    nombres.forEach((nombre, i) => nombre.toggleAttribute('data-dentro', i === actual));
    descripciones.forEach((descripcion, i) => descripcion.toggleAttribute('data-dentro', i === actual));
    medirNombre();
    aviso.textContent = `Vista ${actual + 1} de ${n}`;
  }

  // Da la vuelta: antes de la primera va la última y después de la última, la primera
  function ir(lugar) {
    actual = ((lugar % n) + n) % n;
    pista.toggleAttribute('data-regresa', false);
    acomodar();
  }

  for (const boton of vistas.querySelectorAll('[data-paso]')) {
    boton.addEventListener('click', () => ir(actual + Number(boton.dataset.paso)));
  }

  vistas.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowRight') {
      e.preventDefault();
      ir(actual + 1);
    } else if (e.key === 'ArrowLeft') {
      e.preventDefault();
      ir(actual - 1);
    }
  });

  // Arrastrar la pantalla a los lados (con el mouse o el dedo; hacia arriba y abajo la página sigue bajando).
  // La velocidad al soltar se mide como en Motion: del último punto al primero de hace más de 100 ms.
  let arrastre = null;

  function velocidad(puntos) {
    const ultimo = puntos[puntos.length - 1];
    let desde = puntos[0];
    for (let i = puntos.length - 1; i >= 0; i--) {
      desde = puntos[i];
      if (ultimo.t - desde.t > 100) break;
    }
    const segundos = (ultimo.t - desde.t) / 1000;
    return segundos > 0 ? (ultimo.x - desde.x) / segundos : 0;
  }

  pantalla.addEventListener('pointerdown', (e) => {
    if (sinMovimiento.matches || n < 2 || !e.isPrimary || e.button !== 0) return;
    arrastre = { id: e.pointerId, x: e.clientX, y: e.clientY, puntos: [{ x: e.clientX, t: e.timeStamp }], empezado: false };
    pantalla.setPointerCapture(e.pointerId);
  });

  pantalla.addEventListener('pointermove', (e) => {
    if (!arrastre || e.pointerId !== arrastre.id) return;
    arrastre.puntos.push({ x: e.clientX, t: e.timeStamp });
    const dx = e.clientX - arrastre.x;
    if (!arrastre.empezado) {
      if (Math.hypot(dx, e.clientY - arrastre.y) < EMPEZAR_ARRASTRE) return;
      arrastre.empezado = true;
      pista.toggleAttribute('data-arrastrando', true);
    }
    correr(dx * ELASTICO);
  });

  // Al soltar (o si el navegador se queda con el gesto para bajar la página) pasa de vista o regresa
  function soltar(e) {
    if (!arrastre || e.pointerId !== arrastre.id) return;
    const { empezado, puntos } = arrastre;
    arrastre = null;
    if (!empezado) return;
    // Con pointercancel el navegador puede no dar la posición: cuenta el último punto que se movió
    if (e.type === 'pointerup') puntos.push({ x: e.clientX, t: e.timeStamp });
    const dx = puntos[puntos.length - 1].x - puntos[0].x;
    const v = velocidad(puntos);
    pista.toggleAttribute('data-arrastrando', false);
    if (dx < -DISTANCIA_PASAR || v < -VELOCIDAD_PASAR) ir(actual + 1);
    else if (dx > DISTANCIA_PASAR || v > VELOCIDAD_PASAR) ir(actual - 1);
    else {
      pista.toggleAttribute('data-regresa', true);
      correr();
    }
  }
  pantalla.addEventListener('pointerup', soltar);
  pantalla.addEventListener('pointercancel', soltar);

  const observador = new ResizeObserver((cambios) => {
    for (const cambio of cambios) anchos[nombres.indexOf(cambio.target)] = cambio.borderBoxSize[0].inlineSize;
    medirNombre();
  });
  nombres.forEach((nombre) => observador.observe(nombre));
  acomodar();
})();
