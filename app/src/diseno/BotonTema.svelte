<!--
  El botón del tema: un solo cuadrito donde el sol se vuelve luna (el «Animated Theme Toggle» de 21st.dev que pegó el
  developer el 10 nov 2026, planes/trabajo/rediseno/21dev/01-tema-sol-luna.md; en Ajustes desde el 12 nov 2026, maqueta
  FiHkjmT1meyTu7zuU3En2n). Su movimiento, pasado de motion a la Web Animations API: cada trazo escala desde su centro y
  se dibuja de 0.6 a 1 de su escala; el sol se va y la luna llega a la vez, 0.7 s, ease-in-out. Con «reducir
  movimiento», cambia de golpe. Lleva la cajita del dock (`ayuda`), no la del navegador. Sirve para el tema del panel
  (Ajustes) y para el del menú del cliente («Tu menú en línea»): quien lo usa dice qué cambia.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import { pista } from './pista';

  let {
    tema,
    ayuda,
    alCambiar,
  }: {
    tema: 'claro' | 'oscuro';
    // «Cambiar tu panel a oscuro»: lo que dice su cajita y lo que lee un lector de pantalla.
    ayuda: string;
    alCambiar: () => void;
  } = $props();

  const SOL = [
    'M12.4058 17.7625C15.1672 17.7625 17.4058 15.5239 17.4058 12.7625C17.4058 10.0011 15.1672 7.76251 12.4058 7.76251C9.64434 7.76251 7.40576 10.0011 7.40576 12.7625C7.40576 15.5239 9.64434 17.7625 12.4058 17.7625Z',
    'M12.4058 1.76251V3.76251',
    'M12.4058 21.7625V23.7625',
    'M4.62598 4.98248L6.04598 6.40248',
    'M18.7656 19.1225L20.1856 20.5425',
    'M1.40576 12.7625H3.40576',
    'M21.4058 12.7625H23.4058',
    'M4.62598 20.5425L6.04598 19.1225',
    'M18.7656 6.40248L20.1856 4.98248',
  ];
  const LUNA =
    'M21.1918 13.2013C21.0345 14.9035 20.3957 16.5257 19.35 17.8781C18.3044 19.2305 16.8953 20.2571 15.2875 20.8379C13.6797 21.4186 11.9398 21.5294 10.2713 21.1574C8.60281 20.7854 7.07479 19.9459 5.86602 18.7371C4.65725 17.5283 3.81774 16.0003 3.4457 14.3318C3.07367 12.6633 3.18451 10.9234 3.76526 9.31561C4.346 7.70783 5.37263 6.29868 6.72501 5.25307C8.07739 4.20746 9.69959 3.56862 11.4018 3.41132C10.4052 4.75958 9.92564 6.42077 10.0503 8.09273C10.175 9.76469 10.8957 11.3364 12.0812 12.5219C13.2667 13.7075 14.8384 14.4281 16.5104 14.5528C18.1823 14.6775 19.8435 14.1979 21.1918 13.2013Z';

  let svg: SVGSVGElement;

  // pathLength = transform(scale, [0.6, 1], [0, 1]), como en la referencia.
  function cuadro(escala: number): Keyframe {
    const largo = Math.max(0, Math.min(1, (escala - 0.6) / 0.4));
    return { transform: `scale(${escala})`, strokeDasharray: `${largo} 1`, opacity: largo > 0 ? 1 : 0 };
  }

  // La ease-in-out de motion (cubic-bezier 0.42, 0, 0.58, 1), muestreada: así el largo del trazo sigue a la escala.
  function curva(x: number) {
    const bez = (u: number, a: number, b: number) => 3 * a * u * (1 - u) * (1 - u) + 3 * b * u * u * (1 - u) + u * u * u;
    let lo = 0;
    let hi = 1;
    for (let i = 0; i < 30; i++) {
      const m = (lo + hi) / 2;
      if (bez(m, 0.42, 0.58) < x) lo = m;
      else hi = m;
    }
    return bez((lo + hi) / 2, 0, 1);
  }

  function trazos(de: string) {
    return [...svg.querySelectorAll<SVGPathElement>(`${de} path`)];
  }

  function poner(t: 'claro' | 'oscuro') {
    for (const p of [...trazos('.sol'), ...trazos('.luna')]) p.getAnimations().forEach((a) => a.cancel());
    for (const p of trazos('.sol')) Object.assign(p.style, cuadro(t === 'claro' ? 1 : 0));
    for (const p of trazos('.luna')) Object.assign(p.style, cuadro(t === 'oscuro' ? 1 : 0));
  }

  function animar(aOscuro: boolean) {
    if (window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) return poner(aOscuro ? 'oscuro' : 'claro');
    const N = 28;
    const pasos = (de: number, a: number) => Array.from({ length: N + 1 }, (_, i) => cuadro(de + (a - de) * curva(i / N)));
    for (const p of trazos('.sol')) p.animate(pasos(aOscuro ? 1 : 0, aOscuro ? 0 : 1), { duration: 700, fill: 'forwards' });
    for (const p of trazos('.luna')) p.animate(pasos(aOscuro ? 0 : 1, aOscuro ? 1 : 0), { duration: 700, fill: 'forwards' });
  }

  // Si el tema cambia por el botón, se anima; si cambia por otro lado, se pone de una vez.
  let visto: 'claro' | 'oscuro' | null = null;
  let porElBoton = false;
  $effect(() => {
    const t = tema;
    if (visto === null || !svg) return;
    if (t === visto) return;
    if (porElBoton) animar(t === 'oscuro');
    else poner(t);
    visto = t;
    porElBoton = false;
  });

  onMount(() => {
    poner(tema);
    visto = tema;
  });
