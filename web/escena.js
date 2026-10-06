// escena.js — la escena del video en la página de Fragmentless (index.html).
// Al bajar, el hueco del video se encoge y se gira de lado, el fondo se oscurece (y el video del panel
// oscuro cambia al del panel claro) y sale el texto del centro; luego la tarjeta se va a la derecha
// y sale el texto de la izquierda con su botón.
// La tarjeta y el fondo los mueve el scroll: cada cuadro se calcula de cuánto has bajado dentro de la
// escena. Los textos no: al llegar a su momento entran solos, con el reloj (style.css), y al pasarlo se van.
(() => {
  const escena = document.querySelector('.escena');
  const fija = escena.querySelector('.escena-fija');
  const noche = escena.querySelector('.noche');
  const video = escena.querySelector('.video');
  const eslogan = video.querySelector('h1');
  const videoNoche = video.querySelector('.video-noche');
  const centro = escena.querySelector('.texto-centro');
  const lado = escena.querySelector('.texto-lado');
  const celular = matchMedia('(max-width: 760px)');
  const sinMovimiento = matchMedia('(prefers-reduced-motion: reduce)');

  // Poses de la tarjeta, medidas del video de referencia (pantalla de 1896×916).
  // x, y: dónde queda su centro (fracción de la pantalla). ancho, alto: lo más que puede medir
  // ya encogida. rx, ry, rz: giros en grados (ry negativo = el lado izquierdo se va hacia atrás).
  // k: cuánto se encoge al irse al lado, respecto a la pose del centro.
  const POSES = {
    escritorio: {
      centro: { x: 0.5, y: 0.413, ancho: 0.497, alto: 0.462, rx: 0, ry: -53, rz: 0 },
      lado: { x: 0.645, y: 0.495, k: 0.9, rx: -9.6, ry: -47.2, rz: 1.8 },
    },
    // En celular la tarjeta no se va a la derecha: se queda arriba y los textos salen debajo.
    celular: {
      centro: { x: 0.5, y: 0.36, ancho: 0.62, alto: 0.42, rx: 0, ry: -40, rz: 0 },
      lado: { x: 0.5, y: 0.34, k: 0.9, rx: -9.6, ry: -47.2, rz: 1.8 },
    },
  };
  // La perspectiva mide 3.75 veces el ancho de la tarjeta encogida (también medido).
  const PROFUNDIDAD = 3.75;

  // Tramos del recorrido: 0 es arriba de la escena y 1 el final.
  const TRAMOS = {
    encoger: [0, 0.22],
    eslogan: [0, 0.1],
    noche: [0.02, 0.14],
    irseAlLado: [0.48, 0.72],
  };
  // Entre qué puntos del recorrido está dentro cada texto (el de la izquierda se queda hasta el final).
  const TEXTOS = {
    centro: [0.16, 0.48],
    lado: [0.62, Infinity],
  };

  // Cada palabra de los párrafos que se encienden va en su propio <span> (ver .se-enciende en style.css);
  // el texto entero sabe cuántas son, para que su botón salga después de la última.
  for (const p of escena.querySelectorAll('.se-enciende')) {
    const palabras = p.textContent.trim().split(/\s+/);
    p.replaceChildren();
    palabras.forEach((palabra, i) => {
      const span = document.createElement('span');
      span.textContent = palabra;
      span.style.setProperty('--i', i);
      p.append(span, i < palabras.length - 1 ? ' ' : '');
    });
    p.parentElement.style.setProperty('--n', palabras.length);
  }

  const limitar = (v) => Math.min(1, Math.max(0, v));
  const tramo = (p, [desde, hasta]) => limitar((p - desde) / (hasta - desde));
  const adentro = (p, [desde, hasta]) => p >= desde && p < hasta;
  const suave = (t) => (t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2);
  const mezclar = (a, b, t) => {
    const r = {};
    for (const clave in a) r[clave] = a[clave] + (b[clave] - a[clave]) * t;
    return r;
  };

  let pendiente = false;

  function pintar() {
    pendiente = false;
    const anchoPantalla = fija.clientWidth; // sin la barra de desplazamiento
    const altoPantalla = innerHeight;
    // La última pantalla de la escena no cuenta: en ella la hoja de la sección 3 sube encima (hoja.js).
    const recorrido = escena.offsetHeight - fija.offsetHeight * 2;
    const p = recorrido > 0 ? limitar(-escena.getBoundingClientRect().top / recorrido) : 0;

    // La tarjeta: del hueco a todo lo ancho, a la pose del centro y de ahí a la del lado.
    const poses = celular.matches ? POSES.celular : POSES.escritorio;
    const ancho = video.offsetWidth;
    const alto = video.offsetHeight;
    const x0 = video.offsetLeft + ancho / 2;
    const y0 = video.offsetTop + alto / 2;
    const k = Math.min(poses.centro.ancho * anchoPantalla / ancho, poses.centro.alto * altoPantalla / alto);
    const giro = sinMovimiento.matches ? 0 : 1;
    const hueco = { x: x0, y: y0, k: 1, rx: 0, ry: 0, rz: 0 };
    const enCentro = {
      x: poses.centro.x * anchoPantalla, y: poses.centro.y * altoPantalla, k,
      rx: poses.centro.rx * giro, ry: poses.centro.ry * giro, rz: poses.centro.rz * giro,
    };
    const alLado = {
      x: poses.lado.x * anchoPantalla, y: poses.lado.y * altoPantalla, k: k * poses.lado.k,
      rx: poses.lado.rx * giro, ry: poses.lado.ry * giro, rz: poses.lado.rz * giro,
    };
    const pose = mezclar(
      mezclar(hueco, enCentro, suave(tramo(p, TRAMOS.encoger))),
      alLado,
      suave(tramo(p, TRAMOS.irseAlLado)),
    );
    video.style.transform =
      `translate(${pose.x - x0}px, ${pose.y - y0}px) perspective(${PROFUNDIDAD * k * ancho}px) ` +
      `rotateX(${pose.rx}deg) rotateY(${pose.ry}deg) rotateZ(${pose.rz}deg) scale(${pose.k})`;
    video.style.setProperty('--k', pose.k);

    // El eslogan se va, y con él la capa oscura que lo hace legible.
    const quedaEslogan = 1 - tramo(p, TRAMOS.eslogan);
    eslogan.style.opacity = quedaEslogan;
    video.style.setProperty('--capa', quedaEslogan);

    // El fondo se oscurece y entra el video del panel claro; pasada la mitad, la barra también se vuelve oscura.
    const oscuro = tramo(p, TRAMOS.noche);
    noche.style.opacity = oscuro;
    if (videoNoche) videoNoche.style.opacity = oscuro;
    document.documentElement.toggleAttribute('data-noche', oscuro >= 0.5);

    // Los textos: aquí solo se decide si están dentro; la animación la hace style.css. El del centro
    // se va cuando la tarjeta empieza a moverse, y el de la izquierda entra cuando ya va llegando.
    centro.toggleAttribute('data-dentro', adentro(p, TEXTOS.centro));
    lado.toggleAttribute('data-dentro', adentro(p, TEXTOS.lado));
  }

  function pedirCuadro() {
    if (pendiente) return;
    pendiente = true;
    requestAnimationFrame(pintar);
  }

  addEventListener('scroll', pedirCuadro, { passive: true });
  addEventListener('resize', pedirCuadro);
  celular.addEventListener('change', pedirCuadro);
  sinMovimiento.addEventListener('change', pedirCuadro);
  pintar();
})();
