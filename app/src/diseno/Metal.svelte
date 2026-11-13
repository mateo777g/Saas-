<!--
  El metal del botón de mandar del Agente IA en Cristal (el developer, 13 nov 2026; maqueta FiHkjmT1meyTu7zuU3En2n v48,
  «Vista: Agente IA»; planes/trabajo/estilo-cristal/agente.md). Va dentro del botón, como su primer hijo; el botón pone
  su forma, su aro de sombras y el ícono (gerente/agente/CajaPregunta.svelte).

  · En claro, el «Metallic button» que trajo el developer (21st.dev): el metal líquido de Paper Shaders («liquidMetal»,
    WebGL2) portado sin React ni paquetes, con los valores de su demo (base negra, brillo blanco, 4 bandas, borde 0.5,
    ángulo 45, zoom 8, 0.3 de rojo y de azul); la cara negra 2 px adentro; la velocidad cambia (0.6 quieto, 1 con el
    mouse encima, 2.4 al picar por 300 ms) y al picar sale una onda desde donde picaste.
  · En oscuro, el «Aro»: el MetalButton de Spectrum UI, que usa metal-fx (Jakub Antalík, MIT; solo para React) y por
    dentro es el mismo shader. Su forma «circle»: un aro de 2 px con el centro transparente (se ve la caja de vidrio),
    con su preset «chromatic» oscuro (metal-fx 2.0.11), a velocidad 1, sin onda.

  Solo existe en Cristal. `prendido` es el botón con algo que mandar (o «Detener»): apagado, el botón sigue gris como
  en Simple y el metal no se ve ni corre. Con «reducir movimiento», un cuadro quieto y sin onda.