</script>

<button
  type="button"
  class="boton-tema"
  aria-label={ayuda}
  use:pista={ayuda}
  onclick={() => {
    porElBoton = true;
    alCambiar();
  }}
>
  <svg bind:this={svg} viewBox="0 0 25 25" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
    <g class="sol">
      {#each SOL as d (d)}<path pathLength="1" {d}></path>{/each}
    </g>
    <g class="luna"><path pathLength="1" d={LUNA}></path></g>
  </svg>
</button>

<style>
  .boton-tema {
    position: relative;
    width: 64px;
    height: 40px;
    flex: none;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    padding: 0;
    border: 1px solid var(--linea-fuerte);
    border-radius: 12px;
    background: var(--solido);
    color: var(--texto);
    cursor: pointer;
    transition:
      background-color 0.15s ease,
      transform 0.15s ease;
  }

  .boton-tema:hover {
    background: var(--chip);
  }

  .boton-tema:active {
    transform: scale(0.96);
  }

  .boton-tema:focus-visible {
    outline: none;
    box-shadow: 0 0 0 2px var(--campo-aro);
  }

  svg {
    width: 20px;
    height: 20px;
    overflow: visible;
  }

  path {
    transform-box: fill-box;
    transform-origin: center;
  }

  /* Cristal: dentro de una cajita de material, un relleno transparente (nunca vidrio sobre vidrio). */
  :global(:root[data-estilo='cristal'][data-tema='oscuro']) .boton-tema {
    background: rgba(255, 255, 255, 0.06);
    border-color: rgba(255, 255, 255, 0.1);
  }

  :global(:root[data-estilo='cristal'][data-tema='oscuro']) .boton-tema:hover {
    background: rgba(255, 255, 255, 0.1);
  }

  :global(:root[data-estilo='cristal'][data-tema='claro']) .boton-tema {
    background: var(--cl-relleno);
    border-color: rgba(255, 255, 255, 0.7);
  }

  :global(:root[data-estilo='cristal'][data-tema='claro']) .boton-tema:hover {
    background: rgba(118, 118, 128, 0.16);
  }

  @media (prefers-reduced-motion: reduce) {
    .boton-tema {
      transition: none;
    }
  }
</style>
