// barrido.js — el cambio de la pantalla de la laptop (index.html) del azul en vivo a la captura del panel, y de
// regreso: una franja de luz blanca y tenue, como un reflejo que pasa por el vidrio, cruza la pantalla y deja el
// panel detrás, pegado a ella (de un lado el panel y del otro el azul, con la orilla escondida debajo de la luz).
// Va hacia donde va el scroll: al bajar, de izquierda a derecha; al subir, de regreso hacia la izquierda. Antes la
// captura entraba desvaneciéndose sobre el azul con el scroll, y a la mitad se veían los dos encimados.
// Sale del «Prism Sweep Transition» de SmoothUI (en React), pasado a JS normal: su sombreador y sus tiempos tal
// cual, pero en blanco en lugar de cian y rosa, que rompía lo sobrio de la página, y con el panel pegado a la
// franja en lugar de cambiar de golpe a la mitad. También se probó una línea de luz delgada sin franja.
// escena.js dice cuál toca (data-panel en .video, cuando el fondo ya va a la mitad del paso a negro); el cambio va
// con el reloj, como en el componente. Con «reducir movimiento» o sin WebGL, es de golpe.
(() => {
  const video = document.querySelector('.video');
  const lienzo = video && video.querySelector('.barrido-luz');
  const panel = video && video.querySelector('.panel-sistema');
  if (!lienzo || !panel) return;
  const sinMovimiento = matchMedia('(prefers-reduced-motion: reduce)');

  // Los tiempos del componente: lo que tarda en cruzar la franja, lo que tarda en apagarse al final y lo menos que
  // dura un barrido (en ms)
  const DURACION = 1240;
  const APAGARSE = 82;
  const MINIMO = 80;
  // Qué tanto se ve (1 es lo del componente) y su tono: blanca, apenas plateada abajo, con la orilla menos
  // ondulada que la del componente, pocas facetas y poco destello
  const FUERZA = 0.55;
  const TONO = {
    curva: 0.35, destello: 0.3, facetas: 6, suavidad: 0.09, ancho: 0.12,
    frio: [0.86, 0.9, 0.96], calido: [1, 1, 1], perla: [1, 1, 1], tinta: [0.5, 0.5, 0.52],
  };

  // Avanza a lo ancho. Al panel sale de la izquierda (la dirección «left» del componente, que dice de dónde sale,
  // y la que trae por omisión) y de regreso al azul, de la derecha («right»): así, al subir, va hacia la izquierda
  const EJE = 0;
  let adelante = 1;

  // El sombreador va tal cual del componente, con sus nombres, para poder compararlo con el original
  const VERTICES = `
attribute vec2 position;
varying vec2 vUv;

void main() {
  vUv = position * 0.5 + 0.5;
  gl_Position = vec4(position, 0.0, 1.0);
}`;

  const FRAGMENTOS = `
precision mediump float;

varying vec2 vUv;

uniform vec2 uResolution;
uniform float uClock;
uniform float uTravel;
uniform float uOpacity;
uniform float uAxis;
uniform float uForward;
uniform float uSpan;
uniform float uSoftness;
uniform float uBend;
uniform float uFacet;
uniform float uBloom;
uniform vec3 uInk;
uniform vec3 uPearl;
uniform vec3 uWarm;
uniform vec3 uCool;

float saturate(float value) {
  return clamp(value, 0.0, 1.0);
}

float triangleWave(float value) {
  return abs(fract(value) * 2.0 - 1.0);
}

float softRidge(float distance, float width) {
  return exp(-distance * distance / max(width, 0.0001));
}

void main() {
  vec2 uv = vUv;
  vec2 pixel = 1.0 / max(uResolution, vec2(1.0));

  float mainAxis = mix(uv.x, uv.y, uAxis);
  float crossAxis = mix(uv.y, uv.x, uAxis);
  mainAxis = mix(mainAxis, 1.0 - mainAxis, step(0.0, -uForward));

  float time = uClock * 0.42;
  float drift =
      sin(crossAxis * 7.0 + time * 1.8) * 0.024
    + sin(crossAxis * 17.0 - time * 1.1 + 1.6) * 0.010
    + sin((mainAxis + crossAxis) * 11.0 + time * 0.7) * 0.006;
  drift *= uBend;

  float travel = -0.34 + uTravel * 1.68;
  float d = mainAxis - travel - drift;
  float ad = abs(d);

  float field = 1.0 - smoothstep(uSpan, uSpan + uSoftness, ad);
  float inner = 1.0 - smoothstep(uSpan * 0.28, uSpan, ad);
  float frontRidge = softRidge(d - uSpan * 0.34, 0.0017 + pixel.x * 16.0);
  float backRidge = softRidge(d + uSpan * 0.54, 0.0035 + pixel.y * 14.0) * 0.55;

  float facetGrid = triangleWave(crossAxis * uFacet + mainAxis * 2.1 + time * 0.35);
  float facetCuts = smoothstep(0.18, 0.92, facetGrid);
  float diagonal = triangleWave((crossAxis - mainAxis * 0.36) * (uFacet * 0.44) - time * 0.2);
  float caustic = pow(1.0 - diagonal, 4.0) * 0.42 + pow(facetCuts, 2.2) * 0.22;

  float glass = saturate(field * (0.5 + inner * 0.42) + frontRidge * 0.52 + backRidge * 0.2);
  float gateIn = smoothstep(0.02, 0.14, uTravel);
  float gateOut = 1.0 - smoothstep(0.9, 1.0, uTravel);
  float envelope = gateIn * gateOut;

  vec3 base = mix(uCool, uWarm, saturate(crossAxis * 0.82 + drift * 4.5));
  vec3 prism = mix(base, uPearl, inner * 0.36 + frontRidge * 0.5);
  prism = mix(prism, uInk, smoothstep(0.55, 0.0, ad) * 0.1);
  prism += caustic * uBloom * mix(uWarm, uPearl, 0.38);
  prism += frontRidge * uBloom * mix(uWarm, uCool, 0.22) * 0.72;
  prism += backRidge * uBloom * uCool * 0.7;

  float vignette = smoothstep(0.0, 0.025, crossAxis) * smoothstep(1.0, 0.975, crossAxis);
  float alpha = saturate(glass * 0.64 + frontRidge * 0.24 + backRidge * 0.14);
  alpha *= uOpacity * envelope * vignette;

  gl_FragColor = vec4(prism * alpha, alpha);
}`;

  const cambiar = (conPanel) => { panel.style.opacity = conPanel ? '1' : '0'; };
  const limitar = (v) => Math.min(1, Math.max(0, v));

  // Al cargar, lo que toque, sin barrido (como el componente en su primer dibujo). escena.js ya acomodó la
  // escena, porque se carga antes.
  let objetivo = video.hasAttribute('data-panel');
  cambiar(objetivo);

  const gl = lienzo.getContext('webgl', {
    alpha: true, antialias: false, depth: false, premultipliedAlpha: true, preserveDrawingBuffer: false,
    stencil: false,
  });
  const programa = gl && crearPrograma();
  let u = null;
  if (programa) {
    gl.useProgram(programa);
    // Dos triángulos que tapan todo el lienzo, como en el componente
    gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1]), gl.STATIC_DRAW);
    const lugar = gl.getAttribLocation(programa, 'position');
    gl.enableVertexAttribArray(lugar);
    gl.vertexAttribPointer(lugar, 2, gl.FLOAT, false, 0, 0);
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
    u = Object.fromEntries(['uResolution', 'uClock', 'uTravel', 'uOpacity', 'uAxis', 'uForward', 'uSpan',
      'uSoftness', 'uBend', 'uFacet', 'uBloom', 'uInk', 'uPearl', 'uWarm', 'uCool']
      .map((nombre) => [nombre, gl.getUniformLocation(programa, nombre)]));
    gl.uniform1f(u.uAxis, EJE);
    gl.uniform1f(u.uForward, adelante);
    gl.uniform1f(u.uSpan, TONO.ancho);
    gl.uniform1f(u.uSoftness, TONO.suavidad);
    gl.uniform1f(u.uBend, TONO.curva);
    gl.uniform1f(u.uFacet, TONO.facetas);
    gl.uniform1f(u.uBloom, TONO.destello);
    gl.uniform3fv(u.uInk, TONO.tinta);
    gl.uniform3fv(u.uPearl, TONO.perla);
    gl.uniform3fv(u.uWarm, TONO.calido);
    gl.uniform3fv(u.uCool, TONO.frio);
  }

  function crearPrograma() {
    const compilar = (tipo, codigo) => {
      const sombreador = gl.createShader(tipo);
      gl.shaderSource(sombreador, codigo);
      gl.compileShader(sombreador);
      if (!gl.getShaderParameter(sombreador, gl.COMPILE_STATUS)) {
        console.warn('barrido.js: no compiló el sombreador', gl.getShaderInfoLog(sombreador));
      }
      return sombreador;
    };
    const p = gl.createProgram();
    gl.attachShader(p, compilar(gl.VERTEX_SHADER, VERTICES));
    gl.attachShader(p, compilar(gl.FRAGMENT_SHADER, FRAGMENTOS));
    gl.linkProgram(p);
    return gl.getProgramParameter(p, gl.LINK_STATUS) ? p : null;
  }

  // Por dónde va la franja (0 antes de entrar, 1 ya del otro lado) y qué tanto se ve
  let recorrido = 0;
  let opacidad = 0;
  let cuadro = 0;
  const inicio = performance.now();

  // Como mucho 1280 de ancho, como el azul (pantalla.js): la pantalla está encogida mientras pasa la franja, así
  // que no se nota, y la tarjeta de video trabaja mucho menos
  function medir() {
    const ancho = lienzo.clientWidth;
    const alto = lienzo.clientHeight;
    if (!ancho || !alto) return;
    const escala = Math.min(1280 / ancho, devicePixelRatio || 1);
    const w = Math.max(1, Math.round(ancho * escala));
    const h = Math.max(1, Math.round(alto * escala));
    if (lienzo.width !== w || lienzo.height !== h) {
      lienzo.width = w;
      lienzo.height = h;
    }
    gl.viewport(0, 0, w, h);
    gl.uniform2f(u.uResolution, w, h);
  }

  function dibujar() {
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.uniform1f(u.uClock, (performance.now() - inicio) / 1000);
    gl.uniform1f(u.uTravel, recorrido);
    gl.uniform1f(u.uOpacity, opacidad);
    gl.drawArrays(gl.TRIANGLES, 0, 6);
  }

  // El panel se ve a la izquierda del centro de la franja, con su orilla suave debajo de la luz. El sombreador
  // lleva ese centro de −0.34 a 1.34 a lo ancho (de regreso, contado desde la derecha), y el CSS pone la orilla en
  // --corte × 104 % − 2 %.
  function ponerOrilla() {
    const centro = -0.34 + 1.68 * recorrido;
    const x = adelante > 0 ? centro : 1 - centro;
    video.style.setProperty('--corte', (x + 0.02) / 1.04);
  }

  // Un barrido: la franja sigue desde donde vaya (si cambia de idea a medio camino, no empieza de cero), lleva el
  // panel pegado, llega al otro lado y se apaga
  function barrer(conPanel) {
    cancelAnimationFrame(cuadro);
    if (!programa || sinMovimiento.matches) {
      video.removeAttribute('data-recorte');
      cambiar(conPanel);
      return;
    }
    // Si cambia de idea a medio camino, la franja sigue desde donde está, ahora hacia el otro lado: contado desde
    // el otro lado, ese mismo lugar es 1 − recorrido
    const sentido = conPanel ? 1 : -1;
    if (sentido !== adelante && recorrido > 0) recorrido = 1 - recorrido;
    adelante = sentido;
    gl.uniform1f(u.uForward, adelante);
    medir();
    lienzo.setAttribute('data-barriendo', '');
    opacidad = FUERZA;
    // Mientras cruza, la captura va a 0.999 y no a 1, porque con 1 pantalla.js deja de dibujar el azul, que
    // todavía se ve del otro lado de la franja
    panel.style.opacity = '0.999';
    ponerOrilla();
    video.setAttribute('data-recorte', '');
    const empieza = performance.now();
    const desde = recorrido;
    const dura = Math.max(MINIMO, DURACION * (1 - desde));

    const avanzar = (ahora) => {
      const t = limitar((ahora - empieza) / dura);
      recorrido = desde + (1 - desde) * (1 - (1 - t) ** 3.35);
      ponerOrilla();
      dibujar();
      if (t < 1) {
        cuadro = requestAnimationFrame(avanzar);
        return;
      }
      cambiar(conPanel);
      video.removeAttribute('data-recorte');
      recorrido = 1;
      const apaga = performance.now();
      const apagar = (ahora2) => {
        const a = limitar((ahora2 - apaga) / APAGARSE);
        opacidad = FUERZA * (1 - a * a * (3 - 2 * a));
        dibujar();
        if (a < 1) {
          cuadro = requestAnimationFrame(apagar);
          return;
        }
        recorrido = 0;
        opacidad = 0;
        dibujar();
        lienzo.removeAttribute('data-barriendo');
      };
      cuadro = requestAnimationFrame(apagar);
    };
    cuadro = requestAnimationFrame(avanzar);
  }

  new MutationObserver(() => {
    const conPanel = video.hasAttribute('data-panel');
    if (conPanel === objetivo) return;
    objetivo = conPanel;
    barrer(conPanel);
  }).observe(video, { attributes: true, attributeFilter: ['data-panel'] });
})();
