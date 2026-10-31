<!--
  Mientras se hace el anuncio: la rejilla de puntitos de OpenAI (encuestas 5 a 7 de la 7b, el código
  en planes/trabajo/7b/cargador-7b.md, ya sin React). Dos manchas de luz se mueven por la rejilla y
  crecen con el tiempo que suele tardar un anuncio (unos 2 minutos); OpenAI no dice cuánto lleva, así
  que no hay porcentaje: la pastilla de la esquina cuenta los segundos. Los puntitos son del color del
  texto, así sirven en los dos temas; con «reducir movimiento», las manchas se quedan quietas y se
  dibuja una vez por segundo.
-->
<script lang="ts">
  import { onMount } from 'svelte';

  // Cuándo empezó, con el reloj de este navegador.
  let { desde }: { desde: number } = $props();

  let lienzo: HTMLCanvasElement;
  let ahora = $state(Date.now());

  const GRID_GAP = 40 / 3;
  const BASE_DOT_RADIUS = 1.1;
  const BASE_ALPHA = 0.2;
  const ORB_RADIUS_SCALE = 0.5;
  const MIN_ACTIVE_DOT_DIAMETER = 2;
  const MAX_ACTIVE_DOT_DIAMETER = 7;
  const FULL_SIZE_PROGRESS = 0.7;
  const PROGRESS_NORMALIZER = 0.82;
  const FRAME_DURATION = 1000 / 30;

  const clamp = (v: number) => Math.min(1, Math.max(0, v));
  function smoothstep(v: number) {
    const c = clamp(v);
    return c * c * (3 - 2 * c);
  }
  function pingPong(from: number, to: number, duration: number, elapsed: number) {
    const phase = (elapsed / duration) % 2;
    const tri = phase <= 1 ? phase : 2 - phase;
    return from + (to - from) * ((1 - Math.cos(tri * Math.PI)) / 2);
  }
  function orbFalloff(radius: number, distance: number) {
    const inner = radius * 0.14;
    const broad = (distance - inner) / Math.max(radius - inner, 0.001);
    const core = (distance - inner) / Math.max(radius * 0.32, 0.001);
    return (1 - smoothstep(broad)) * (1 - smoothstep(core) * 0.12);
  }

  type Opciones = { accentColor: string; elapsedMilliseconds: number; width: number; height: number; progress: number; reducedMotion: boolean };
  function drawLoader(ctx: CanvasRenderingContext2D, o: Opciones) {
    const { width, height, progress } = o;
    ctx.clearRect(0, 0, width, height);
    if (width < GRID_GAP || height < GRID_GAP) return;
    const columns = Math.floor(width / GRID_GAP);
    const rows = Math.floor(height / GRID_GAP);
    const offsetX = (width - (columns - 1) * GRID_GAP) / 2;
    const offsetY = (height - (rows - 1) * GRID_GAP) / 2;
    const t = o.reducedMotion ? 0 : Math.max(0, o.elapsedMilliseconds) / 1000;
    const isCorner = (c: number, r: number) => (c === 0 || c === columns - 1) && (r === 0 || r === rows - 1);

    ctx.save();
    ctx.fillStyle = o.accentColor;
    ctx.globalAlpha = BASE_ALPHA;
    ctx.beginPath();
    for (let c = 0; c < columns; c++) {
      for (let r = 0; r < rows; r++) {
        if (isCorner(c, r)) continue;
        const x = offsetX + c * GRID_GAP;
        const y = offsetY + r * GRID_GAP;
        ctx.moveTo(x + BASE_DOT_RADIUS, y);
        ctx.arc(x, y, BASE_DOT_RADIUS, 0, Math.PI * 2);
      }
    }
    ctx.fill();

    const pf = Math.pow(clamp(progress / PROGRESS_NORMALIZER), 1.28);
    const growth = pf * (0.72 - 0.08 * smoothstep((pf - 0.5) / 0.5));
    const o1x = pingPong(0.18, 0.82, 3.46, t);
    const o1y = pingPong(0.18, 0.82, 4.87, t);
    const o2x = pingPong(0.82, 0.18, 4.31, t);
    const o2y = pingPong(0.82, 0.18, 4.42, t);
    const o1r = pingPong(0.35, 0.6, 3.6, t) * ORB_RADIUS_SCALE + growth;
    const o2r = pingPong(0.43, 0.7, 2.4, t) * ORB_RADIUS_SCALE + growth;
    const radiusStrength = o.reducedMotion ? 0.234 : pingPong(0.105, 0.234, 2.25, t);
    const minBright = pingPong(0.58, 0.82, 2.1, t);
    const maxDiam = MIN_ACTIVE_DOT_DIAMETER + (MAX_ACTIVE_DOT_DIAMETER - MIN_ACTIVE_DOT_DIAMETER) * smoothstep(progress / FULL_SIZE_PROGRESS);
    const maxR = Math.min(GRID_GAP * 0.48, maxDiam / 2);
    for (let c = 0; c < columns; c++) {
      for (let r = 0; r < rows; r++) {
        if (isCorner(c, r)) continue;
        const nx = columns === 1 ? 0.5 : c / (columns - 1);
        const ny = rows === 1 ? 0.5 : r / (rows - 1);
        const field = Math.max(orbFalloff(o1r, Math.hypot(nx - o1x, ny - o1y)), orbFalloff(o2r, Math.hypot(nx - o2x, ny - o2y)));
        const brightness = pf * Math.pow(field, 0.85 + pf * 1.1);
        const dotR = maxR * Math.pow(field, 1.15) * (radiusStrength / 0.234);
        if (dotR <= 0.2) continue;
        ctx.globalAlpha = minBright + (1 - minBright) * brightness * 0.64;
        ctx.beginPath();
        ctx.arc(offsetX + c * GRID_GAP, offsetY + r * GRID_GAP, dotR, 0, Math.PI * 2);
        ctx.fill();
      }
    }
    ctx.restore();
  }

  // Desde el primer segundo las manchas ya agrandan los puntitos (arrancan en un tercio de lo que
  // crecen) y siguen creciendo hasta los 2 minutos que suele tardar un anuncio.
  const crecimiento = (ms: number) => 0.35 + 0.65 * (1 - Math.exp(-ms / 60000));

  const segundos = $derived.by(() => {
    const s = Math.max(0, Math.floor((ahora - desde) / 1000));
    return s < 60 ? `${s} s` : `${Math.floor(s / 60)} min ${s % 60} s`;
  });

  onMount(() => {
    const reducido = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    let ultimo = -Infinity;
    let vivo = true;
    let espera = 0;
    const cuadro = (t: number) => {
      if (!vivo) return;
      if (t - ultimo >= FRAME_DURATION) {
        const w = lienzo.clientWidth;
        const h = lienzo.clientHeight;
        const pr = Math.min(window.devicePixelRatio || 1, 2);
        if (lienzo.width !== Math.round(w * pr) || lienzo.height !== Math.round(h * pr)) {
          lienzo.width = Math.round(w * pr);
          lienzo.height = Math.round(h * pr);
        }
        const ctx = lienzo.getContext('2d');
        ahora = Date.now();
        if (ctx) {
          ctx.setTransform(pr, 0, 0, pr, 0, 0);
          const ms = ahora - desde;
          drawLoader(ctx, { accentColor: getComputedStyle(lienzo).color, elapsedMilliseconds: ms, width: w, height: h, progress: crecimiento(ms), reducedMotion: reducido });
        }
        ultimo = t;
      }
      if (reducido) espera = window.setTimeout(() => cuadro(performance.now()), 1000);
      else espera = requestAnimationFrame(cuadro);
    };
    espera = requestAnimationFrame(cuadro);
    return () => {
      vivo = false;
      cancelAnimationFrame(espera);
      clearTimeout(espera);
    };
  });
