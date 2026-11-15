<!--
  El «⋯» de la cuenta a lo ancho (adaptabilidad; maqueta GBWEGCsQFcwKkWm7Qe9FPA v4, «Mesa 4»): el botón de solo ícono y
  su lista, que se abre como la de Mi menú (diseno/Lista.svelte; regla «Las listas que se abren»): el fondo crece con su
  resorte (220/28) y cada opción sale del botón, de 0.8 a 1, una tras otra (220/26, 45 ms); al cerrar regresan al botón,
  más rápido (de 20 en 20 ms). Cada opción lleva su ícono en un cuadrito gris; la que borra, en rojo. 250 de ancho, 8
  debajo del botón y a ras de su orilla derecha; si no cabe abajo, se abre arriba.

  La lista vive en <body> (como la de la barra lateral plegada): la tarjeta de la derecha se desliza por dentro y la
  cortaría. Se cierra con un clic afuera, con Escape (regresa al botón), al deslizar o al cambiar el tamaño de la ventana.
  Respeta «reducir movimiento».
-->
<script lang="ts" module>
  export type OpcionMenu = { clave: string; texto: string; icono: string; peligro?: boolean; apagado?: boolean };
</script>

<script lang="ts">
  import { tick } from 'svelte';
  import BotonCuadro from '../../../diseno/BotonCuadro.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import { vidrio } from '../../../diseno/vidrio';

  let {
    opciones,
    ayuda = 'Más acciones',
    alElegir,
  }: { opciones: OpcionMenu[]; ayuda?: string; alElegir: (clave: string) => void } = $props();

  const ANCHO = 250;
  const quieto = typeof matchMedia === 'function' ? matchMedia('(prefers-reduced-motion: reduce)') : null;

  let boton: HTMLElement | null = null;
  let caja = $state<HTMLDivElement>();
  let puesta = $state(false); // en la página (también mientras se cierra)
  let abierta = $state(false);
  let arriba = $state(false);
  let midiendo = $state(false);
  let lugar = $state({ top: 0, left: 0 });
  let alto = $state(0);
  let desde = $state<number[]>([]);
  let cierre: ReturnType<typeof setTimeout> | undefined;

  // La lista vive en <body>; al irse, Svelte la quita de ahí.
  function alCuerpo(nodo: HTMLElement) {
    document.body.append(nodo);
    return { destroy: () => nodo.remove() };
  }

  async function abrir(b: HTMLElement) {
    clearTimeout(cierre);
    boton = b;
    abierta = false;
    midiendo = true;
    puesta = true;
    await tick();
    if (!caja) return;
    const r = b.getBoundingClientRect();
    const alLista = caja.offsetHeight;
    arriba = r.bottom + 8 + alLista > window.innerHeight - 8 && r.top - 8 - alLista > 8;
    lugar = { top: arriba ? r.top - 8 - alLista : r.bottom + 8, left: Math.max(8, r.right - ANCHO) };
    // De dónde sale cada renglón: del centro del botón hasta su propio centro.
    const centro = r.top + r.height / 2;
    desde = [...caja.querySelectorAll<HTMLElement>('.renglon')].map((f) => centro - (lugar.top + f.offsetTop + f.offsetHeight / 2));
    await tick();
    void caja.offsetHeight;
    midiendo = false;
    abierta = true;
    caja.querySelector<HTMLButtonElement>('button:not(:disabled)')?.focus({ preventScroll: true });
  }

  function cerrar(volverAlBoton = false) {
    if (!puesta) return;
    abierta = false;
    if (volverAlBoton) boton?.focus({ preventScroll: true });
    clearTimeout(cierre);
    if (quieto?.matches) puesta = false;
    else cierre = setTimeout(() => (puesta = abierta), 450);
  }

  function elegir(o: OpcionMenu) {
    cerrar();
    alElegir(o.clave);
  }

  function tecla(e: KeyboardEvent) {
    if ((e.key !== 'ArrowDown' && e.key !== 'ArrowUp') || !caja) return;
    e.preventDefault();
    const botones = [...caja.querySelectorAll<HTMLButtonElement>('button:not(:disabled)')];
    const i = botones.indexOf(document.activeElement as HTMLButtonElement);
    botones[(i + (e.key === 'ArrowDown' ? 1 : botones.length - 1)) % botones.length]?.focus();
  }

  $effect(() => {
    if (!puesta) return;
    const fuera = (e: PointerEvent) => {
      const t = e.target as Node;
      if (!caja?.contains(t) && !boton?.contains(t)) cerrar();
    };
    const esc = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && abierta) {
        e.stopPropagation();
        cerrar(true);
      }
    };
    const mueve = (e: Event) => {
      if (!caja?.contains(e.target as Node)) cerrar();
    };
    const cambia = () => cerrar();
    document.addEventListener('pointerdown', fuera, true);
    document.addEventListener('keydown', esc, true);
    document.addEventListener('scroll', mueve, true);
    window.addEventListener('resize', cambia);
    return () => {
      document.removeEventListener('pointerdown', fuera, true);
      document.removeEventListener('keydown', esc, true);
      document.removeEventListener('scroll', mueve, true);
      window.removeEventListener('resize', cambia);
    };
  });

  $effect(() => () => clearTimeout(cierre));
