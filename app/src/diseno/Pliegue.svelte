<!--
  El fondo «Glass fold» del Agente IA en Cristal (el developer, 13 nov 2026; maqueta FiHkjmT1meyTu7zuU3En2n v48, «Vista:
  Agente IA»; planes/trabajo/estilo-cristal/agente.md). Es el shader de GradFlow (21st.dev) portado sin React ni paquetes,
  con los valores que eligió el developer: Noise 0.12, Scale 1, Speed 0.5, colores #5E5E5E, #1C1C1E y #FFFFFF.

  Un solo lienzo de todo el tamaño de lo que lo contiene, que se ve en dos esquinas («Dos esquinas»): arriba a la
  izquierda, más chica para no tapar el título, y abajo a la derecha; los pliegues siguen de una a otra. En oscuro se
  mezcla con el fondo de Cristal (screen: lo negro del shader casi no se nota); en claro, «Luz blanca» (screen al 0.85).

  Solo existe en Cristal. `visible` lo prende o lo desvanece (el agente: solo en blanco; al mandar la primera pregunta se
  va). Su bucle corre solo mientras se ve, en Cristal y con la pestaña a la vista (regla «Movimiento»: nada corre si no
  hay nada que dibujar); con «reducir movimiento», un cuadro quieto.
-->
<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { alCambiarEstilo, estiloActual } from '../lib/estilo';

  let { visible }: { visible: boolean } = $props();

  const AJUSTES = { color1: '#5E5E5E', color2: '#1C1C1E', color3: '#FFFFFF', velocidad: 0.5, escala: 1, grano: 0.12 };
  // Lo que tarda en desvanecerse (el CSS de abajo): después ya no se dibuja.
  const DESVANECE_MS = 600;

  const VERTEX = `attribute vec2 position;
varying vec2 vUv;
void main() {
  vUv = position * 0.5 + 0.5;
  gl_Position = vec4(position, 0.0, 1.0);
}`;

  const FRAGMENT = `precision highp float;
uniform float u_time;
uniform vec3 u_color1;
uniform vec3 u_color2;
uniform vec3 u_color3;
uniform float u_scale;
uniform float u_noise;
uniform vec2 u_resolution;
varying vec2 vUv;
float grain(vec2 st) { return fract(sin(dot(st, vec2(12.9898, 78.233))) * 43758.5453); }
vec2 centered(vec2 uv) { vec2 p = uv - 0.5; p.x *= u_resolution.x / max(u_resolution.y, 1.0); return p; }
mat2 rot(float a) { float s = sin(a); float c = cos(a); return mat2(c, -s, s, c); }
vec3 shade(vec2 uv, float time) {
  vec2 q = rot(0.6) * centered(uv) * 2.0 * u_scale;
  float t = time * 0.6;
  float pixel = 2.0 * u_scale / max(u_resolution.y, 1.0);
  vec3 color = mix(u_color2, u_color2 * 0.45, clamp(length(centered(uv)) * 1.3, 0.0, 1.0));
  for (int i = 0; i < 6; i++) {
    float fi = float(i);
    float bend = mod(fi, 2.0) * 2.0 - 1.0;
    float crease = (fi - 2.5) * 0.4
                 + 0.26 * sin(q.x * (1.05 + 0.12 * fi) + fi * 1.9 + t * (0.25 + 0.05 * fi))
                 + 0.1 * bend * q.x * q.x;
    float s = q.y - crease;
    float pane = smoothstep(-pixel, pixel, s);
    float back = max(s, 0.0);
    float body = exp(-back * 1.7);
    float fresnel = exp(-back * 8.0);
    float rim = exp(-back * 80.0);
    float inner = exp(-pow((back - 0.045) / 0.014, 2.0));
    float bloom = exp(-abs(s) * 20.0);
    vec3 tint = mix(u_color1, u_color3, clamp(fresnel * 0.6 + 0.08 + 0.14 * sin(fi * 2.1 + q.x * 0.8 + t * 0.2), 0.0, 1.0));
    vec3 light = tint * pane * (body * 0.42 + fresnel * 0.4)
               + u_color3 * (pane * (rim * 0.6 + inner * 0.12) + bloom * 0.1);
    color += light * (1.0 - color);
  }
  return clamp(color, 0.0, 1.0);
}
void main() {
  vec3 color = shade(vUv, u_time);
  if (u_noise > 0.001) {
    float g = grain(vUv * 200.0 + u_time * 0.1);
    color *= 1.0 - u_noise * 0.4 + u_noise * g * 0.4;
  }
  gl_FragColor = vec4(color, 1.0);
}`;

  function aVec3(hex: string): [number, number, number] {
    const n = parseInt(hex.replace('#', ''), 16);
    return [((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255];
  }

  let enCristal = $state(estiloActual() === 'cristal');
  const dejarDeEscuchar = alCambiarEstilo((estilo) => (enCristal = estilo === 'cristal'));
  onDestroy(dejarDeEscuchar);

  const quieto = typeof matchMedia === 'function' ? matchMedia('(prefers-reduced-motion: reduce)') : null;

  let canvas = $state<HTMLCanvasElement | null>(null);
  // Lo que prende el bucle (lo pone el efecto de abajo cuando el lienzo ya tiene su shader).
  let alCambiarVisible: ((si: boolean) => void) | null = null;

  // Monta el shader en el lienzo y lo corre mientras haga falta; al quitarlo, suelta el contexto de WebGL (el navegador
  // tiene pocos).
  $effect(() => {
    const c = canvas;
    if (!c) return;
    const gl = c.getContext('webgl', { antialias: false, alpha: false, preserveDrawingBuffer: true });
    if (!gl) {
      console.error('[pliegue] el navegador no dio WebGL: el agente se queda con el fondo de siempre');
      return;
    }
    const compilar = (tipo: number, fuente: string) => {
      const s = gl.createShader(tipo)!;
      gl.shaderSource(s, fuente);
      gl.compileShader(s);
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) console.error('[pliegue]', gl.getShaderInfoLog(s));
      return s;
    };
    const prog = gl.createProgram()!;
    gl.attachShader(prog, compilar(gl.VERTEX_SHADER, VERTEX));
    gl.attachShader(prog, compilar(gl.FRAGMENT_SHADER, FRAGMENT));
    gl.linkProgram(prog);
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
      console.error('[pliegue]', gl.getProgramInfoLog(prog));
      return;
    }
    gl.useProgram(prog);
    gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1]), gl.STATIC_DRAW);
    const pos = gl.getAttribLocation(prog, 'position');
    gl.enableVertexAttribArray(pos);
    gl.vertexAttribPointer(pos, 2, gl.FLOAT, false, 0, 0);
    const u = (k: string) => gl.getUniformLocation(prog, `u_${k}`);
    const uTiempo = u('time');
    const uResolucion = u('resolution');
    gl.uniform3fv(u('color1'), aVec3(AJUSTES.color1));
    gl.uniform3fv(u('color2'), aVec3(AJUSTES.color2));
    gl.uniform3fv(u('color3'), aVec3(AJUSTES.color3));
    gl.uniform1f(u('scale'), AJUSTES.escala);
    gl.uniform1f(u('noise'), AJUSTES.grano);

    const dibujar = (tiempo: number) => {
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      const w = Math.max(1, Math.round(c.clientWidth * dpr));
      const h = Math.max(1, Math.round(c.clientHeight * dpr));
      if (c.width !== w || c.height !== h) {
        c.width = w;
        c.height = h;
      }
      gl.viewport(0, 0, w, h);
      gl.uniform1f(uTiempo, tiempo);
      gl.uniform2f(uResolucion, w, h);
      gl.drawArrays(gl.TRIANGLES, 0, 6);
    };

    let cuadro = 0;
    let transcurrido = 0;
    let antes: number | null = null;
    let prendido = false;
    let apagarEn = 0;
    const paso = (ahora: number) => {
      cuadro = 0;
      if (antes !== null) transcurrido += Math.min((ahora - antes) / 1000, 0.1) * AJUSTES.velocidad;
      antes = ahora;
      dibujar(transcurrido);
      if (!quieto?.matches && (prendido || ahora < apagarEn)) cuadro = requestAnimationFrame(paso);
    };
    const arrancar = () => {
      if (cuadro) cancelAnimationFrame(cuadro);
      antes = null;
      cuadro = requestAnimationFrame(paso);
    };

    // Prende al verse; al desvanecerse sigue lo que dura el desvanecido y se detiene. Con «reducir movimiento», un cuadro.
    alCambiarVisible = (si) => {
      prendido = si;
      if (si) arrancar();
      else apagarEn = performance.now() + DESVANECE_MS;
    };
    alCambiarVisible(untrack(() => visible));
    const alCambiarTamano = new ResizeObserver(() => {
      if (!cuadro && prendido) arrancar();
    });
    alCambiarTamano.observe(c);
    const alQuieto = () => {
      if (prendido) arrancar();
    };
    quieto?.addEventListener('change', alQuieto);

    return () => {
      alCambiarVisible = null;
      if (cuadro) cancelAnimationFrame(cuadro);
      alCambiarTamano.disconnect();
      quieto?.removeEventListener('change', alQuieto);
      gl.getExtension('WEBGL_lose_context')?.loseContext();
    };
  });

  $effect(() => {
    const si = visible;
    alCambiarVisible?.(si);
  });
