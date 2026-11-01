// escena.js — la escena de la laptop en la página de Fragmentless (index.html).
// Al bajar, la pantalla se encoge y se gira de lado, el fondo se oscurece (y una franja de luz cambia el azul
// en vivo de pantalla.js por la captura del panel, barrido.js) y sale el texto del centro; luego la tarjeta se
// va a la derecha y sale el texto de la izquierda con su botón (en celular no: ahí se cierra después del texto
// del centro). La tarjeta no sigue al cursor: quieta, su sombra y su luz se ven siempre igual en cada pose.
// La tarjeta es la pantalla de una laptop: mientras se encoge le sale el marco y el teclado se desdobla
// desde su orilla de abajo, y la laptop entera hace los mismos movimientos. Al final la laptop se cierra, la
// cámara gira para verla de frente, se vuelve a abrir con la pantalla en blanco y la cámara avanza hasta que
// esa pantalla llena todo: ahí está la sección 3 (hoja.js). El azul deja de dibujarse solo, en cuanto la
// captura lo tapa (pantalla.js).
// La tarjeta y el fondo los mueve el scroll: cada cuadro se calcula de cuánto has bajado dentro de la
// escena. Los textos no: al llegar a su momento entran solos, con el reloj (style.css), y al pasarlo se van.
(() => {
  const escena = document.querySelector('.escena');
  const fija = escena.querySelector('.escena-fija');
  const noche = escena.querySelector('.noche');
  const laptop = escena.querySelector('.laptop');
  const video = laptop.querySelector('.video');
  const teclado = laptop.querySelector('.teclado');
  const portada = escena.querySelector('.portada-copy');
  const centro = escena.querySelector('.texto-centro');
  const lado = escena.querySelector('.texto-lado');
  const celular = matchMedia('(max-width: 760px)');
  const sinMovimiento = matchMedia('(prefers-reduced-motion: reduce)');

  // Poses de la tarjeta, medidas del video de referencia (pantalla de 1896×916).
  // x, y: dónde queda su centro (fracción de la pantalla). ancho, alto: lo más que puede medir
  // en la portada. rx, ry, rz: giros en grados (ry negativo = el lado izquierdo se va hacia atrás).
  // k: cuánto se encoge respecto a la portada (sin k, nada).
  // La del lado iba más abajo (y: 0.495) y el teclado se cortaba con la orilla de la pantalla: ahora se
  // queda a la altura de la del centro, así se va derecho a la derecha sin bajar y se ve entera.
  // La del centro en escritorio va un poco más chica y más arriba (antes k 1, y 0.413), y su texto un poco
  // más abajo (style.css): con la laptop plateada, el texto blanco le pasaba encima a la base y no se leía.
  // hueco: dónde va en la portada (con el tamaño y los giros de la del centro).
  const POSES = {
    escritorio: {
      hueco: { x: 0.72, y: 0.43 },
      centro: { x: 0.5, y: 0.38, k: 0.86, ancho: 0.497, alto: 0.462, rx: 0, ry: -53, rz: 0 },
      lado: { x: 0.645, y: 0.413, k: 0.9, rx: -9.6, ry: -47.2, rz: 1.8 },
    },
    // En celular no hay pose del lado: después del texto del centro la laptop se cierra ahí mismo (TRAMOS_CELULAR).
    // Ahí x pasa del medio: de lado, el teclado sale hacia la izquierda, y con la pantalla al centro la laptop se
    // veía cargada a ese lado (unos 37 px en 375). Con la laptop entera al centro (x 0.6) se veía cargada a la
    // derecha, porque ahí queda la pantalla, que es lo que más pesa: va a medio camino (como todo en la laptop
    // crece con el ancho, sirve en cualquier celular). En la portada va al centro del espacio que deja el texto
    // debajo de él (pintar() saca su y de dónde termina el texto: en fracción de la pantalla, en un celular bajito
    // quedaba casi pegada al botón).
    celular: {
      hueco: { x: 0.548 },
      centro: { x: 0.55, y: 0.36, ancho: 0.62, alto: 0.42, rx: 0, ry: -40, rz: 0 },
    },
  };
  // La perspectiva mide 3.75 veces el ancho de la tarjeta encogida (también medido).
  const PROFUNDIDAD = 3.75;
  // La bisagra: grados entre la pantalla y el teclado. Arriba, a todo lo ancho, el teclado está doblado
  // hacia atrás, de canto detrás de la pantalla (no se ve); mientras la tarjeta se encoge baja y se abre.
  // Al final se cierra: la pantalla baja sobre el teclado.
  const BISAGRA = { doblada: 270, abierta: 110, cerrada: 0 };

  // Tramos del recorrido: 0 es arriba de la escena y 1 el final.
  const TRAMOS = {
    encoger: [0.025, 0.25],
    eslogan: [0.025, 0.13],
    noche: [0.06, 0.25],
    irseAlLado: [0.48, 0.72],
  };
  // Cuándo se cierra la laptop, en pantallas de scroll contadas desde el final del recorrido (antes es
  // negativo): empieza casi una pantalla antes, al terminar de irse al lado, y queda cerrada un cuarto de
  // pantalla antes del final.
  const CIERRE = [-0.95, -0.25];
  // La cámara, contada igual. Después del recorrido vienen CAMARA pantallas más (style.css alarga la escena) y
  // la última, en la que llega la sección 3 (hoja.js): llega arriba en CAMARA + 1. Ya cerrada, la cámara gira
  // para ver la laptop de frente (GIRO), la laptop se vuelve a abrir con la pantalla en blanco (REABRIR) y la
  // cámara avanza hasta que esa pantalla llena todo (ZOOM), un poco antes de que llegue la sección 3.
  const CAMARA = 1.5;
  const GIRO = [-0.2, 0.7];
  const REABRIR = [0.5, 1.2];
  const ZOOM = [1.15, 2.35];
  // De frente, en dos tiempos (la cámara ve la base desde 20° − rx de alto). Cerrada, desde unos 40° y con más
  // perspectiva (PROFUNDIDAD_FRENTE), para que se vea su fondo y no una tira. Abierta, desde unos 34°, con la
  // perspectiva y la tapa de siempre (echarla más hacia atrás, con la cámara más abajo, se probó y se
  // prefirió así), y más abajo, para quedar centrada con su teclado.
  const FRENTE_CERRADA = { x: 0.5, y: 0.17, k: 0.9, rx: -20, ry: 0, rz: 0 };
  const FRENTE_ABIERTA = { x: 0.5, y: 0.38, k: 0.9, rx: -14, ry: 0, rz: 0 };
  // En celular, de frente, no hay nada más en la pantalla: la laptop va a media altura (y es dónde va el
  // centro de su pantalla; se midió para que la laptop entera quede a la mitad, cerrada y abierta).
  const FRENTE_CELULAR = { cerrada: 0.367, abierta: 0.453 };
  const PROFUNDIDAD_FRENTE = 2.4;
  // En celular, --k (con él las esquinas y las orillas finas se ven siempre igual en pantalla, style.css) solo se
  // cambia cuando la escala varía más de un 10 %: cada cambio repinta la laptop entera, y en el zoom, ya grande en
  // pantalla, el celular no alcanzaba a repintarla en cada cuadro y se trababa. Un 10 % en esquinas de 12 px no se
  // nota, y al llenar todo la escala va tan grande que las esquinas de adentro quedan rectas igual.
  const CAMBIO_K = Math.log(1.1);
  // El bloque lateral también sale; reutiliza el mismo desvanecimiento que el texto central.
  const TEXTOS = {
    centro: [0.25, 0.48],
    lado: [0.62, 0.80],
  };
  // En celular la laptop no se va al lado ni sale el texto de la izquierda: del texto del centro pasa directo a
  // cerrarse, para que la escena no sea tan larga. Su recorrido mide 2.6 pantallas y no 3.5 (style.css acorta la
  // escena), y lo de antes pasa en las mismas pantallas que en escritorio: los tramos se estiran en esa proporción.
  // Así el texto del centro se va justo cuando empieza a cerrarse (CIERRE, que va contado desde el final).
  const RECORRIDO = { escritorio: 3.5, celular: 2.6 };
  const aCelular = (tramo) => tramo.map((v) => (v * RECORRIDO.escritorio) / RECORRIDO.celular);
  const TRAMOS_CELULAR = {
    encoger: aCelular(TRAMOS.encoger),
    eslogan: aCelular(TRAMOS.eslogan),
    noche: aCelular(TRAMOS.noche),
  };
  const TEXTOS_CELULAR = { centro: aCelular(TEXTOS.centro) };

  // Cada palabra de los párrafos que se encienden va en su propio <span> (ver .se-enciende en style.css), con su
  // lugar en --i.
  const partirEnPalabras = (elemento) => {
    const palabras = elemento.textContent.trim().split(/\s+/);
    elemento.replaceChildren();
    palabras.forEach((palabra, i) => {
      const span = document.createElement('span');
      span.textContent = palabra;
      span.style.setProperty('--i', i);
      elemento.append(span, i < palabras.length - 1 ? ' ' : '');
    });
    return palabras.length;
  };
  // Los títulos a los que les pasa el brillo azul (el titular de la portada y .se-brilla en style.css), letra por
  // letra: cada una en su <span>, con su lugar en --i.
  const partirEnLetras = (elemento) => {
    let indice = 0;
    for (const nodo of [...elemento.childNodes]) {
      if (nodo.nodeType !== Node.TEXT_NODE) continue;
      const fragmento = document.createDocumentFragment();
      for (const caracter of nodo.textContent) {
        if (/\s/.test(caracter)) fragmento.append(caracter);
        else {
          const letra = document.createElement('span');
          letra.textContent = caracter;
          letra.style.setProperty('--i', indice++);
          fragmento.append(letra);
        }
      }
      nodo.replaceWith(fragmento);
    }
  };
  // El texto entero sabe cuántas palabras tiene su párrafo, para que sus botones salgan después de la última.
  for (const p of escena.querySelectorAll('.se-enciende')) {
    p.parentElement.style.setProperty('--n', partirEnPalabras(p));
  }
  for (const titulo of escena.querySelectorAll('.se-brilla')) partirEnLetras(titulo);

  // La introducción se ejecuta una vez; no interfiere al abrir un enlace interno.
  const introInicio = performance.now();
  let introTerminada = sinMovimiento.matches || scrollY > 8 || Boolean(location.hash);
  if (!introTerminada) {
    partirEnLetras(portada.querySelector('h1'));
    partirEnPalabras(portada.querySelector('.portada-resumen'));
    document.documentElement.classList.add('intro-activa');
  }

  const limitar = (v) => Math.min(1, Math.max(0, v));
  const tramo = (p, [desde, hasta]) => limitar((p - desde) / (hasta - desde));
  const adentro = (p, [desde, hasta]) => p >= desde && p < hasta;
  const suave = (t) => (t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2);
  // Más pareja que suave(): a medio camino va a la mitad de su prisa
  const delicada = (t) => (1 - Math.cos(Math.PI * t)) / 2;
  const mezclar = (a, b, t) => {
    const r = {};
    for (const clave in a) r[clave] = a[clave] + (b[clave] - a[clave]) * t;
    return r;
  };

  let pendiente = false;
  let kPuesta = 0; // la última escala que se le pasó a --k

  function pintar() {
    pendiente = false;
    const anchoPantalla = fija.clientWidth; // sin la barra de desplazamiento
    const altoPantalla = innerHeight;
    // El recorrido no cuenta las pantallas de la cámara ni la última, en la que llega la sección 3 (hoja.js)
    const recorrido = escena.offsetHeight - fija.offsetHeight * (2 + CAMARA);
    const bajado = -escena.getBoundingClientRect().top;
    const p = recorrido > 0 ? limitar(bajado / recorrido) : 0;
    const introTiempo = performance.now() - introInicio;
    if (!introTerminada && (introTiempo >= 1900 || p > .025 || sinMovimiento.matches)) {
      introTerminada = true;
      document.documentElement.classList.remove('intro-activa');
    }
    const abrirIntro = introTerminada ? 1 : suave(limitar((introTiempo - 200) / 1500));
    // Cuántas pantallas lleva después del recorrido (antes es negativo): con esto van el cierre y la cámara.
    const despues = (bajado - recorrido) / fija.offsetHeight;

    // La tarjeta: del hueco a todo lo ancho, a la pose del centro y de ahí a la del lado (en celular no).
    // Se mide la laptop, que es del tamaño de la pantalla (el teclado cuelga de su orilla de abajo).
    const poses = celular.matches ? POSES.celular : POSES.escritorio;
    const tramos = celular.matches ? TRAMOS_CELULAR : TRAMOS;
    const textos = celular.matches ? TEXTOS_CELULAR : TEXTOS;
    const ancho = laptop.offsetWidth;
    const alto = laptop.offsetHeight;
    const x0 = laptop.offsetLeft + ancho / 2;
    const y0 = laptop.offsetTop + alto / 2;
    const k = Math.min(poses.centro.ancho * anchoPantalla / ancho, poses.centro.alto * altoPantalla / alto);
    const giro = sinMovimiento.matches ? 0 : 1;
    // En celular, la laptop entera al centro del espacio debajo del texto. y es dónde va el centro de su pantalla,
    // que de lado queda un cuarto de su alto arriba del centro de la laptop entera (medido).
    const yHueco = poses.hueco.y === undefined
      ? (portada.offsetTop + portada.offsetHeight + altoPantalla) / 2 - 0.25 * k * alto
      : poses.hueco.y * altoPantalla;
    const hueco = {
      x: poses.hueco.x * anchoPantalla, y: yHueco, k,
      rx: poses.centro.rx * giro, ry: poses.centro.ry * giro, rz: poses.centro.rz * giro,
    };
    const enCentro = {
      x: poses.centro.x * anchoPantalla, y: poses.centro.y * altoPantalla, k: k * (poses.centro.k ?? 1),
      rx: poses.centro.rx * giro, ry: poses.centro.ry * giro, rz: poses.centro.rz * giro,
    };
    const encogida = suave(tramo(p, tramos.encoger));
    let pose = mezclar(hueco, enCentro, encogida);
    if (poses.lado) {
      const alLado = {
        x: poses.lado.x * anchoPantalla, y: poses.lado.y * altoPantalla, k: k * poses.lado.k,
        rx: poses.lado.rx * giro, ry: poses.lado.ry * giro, rz: poses.lado.rz * giro,
      };
      pose = mezclar(pose, alLado, suave(tramo(p, tramos.irseAlLado)));
    }

    // La cámara. Ya cerrada, gira hasta verla de frente (en realidad gira la laptop, que es lo mismo), y
    // mientras se abre baja y la acomoda al centro.
    const enPantalla = (frente) => ({
      x: frente.x * anchoPantalla, y: frente.y * altoPantalla, k: k * frente.k,
      rx: frente.rx * giro, ry: frente.ry * giro, rz: frente.rz * giro,
    });
    const frenteCerrada = celular.matches ? { ...FRENTE_CERRADA, y: FRENTE_CELULAR.cerrada } : FRENTE_CERRADA;
    const frenteAbierta = celular.matches ? { ...FRENTE_ABIERTA, y: FRENTE_CELULAR.abierta } : FRENTE_ABIERTA;
    const girada = suave(tramo(despues, GIRO));
    pose = mezclar(pose, enPantalla(frenteCerrada), girada);
    const reabierta = delicada(tramo(despues, REABRIR));
    pose = mezclar(pose, enPantalla(frenteAbierta), reabierta);
    // Llena: la pantalla de frente, tan grande que lo de adentro del marco cubre toda la pantalla del usuario.
    // El marco mide 2.6 % del lado corto de la pantalla arriba y a los lados, y 4.4 % abajo (style.css).
    const ladoCorto = Math.min(ancho, alto);
    const bisel = 0.026 * ladoCorto;
    const biselAbajo = 0.044 * ladoCorto;
    const kLlena = Math.max(anchoPantalla / (ancho - 2 * bisel), altoPantalla / (alto - bisel - biselAbajo)) * 1.01;
    const llena = { x: anchoPantalla / 2, y: altoPantalla / 2 - kLlena * (bisel - biselAbajo) / 2, k: kLlena };
    // El zoom: el tamaño crece parejo en escala de veces (como una cámara que avanza), y el centro se va
    // corriendo al de la pantalla al mismo paso que se agranda, para no barrer de lado.
    const zoom = suave(tramo(despues, ZOOM));
    if (zoom > 0) {
      const kz = Math.exp(Math.log(pose.k) + Math.log(llena.k / pose.k) * zoom);
      const avance = (1 / kz - 1 / pose.k) / (1 / llena.k - 1 / pose.k);
      pose = {
        x: pose.x + (llena.x - pose.x) * avance, y: pose.y + (llena.y - pose.y) * avance, k: kz,
        rx: pose.rx * (1 - zoom), ry: pose.ry * (1 - zoom), rz: pose.rz * (1 - zoom),
      };
    }

    // Mientras se encoge, a la pantalla le sale el marco y el teclado se desdobla hasta quedar abierto.
    // Al final se cierra: la pantalla gira sobre su orilla de abajo (la bisagra) hacia el teclado, y el
    // teclado gira lo mismo al revés para quedarse quieto. De frente se vuelve a abrir igual; con la cámara a
    // 0°, al llenar todo la pantalla queda de frente.
    laptop.style.setProperty('--marco', 1);
    const desdoblada = BISAGRA.abierta;
    const angulo = reabierta > 0
      ? desdoblada * reabierta
      : desdoblada + (BISAGRA.cerrada - desdoblada) * delicada(tramo(despues, CIERRE));
    const apertura = angulo * abrirIntro;
    teclado.style.transform = `rotateX(${180 - apertura}deg)`;
    // Ya cerrada, la pantalla cambia la captura del panel por el blanco de la sección 3 (style.css)
    laptop.toggleAttribute('data-seccion', despues > CIERRE[1]);

    // Cerrada de frente la perspectiva es más fuerte (la cámara más cerca), para que se note su fondo: con la
    // de siempre se veía como una tira. Mientras se abre regresa a la de siempre.
    const profundidad = PROFUNDIDAD + (PROFUNDIDAD_FRENTE - PROFUNDIDAD) * girada * (1 - reabierta);
    // scale3d y no scale: scale() no encoge lo hondo, y el teclado saldría al frente el doble de lo que mide.
    laptop.style.transform =
      `translate(${pose.x - x0}px, ${pose.y - y0}px) perspective(${profundidad * k * ancho}px) ` +
      `rotateX(${pose.rx}deg) rotateY(${pose.ry}deg) rotateZ(${pose.rz}deg) ` +
      `scale3d(${pose.k}, ${pose.k}, ${pose.k}) ` +
      `translateY(${alto / 2}px) rotateX(${apertura - desdoblada}deg) translateY(${-alto / 2}px)`;
    if (!celular.matches || Math.abs(Math.log(pose.k / kPuesta)) > CAMBIO_K) {
      kPuesta = pose.k;
      laptop.style.setProperty('--k', pose.k);
    }

    // El eslogan se va.
    const quedaEslogan = 1 - tramo(p, tramos.eslogan);
    portada.style.opacity = quedaEslogan;
    portada.style.transform = `translateY(${-24 * (1 - quedaEslogan)}px)`;
    portada.inert = quedaEslogan < .1;
    portada.style.visibility = quedaEslogan === 0 ? 'hidden' : 'visible';

    // El fondo pasa a negro, y a la mitad la pantalla cambia del azul al panel.
    const oscuro = delicada(tramo(p, tramos.noche));
    noche.style.opacity = oscuro;
    laptop.style.setProperty('--oscuro', oscuro); // enciende el piso de luz debajo de la laptop
    // La luz del fondo (style.css): de alto, un poco arriba de la bisagra de la pose del centro, y no se
    // mueve; de lado sigue a la laptop, al centro de su silueta (el teclado sale hacia la izquierda de la
    // pantalla, por eso se corre de pose.x).
    noche.style.setProperty('--luz-y', `${enCentro.y + alto * enCentro.k / 2 - altoPantalla * 0.07}px`);
    // En celular, durante el zoom se queda donde estaba: moverla repinta todo el fondo en cada cuadro, y la laptop ya
    // lo va tapando.
    if (!celular.matches || zoom === 0) noche.style.setProperty('--luz-x', `${pose.x - ancho * pose.k * 0.2}px`);
    // El cambio lo hace una franja de luz que cruza la pantalla (barrido.js): aquí solo se dice cuál toca
    video.toggleAttribute('data-panel', oscuro >= 0.5);
    // Con el zoom, la pantalla blanca va cubriendo todo: la barra regresa a letra negra
    document.documentElement.toggleAttribute('data-noche', oscuro >= 0.5 && zoom < 0.6);

    // Los textos: aquí solo se decide si están dentro; la animación la hace style.css. El del centro
    // se va cuando la tarjeta empieza a moverse, y el de la izquierda entra cuando ya va llegando.
    centro.toggleAttribute('data-dentro', adentro(p, textos.centro));
    lado.toggleAttribute('data-dentro', Boolean(textos.lado) && adentro(p, textos.lado));

    // Mientras dura la entrada (va con el reloj, no con el scroll), sigue en el siguiente cuadro.
    if (!introTerminada) pedirCuadro();
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
  // Ya acomodada la laptop, se muestra (style.css la esconde hasta aquí).
  document.documentElement.setAttribute('data-escena', '');
})();