</script>

<canvas bind:this={lienzo} aria-hidden="true"></canvas>
<span class="pastilla arriba-izq" role="status"><span class="latido"></span>Haciendo tu anuncio…</span>
<span class="pastilla abajo-der">{segundos}</span>

<style>
  canvas {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    display: block;
    pointer-events: none;
  }

  .pastilla {
    position: absolute;
    z-index: 1;
    height: 28px;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 7px;
    padding: 0 11px;
    border-radius: 14px;
    border: 1px solid var(--linea);
    background: var(--vidrio);
    backdrop-filter: blur(12px);
    -webkit-backdrop-filter: blur(12px);
    box-shadow: 0 1px 3px var(--sombra-segmento);
    font-size: 12px;
    font-weight: 600;
    white-space: nowrap;
  }

  .arriba-izq {
    top: 14px;
    left: 14px;
  }

  .abajo-der {
    right: 14px;
    bottom: 14px;
    min-width: 56px;
    font-size: 13px;
    font-variant-numeric: tabular-nums;
  }

  .latido {
    position: relative;
    width: 6px;
    height: 6px;
    flex: none;
  }

  .latido::before,
  .latido::after {
    content: '';
    position: absolute;
    inset: 0;
    border-radius: 50%;
    background: currentColor;
  }

  .latido::before {
    opacity: 0.5;
    animation: latir 1s cubic-bezier(0, 0, 0.2, 1) infinite;
  }

  @keyframes latir {
    75%,
    100% {
      transform: scale(2.4);
      opacity: 0;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .latido::before {
      animation: none;
    }
  }
</style>