</script>

<BotonCuadro
  icono="puntos"
  {ayuda}
  expandido={abierta}
  onclick={(e) => (abierta ? cerrar() : abrir(e.currentTarget as HTMLElement))}
/>

{#if puesta}
  {@const n = opciones.length}
  <div
    class="menu-cuenta"
    class:abierta
    class:arriba
    class:midiendo
    role="menu"
    tabindex="-1"
    aria-label={ayuda}
    inert={!abierta && !midiendo}
    style:top="{lugar.top}px"
    style:left="{lugar.left}px"
    style:width="{ANCHO}px"
    style:--alto="{alto}px"
    bind:this={caja}
    bind:offsetHeight={alto}
    onkeydown={tecla}
    use:alCuerpo
  >
    <div class="fondo" aria-hidden="true" use:vidrio={'hoja'}></div>
    {#each opciones as o, j (o.clave)}
      {@const k = arriba ? n - 1 - j : j}
      <button
        type="button"
        role="menuitem"
        class="renglon"
        class:peligro={o.peligro}
        disabled={o.apagado}
        style:--y="{desde[j] ?? 0}px"
        style:--da="{Math.min(k, 8) * 45}ms"
        style:--dc="{(n - 1 - k) * 20}ms"
        onclick={() => elegir(o)}
      >
        <span class="cuadro-l"><Icono nombre={o.icono} tamano={16} /></span>
        <span>{o.texto}</span>
      </button>
    {/each}
  </div>
{/if}

<style>
  .menu-cuenta {
    position: fixed;
    z-index: 60;
    padding: 8px;
    display: flex;
    flex-direction: column;
    gap: 2px;
    isolation: isolate;
    outline: none;
    pointer-events: none;
    font-family: var(--jakarta, inherit);
  }

  .menu-cuenta.abierta {
    pointer-events: auto;
  }

  /* El fondo crece desde el botón hasta lo que mide la lista (hacia arriba si se abrió arriba). */
  .fondo {
    position: absolute;
    left: 0;
    right: 0;
    top: 0;
    z-index: -1;
    height: 0;
    border: 1px solid var(--linea);
    border-radius: 18px;
    background: var(--solido);
    opacity: 0;
    transition:
      height 0.32s ease-in,
      opacity 0.2s ease 0.1s,
      box-shadow 0.25s ease;
  }

  .arriba .fondo {
    top: auto;
    bottom: 0;
  }

  .abierta .fondo {
    height: var(--alto);
    opacity: 1;
    box-shadow: 0 24px 60px var(--sombra);
    transition:
      height 0.518s var(--resorte-fondo),
      opacity 0.25s ease,
      box-shadow 0.25s ease;
  }

  .renglon {
    height: 44px;
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 0 10px;
    border: 0;
    border-radius: 12px;
    background: transparent;
    color: var(--texto);
    font-size: 13px;
    font-weight: 600;
    text-align: left;
    white-space: nowrap;
    opacity: 0;
    transform: translateY(var(--y)) scale(0.8);
    transition:
      transform 0.35s ease-in var(--dc),
      opacity 0.2s ease var(--dc),
      background-color 0.15s ease;
  }

  .abierta .renglon {
    opacity: 1;
    transform: none;
    transition:
      transform 0.607s var(--resorte-opcion) var(--da),
      opacity 0.3s ease var(--da),
      background-color 0.15s ease;
  }

  .midiendo .renglon {
    transition: none;
  }

  .renglon:hover:not(:disabled),
  .renglon:focus-visible {
    background: var(--chip);
    outline: none;
  }

  .abierta .renglon:active:not(:disabled) {
    transform: scale(0.95);
    transition: transform 0.15s ease;
  }

  .abierta .renglon:disabled {
    opacity: 0.45;
    cursor: default;
  }

  .cuadro-l {
    width: 32px;
    height: 32px;
    flex: none;
    display: grid;
    place-items: center;
    border-radius: 10px;
    background: var(--chip);
  }

  .peligro {
    color: var(--rojo);
  }

  .peligro .cuadro-l {
    background: color-mix(in srgb, var(--rojo) 11%, transparent);
  }

  @media (prefers-reduced-motion: reduce) {
    .menu-cuenta,
    .menu-cuenta * {
      transition: none !important;
    }
  }
</style>
