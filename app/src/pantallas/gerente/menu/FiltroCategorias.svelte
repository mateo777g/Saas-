<!--
  El filtro de Productos (maqueta del Menú CC2rrjbgxC2yykNa33a3sA): un botón que abre la lista de
  las categorías del restaurante, como la cajita de sucursales, cada una con su ícono y cuántos
  productos tiene; arriba, Todas. Se cierra al elegir, con un clic afuera o con Escape. Sin
  categorías queda apagado.
-->
<script lang="ts">
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
  const idLista = $props.id();

  const elegida = $derived(categorias.find((c) => c.id === filtro) ?? null);

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

<div class="filtro" bind:this={caja}>
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
    <span class="suave"><Icono nombre="abajo" tamano={14} /></span>
  </button>

  {#if abierta}
    <div class="lista" id={idLista}>
      <span class="etiqueta titulo">CATEGORÍAS</span>
      <button type="button" class="opcion" onclick={() => elegir(null)}>
        <span class="cuadro-icono"><Icono nombre="menu" tamano={16} /></span>
        <span class="nombre">Todas</span>
        <span class="cuenta">{productos.length}</span>
        {#if filtro === null}<Icono nombre="check-delgado" tamano={16} />{/if}
      </button>
      {#each categorias as c (c.id)}
        <button type="button" class="opcion" onclick={() => elegir(c.id)}>
          <span class="cuadro-icono"><IconoCategoria id={c.icono} tamano={16} /></span>
          <span class="nombre">{c.nombre}</span>
          <span class="cuenta">{cuantos(c.id)}</span>
          {#if filtro === c.id}<Icono nombre="check-delgado" tamano={16} />{/if}
        </button>
      {/each}
    </div>
  {/if}
</div>

<style>
  .filtro {
    position: relative;
    display: flex;
  }

  /* boton() de diseno.py, el secundario; abierto, con chip. */
  .boton {
    height: 40px;
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
    transition: opacity 150ms;
  }

  .boton:hover:not(:disabled) {
    opacity: 0.86;
  }

  .boton:disabled {
    opacity: 0.4;
    cursor: default;
  }

  .boton[aria-expanded='true'] {
    background: var(--chip);
  }

  .suave {
    display: flex;
    color: var(--suave);
  }

  .lista {
    position: absolute;
    top: calc(100% + 8px);
    left: 0;
    z-index: 4;
    width: 320px;
    max-height: 640px;
    overflow-y: auto;
    padding: 8px;
    display: flex;
    flex-direction: column;
    gap: 2px;
    background: var(--solido);
    border: 1px solid var(--linea);
    border-radius: 18px;
    box-shadow: 0 24px 60px var(--sombra);
  }

  .titulo {
    padding: 10px 10px 8px;
  }

  .opcion {
    width: 100%;
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 6px 10px;
    border: 0;
    border-radius: 12px;
    background: transparent;
    color: var(--texto);
    text-align: left;
    transition: background-color 150ms;
  }

  .opcion:hover {
    background: var(--chip);
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
</style>
