// lanzamiento.js — la sección 3 de la página (index.html), como el «hero launch» de snapcn (una composición de
// Remotion), pero en blanco, sin Remotion y con el scroll en lugar del reloj. Antes era la fila curva de capturas
// (hoja.js). Llega cuando la pantalla blanca de la laptop ya llena todo: la sección toca el borde de arriba
// y sobre ese blanco aparece la primera tarjeta, a todo lo ancho, con una frase que tiene una imagen en medio que
// cambia entre tres. Al bajar se aleja a su tamaño, la frase se va y sus imágenes forman un anillo que se da
// vuelta; se inclina sobre su orilla de adentro y se va a la izquierda. La segunda entra por la derecha,
// inclinada al revés, con un remolino de imágenes alrededor de una frase. Las imágenes del anillo se amontonan y
// queda una sola. Las dos bajan un poco y sale el título.
// Lo de adentro de las tarjetas no lo inventa el original: en su ejemplo son dos videos. Aquí se arma con
// imágenes, que por ahora no hay.
// El scroll mueve las tarjetas, el título y lo que cuenta algo en orden (las imágenes de la frase), así no se
// pierde nada aunque se baje rápido. Lo de adentro de las tarjetas se mueve solo, como el video que es en el
// original: donde uno se detenga, sigue vivo.
// Las medidas son las del original (una escena de 1280 × 720); los momentos, en fracciones del recorrido de la
// sección después de la frase.
(() => {
  const seccion = document.querySelector('.lanzamiento');
  const fija = seccion.querySelector('.lanzamiento-fija');
  const grupo = seccion.querySelector('.lanzamiento-grupo');
  const izq = seccion.querySelector('.tarjeta-izq');
  const der = seccion.querySelector('.tarjeta-der');
  const intro = seccion.querySelector('.intro');
  const introFrase = intro.querySelector('.intro-frase');
  const introImagenes = [...seccion.querySelectorAll('.intro-imagenes img')];
  const marcoFrase = seccion.querySelector('.intro-imagenes');
  const capaOrbita = seccion.querySelector('.orbita');
  const centroOrbita = seccion.querySelector('.orbita-centro');
  const centroRemolino = seccion.querySelector('.remolino-centro');
  const orillas = seccion.querySelector('.lanzamiento-orillas');
  const texto = seccion.querySelector('.lanzamiento-texto');
  const titulo = texto.querySelector('h2');
  const filaBarra = document.querySelector('.barra-fila');
  const celular = matchMedia('(max-width: 760px)');
  const sinMovimiento = matchMedia('(prefers-reduced-motion: reduce)');

  // El brillo azul de la barra y el footer pasa por la frase con el scroll y por el título en cuanto queda nítido
  // (en el CSS), letra por letra de izquierda a derecha: cada letra en su span, con su lugar (--i). En la frase se
  // cuentan los dos lados seguidos, saltando la imagen. Devuelve cuántas letras son.
  const separarLetras = (textos) => {
    let letra = 0;
    for (const texto of textos) {
      texto.replaceChildren(...[...texto.textContent].map((caracter) => {
        if (caracter === ' ') return ' ';
        const span = document.createElement('span');
        span.className = 'brilla';
        span.style.setProperty('--i', letra++);
        span.textContent = caracter;
        return span;
      }));
    }
    return letra;
  };
  const letrasFrase = separarLetras(introFrase.querySelectorAll(':scope > span:not(.intro-imagenes)'));
  separarLetras([titulo]);
  // Lo que dura el brillo de la frase de la primera letra a la última (con los mismos .4s por letra y 18 ms entre
  // una y otra del CSS): el scroll lo recorre a lo largo del tramo de la frase.
  const BRILLO_FRASE = 400 + (letrasFrase - 1) * 18;

  // Las imágenes del anillo de la primera tarjeta y las del remolino de la segunda, cada una { src }. La primera
  // del anillo es la que se queda sola al final. Por ahora el anillo lleva las tres de la frase, repetidas, y empieza
  // por la última de la frase, que es la que se ve cuando sale el anillo y por la que se cambia la que se quedó
  // sola al subir. Las suyas van a llegar hechas para él; vacía, van colores de relleno. El remolino lleva las
  // capturas del panel, que se repiten en orden (son provisionales: el panel ya ofrece más cosas).
  const IMAGENES = ['cuentas', 'libreta', 'mesera'].map((foto) => ({ src: `prueba/tarjeta-${foto}.webp` }));
  const IMAGENES_REMOLINO = [
    'sesion', 'inicio', 'menu', 'mesas', 'agente', 'contenido', 'biblioteca',
  ].map((vista) => ({ src: `prueba/vista-${vista}.webp` }));

  // La frase va primero, con su propio tramo de scroll (FRASE pantallas, que el CSS suma al alto de la sección):
  // cada una de sus tres imágenes dura PASO_IMAGEN de pantalla y la última se queda hasta que empieza lo demás.
  const FRASE = 0.75;
  const PASO_IMAGEN = 0.25;
  // La primera tarjeta empieza a todo lo ancho, debajo de la barra y ASOMA pixeles de la escena original más
  // abajo, con su orilla de arriba a la vista y el blanco de la página detrás, como en el original (allá sin
  // barra). No se mueve al llegar: aparece de la nada (en el CSS).
  const ASOMA = 40;

  // Grados que se inclina cada tarjeta, sobre su orilla de adentro (solo de lado, así esas dos orillas se quedan
  // derechas y el hueco del centro es parejo), y el hueco entre las dos, en pixeles de la escena original.
  const INCLINACION = 17;
  const HUECO = 92;
  // Como en el original, la frase se queda mientras la tarjeta empieza a alejarse, y se va antes de que se incline
  // hacia la izquierda.
  const TRAMOS = {
    seVaLaFrase: [0.07, 0.12],
    // Lo del anillo se apaga en la segunda mitad de lo que tarda en salir la frase, al subir: así no se enciman
    seApagaElAnillo: [0.095, 0.12],
    alejarse: [0.06, 0.24],
    irseALaIzquierda: [0.1, 0.3],
    entrarLaDerecha: [0.18, 0.4],
    bajar: [0.6, 0.78],
    // Las sombras de las dos empiezan a salir un poco antes de que bajen y ya están completas antes de que se
    // acomoden: con la curva de la bajada salían tarde
    sombras: [0.55, 0.7],
    titulo: [0.62, 0.84],
  };
  // El anillo de la primera tarjeta no va con el scroll: corre solo, como un video. El scroll solo dice qué parte
  // toca: se forma y se da vuelta en cuanto se va la frase, y se amontona cuando la segunda ya entró y ahí se
  // queda. Al regresar se deshace al revés.
  // Juntarse en una sí va con el scroll, mientras caen las dos tarjetas (TRAMOS.bajar), como en el original: así,
  // por rápido que se baje, cuando ya cayeron queda una sola. Solo corriendo sola, iba atrasada.
  const SALE_EL_ANILLO = 0.1;
  const SE_AMONTONA = 0.42;

  const crearImagen = ({ src }) => {
    const img = document.createElement('img');
    img.src = src;
    img.alt = '';
    img.decoding = 'async';
    return img;
  };

  // La tarjeta clara: el anillo del componente «Orbit Flip Slider» de 21st.dev (Hyperiux Vault) en su modo Ring,
  // con los números de su demo. Las imágenes van en un anillo inclinado, todas planas y de frente; las de enfrente,
  // más grandes y encima, y el anillo gira despacio. Como en el original, primero salen de una en una, muy rápido,
  // formando el anillo mirando a la derecha (el del componente al espejo); luego se da vuelta y mira a la izquierda,
  // como el del componente; al final se amontonan parejas, una detrás de otra, y se juntan en una sola. Al subir ya
  // no se arma otra vez: la que se quedó va al centro y se vuelve la imagen de la frase.
  // Las medidas son pixeles del componente; ESCALA_ORBITA dice cuántos cqw de la tarjeta mide cada uno.
  const ORBITA = {
    imagenes: 16,
    ancho: 90,
    alto: 140,
    hueco: 0,
    inclinacion: 31, // ringRotateX
    desfase: 56, // ringRotateY: en qué lugar del anillo va la primera
    giroPlano: -25, // ringRotateZ
    radioX: 1.5,
    radioY: 1.2,
    escala: 1,
    velocidad: 4, // rotateSpeed: grados por segundo
  };
  const ESCALA_ORBITA = 0.078;
  // Dónde va el centro del anillo en la tarjeta, en %: en medio de lo que se ve de ella cuando ya se fue a la
  // izquierda, y un poco arriba, porque las de enfrente bajan. Lo que se ve depende de la ventana: se acomodó a ojo
  // en una como las de siempre (1920 × 960, más ancha que la escena), donde las grandes de enfrente cargan el
  // anillo a la derecha; en una de 16:9 justo queda más a la izquierda.
  const CENTRO_ORBITA = { x: 54, y: 46 };
  // La pila: la primera adelante (la que se queda) y las demás una detrás de otra, parejas, hacia el fondo: como
  // en el original, cada una más chica y más cerca de un punto arriba a la derecha (fugaX, fugaY, desde la de
  // adelante), así las de atrás se van juntando. fondo: cuánto más lejos va cada una.
  // s es el tamaño, con 1 el de la demo; la de adelante es más grande que las del anillo, como en el original.
  // x y y van desde el centro del anillo: la de adelante cae al 52.6 % de la tarjeta.
  const PILA = { x: -18, y: -10, s: 2.6, fugaX: 420, fugaY: -260, fondo: 0.12 };
  // Cuánto dura cada parte, en segundos. Amontonarse dura lo que tarda el componente al cambiar de modo (0.9 s, y
  // cada imagen 0.015 s después de la anterior); darse vuelta, menos, porque así se veía lenta.
  const SALE_CADA = 0.05; // entre una imagen y la siguiente al formar el anillo
  const SALE_EN = 0.25; // lo que tarda cada una en aparecer
  const VUELTA = 0.6;
  const CAMBIO = 0.9;
  const ESCALON = 0.015;
  const REGRESO = 3; // al regresar va tantas veces más rápido
  // Toda la secuencia va tantas veces más rápido que con esos tiempos: con los del componente se veía lenta. El
  // giro del anillo no cambia.
  const RITMO = 2;
  // Lo que tardan todas, con la diferencia entre la primera y la última
  const vueltaCompleta = VUELTA + ESCALON * (ORBITA.imagenes - 1);
  const cambio = CAMBIO + ESCALON * (ORBITA.imagenes - 1);
  const MOMENTOS = {};
  MOMENTOS.vuelta = SALE_CADA * (ORBITA.imagenes - 1) + SALE_EN + 0.5;
  MOMENTOS.pila = MOMENTOS.vuelta + vueltaCompleta + 0.4; // aquí espera, girando, a que toque amontonarse
  MOMENTOS.fin = MOMENTOS.pila + cambio; // y aquí se quedan, amontonadas

  const radian = (grados) => (grados * Math.PI) / 180;
  // La cuenta del componente: el radio sale de cuántas imágenes son, y en el modo Ring va un poco más grande
  const lado = Math.max(ORBITA.ancho, ORBITA.alto) + ORBITA.hueco;
  const radioOrbita = 1.12 * Math.max(((ORBITA.imagenes * lado) / (2 * Math.PI)) * 0.62, lado * 0.9);
  // Dónde va la imagen i: x, y de su centro, desde el centro del anillo; s, su tamaño; capa, su z-index.
  // Como en el componente, el anillo se inclina en 3D, la cercanía agranda la imagen y la separa del centro, y luego
  // se estira (radioX, radioY) y se gira en el plano. Al espejo, mira hacia el otro lado.
  function enAnillo(i, alEspejo) {
    const camara = radioOrbita * 1.75;
    const angulo = radian(-90 + ORBITA.desfase + giroOrbita + (i / ORBITA.imagenes) * 360);
    const inclinacion = radian(ORBITA.inclinacion);
    const fondo = -radioOrbita * Math.cos(angulo);
    const cerca = Math.max(camara / (camara + fondo * Math.cos(inclinacion)), 0.05);
    const separa = 1 + (cerca - 1) * 0.45;
    const x = radioOrbita * Math.sin(angulo) * separa * ORBITA.radioX * ORBITA.escala;
    const y = -fondo * Math.sin(inclinacion) * separa * ORBITA.radioY * ORBITA.escala;
    const plano = radian(ORBITA.giroPlano);
    const xGirada = x * Math.cos(plano) - y * Math.sin(plano);
    return {
      x: alEspejo ? -xGirada : xGirada,
      y: x * Math.sin(plano) + y * Math.cos(plano),
      s: (1 + (cerca - 1) * 0.42) * ORBITA.escala,
      capa: Math.round(cerca * 1000) + 1,
    };
  }
  const enPila = (k) => {
    const cerca = 1 / (1 + k * PILA.fondo);
    return {
      x: PILA.x + PILA.fugaX * (1 - cerca), y: PILA.y + PILA.fugaY * (1 - cerca), s: PILA.s * cerca, capa: 2000 - k,
    };
  };
  // power3.inOut de GSAP, la curva con que el componente cambia de modo
  const CAMBIA = (x) => (x < 0.5 ? 4 * x ** 3 : 1 - (-2 * x + 2) ** 3 / 2);

  // Miden lo de la de adelante de la pila, la más grande, y se achican con scale: así una imagen nunca se estira
  // más de su tamaño y no se ve borrosa
  centroOrbita.style.setProperty('--ancho', `${ORBITA.ancho * PILA.s * ESCALA_ORBITA}cqw`);
  centroOrbita.style.setProperty('--alto', `${ORBITA.alto * PILA.s * ESCALA_ORBITA}cqw`);
  centroOrbita.style.left = `${CENTRO_ORBITA.x}%`;
  centroOrbita.style.top = `${CENTRO_ORBITA.y}%`;
  const piezasOrbita = Array.from({ length: ORBITA.imagenes }, (_, i) => {
    const el = document.createElement('div');
    el.className = 'orbita-pieza';
    el.style.setProperty('--tinte', `hsl(${(i * 47) % 360} 42% 64%)`);
    if (IMAGENES.length > 0) el.append(crearImagen(IMAGENES[i % IMAGENES.length]));
    centroOrbita.append(el);
    return el;
  });

  // reloj: en qué segundo de la secuencia va; objetivo: hasta dónde toca llegar (lo pone el scroll); giroOrbita:
  // cuánto ha girado el anillo, en grados. Y del scroll: junta, de 0 a 1, cuánto se han juntado en una; soloUna,
  // si ya se juntaron (de ahí en adelante solo queda esa); enLaFrase, de 0 a 1, cuánto ha ido esa al lugar de la
  // imagen de la frase; ranura, el tamaño de esa imagen, en la escala de las piezas.
  let reloj = 0;
  let objetivo = 0;
  let giroOrbita = 0;
  let junta = 0;
  let soloUna = false;
  let enLaFrase = 0;
  let ranura = 1;

  function pintarOrbita() {
    const primera = enPila(0);
    if (soloUna) {
      // La de adelante, del lugar de la pila al centro de la tarjeta (en cqw de lado y en cqh hacia abajo, porque el
      // centro del anillo está en % de la tarjeta) y del tamaño de la imagen de la frase
      const x = mezclar(primera.x * ESCALA_ORBITA, 50 - CENTRO_ORBITA.x, enLaFrase);
      const y = primera.y * ESCALA_ORBITA * (1 - enLaFrase);
      const abajo = (50 - CENTRO_ORBITA.y) * enLaFrase;
      piezasOrbita[0].style.transform =
        `translate(${x}cqw, calc(${y}cqw + ${abajo}cqh)) scale(${mezclar(1, ranura, enLaFrase)})`;
      piezasOrbita.forEach((el, i) => { el.style.opacity = i === 0 ? 1 : 0; });
      return;
    }
    piezasOrbita.forEach((el, i) => {
      const aparece = limitar((reloj - i * SALE_CADA) / SALE_EN);
      const daLaVuelta = CAMBIA(limitar((reloj - MOMENTOS.vuelta - i * ESCALON) / VUELTA));
      const amontona = CAMBIA(limitar((reloj - MOMENTOS.pila - i * ESCALON) / CAMBIO));
      const derecha = enAnillo(i, true);
      const izquierda = enAnillo(i, false);
      const pila = enPila(i);
      // De un lugar a otro en línea recta, como Flip; la capa cambia de golpe al empezar, como en el componente
      const lugar = (dato) => mezclar(
        mezclar(mezclar(derecha[dato], izquierda[dato], daLaVuelta), pila[dato], amontona), primera[dato], junta,
      );
      const s = lugar('s') * (0.9 + 0.1 * aparece);
      el.style.transform =
        `translate(${lugar('x') * ESCALA_ORBITA}cqw, ${lugar('y') * ESCALA_ORBITA}cqw) scale(${s / PILA.s})`;
      el.style.zIndex = amontona > 0 ? pila.capa : izquierda.capa;
      // Las de atrás se apagan cuando ya casi están detrás de la de adelante: así no se suman sus sombras
      el.style.opacity = aparece * (i === 0 ? 1 : 1 - limitar((junta - 0.6) / 0.4));
    });
  }

  // El anillo gira mientras se ve como anillo: no mientras se da vuelta (el componente también se detiene) ni ya
  // amontonado
  const giraElAnillo = () =>
    reloj > 0 && reloj <= MOMENTOS.pila && (reloj <= MOMENTOS.vuelta || reloj >= MOMENTOS.vuelta + vueltaCompleta);
  let orbitando = false;
  let seVeOrbita = false;
  let antesOrbita = 0;
  function orbitar(ahora) {
    if (!seVeOrbita) {
      orbitando = false;
      return;
    }
    const segundos = Math.min(0.1, Math.max(0, (ahora - antesOrbita) / 1000));
    antesOrbita = ahora;
    if (giraElAnillo()) giroOrbita += ORBITA.velocidad * segundos;
    reloj = reloj < objetivo
      ? Math.min(objetivo, reloj + segundos * RITMO)
      : Math.max(objetivo, reloj - segundos * RITMO * REGRESO);
    pintarOrbita();
    if (reloj === objetivo && !giraElAnillo()) {
      orbitando = false;
      return;
    }
    requestAnimationFrame(orbitar);
  }
  // Solo corre mientras la tarjeta se ve; con «reducir movimiento» va directo a como queda
  function ponerAOrbitar(seVe) {
    seVeOrbita = seVe;
    if (sinMovimiento.matches) {
      reloj = objetivo;
      pintarOrbita();
      return;
    }
    if (!seVe || orbitando || (reloj === objetivo && !giraElAnillo())) return;
    orbitando = true;
    antesOrbita = performance.now();
    requestAnimationFrame(orbitar);
  }

  // La tarjeta oscura: el anillo de imágenes del componente «Image Arc» de 21st.dev (tweenly-image-arc), otro
  // igual más chico adentro y una espiral de chiquitas al centro, alrededor de su frase. Las imágenes van como en el
  // componente: parejas, a la misma distancia, del mismo tamaño (en proporción a su anillo) y mirando hacia afuera;
  // solo que son capturas del panel, horizontales, y cada pieza se alarga hacia el centro (en el CSS). Giran al
  // revés del reloj, como en el original, y más rápido que en el componente (allá, una vuelta en 80 s); el de
  // adentro, un poco más.
  // Las medidas, en cqw de la tarjeta.
  const REMOLINO = {
    tamano: 0.26, // ancho de las imágenes, en fracción del radio de su anillo, como en el componente
    hueco: 0.067, // espacio entre ellas sobre el anillo, en fracción del radio (sus 28 px con su radio de 420)
    anillos: [
      // El de afuera, tan grande como en el original: casi todo se sale de la tarjeta y de él se ve sobre todo su
      // fila de la izquierda, pegada a la orilla
      { radio: 46, giro: 24 }, // giro: grados por segundo
      // El de adentro lleva menos de las que le caben: en el original van más separadas que afuera, con casi el
      // ancho de una imagen entre una y otra
      { radio: 22, giro: 32, imagenes: 12 },
    ],
    // Y al centro, chiquitas en espiral, como en el original: un círculo que se va cerrando, cada una un poco más
    // adentro y más chica que la anterior (de «radio» a «hasta»), lejos del segundo anillo. Van avanzando por la
    // espiral: solo la última se va hasta el centro, como succionada, y desaparece, y por fuera entra una nueva.
    // «segundos»: lo que tarda cada una en llegar al lugar de la siguiente.
    centro: { radio: 11, hasta: 5, giro: 40, imagenes: 7, segundos: 1.2 },
  };
  // Cuántas caben en un anillo, con la cuenta del componente (en proporción, las mismas en cualquier tamaño)
  const CABEN = Math.floor((2 * Math.PI) / (REMOLINO.tamano + REMOLINO.hueco));
  const radioAfuera = REMOLINO.anillos[0].radio;
  centroRemolino.style.setProperty('--ancho', `${REMOLINO.tamano * radioAfuera}cqw`);
  let cuenta = 0;
  const crearPieza = () => {
    const i = cuenta++;
    const el = document.createElement('div');
    el.className = 'remolino-pieza';
    // El color de relleno del componente
    el.style.setProperty('--tinte', `hsl(${(i * 47) % 360} 42% 52% / .4)`);
    if (IMAGENES_REMOLINO.length > 0) el.append(crearImagen(IMAGENES_REMOLINO[i % IMAGENES_REMOLINO.length]));
    centroRemolino.append(el);
    return el;
  };
  // Cada anillo gira junto; cada pieza tiene su radio y su lugar en él (desfase)
  const anillo = ({ radio, giro, imagenes = CABEN }, k) => ({
    giro: (giro * Math.PI) / 180,
    // Uno sí y otro no, corrido media imagen
    angulo: (k * Math.PI) / imagenes,
    piezas: Array.from({ length: imagenes }, (_, j) => ({
      el: crearPieza(), radio, desfase: (j / imagenes) * 2 * Math.PI,
    })),
  });
  const grupos = REMOLINO.anillos.map(anillo);
  // La espiral también gira junta; cada pieza sabe en qué lugar de la espiral va (0 es el de afuera)
  const { centro } = REMOLINO;
  grupos.push({
    giro: (centro.giro * Math.PI) / 180,
    angulo: 0,
    espiral: centro,
    avance: 0,
    piezas: Array.from({ length: centro.imagenes }, (_, lugar) => ({ el: crearPieza(), lugar })),
  });

  const transformar = (angulo, r) => `rotate(${angulo}rad) translateY(${-r}cqw) scale(${r / radioAfuera})`;

  // Cada pieza avanza por la espiral hasta el último lugar, y de ahí se va al centro, cada vez más rápido,
  // achicándose y apagándose; al llegar vuelve a entrar por fuera. Como van a un lugar de distancia, solo una se va
  // al centro a la vez.
  function moverEspiral(grupo, segundos) {
    const { radio, hasta, imagenes, segundos: paso } = grupo.espiral;
    const ultimo = imagenes - 1;
    grupo.avance = (grupo.avance + segundos / paso) % imagenes;
    for (const { el, lugar } of grupo.piezas) {
      const donde = (lugar + grupo.avance) % imagenes;
      const ida = Math.max(0, donde - ultimo); // de 0 a 1, del último lugar al centro
      const r = radio * (hasta / radio) ** (Math.min(donde, ultimo) / ultimo) * (1 - ida * ida);
      // Hacia adentro la espiral avanza en el sentido del giro, como un remolino que se traga lo de afuera
      el.style.transform = transformar(grupo.angulo - (donde / imagenes) * 2 * Math.PI, r);
      el.style.opacity = limitar(donde / 0.3) * (1 - ida);
    }
  }

  function moverRemolino(segundos) {
    for (const grupo of grupos) {
      grupo.angulo -= grupo.giro * segundos;
      if (grupo.espiral) {
        moverEspiral(grupo, segundos);
        continue;
      }
      for (const { el, radio, desfase } of grupo.piezas) {
        el.style.transform = transformar(grupo.angulo + desfase, radio);
      }
    }
  }

  // No va con el scroll: corre solo, como un video, mientras la tarjeta oscura se ve, y con «reducir movimiento»
  // se queda quieto
  let girando = false;
  let antes = 0;
  function girar(ahora) {
    if (!girando) return;
    // Sin brincos si el navegador dejó de pintar un rato (por ejemplo, en otra pestaña)
    moverRemolino(Math.min(0.1, Math.max(0, (ahora - antes) / 1000)));
    antes = ahora;
    requestAnimationFrame(girar);
  }
  function ponerAGirar(seVe) {
    const toca = seVe && !sinMovimiento.matches;
    if (toca === girando) return;
    girando = toca;
    if (!girando) return;
    antes = performance.now();
    requestAnimationFrame(girar);
  }

  // Las curvas del original: SALIDA llega rápido y se asienta suave (cubic-bezier(.22, 1, .36, 1)); CAIDA
  // acelera, como algo que cae (cubic-bezier(.5, 0, .9, .4)).
  const curva = (x1, y1, x2, y2) => {
    const punto = (a, b, t) => 3 * a * t * (1 - t) ** 2 + 3 * b * (1 - t) * t * t + t ** 3;
    return (x) => {
      if (x <= 0) return 0;
      if (x >= 1) return 1;
      let desde = 0;
      let hasta = 1;
      let t = x;
      for (let i = 0; i < 24; i++) {
        t = (desde + hasta) / 2;
        if (punto(x1, x2, t) < x) desde = t;
        else hasta = t;
      }
      return punto(y1, y2, t);
    };
  };
  const SALIDA = curva(0.22, 1, 0.36, 1);
  const CAIDA = curva(0.5, 0, 0.9, 0.4);

  const limitar = (v) => Math.min(1, Math.max(0, v));
  const tramo = (p, [desde, hasta]) => limitar((p - desde) / (hasta - desde));
  const mezclar = (a, b, t) => a + (b - a) * t;

  // En escritorio la escena original cabe completa en la ventana (s: cuánto mide uno de sus pixeles) y se
  // centra. En celular a lo alto no caben una junto a la otra (se veían solo sus orillas de adentro): van una
  // encima de la otra (vertical), a lo ancho de la pantalla, con el título arriba. La primera se va hacia arriba y
  // la segunda entra por abajo; las dos bajan lo que hace falta para que quepa el título. El título, de dos
  // renglones, el hueco hasta las tarjetas y las dos tarjetas quedan juntos al centro, debajo de la barra.
  const MARGEN_CELULAR = 16;
  const LETRA_CELULAR = 30;
  const ESPACIO_TITULO = 24;
  // Inclinada, cada tarjeta se ve más baja que su caja: su orilla de afuera se va hacia atrás (y la perspectiva
  // sale de la orilla de adentro). Esto es lo que se ve de alto, en pixeles de la escena original; con la caja, el
  // título quedaba muy lejos de las tarjetas y todo cargado hacia arriba.
  const inclinada = (INCLINACION * Math.PI) / 180;
  const ALTO_VISTO = (620 * Math.cos(inclinada) * 1000) / (1000 + 620 * Math.sin(inclinada));
  const medir = (ancho, alto) => {
    if (celular.matches && alto > ancho) {
      const barra = filaBarra.offsetHeight;
      const altoTitulo = 2 * LETRA_CELULAR * 1.15;
      // Lo que se ve de las dos tarjetas con el hueco en medio
      const libre = alto - barra - 2 * MARGEN_CELULAR - altoTitulo - ESPACIO_TITULO;
      const s = Math.min((ancho - 2 * MARGEN_CELULAR) / 1000, libre / (2 * ALTO_VISTO + HUECO));
      const altoPar = (2 * ALTO_VISTO + HUECO) * s;
      const tituloArriba = barra + (alto - barra - altoTitulo - ESPACIO_TITULO - altoPar) / 2;
      return {
        vertical: true, s, ancho: 1000 * s, alto: 620 * s, izquierda: (ancho - 1000 * s) / 2,
        // Antes de bajar, las dos juntas al centro de la pantalla
        arriba: (alto - 620 * s) / 2,
        tituloArriba, letra: LETRA_CELULAR,
        bajada: tituloArriba + altoTitulo + ESPACIO_TITULO - (alto - altoPar) / 2,
      };
    }
    const s = Math.min(alto / 720, ancho / 1280);
    const x0 = (ancho - 1280 * s) / 2;
    const y0 = (alto - 720 * s) / 2;
    return {
      s, ancho: 1000 * s, alto: 620 * s, izquierda: x0 + 140 * s, arriba: y0 + 216 * s,
      // El título, solo, va donde estaba el centro de él y su descripción (que se quitó)
      tituloArriba: y0 + 200 * s, letra: 42 * s, bajada: 115 * s,
    };
  };

  const ponerCaja = (tarjeta, x, y, ancho, alto) => {
    tarjeta.style.left = `${x}px`;
    tarjeta.style.top = `${y}px`;
    tarjeta.style.width = `${ancho}px`;
    tarjeta.style.height = `${alto}px`;
  };
  // Sombra suave sobre el blanco, que sale alrededor de cuando las dos tarjetas bajan a su lugar (TRAMOS.sombras):
  // si salía mientras la primera se alejaba y la segunda entraba, se veía mucho antes de tiempo
  const sombra = (s, fuerza) =>
    `0 ${20 * s}px ${52 * s}px ${-24 * s}px rgba(10, 10, 11, ${0.32 * fuerza}), ` +
    `0 2px 6px rgba(10, 10, 11, ${0.06 * fuerza})`;

  let pendiente = false;

  function pintar() {
    pendiente = false;
    const anchoPantalla = document.documentElement.clientWidth; // sin la barra de desplazamiento
    const altoPantalla = innerHeight;
    const caja = seccion.getBoundingClientRect();

    // No se ve hasta que llega arriba (un pixel de margen por el redondeo del scroll): antes iría subiendo
    // encima de la laptop. Y cambia el tema de la barra (blanca de aquí para abajo).
    seccion.toggleAttribute('data-llego', caja.top <= 1);
    document.documentElement.toggleAttribute('data-hoja', caja.top <= filaBarra.offsetHeight / 2);
    // Al regresar, mientras la tarjeta y la frase se desvanecen (CSS), lo fijo se queda arriba en vez de bajar
    // con la sección
    fija.style.transform = caja.top > 0 ? `translateY(${-caja.top}px)` : '';

    // Primero la frase: cuál de sus imágenes se ve, según cuántas pantallas se ha bajado, y por dónde va el brillo
    const bajado = Math.max(0, -caja.top);
    const cual = Math.min(introImagenes.length - 1, Math.floor(bajado / altoPantalla / PASO_IMAGEN));
    introImagenes.forEach((img, i) => { img.hidden = i !== cual; });
    const frase = FRASE * altoPantalla;
    introFrase.style.setProperty('--brillo', `${limitar(bajado / frase) * BRILLO_FRASE}ms`);

    // Luego lo demás, sin el tramo de la frase
    const recorrido = seccion.offsetHeight - altoPantalla - frase;
    const p = sinMovimiento.matches ? 1 : limitar((bajado - frase) / recorrido);
    const m = medir(anchoPantalla, altoPantalla);

    const alejada = SALIDA(tramo(p, TRAMOS.alejarse));
    const ida = SALIDA(tramo(p, TRAMOS.irseALaIzquierda));
    const entrada = SALIDA(tramo(p, TRAMOS.entrarLaDerecha));
    const bajada = CAIDA(tramo(p, TRAMOS.bajar));
    const sombras = tramo(p, TRAMOS.sombras);
    const sale = SALIDA(tramo(p, TRAMOS.titulo));
    // Cada tarjeta queda a un lado del centro, con el hueco justo en medio. En celular, una arriba y otra abajo:
    // se mueven de alto en vez de lado y se inclinan sobre su orilla de adentro, que ahí es la de abajo de la
    // primera y la de arriba de la segunda (por eso el giro va al revés).
    const aUnLado = ((m.vertical ? m.alto : m.ancho) + HUECO * m.s) / 2;
    const perspectiva = `perspective(${1000 * m.s}px)`;
    const mover = m.vertical ? 'translateY' : 'translateX';
    const inclinar = m.vertical ? 'rotateX' : 'rotateY';
    const signo = m.vertical ? -1 : 1;

    // La primera: de todo lo ancho (debajo de la barra) a su tamaño; la frase se va y sale el anillo
    const anchoClara = mezclar(anchoPantalla, m.ancho, alejada);
    ponerCaja(
      izq,
      mezclar(0, m.izquierda, alejada), mezclar(filaBarra.offsetHeight + ASOMA * m.s, m.arriba, alejada),
      anchoClara, mezclar(altoPantalla, m.alto, alejada),
    );
    izq.style.transform = `${mover}(${-aUnLado * ida}px)`;
    izq.firstElementChild.style.transform = `${perspectiva} ${inclinar}(${-signo * INCLINACION * ida}deg)`;
    izq.firstElementChild.style.transformOrigin = m.vertical ? '50% 100%' : '100% 50%';
    const caraIzq = izq.querySelector('.lanzamiento-cara');
    caraIzq.style.borderRadius = `${30 * m.s * alejada}px`;
    caraIzq.style.boxShadow = sombra(m.s, sombras);
    intro.style.opacity = 1 - tramo(p, TRAMOS.seVaLaFrase);

    // El anillo: qué parte toca, y cuánto se han juntado en una mientras caen las tarjetas
    objetivo = p >= SE_AMONTONA ? MOMENTOS.fin : p >= SALE_EL_ANILLO ? MOMENTOS.pila : 0;
    junta = CAMBIA(tramo(p, TRAMOS.bajar));
    // Ya juntas, se queda una sola: al subir no se arma otra vez el anillo, sino que esa va al centro mientras la
    // tarjeta regresa, y ahí se vuelve la imagen de la frase. De vuelta en la frase (ya sin nada del anillo a la
    // vista), todo empieza otra vez.
    if (junta >= 1) soloUna = true;
    if (p <= TRAMOS.seApagaElAnillo[0]) {
      soloUna = false;
      reloj = 0;
    }
    enLaFrase = 1 - SALIDA(tramo(p, [TRAMOS.seVaLaFrase[1], TRAMOS.irseALaIzquierda[1]]));
    ranura = ((marcoFrase.offsetHeight / anchoClara) * 100) / (ORBITA.alto * PILA.s * ESCALA_ORBITA);
    // Lo del anillo se apaga mientras sale la frase: así, aunque se suba rápido, no se encima con ella (y la imagen
    // que se quedó sola se cambia por la de la frase)
    capaOrbita.style.opacity = tramo(p, TRAMOS.seApagaElAnillo);
    ponerAOrbitar(!soloUna && seccion.hasAttribute('data-llego') && caja.bottom > 0);
    // Lo que va con el scroll se pinta aquí si el anillo no está corriendo
    if (!orbitando || soloUna) pintarOrbita();

    // La segunda: entra desde fuera de la pantalla, por la derecha (en celular, por abajo)
    ponerCaja(der, m.izquierda, m.arriba, m.ancho, m.alto);
    const fuera = (m.vertical ? altoPantalla : anchoPantalla) * 1.08;
    der.style.transform = `${mover}(${mezclar(fuera, aUnLado, entrada)}px)`;
    der.style.opacity = limitar(entrada / 0.35);
    der.firstElementChild.style.transform = `${perspectiva} ${inclinar}(${signo * INCLINACION}deg)`;
    der.firstElementChild.style.transformOrigin = m.vertical ? '50% 0%' : '0% 50%';
    const caraDer = der.querySelector('.lanzamiento-cara');
    caraDer.style.borderRadius = `${30 * m.s}px`;
    caraDer.style.boxShadow = sombra(m.s, sombras);
    ponerAGirar(entrada > 0 && caja.bottom > 0 && seccion.hasAttribute('data-llego'));

    grupo.style.transform = `translateY(${m.bajada * bajada}px)`;
    // Las orillas blancas, a la par del título: si salían antes, se notaban solas
    orillas.style.opacity = sale;

    // El título sale desenfocado y chico, y se acerca hasta quedar nítido
    texto.style.top = `${m.tituloArriba}px`;
    titulo.style.fontSize = `${m.letra}px`;
    texto.style.opacity = sale;
    texto.style.filter = sale < 1 ? `blur(${10 * (1 - sale)}px)` : 'none';
    texto.style.transform = `translateY(${40 * m.s * (1 - sale)}px) scale(${0.82 + 0.18 * sale})`;
    // Ya nítido le pasa el brillo (CSS). Vuelve a pasar solo si el título se fue del todo, no con cada vaivén
    // del scroll alrededor del final.
    if (sale === 1) seccion.setAttribute('data-titulo', '');
    else if (sale === 0) seccion.removeAttribute('data-titulo');
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
  moverRemolino(0);
  pintarOrbita();
  pintar();
})();
