<!--
  El bote de basura 3D de las ventanas de eliminar (Mi menú, versiones 11 y 12; maqueta U9YqpsSb2PeB5pFXTPvh1C):
  dibujado a mano con el estilo de las figuras de @lucasmarkes/hairline (líneas de 0.9 px que no crecen con
  la figura, caras lisas, los mismos colores medidos en claro y en oscuro). Un cilindro isométrico que se
  angosta abajo, con 5 costillas, y una tapa con asa, la pieza que se mueve: un disco en 3D de verdad que
  gira sobre una bisagra atrás a la derecha de la boca, como la tapa de una botella. Se dibuja cuadro por
  cuadro, sin sus caras de atrás.

  `abierta` la abre hasta quedar parada (1.85 rad) con un resorte 200/16; al cerrarse choca con la boca y
  rebota (regresa con el 35 % de su velocidad). Con «reducir movimiento» va directo. Mide 136 px.
-->
<script lang="ts">
  import { onDestroy, onMount } from 'svelte';

  let { abierta = false }: { abierta?: boolean } = $props();

  let tapa: SVGGElement;

  // Mundo isométrico: x → (0.866, 0.5) en pantalla, y → (−0.866, 0.5), z → (0, −1). La tapa (radio 75, 13 de
  // grueso) gira sobre una bisagra a lo largo del eje x: su eje hacia el frente (y) se vuelve y·cosφ + z·senφ.
  const TAPA = { cx: 200, cy: 130, R: 75, h: 13, asa: 22, alto: 16, fondo: 5 };
  const N = 48;
  const ABIERTA = 1.85;
  const pantalla = (x: number, y: number, z: number) => [0.866 * (x - y), 0.5 * (x + y) - z];
  const BISAGRA = (() => {
    const [sx, sy] = pantalla(0, -TAPA.R, 0);
    return [TAPA.cx + sx, TAPA.cy + sy];
  })();
  // Un punto de la tapa: a lo largo de la bisagra (a), desde la bisagra hacia el frente (b), de grueso (z).
  function mundo(a: number, b: number, z: number, f: number): [number, number, number] {
    const c = Math.cos(f);
    const s = Math.sin(f);
    return [a, b * c - z * s, b * s + z * c];
  }
  function aPantalla(q: [number, number, number]): [number, number] {
    const [sx, sy] = pantalla(q[0], q[1], q[2]);
    return [BISAGRA[0] + sx, BISAGRA[1] + sy];
  }
  const camino = (pts: [number, number][], cerrar = true) =>
    'M' + pts.map((q) => q[0].toFixed(1) + ' ' + q[1].toFixed(1)).join(' L') + (cerrar ? ' Z' : '');

  function dibujar(f: number) {
    if (!tapa) return;
    const c = Math.cos(f);
    const s = Math.sin(f);
    const anillo = (z: number, r = TAPA.R) =>
      Array.from({ length: N }, (_, k) => {
        const al = (2 * Math.PI * k) / N;
        return mundo(r * Math.cos(al), TAPA.R + r * Math.sin(al), z, f);
      });
    const abajo = anillo(0);
    const arriba = anillo(TAPA.h);
    const caraArriba = -s + c > 0;
    const visibles: boolean[] = [];
    for (let k = 0; k < N; k++) {
      const al = (2 * Math.PI * (k + 0.5)) / N;
      visibles.push(Math.cos(al) + Math.sin(al) * c + Math.sin(al) * s > 0);
    }
    const piezas: string[] = [];
    for (let k = 0; k < N; k++) {
      if (!visibles[k]) continue;
      const k2 = (k + 1) % N;
      piezas.push(`<path class="b-banda" d="${camino([abajo[k], abajo[k2], arriba[k2], arriba[k]].map(aPantalla))}"></path>`);
    }
    const lejano = caraArriba ? abajo : arriba;
    let orillas = '';
    for (let k = 0; k < N; k++) {
      const k2 = (k + 1) % N;
      if (visibles[k]) orillas += camino([lejano[k], lejano[k2]].map(aPantalla), false) + ' ';
      if (visibles[k] !== visibles[(k + N - 1) % N]) orillas += camino([abajo[k], arriba[k]].map(aPantalla), false) + ' ';
    }
    const cara = `<path class="b-tapa${caraArriba ? '' : ' b-tapa-dentro'}" d="${camino((caraArriba ? arriba : abajo).map(aPantalla))}"></path>`;
    let asa = '';
    if (caraArriba) {
      const L = TAPA.asa;
      const z1 = TAPA.h;
      const z2 = TAPA.h + TAPA.alto;
      const o = TAPA.fondo;
      const tramo = (db: number) =>
        camino([mundo(-L, TAPA.R + db, z1, f), mundo(-L, TAPA.R + db, z2, f), mundo(L, TAPA.R + db, z2, f), mundo(L, TAPA.R + db, z1, f)].map(aPantalla), false);
      const union =
        camino([mundo(-L, TAPA.R, z2, f), mundo(-L, TAPA.R + o, z2, f)].map(aPantalla), false) +
        ' ' +
        camino([mundo(L, TAPA.R, z2, f), mundo(L, TAPA.R + o, z2, f)].map(aPantalla), false);
      asa = `<path class="b-asa" d="${tramo(o)}"></path><path class="b-asa" d="${tramo(0)}"></path><path class="b-asa" d="${union}"></path>`;
    }
    const dentro = caraArriba ? '' : `<path class="b-tenue" d="${camino(anillo(0, TAPA.R - 8).map(aPantalla))}"></path>`;
    tapa.innerHTML = piezas.join('') + `<path class="b-asa" d="${orillas}"></path>` + cara + dentro + asa;
  }

  // Un resorte de verdad (200/16): al abrir se pasa un poco y regresa; al cerrar, la tapa choca y rebota.
  const e = { f: 0, w: 0, meta: 0, corriendo: false };
  let cuadro = 0;
  const quieto = typeof matchMedia === 'function' ? matchMedia('(prefers-reduced-motion: reduce)') : null;

  function correr() {
    let antes = performance.now();
    const paso = (ahora: number) => {
      const dt = Math.min(0.032, (ahora - antes) / 1000);
      antes = ahora;
      for (let i = 0; i < 4; i++) {
        const h = dt / 4;
        e.w += (200 * (e.meta - e.f) - 16 * e.w) * h;
        e.f += e.w * h;
        if (e.f < 0) {
          e.f = 0;
          e.w = -e.w * 0.35;
        }
      }
      if (Math.abs(e.meta - e.f) < 0.002 && Math.abs(e.w) < 0.03) {
        e.f = e.meta;
        e.w = 0;
        e.corriendo = false;
        dibujar(e.f);
        return;
      }
      dibujar(e.f);
      cuadro = requestAnimationFrame(paso);
    };
    cuadro = requestAnimationFrame(paso);
  }

  function ir(meta: number) {
    e.meta = meta;
    if (quieto?.matches) {
      e.f = meta;
      e.w = 0;
      dibujar(meta);
      return;
    }
    if (!e.corriendo) {
      e.corriendo = true;
      correr();
    }
  }

  onMount(() => dibujar(0));
  onDestroy(() => cancelAnimationFrame(cuadro));

  $effect(() => {
    ir(abierta ? ABIERTA : 0);
  });
