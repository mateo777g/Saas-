<!--
  La parte Opciones de la ventana del producto (maqueta de Opciones y áreas GhrEVWPmevfBZtWzi4exKi):
  cada grupo que lleva es una pastilla con cuántas se eligen y su X, en el orden de la pestaña
  Opciones (el mismo en todos los productos). «Agregar grupo» abre hacia arriba la lista de los que
  le faltan, cada uno con sus opciones debajo; se cierra al elegir, con un clic afuera o con Escape.
  Sin grupos en el restaurante, solo dice dónde se crean. Se guarda con el producto.
-->
<script lang="ts">
  import Icono from '../../../diseno/Icono.svelte';
  import { dinero } from '../../../lib/formato';
  import type { Grupo } from '../../../lib/menu';
  import { reglaCorta } from '../../../lib/opciones';

  let {
    grupos,
    elegidos = $bindable([]),
    apagado = false,
  }: {
    grupos: Grupo[];
    elegidos?: number[];
    apagado?: boolean;
  } = $props();

  let abierta = $state(false);
  let caja = $state<HTMLDivElement>();
  let boton = $state<HTMLButtonElement>();
  const idLista = $props.id();

  const puestos = $derived(grupos.filter((g) => elegidos.includes(g.id)));
  const libres = $derived(grupos.filter((g) => !elegidos.includes(g.id)));

  // «Verde · Roja · Habanero (agotada)», con el precio extra cuando suma.
  function previa(g: Grupo) {
    return g.opciones
      .map((o) => (o.visible ? o.nombre + (o.precio_extra > 0 ? ` +${dinero(o.precio_extra)}` : '') : `${o.nombre} (agotada)`))
      .join(' · ');
  }

  function poner(id: number) {
    elegidos = [...elegidos, id];
    abierta = false;
    boton?.focus();
  }

  function quitar(id: number) {
    elegidos = elegidos.filter((x) => x !== id);
  }
</script>

<svelte:window
  onclick={(e) => {
    if (abierta && caja && !caja.contains(e.target as Node)) abierta = false;
  }}
  onkeydown={(e) => {
    // Escape cierra la lista, no la ventana del producto.
    if (abierta && e.key === 'Escape') {
      e.preventDefault();
      e.stopPropagation();
      abierta = false;
      boton?.focus();
    }
  }}
/>

<div class="campo" bind:this={caja}>
  <span class="etiqueta">OPCIONES</span>
  {#if !grupos.length}
    <p class="pista">Todavía no tienes grupos de opciones, como Salsa o Tamaño. Los creas en la pestaña Opciones.</p>
  {:else}
    <div class="pastillas">
      {#each puestos as g (g.id)}
        <span class="pastilla">
          {g.nombre}<span class="regla">{reglaCorta(g.minimo, g.maximo)}</span>
          <button
            type="button"
            class="quitar"
            aria-label="Quitar {g.nombre}"
            title="Quitar"
            disabled={apagado}
            onclick={() => quitar(g.id)}
          >
            <Icono nombre="cerrar" tamano={14} />
          </button>
        </span>
      {/each}
      {#if libres.length}
        <button
          type="button"
          class="agregar"
          bind:this={boton}
          aria-expanded={abierta}
          aria-controls={idLista}
          disabled={apagado}
          onclick={() => (abierta = !abierta)}
        >
          <Icono nombre="mas" tamano={14} />
          Agregar grupo
        </button>
      {/if}
    </div>
    <p class="pista">
      {puestos.length
        ? 'Se eligen en este orden al agregarlo. El orden se cambia en la pestaña Opciones.'
        : 'Sin opciones: se agrega con un solo toque.'}
    </p>

    {#if abierta}
      <div class="lista" id={idLista}>
        <span class="etiqueta titulo">TUS GRUPOS</span>
        {#each libres as g (g.id)}
          <button type="button" class="opcion" onclick={() => poner(g.id)}>
            <span class="textos">
              <span class="nombre">{g.nombre}</span>
              <span class="sub">{previa(g)}</span>
            </span>
            <span class="cuenta">{reglaCorta(g.minimo, g.maximo)}</span>
          </button>
        {/each}
      </div>
    {/if}
  {/if}
</div>

<style>
  /* La lista sale hacia arriba, pegada al campo, para no salirse de la ventana. */
  .campo {
    position: relative;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .pastillas {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 8px;
  }

  .pastilla {
    height: 34px;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 0 4px 0 12px;
    border: 1px solid var(--linea);
    border-radius: 10px;
    font-size: 12.5px;
    font-weight: 700;
    white-space: nowrap;
  }

  .regla {
    font-weight: 500;
    color: var(--tenue);
  }

  .quitar {
    width: 26px;
    height: 26px;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0;
    border: 0;
    border-radius: 7px;
    background: transparent;
    color: var(--suave);
  }

  .quitar:hover:not(:disabled) {
    background: var(--chip);
    color: var(--texto);
  }

  /* El botón chico de la maqueta. */
  .agregar {
    height: 34px;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 0 12px;
    border: 1px solid var(--linea);
    border-radius: 12px;
    background: transparent;
    color: var(--texto);
    font-size: 12.5px;
    font-weight: 600;
    white-space: nowrap;
    transition: opacity 150ms;
  }

  .agregar:hover:not(:disabled) {
    opacity: 0.86;
  }

  .agregar[aria-expanded='true'] {
    background: var(--chip);
  }

  .agregar:disabled,
  .quitar:disabled {
    opacity: 0.4;
  }

  .pista {
    margin: 0;
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--tenue);
  }

  .lista {
    position: absolute;
    bottom: calc(100% + 8px);
    left: 0;
    z-index: 4;
    width: 340px;
    max-height: 300px;
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

  .textos {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .nombre {
    font-size: 13.5px;
    font-weight: 700;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .sub {
    font-size: 11.5px;
    font-weight: 500;
    color: var(--suave);
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
    .agregar,
    .opcion {
      transition: none;
    }
  }
</style>
