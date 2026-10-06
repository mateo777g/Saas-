// vistas.js — las vistas del panel en la sección 3 de la página de Fragmentless (index.html).
// Pasada del componente "Coverflow Carousel" (React + Motion) a JavaScript sin librerías, con sus valores.
// Cada tarjeta se acomoda según su distancia d a la del frente (d = su lugar − el de la del frente):
//
//   x = d·espacio      z = −|d|·hondo      escala = max(1 − |d|·0.15, 0.4)      giro en y = −d·45°
//
// Solo se ven las que están a 3 lugares o menos. d no da la vuelta, como en el ejemplo: con la primera al
// frente no hay nada a la izquierda, y de la última se pasa a la primera regresando toda la fila.
// espacio y hondo crecen con el tamaño de las tarjetas (style.css). Los movimientos son transiciones de CSS
// con las curvas de los resortes del ejemplo (--resorte y --resorte-regreso en style.css).
(() => {
  const vistas = document.querySelector('.vistas');
  const pista = vistas.querySelector('.vistas-pista');
  const tarjetas = [...pista.children];
  const textos = [...vistas.querySelectorAll('.vistas-texto')];
  const aviso = vistas.querySelector('.solo-lector');
  const sinMovimiento = matchMedia('(prefers-reduced-motion: reduce)');
  const n = tarjetas.length;

  const GIRO = 45;              // grados por cada lugar de distancia
  const PASO_ESCALA = 0.15;
  const ESCALA_MINIMA = 0.4;
  const MAS_LEJOS = 3;          // a más lugares de distancia ya no se ven
  // Al arrastrar, la pista sigue al dedo solo un 12 %; se pasa de vista si se arrastró más de 80 px
  // o se soltó a más de 500 px por segundo.
  const ELASTICO = 0.12;
  const DISTANCIA_PASAR = 80;
  const VELOCIDAD_PASAR = 500;
  const EMPEZAR_ARRASTRE = 3;   // px que hay que mover antes de que cuente como arrastre

  let actual = 0;

  function acomodar() {
    const quieto = sinMovimiento.matches;
    tarjetas.forEach((tarjeta, i) => {
      const d = i - actual;
      const lejos = Math.abs(d);
      // Las que no se ven salen de la página, y al volver aparecen ya en su lugar (en el ejemplo se desmontan)
      tarjeta.hidden = lejos > MAS_LEJOS;
      if (d === 0) tarjeta.removeAttribute('aria-hidden');
      else tarjeta.setAttribute('aria-hidden', 'true');
      tarjeta.style.zIndex = n - lejos;
      if (quieto) {
        // Con menos movimiento: sin giros ni fondo, solo se ve la del frente y cambia de golpe
        tarjeta.style.transform = `translateX(calc(${d} * var(--espacio)))`;
        tarjeta.style.opacity = d === 0 ? 1 : 0;
      } else {
        const escala = Math.max(1 - lejos * PASO_ESCALA, ESCALA_MINIMA);
        tarjeta.style.transform =
          `translateX(calc(${d} * var(--espacio))) translateZ(calc(${-lejos} * var(--hondo))) ` +
          `scale(${escala}) rotateY(${-d * GIRO}deg)`;
        tarjeta.style.opacity = 1;
      }
    });
    textos.forEach((texto, i) => texto.toggleAttribute('data-dentro', i === actual));
    aviso.textContent = `Vista ${actual + 1} de ${n}`;
  }

  // Da la vuelta: antes de la primera va la última y después de la última, la primera
  function ir(lugar) {
    actual = ((lugar % n) + n) % n;
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

  // Arrastrar a los lados (con el mouse o el dedo; hacia arriba y abajo la página sigue bajando).
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

  pista.addEventListener('pointerdown', (e) => {
    if (sinMovimiento.matches || n < 2 || !e.isPrimary || e.button !== 0) return;
    arrastre = { id: e.pointerId, x: e.clientX, y: e.clientY, puntos: [{ x: e.clientX, t: e.timeStamp }], empezado: false };
    pista.setPointerCapture(e.pointerId);
  });

  pista.addEventListener('pointermove', (e) => {
    if (!arrastre || e.pointerId !== arrastre.id) return;
    arrastre.puntos.push({ x: e.clientX, t: e.timeStamp });
    const dx = e.clientX - arrastre.x;
    if (!arrastre.empezado) {
      if (Math.hypot(dx, e.clientY - arrastre.y) < EMPEZAR_ARRASTRE) return;
      arrastre.empezado = true;
      pista.toggleAttribute('data-arrastrando', true);
    }
    pista.style.transform = `translateX(${dx * ELASTICO}px)`;
  });

  // Al soltar (o si el navegador se queda con el gesto para bajar la página) la pista regresa a su lugar
  function soltar(e) {
    if (!arrastre || e.pointerId !== arrastre.id) return;
    const { empezado, puntos } = arrastre;
    arrastre = null;
    if (!empezado) return;
    // Con pointercancel el navegador puede no dar la posición: cuenta el último punto que se movió
    if (e.type === 'pointerup') puntos.push({ x: e.clientX, t: e.timeStamp });
    const dx = puntos[puntos.length - 1].x - puntos[0].x;
    const v = velocidad(puntos);
    if (dx < -DISTANCIA_PASAR || v < -VELOCIDAD_PASAR) ir(actual + 1);
    else if (dx > DISTANCIA_PASAR || v > VELOCIDAD_PASAR) ir(actual - 1);
    pista.toggleAttribute('data-arrastrando', false);
    pista.style.transform = '';
  }
  pista.addEventListener('pointerup', soltar);
  pista.addEventListener('pointercancel', soltar);

  sinMovimiento.addEventListener('change', acomodar);
  acomodar();
})();