</script>

{#if enCristal}
  <canvas class="pliegue" class:fuera={!visible} aria-hidden="true" bind:this={canvas}></canvas>
{/if}

<style>
  /* Dos esquinas (el developer, 13 nov 2026; se descartaron «Franja», «Mancha» y «Esquina»). */
  .pliegue {
    position: absolute;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    display: block;
    pointer-events: none;
    -webkit-mask-image:
      radial-gradient(circle 560px at 0 0, #000 20%, transparent 100%),
      radial-gradient(circle 700px at 100% 100%, #000 22%, transparent 100%);
    mask-image:
      radial-gradient(circle 560px at 0 0, #000 20%, transparent 100%),
      radial-gradient(circle 700px at 100% 100%, #000 22%, transparent 100%);
    mix-blend-mode: screen;
    animation: pliegue-entra 0.6s ease;
    transition: opacity 0.6s ease;
  }

  @keyframes pliegue-entra {
    from {
      opacity: 0;
    }
  }

  /* En claro, «Luz blanca» (el developer, 13 nov 2026; se descartó «Al revés», las rayas grises). */
  :global(:root[data-tema='claro']) .pliegue {
    opacity: 0.85;
  }

  :global(:root) .pliegue.fuera {
    opacity: 0;
  }

  @media (prefers-reduced-motion: reduce) {
    .pliegue {
      animation: none;
      transition: none;
    }
  }
</style>
