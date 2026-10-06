// escena.js — la escena del video en la página de Fragmentless (index.html).
// Al bajar, el hueco del video se encoge y se gira de lado, el fondo se oscurece (y el video del panel
// oscuro cambia al del panel claro) y sale el texto del centro; luego la tarjeta se va a la derecha
// y sale el texto de la izquierda con su botón. Con mouse, la tarjeta además mira hacia el cursor.
// La tarjeta es la pantalla de una laptop: mientras se encoge le sale el marco y el teclado se desdobla
// desde su orilla de abajo, y la laptop entera hace los mismos movimientos.
// La tarjeta y el fondo los mueve el scroll: cada cuadro se calcula de cuánto has bajado dentro de la
// escena. Los textos no: al llegar a su momento entran solos, con el reloj (style.css), y al pasarlo se van.
(() => {
  const escena = document.querySelector('.escena');
  const fija = escena.querySelector('.escena-fija');
  const noche = escena.querySelector('.noche');
  const laptop = escena.querySelector('.laptop');
  const video = laptop.querySelector('.video');
  const teclado = laptop.querySelector('.teclado');
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
  // La tarjeta mira hacia el cursor: se gira hasta estos grados de más, encima de su pose
  // (x: hacia arriba o abajo, y: hacia los lados). No salta: lo persigue, y en `demora` ms
  // recorre casi dos tercios del camino.
  const MIRADA = { x: 10, y: 12, demora: 120 };
  // La bisagra: grados entre la pantalla y el teclado. Arriba, a todo lo ancho, el teclado está doblado
  // hacia atrás, de canto detrás de la pantalla (no se ve); mientras la tarjeta se encoge baja y se abre.
  const BISAGRA = { doblada: 270, abierta: 110 };
  // Las teclas, fila por fila, como las de una laptop con teclado numérico a la derecha: lo que mide de
  // ancho cada una, en teclas normales ("1*12" son doce de 1). Todas las filas miden 19. La de arriba
  // (esc, las F y las de arriba del numérico) es más bajita. "1^" es una tecla alta, que baja a la fila
  // de abajo (el + y el enter del numérico), y "_1" es el hueco que deja ahí. Las flechas van abajo a la
  // derecha de las letras: ↑ junto al shift y ← ↓ → debajo, con el 1 del numérico encima de la →.
  const TECLAS = {
    filas: [
      '1*19', // esc, F1–F12 … | inicio, fin, re pág, av pág
      '1*13 2 1*4', // º 1 … = borrar | bloq num, /, *, -
      '1.5 1*12 1.5 1*3 1^', // tab q … \ | 7 8 9, +
      '1.75 1*11 2.25 1*3 _1', // mayús a … enter | 4 5 6
      '2.25 1*10 1.75 1 1*3 1^', // shift z … shift, ↑ | 1 2 3, enter
      '1.25 1 1 1.25 5 1 1 1.5 1*5 _1', // ctrl fn win alt espacio alt menú ctrl, ← ↓ → | 0 .
    ],
    numerico: 4, // lo que mide el teclado numérico: el trackpad va centrado debajo de lo demás
    altoFunciones: 0.6, // la fila de arriba, respecto a las demás
    junta: 0.16, // lo que queda entre tecla y tecla, en teclas
  };

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

  // Las teclas: cada una es un <span> acomodado en % dentro de .teclas, que mide lo que el teclado entero.
  const cajaTeclas = teclado.querySelector('.teclas');
  const anchoTeclas = 19;
  const altoTeclas = TECLAS.altoFunciones + TECLAS.filas.length - 1;
  teclado.style.setProperty('--proporcion', anchoTeclas / altoTeclas);
  teclado.style.setProperty('--trackpad', -TECLAS.numerico / 2 / anchoTeclas);
  const ponerTecla = (x, y, anchoTecla, altoTecla) => {
    const orilla = TECLAS.junta / 2;
    const tecla = document.createElement('span');
    tecla.style.left = `${((x + orilla) / anchoTeclas) * 100}%`;
    tecla.style.top = `${((y + orilla) / altoTeclas) * 100}%`;
    tecla.style.width = `${((anchoTecla - TECLAS.junta) / anchoTeclas) * 100}%`;
    tecla.style.height = `${((altoTecla - TECLAS.junta) / altoTeclas) * 100}%`;
    cajaTeclas.append(tecla);
  };
  let filaY = 0;
  TECLAS.filas.forEach((fila, i) => {
    const altoFila = i === 0 ? TECLAS.altoFunciones : 1;
    let x = 0;
    for (const pieza of fila.split(' ')) {
      const [medida, veces = 1] = pieza.split('*');
      for (let n = 0; n < veces; n++) {
        if (medida.startsWith('_')) {
          x += Number(medida.slice(1));
          continue;
        }
        const alta = medida.endsWith('^');
        const anchoTecla = Number(alta ? medida.slice(0, -1) : medida);
        ponerTecla(x, filaY, anchoTecla, alta ? altoFila + 1 : altoFila);
        x += anchoTecla;
      }
    }
    if (x !== anchoTeclas) console.error(`escena.js: la fila ${i + 1} del teclado mide ${x} y no ${anchoTeclas}`);
    filaY += altoFila;
  });

  const limitar = (v) => Math.min(1, Math.max(0, v));
  const deMenosAMasUno = (v) => Math.min(1, Math.max(-1, v));
  const tramo = (p, [desde, hasta]) => limitar((p - desde) / (hasta - desde));
  const adentro = (p, [desde, hasta]) => p >= desde && p < hasta;
  const suave = (t) => (t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2);
  const mezclar = (a, b, t) => {
    const r = {};
    for (const clave in a) r[clave] = a[clave] + (b[clave] - a[clave]) * t;
    return r;
  };

  let pendiente = false;
  let cursor = null; // dónde está el mouse en la pantalla; null = fuera de la página
  const mirada = { x: 0, y: 0 }; // los grados de más que lleva ahorita
  let ultimoCuadro = 0;

  function pintar() {
    pendiente = false;
    const anchoPantalla = fija.clientWidth; // sin la barra de desplazamiento
    const altoPantalla = innerHeight;
    // La última pantalla de la escena no cuenta: en ella la hoja de la sección 3 sube encima (hoja.js).
    const recorrido = escena.offsetHeight - fija.offsetHeight * 2;
    const p = recorrido > 0 ? limitar(-escena.getBoundingClientRect().top / recorrido) : 0;

    // La tarjeta: del hueco a todo lo ancho, a la pose del centro y de ahí a la del lado.
    // Se mide la laptop, que es del tamaño de la pantalla (el teclado cuelga de su orilla de abajo).
    const poses = celular.matches ? POSES.celular : POSES.escritorio;
    const ancho = laptop.offsetWidth;
    const alto = laptop.offsetHeight;
    const x0 = laptop.offsetLeft + ancho / 2;
    const y0 = laptop.offsetTop + alto / 2;
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
    const encogida = suave(tramo(p, TRAMOS.encoger));
    const pose = mezclar(mezclar(hueco, enCentro, encogida), alLado, suave(tramo(p, TRAMOS.irseAlLado)));

    // Hacia dónde quiere mirar: el cursor respecto al centro de la tarjeta (a media pantalla de
    // distancia, el giro completo). Crece conforme se encoge: a todo lo ancho, arriba, no se gira.
    const metida = encogida * giro;
    const meta = cursor
      ? {
          x: -deMenosAMasUno((cursor.y - pose.y) / (altoPantalla / 2)) * MIRADA.x * metida,
          y: deMenosAMasUno((cursor.x - pose.x) / (anchoPantalla / 2)) * MIRADA.y * metida,
        }
      : { x: 0, y: 0 };
    const ahora = performance.now();
    const avance = 1 - Math.exp(-Math.min(ahora - ultimoCuadro, 34) / MIRADA.demora);
    ultimoCuadro = ahora;
    mirada.x += (meta.x - mirada.x) * avance;
    mirada.y += (meta.y - mirada.y) * avance;

    // scale3d y no scale: scale() no encoge lo hondo, y el teclado saldría al frente el doble de lo que mide.
    laptop.style.transform =
      `translate(${pose.x - x0}px, ${pose.y - y0}px) perspective(${PROFUNDIDAD * k * ancho}px) ` +
      `rotateX(${pose.rx + mirada.x}deg) rotateY(${pose.ry + mirada.y}deg) rotateZ(${pose.rz}deg) ` +
      `scale3d(${pose.k}, ${pose.k}, ${pose.k})`;
    laptop.style.setProperty('--k', pose.k);

    // Mientras se encoge, a la pantalla le sale el marco y el teclado se desdobla hasta quedar abierto.
    laptop.style.setProperty('--marco', encogida);
    const apertura = BISAGRA.doblada + (BISAGRA.abierta - BISAGRA.doblada) * encogida;
    teclado.style.transform = `rotateX(${180 - apertura}deg)`;

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

    // Si la tarjeta todavía no llega a donde quiere mirar, sigue en el siguiente cuadro.
    if (Math.abs(meta.x - mirada.x) > 0.01 || Math.abs(meta.y - mirada.y) > 0.01) pedirCuadro();
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

  // El cursor: solo el del mouse (con el dedo no hay hacia dónde mirar). Si sale de la página
  // o la ventana pierde el foco, la tarjeta vuelve a su pose.
  addEventListener('pointermove', (e) => {
    if (e.pointerType !== 'mouse') return;
    cursor = { x: e.clientX, y: e.clientY };
    pedirCuadro();
  }, { passive: true });
  const olvidarCursor = () => {
    cursor = null;
    pedirCuadro();
  };
  document.documentElement.addEventListener('mouseleave', olvidarCursor);
  addEventListener('blur', olvidarCursor);
  pintar();
})();
