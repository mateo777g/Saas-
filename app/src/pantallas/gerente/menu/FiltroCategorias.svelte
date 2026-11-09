<!--
  El filtro de Productos (maqueta del Menú CC2rrjbgxC2yykNa33a3sA): un botón que abre la lista de
  las categorías del restaurante, como la cajita de sucursales, cada una con su ícono y cuántos
  productos tiene; arriba, Todas. Se cierra al elegir, con un clic afuera o con Escape. Sin
  categorías queda apagado.

  Se abre como la lista de «Nuevo producto» (diseno/Lista.svelte; regla «Movimiento», 8 nov 2026): el
  fondo crece desde el botón (220/28), cada opción sale de debajo del botón, de 0.8 a 1, una tras otra
  (220/26, 45 ms entre una y otra, máximo 8; al cerrar, al revés y de 20 en 20 ms) y la flecha se dobla en
  ✕ (260/22). Lo de adentro no cambió. Respeta «reducir movimiento».
-->
<script lang="ts">
  import { Tween } from 'svelte/motion';
  import { DURA_FLECHA, resorteFlecha, trazosFlecha } from '../../../diseno/flecha';
  import Icono from '../../../diseno/Icono.svelte';
  import IconoCategoria from '../../../diseno/IconoCategoria.svelte';
  import type { Categoria, Producto } from '../../../lib/menu';

  let {
    categorias,
    productos,
    filtro,
    alElegir,
  }: {
    categorias: Categoria[];
    productos: Producto[];
    filtro: number | null;
    alElegir: (id: number | null) => void;
  } = $props();

  let abierta = $state(false);
  let caja: HTMLDivElement;
  let boton: HTMLButtonElement;
  let alto = $state(0);
  const idLista = $props.id();

  const elegida = $derived(categorias.find((c) => c.id === filtro) ?? null);
  // Todas y cada categoría: cuántas opciones salen, para el orden de su salida.
  const n = $derived(categorias.length + 1);

  const quieto = typeof matchMedia === 'function' ? matchMedia('(prefers-reduced-motion: reduce)') : null;
  const doblez = new Tween(0, { duration: DURA_FLECHA, easing: resorteFlecha });
  $effect(() => {
    doblez.set(abierta ? 1 : 0, quieto?.matches ? { duration: 0 } : undefined);
  });
  const trazos = $derived(trazosFlecha(doblez.current));

  function cuantos(id: number) {
    return productos.filter((p) => p.categoria_id === id).length;
  }

  function elegir(id: number | null) {
    abierta = false;
    alElegir(id);
  }
</script>

<svelte:window
  onclick={(e) => {
    if (abierta && !caja.contains(e.target as Node)) abierta = false;
  }}
  onkeydown={(e) => {
    if (abierta && e.key === 'Escape') {
      abierta = false;
      boton.focus();
    }
  }}
/>