-->
<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { alCambiarEstilo, estiloActual } from '../lib/estilo';

  let { prendido }: { prendido: boolean } = $props();

  const VERTEX = `#version 300 es
precision mediump float;
layout(location = 0) in vec4 a_position;
uniform vec2 u_resolution;
uniform float u_pixelRatio;
uniform float u_originX;
uniform float u_originY;
uniform float u_worldWidth;
uniform float u_worldHeight;
uniform float u_fit;
uniform float u_scale;
uniform float u_rotation;
uniform float u_offsetX;
uniform float u_offsetY;
out vec2 v_objectUV;
out vec2 v_responsiveUV;
out vec2 v_responsiveBoxGivenSize;
vec3 getBoxSize(float boxRatio, vec2 givenBoxSize) {
  vec2 box = vec2(0.);
  box.x = boxRatio * min(givenBoxSize.x / boxRatio, givenBoxSize.y);
  float noFitBoxWidth = box.x;
  if (u_fit == 1.) {
    box.x = boxRatio * min(u_resolution.x / boxRatio, u_resolution.y);
  } else if (u_fit == 2.) {
    box.x = boxRatio * max(u_resolution.x / boxRatio, u_resolution.y);
  }
  box.y = box.x / boxRatio;
  return vec3(box, noFitBoxWidth);
}
void main() {
  gl_Position = a_position;
  vec2 uv = gl_Position.xy * .5;
  vec2 boxOrigin = vec2(.5 - u_originX, u_originY - .5);
  vec2 givenBoxSize = vec2(u_worldWidth, u_worldHeight);
  givenBoxSize = max(givenBoxSize, vec2(1.)) * u_pixelRatio;
  float r = u_rotation * 3.14159265358979323846 / 180.;
  mat2 graphicRotation = mat2(cos(r), sin(r), -sin(r), cos(r));
  vec2 graphicOffset = vec2(-u_offsetX, u_offsetY);
  float fixedRatio = 1.;
  vec2 fixedRatioBoxGivenSize = vec2(
  (u_worldWidth == 0.) ? u_resolution.x : givenBoxSize.x,
  (u_worldHeight == 0.) ? u_resolution.y : givenBoxSize.y
  );
  vec2 objectBoxSize = getBoxSize(fixedRatio, fixedRatioBoxGivenSize).xy;
  vec2 objectWorldScale = u_resolution.xy / objectBoxSize;
  v_objectUV = uv;
  v_objectUV *= objectWorldScale;
  v_objectUV += boxOrigin * (objectWorldScale - 1.);
  v_objectUV += graphicOffset;
  v_objectUV /= u_scale;
  v_objectUV = graphicRotation * v_objectUV;
  v_responsiveBoxGivenSize = vec2(
  (u_worldWidth == 0.) ? u_resolution.x : givenBoxSize.x,
  (u_worldHeight == 0.) ? u_resolution.y : givenBoxSize.y
  );
  float responsiveRatio = v_responsiveBoxGivenSize.x / v_responsiveBoxGivenSize.y;
  vec2 responsiveBoxSize = getBoxSize(responsiveRatio, v_responsiveBoxGivenSize).xy;
  vec2 responsiveBoxScale = u_resolution.xy / responsiveBoxSize;
  v_responsiveUV = uv;
  v_responsiveUV *= responsiveBoxScale;
  v_responsiveUV += boxOrigin * (responsiveBoxScale - 1.);
  v_responsiveUV += graphicOffset;
  v_responsiveUV /= u_scale;
  v_responsiveUV.x *= responsiveRatio;
  v_responsiveUV = graphicRotation * v_responsiveUV;
  v_responsiveUV.x /= responsiveRatio;
}`;

  const FRAGMENT = `#version 300 es
precision mediump float;
uniform vec2 u_resolution;
uniform float u_time;
uniform vec4 u_colorBack;
uniform vec4 u_colorTint;
uniform float u_softness;
uniform float u_repetition;
uniform float u_shiftRed;
uniform float u_shiftBlue;
uniform float u_distortion;
uniform float u_contour;
uniform float u_angle;
in vec2 v_objectUV;
in vec2 v_responsiveUV;
in vec2 v_responsiveBoxGivenSize;
out vec4 fragColor;
#define TWO_PI 6.28318530718
#define PI 3.14159265358979323846
vec2 rotate(vec2 uv, float th) {
  return mat2(cos(th), sin(th), -sin(th), cos(th)) * uv;
}
vec3 permute(vec3 x) { return mod(((x * 34.0) + 1.0) * x, 289.0); }
float snoise(vec2 v) {
  const vec4 C = vec4(0.211324865405187, 0.366025403784439,
    -0.577350269189626, 0.024390243902439);
  vec2 i = floor(v + dot(v, C.yy));
  vec2 x0 = v - i + dot(i, C.xx);
  vec2 i1;
  i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
  vec4 x12 = x0.xyxy + C.xxzz;
  x12.xy -= i1;
  i = mod(i, 289.0);
  vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0))
    + i.x + vec3(0.0, i1.x, 1.0));
  vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy),
      dot(x12.zw, x12.zw)), 0.0);
  m = m * m;
  m = m * m;
  vec3 x = 2.0 * fract(p * C.www) - 1.0;
  vec3 h = abs(x) - 0.5;
  vec3 ox = floor(x + 0.5);
  vec3 a0 = x - ox;
  m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
  vec3 g;
  g.x = a0.x * x0.x + h.x * x0.y;
  g.yz = a0.yz * x12.xz + h.yz * x12.yw;
  return 130.0 * dot(m, g);
}
float getColorChanges(float c1, float c2, float stripe_p, vec3 w, float blur, float bump, float tint) {
  float ch = mix(c2, c1, smoothstep(.0, 2. * blur, stripe_p));
  float border = w[0];
  ch = mix(ch, c2, smoothstep(border, border + 2. * blur, stripe_p));
  border = w[0] + .4 * (1. - bump) * w[1];
  ch = mix(ch, c1, smoothstep(border, border + 2. * blur, stripe_p));
  border = w[0] + .5 * (1. - bump) * w[1];
  ch = mix(ch, c2, smoothstep(border, border + 2. * blur, stripe_p));
  border = w[0] + w[1];
  ch = mix(ch, c1, smoothstep(border, border + 2. * blur, stripe_p));
  float gradient_t = (stripe_p - w[0] - w[1]) / w[2];
  float gradient = mix(c1, c2, smoothstep(0., 1., gradient_t));
  ch = mix(ch, gradient, smoothstep(border, border + .5 * blur, stripe_p));
  ch = mix(ch, 1. - min(1., (1. - ch) / max(tint, 0.0001)), u_colorTint.a);
  return ch;
}
void main() {
  const float firstFrameOffset = 2.8;
  float t = .3 * (u_time + firstFrameOffset);
  vec2 uv = v_objectUV + .5;
  uv.y = 1. - uv.y;
  float cycleWidth = u_repetition;
  float edge = 0.;
  vec2 rotatedUV = uv - vec2(.5);
  float angle = (-u_angle + 70.) * PI / 180.;
  float cosA = cos(angle);
  float sinA = sin(angle);
  rotatedUV = vec2(
  rotatedUV.x * cosA - rotatedUV.y * sinA,
  rotatedUV.x * sinA + rotatedUV.y * cosA
  ) + vec2(.5);
  vec2 shapeUV = uv - .5;
  shapeUV *= .67;
  edge = pow(clamp(3. * length(shapeUV), 0., 1.), 18.);
  edge = mix(smoothstep(.9 - 2. * fwidth(edge), .9, edge), edge, smoothstep(0.0, 0.4, u_contour));
  float opacity = 1. - smoothstep(.9 - 2. * fwidth(edge), .9, edge);
  edge = 1.2 * edge;
  float diagBLtoTR = rotatedUV.x - rotatedUV.y;
  float diagTLtoBR = rotatedUV.x + rotatedUV.y;
  vec3 color = vec3(0.);
  vec3 color1 = vec3(.98, 0.98, 1.);
  vec3 color2 = vec3(.1, .1, .1 + .1 * smoothstep(.7, 1.3, diagTLtoBR));
  vec2 grad_uv = uv - .5;
  float dist = length(grad_uv + vec2(0., .2 * diagBLtoTR));
  grad_uv = rotate(grad_uv, (.25 - .2 * diagBLtoTR) * PI);
  float direction = grad_uv.x;
  float bump = pow(1.8 * dist, 1.2);
  bump = 1. - bump;
  bump *= pow(uv.y, .3);
  float thin_strip_1_ratio = .12 / cycleWidth * (1. - .4 * bump);
  float thin_strip_2_ratio = .07 / cycleWidth * (1. + .4 * bump);
  float wide_strip_ratio = (1. - thin_strip_1_ratio - thin_strip_2_ratio);
  float thin_strip_1_width = cycleWidth * thin_strip_1_ratio;
  float thin_strip_2_width = cycleWidth * thin_strip_2_ratio;
  float noise = snoise(uv - t);
  edge += (1. - edge) * u_distortion * noise;
  direction += diagBLtoTR;
  float contour = 0.;
  direction -= 2. * noise * diagBLtoTR * (smoothstep(0., 1., edge) * (1.0 - smoothstep(0., 1., edge)));
  direction *= mix(1., 1. - edge, smoothstep(.5, 1., u_contour));
  direction -= 1.7 * edge * smoothstep(.5, 1., u_contour);
  direction += .2 * pow(u_contour, 4.) * (1.0 - smoothstep(0., 1., edge));
  bump *= clamp(pow(uv.y, .1), .3, 1.);
  direction *= (.1 + (1.1 - edge) * bump);
  direction *= (.4 + .6 * (1.0 - smoothstep(.5, 1., edge)));
  direction += .18 * (smoothstep(.1, .2, uv.y) * (1.0 - smoothstep(.2, .4, uv.y)));
  direction += .03 * (smoothstep(.1, .2, 1. - uv.y) * (1.0 - smoothstep(.2, .4, 1. - uv.y)));
  direction *= (.5 + .5 * pow(uv.y, 2.));
  direction *= cycleWidth;
  direction -= t;
  float colorDispersion = (1. - bump);
  colorDispersion = clamp(colorDispersion, 0., 1.);
  float dispersionRed = colorDispersion;
  dispersionRed += .03 * bump * noise;
  dispersionRed += 5. * (smoothstep(-.1, .2, uv.y) * (1.0 - smoothstep(.1, .5, uv.y))) * (smoothstep(.4, .6, bump) * (1.0 - smoothstep(.4, 1., bump)));
  dispersionRed -= diagBLtoTR;
  float dispersionBlue = colorDispersion;
  dispersionBlue *= 1.3;
  dispersionBlue += (smoothstep(0., .4, uv.y) * (1.0 - smoothstep(.1, .8, uv.y))) * (smoothstep(.4, .6, bump) * (1.0 - smoothstep(.4, .8, bump)));
  dispersionBlue -= .2 * edge;
  dispersionRed *= (u_shiftRed / 20.);
  dispersionBlue *= (u_shiftBlue / 20.);
  float blur = u_softness / 15. + .3 * contour;
  vec3 w = vec3(thin_strip_1_width, thin_strip_2_width, wide_strip_ratio);
  w[1] -= .02 * smoothstep(.0, 1., edge + bump);
  float stripe_r = fract(direction + dispersionRed);
  float r = getColorChanges(color1.r, color2.r, stripe_r, w, blur + fwidth(stripe_r), bump, u_colorTint.r);
  float stripe_g = fract(direction);
  float g = getColorChanges(color1.g, color2.g, stripe_g, w, blur + fwidth(stripe_g), bump, u_colorTint.g);
  float stripe_b = fract(direction - dispersionBlue);
  float b = getColorChanges(color1.b, color2.b, stripe_b, w, blur + fwidth(stripe_b), bump, u_colorTint.b);
  color = vec3(r, g, b);
  color *= opacity;
  vec3 bgColor = u_colorBack.rgb * u_colorBack.a;
  color = color + bgColor * (1. - opacity);
  opacity = opacity + u_colorBack.a * (1. - opacity);
  color += 1. / 256. * (fract(sin(dot(.014 * gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453123) - .5);
  fragColor = vec4(color, opacity);
}`;

  type Ajustes = {
    colorBack: number[];
    colorTint: number[];
    repetition: number;
    softness: number;
    angle: number;
    scale: number;
    distortion: number;
    contour: number;
    shiftRed: number;
    shiftBlue: number;
  };
  // Los valores de la demo del «Metallic button»: base #000000, brillo #ffffff, 4 bandas, borde 0.5, ángulo 45, zoom 8,
  // sin deformar, 0.3 de rojo y de azul.
  const METAL: Ajustes = {
    colorBack: [0, 0, 0, 1],
    colorTint: [1, 1, 1, 1],
    repetition: 4,
    softness: 0.5,
    angle: 45,
    scale: 8,
    distortion: 0,
    contour: 0,
    shiftRed: 0.3,
    shiftBlue: 0.3,
  };
  // «Aro», el chromatic oscuro de metal-fx: fondo transparente, brillo #88ccff al 18 % (2e), 2 bandas, borde 0.09,
  // deformación 0.1, contorno 0.4, ángulo 90, 0.75 de rojo y de azul, escala 1.3 (la de «circle»).
  const ARO: Ajustes = {
    colorBack: [0, 0, 0, 0],
    colorTint: [0x88 / 255, 0xcc / 255, 1, 0x2e / 255],
    repetition: 2,
    softness: 0.09,
    angle: 90,
    scale: 1.3,
    distortion: 0.1,
    contour: 0.4,
    shiftRed: 0.75,
    shiftBlue: 0.75,
  };
  const VEL = { quieto: 0.6, encima: 1, pica: 2.4 };

  const esAro = () => document.documentElement.dataset.tema === 'oscuro';

  let enCristal = $state(estiloActual() === 'cristal');
  // Al cambiar el tema se pinta otra vez (con «reducir movimiento» no hay bucle que lo haga).
  let tema = $state(document.documentElement.dataset.tema);
  const dejarDeEscuchar = alCambiarEstilo((estilo, t) => {
    enCristal = estilo === 'cristal';
    tema = t;
  });
  onDestroy(dejarDeEscuchar);

  const quieto = typeof matchMedia === 'function' ? matchMedia('(prefers-reduced-motion: reduce)') : null;

  let capa = $state<HTMLSpanElement | null>(null);
  let canvas = $state<HTMLCanvasElement | null>(null);
  let ondas = $state<{ id: number; x: number; y: number }[]>([]);
  let siguienteOnda = 0;
  // Lo que prende o apaga el bucle (lo pone el efecto de abajo cuando el lienzo ya tiene su shader).
  let alCambiar: (() => void) | null = null;

  $effect(() => {
    const c = canvas;
    const boton = capa?.parentElement;
    if (!c || !boton) return;
    const gl = c.getContext('webgl2', { antialias: true, premultipliedAlpha: true, alpha: true });
    if (!gl) {
      console.error('[metal] el navegador no dio WebGL2: el botón de mandar se queda sin metal');
      return;
    }
    const compilar = (tipo: number, fuente: string) => {
      const s = gl.createShader(tipo)!;
      gl.shaderSource(s, fuente);
      gl.compileShader(s);
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
        console.error('[metal]', gl.getShaderInfoLog(s));
        return null;
      }
      return s;
    };
    const v = compilar(gl.VERTEX_SHADER, VERTEX);
    const f = compilar(gl.FRAGMENT_SHADER, FRAGMENT);
    if (!v || !f) return;
    const prog = gl.createProgram()!;
    gl.attachShader(prog, v);
    gl.attachShader(prog, f);
    gl.linkProgram(prog);
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
      console.error('[metal]', gl.getProgramInfoLog(prog));
      return;
    }
    gl.useProgram(prog);
    gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1]), gl.STATIC_DRAW);
    const pos = gl.getAttribLocation(prog, 'a_position');
    gl.enableVertexAttribArray(pos);
    gl.vertexAttribPointer(pos, 2, gl.FLOAT, false, 0, 0);
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
    const L = (n: string) => gl.getUniformLocation(prog, n);
    const uTiempo = L('u_time');
    const uResolucion = L('u_resolution');
    const uPixeles = L('u_pixelRatio');
    const aplicar = (U: Ajustes) => {
      gl.uniform4fv(L('u_colorBack'), U.colorBack);
      gl.uniform4fv(L('u_colorTint'), U.colorTint);
      gl.uniform1f(L('u_repetition'), U.repetition);
      gl.uniform1f(L('u_softness'), U.softness);
      gl.uniform1f(L('u_angle'), U.angle);
      gl.uniform1f(L('u_distortion'), U.distortion);
      gl.uniform1f(L('u_shiftRed'), U.shiftRed);
      gl.uniform1f(L('u_shiftBlue'), U.shiftBlue);
      gl.uniform1f(L('u_contour'), U.contour);
      gl.uniform1f(L('u_scale'), U.scale);
    };
    gl.uniform1f(L('u_fit'), 1);
    gl.uniform1f(L('u_rotation'), 0);
    gl.uniform1f(L('u_offsetX'), 0.1);
    gl.uniform1f(L('u_offsetY'), -0.1);
    gl.uniform1f(L('u_originX'), 0.5);
    gl.uniform1f(L('u_originY'), 0.5);
    gl.uniform1f(L('u_worldWidth'), 0);
    gl.uniform1f(L('u_worldHeight'), 0);

    let cual: 'metal' | 'aro' | null = null;
    let tiempo = 0;
    let velocidad = VEL.quieto;
    let encima = false;
    let reloj = 0;
    const dibujar = () => {
      const ahora = esAro() ? 'aro' : 'metal';
      if (cual !== ahora) {
        cual = ahora;
        aplicar(ahora === 'aro' ? ARO : METAL);
      }
      // Como el original: al menos el doble de pixeles que el tamaño en pantalla.
      const ancho = Math.max(1, boton.clientWidth);
      const escala = Math.max(window.devicePixelRatio || 1, 2);
      const w = Math.round(ancho * escala);
      const h = Math.round(Math.max(1, boton.clientHeight) * escala);
      if (c.width !== w || c.height !== h) {
        c.width = w;
        c.height = h;
        gl.viewport(0, 0, w, h);
        gl.uniform2f(uResolucion, w, h);
        gl.uniform1f(uPixeles, w / ancho);
      }
      gl.clearColor(0, 0, 0, 0);
      gl.clear(gl.COLOR_BUFFER_BIT);
      gl.uniform1f(uTiempo, tiempo * 1e-3);
      gl.drawArrays(gl.TRIANGLES, 0, 6);
    };

    let cuadro = 0;
    let antes: number | null = null;
    const corre = () => untrack(() => prendido) && !quieto?.matches;
    const paso = (t: number) => {
      cuadro = 0;
      const dt = antes === null ? 0 : Math.min(t - antes, 100);
      antes = t;
      if (!quieto?.matches) tiempo += dt * (esAro() ? 1 : velocidad);
      dibujar();
      if (corre()) cuadro = requestAnimationFrame(paso);
    };
    // Prendido corre; apagado se detiene. Con «reducir movimiento», un cuadro quieto cada vez que algo cambia.
    alCambiar = () => {
      if (cuadro) cancelAnimationFrame(cuadro);
      cuadro = 0;
      antes = null;
      if (untrack(() => prendido)) cuadro = requestAnimationFrame(paso);
    };
    alCambiar();

    const alEntrar = () => {
      encima = true;
      velocidad = VEL.encima;
    };
    const alSalir = () => {
      encima = false;
      velocidad = VEL.quieto;
    };
    // Al picar (solo el metal del claro): más rápido 300 ms y la onda desde donde se picó.
    const alPicar = (e: MouseEvent) => {
      if (!untrack(() => prendido) || quieto?.matches || esAro()) return;
      velocidad = VEL.pica;
      clearTimeout(reloj);
      reloj = window.setTimeout(() => (velocidad = encima ? VEL.encima : VEL.quieto), 300);
      const r = boton.getBoundingClientRect();
      const onda = { id: siguienteOnda++, x: e.clientX - r.left, y: e.clientY - r.top };
      ondas = [...ondas, onda];
      setTimeout(() => (ondas = ondas.filter((o) => o.id !== onda.id)), 600);
    };
    boton.addEventListener('mouseenter', alEntrar);
    boton.addEventListener('mouseleave', alSalir);
    boton.addEventListener('click', alPicar);
    quieto?.addEventListener('change', alCambiar);

    return () => {
      alCambiar = null;
      if (cuadro) cancelAnimationFrame(cuadro);
      clearTimeout(reloj);
      boton.removeEventListener('mouseenter', alEntrar);
      boton.removeEventListener('mouseleave', alSalir);
      boton.removeEventListener('click', alPicar);
      gl.getExtension('WEBGL_lose_context')?.loseContext();
    };
  });

  $effect(() => {
    void prendido;
    void tema;
    alCambiar?.();
  });