</script>

<div class="cf-figura" aria-hidden="true">
  <svg class="bote" viewBox="0 -115 400 435" aria-hidden="true">
    <path class="b-cuerpo" d="M114.3 130 L129.0 270 A71.0 41.0 0 0 0 271.0 270 L285.7 130 A85.7 49.5 0 0 1 114.3 130 Z"></path>
    <path class="b-tenue" d="M129.0 270 A71.0 41.0 0 0 1 271.0 270"></path>
    <ellipse cx="200" cy="130" rx="85.7" ry="49.5" class="b-boca"></ellipse>
    <ellipse cx="200" cy="132" rx="79.7" ry="46.0" class="b-tenue"></ellipse>
    <path class="b-tenue" d="M255.8 188.2 L248.8 283.1"></path>
    <path class="b-linea" d="M229.9 197.3 L226.1 291.1"></path>
    <path class="b-linea" d="M200.0 200.5 L200.0 293.9"></path>
    <path class="b-linea" d="M170.1 197.3 L173.9 291.1"></path>
    <path class="b-tenue" d="M144.2 188.2 L151.2 283.1"></path>
    <g class="bote-tapa" bind:this={tapa}></g>
  </svg>
</div>

<style>
  .cf-figura {
    width: 136px;
    aspect-ratio: 400 / 435;
    color: var(--suave);
  }

  .bote {
    --b-linea: rgb(164, 164, 172);
    --b-tenue: rgb(224, 224, 228);
    --b-cara: #ffffff;
    --b-fuerte: rgb(35, 35, 39);
    --b-boca: rgb(238, 238, 241);
    --b-dentro: rgb(226, 226, 231);
    display: block;
    width: 100%;
    height: 100%;
    overflow: visible;
  }

  :global(:root[data-tema='oscuro']) .bote {
    --b-linea: rgb(91, 93, 100);
    --b-tenue: rgb(41, 41, 45);
    --b-cara: rgb(8, 9, 10);
    --b-fuerte: rgb(208, 214, 224);
    --b-boca: rgb(20, 20, 23);
    --b-dentro: rgb(30, 30, 34);
  }

  .bote :global(*) {
    vector-effect: non-scaling-stroke;
    stroke-width: 0.9;
    stroke-linejoin: round;
    stroke-linecap: round;
  }

  .bote :global(.b-cuerpo) {
    fill: var(--b-cara);
    stroke: var(--b-linea);
  }

  .bote :global(.b-boca) {
    fill: var(--b-boca);
    stroke: var(--b-linea);
  }

  .bote :global(.b-tenue) {
    fill: none;
    stroke: var(--b-tenue);
  }

  .bote :global(.b-linea) {
    fill: none;
    stroke: var(--b-linea);
  }

  .bote :global(.b-tapa) {
    fill: var(--b-cara);
    stroke: var(--b-fuerte);
  }

  .bote :global(.b-asa) {
    fill: none;
    stroke: var(--b-fuerte);
  }

  .bote :global(.b-banda) {
    fill: var(--b-cara);
    stroke: var(--b-cara);
  }

  .bote :global(.b-tapa-dentro) {
    fill: var(--b-dentro);
  }
</style>