<!-- Cada opción sale desde el botón: --y es lo que hay de su lugar hasta debajo del botón. -->
{#snippet opcion(j: number, alPicar: () => void, elegidaAqui: boolean, nombre: string, cuenta: number, icono: string | null)}
  <button
    type="button"
    class="opcion"
    style:--i={j}
    style:--y="{50 + Math.min(j, 8) * 50}px"
    style:--dc="{(n - 1 - j) * 20}ms"
    onclick={alPicar}
  >
    <span class="cuadro-icono">
      {#if icono}<IconoCategoria id={icono} tamano={16} />{:else}<Icono nombre="menu" tamano={16} />{/if}
    </span>
    <span class="nombre">{nombre}</span>
    <span class="cuenta">{cuenta}</span>
    {#if elegidaAqui}<Icono nombre="check-delgado" tamano={16} />{/if}
  </button>
{/snippet}

<div class="filtro" class:abierta bind:this={caja} style:--alto="{Math.min(alto, 640)}px">
  <button
    type="button"
    class="boton"
    bind:this={boton}
    aria-expanded={abierta}
    aria-controls={idLista}
    disabled={!categorias.length}
    onclick={() => (abierta = !abierta)}
  >
    {#if elegida}
      <IconoCategoria id={elegida.icono} tamano={16} />
      {elegida.nombre}
    {:else}
      <Icono nombre="menu" tamano={16} />
      Todas las categorías
    {/if}
    <svg class="flecha" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"
      ><path d={trazos[0]}></path><path d={trazos[1]}></path></svg
    >
  </button>

  <div class="fondo" aria-hidden="true"></div>
  <div class="lista" id={idLista} inert={!abierta} bind:offsetHeight={alto}>
    <span class="etiqueta titulo">CATEGORÍAS</span>
    {@render opcion(0, () => elegir(null), filtro === null, 'Todas', productos.length, null)}
    {#each categorias as c, i (c.id)}
      {@render opcion(i + 1, () => elegir(c.id), filtro === c.id, c.nombre, cuantos(c.id), c.icono)}
    {/each}
  </div>
</div>

<style>
  .filtro {
    position: relative;
    display: flex;
  }

  /* boton() de diseno.py, el secundario; abierto, con chip. De 48 desde la tabla nueva (8 nov 2026), parejo con la búsqueda. */
  .boton {
    height: 48px;
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 0 14px;
    border: 1px solid var(--linea);
    border-radius: 12px;
    background: transparent;
    color: var(--texto);
    font-size: 13px;
    font-weight: 600;
    white-space: nowrap;
    transition:
      opacity 150ms,
      transform 0.2s ease;
  }

  .boton:hover:not(:disabled) {
    opacity: 0.86;
  }

  .boton:not(:disabled):active {
    transform: scale(0.95);
  }

  .boton:disabled {
    opacity: 0.4;
    cursor: default;
  }

  .boton[aria-expanded='true'] {
    background: var(--chip);
  }

  .flecha {
    width: 14px;
    height: 14px;
    flex: none;
    color: var(--suave);
  }

  /* El fondo crece desde debajo del botón hasta lo que mide la lista; las opciones van en su propia capa. */
  .fondo,
  .lista {
    position: absolute;
    top: calc(100% + 8px);
    left: 0;
    width: 320px;
  }

  .fondo {
    z-index: 3;
    height: 0;
    border: 1px solid var(--linea);
    border-radius: 18px;
    background: var(--solido);
    opacity: 0;
    pointer-events: none;
    transition:
      height 0.518s var(--resorte-fondo),
      opacity 0.25s ease,
      box-shadow 0.25s ease;
  }

  .abierta .fondo {
    height: var(--alto);
    opacity: 1;
    box-shadow: 0 24px 60px var(--sombra);
  }

  .lista {
    z-index: 4;
    max-height: 640px;
    overflow-y: hidden;
    padding: 8px;
    display: flex;
    flex-direction: column;
    gap: 2px;
    pointer-events: none;
  }

  .abierta .lista {
    overflow-y: auto;
    pointer-events: auto;
  }

  .titulo {
    padding: 10px 10px 8px;
    opacity: 0;
    transition: opacity 0.2s ease;
  }

  .abierta .titulo {
    opacity: 1;
    transition: opacity 0.3s ease 0.05s;
  }

  .opcion {
    width: 100%;
    flex: none;
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 6px 10px;
    border: 0;
    border-radius: 12px;
    background: transparent;
    color: var(--texto);
    text-align: left;
    opacity: 0;
    transform: translateY(calc(-1 * var(--y))) scale(0.8);
    transition:
      transform 0.607s var(--resorte-opcion) var(--dc),
      opacity 0.3s ease var(--dc),
      background-color 150ms;
  }

  .abierta .opcion {
    opacity: 1;
    transform: none;
    transition:
      transform 0.607s var(--resorte-opcion) calc(min(var(--i), 8) * 45ms),
      opacity 0.3s ease calc(min(var(--i), 8) * 45ms),
      background-color 150ms;
  }

  .opcion:hover {
    background: var(--chip);
  }

  .abierta .opcion:active {
    transform: scale(0.95);
    transition: transform 0.15s ease;
  }

  .cuadro-icono {
    width: 36px;
    height: 36px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 11px;
    background: var(--chip);
  }

  .nombre {
    flex: 1;
    min-width: 0;
    font-size: 13.5px;
    font-weight: 700;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .cuenta {
    font-family: var(--mono);
    font-size: 11px;
    color: var(--tenue);
  }

  @media (prefers-reduced-motion: reduce) {
    .filtro,
    .filtro * {
      transition: none !important;
    }
  }
</style>