</script>

{#if enCristal}
  <span class="metal" class:prendido aria-hidden="true" bind:this={capa}>
    <canvas bind:this={canvas}></canvas>
    <span class="cara"></span>
  </span>
  {#each ondas as o (o.id)}
    <span class="onda" aria-hidden="true" style:left="{o.x}px" style:top="{o.y}px"></span>
  {/each}
{/if}

<style>
  .metal {
    display: none;
    position: absolute;
    inset: 0;
    border-radius: 50%;
    overflow: hidden;
    pointer-events: none;
  }

  .metal.prendido {
    display: block;
  }

  canvas {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    display: block;
    border-radius: 50%;
  }

  /* La cara negra, 2 px adentro del metal; al picar se hunde. */
  .cara {
    position: absolute;
    inset: 2px;
    border-radius: 50%;
    background: linear-gradient(180deg, #202020 0%, #000000 100%);
    transition: box-shadow 0.15s cubic-bezier(0.4, 0, 0.2, 1);
  }

  :global(button:active) > .metal .cara {
    box-shadow:
      inset 0 2px 4px rgba(0, 0, 0, 0.4),
      inset 0 1px 2px rgba(0, 0, 0, 0.3);
  }

  .onda {
    position: absolute;
    z-index: 2;
    width: 20px;
    height: 20px;
    border-radius: 50%;
    pointer-events: none;
    background: radial-gradient(circle, rgba(255, 255, 255, 0.4) 0%, rgba(255, 255, 255, 0) 70%);
    animation: onda 0.6s ease-out forwards;
  }

  @keyframes onda {
    0% {
      transform: translate(-50%, -50%) scale(0);
      opacity: 0.6;
    }
    100% {
      transform: translate(-50%, -50%) scale(4);
      opacity: 0;
    }
  }

  /* El «Aro» del oscuro: solo 2 px de metal, el centro transparente; sin cara y sin onda. */
  :global(:root[data-tema='oscuro']) .metal {
    -webkit-mask-image: radial-gradient(closest-side, transparent calc(100% - 2.5px), #000 calc(100% - 2px));
    mask-image: radial-gradient(closest-side, transparent calc(100% - 2.5px), #000 calc(100% - 2px));
  }

  :global(:root[data-tema='oscuro']) :is(.cara, .onda) {
    display: none;
  }
</style>
