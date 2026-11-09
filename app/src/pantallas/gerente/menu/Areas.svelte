<!--
  La sección Áreas de Mi menú (maqueta de Opciones y áreas GhrEVWPmevfBZtWzi4exKi): dónde se prepara
  lo que se manda a cocina, en el orden en que se crearon, cada una con las categorías que le llegan
  y el lápiz. Al final, sin lápiz, «Lo sirve el mesero» con sus categorías: lo que no llega a
  ninguna pantalla. El área de cada categoría se elige en Categorías.

  Desde la tabla nueva (8 nov 2026, maqueta Ltm74p3fb7tiAqYcj5nqbX): la nota va suelta sobre el fondo y la
  tabla, en su marco. Mientras se lee el menú la primera vez (`cargando`), esqueletos con la forma de cada
  área y del conteo; «Lo sirve el mesero» no espera a nada, solo sus categorías.
-->
<script lang="ts">
  import BotonCuadro from '../../../diseno/BotonCuadro.svelte';
  import Esqueleto from '../../../diseno/Esqueleto.svelte';
  import Tabla from '../../../diseno/Tabla.svelte';
  import { plural } from '../../../lib/formato';
  import type { Area, Menu } from '../../../lib/menu';

  let {
    menu,
    cargando = false,
    esqueletos = 3,
    alEditar,
  }: { menu: Menu; cargando?: boolean; esqueletos?: number; alEditar: (a: Area) => void } = $props();

  const ESQUELETO = [
    { nombre: '56px', llegan: '40px' },
    { nombre: '44px', llegan: '52px' },
  ];
  const filasEsqueleto = $derived(Array.from({ length: esqueletos }, (_, i) => ESQUELETO[i % ESQUELETO.length]));

  // «Tacos · Tortas · Paquetes», en el orden del menú.
  function categoriasDe(id: number | null) {
    return menu.categorias.filter((c) => c.area_preparacion_id === id).map((c) => c.nombre);
  }
</script>

{#snippet llegan(nombres: string[])}
  <span class="llegan">
    {#if nombres.length}{nombres.join(' · ')}{:else}<span class="vacio">Sin categorías</span>{/if}
  </span>
{/snippet}

<div class="herramientas">
  <p class="nota">
    Cada categoría manda sus productos a un área, y cada pantalla de cocina muestra una. El área de cada
    categoría se elige en Categorías.
  </p>
  <span class="crece"></span>
  <span class="etiqueta">
    {#if cargando}<Esqueleto ancho="52px" alto="10px" />{:else}{plural(menu.areas.length, 'ÁREA', 'ÁREAS')}{/if}
  </span>
</div>

<Tabla
  columnas="1.4fr 3fr 88px"
  relleno="0 16px"
  altoFila={64}
  marco
  encabezados={[{ texto: 'Área' }, { texto: 'Le llegan' }, { texto: '' }]}
>
  {#if cargando}
    <!-- El esqueleto: tantas filas como áreas había la última vez, con su forma y sin su lápiz. -->
    <span class="solo-lector">Cargando tus áreas…</span>
    {#each filasEsqueleto as e, i (i)}
      <div class="fila quieta" aria-hidden="true">
        <span><Esqueleto ancho={e.nombre} alto="11px" /></span>
        <span><Esqueleto ancho={e.llegan} alto="10px" /></span>
        <span></span>
      </div>
    {/each}
  {:else}
    {#each menu.areas as a (a.id)}
      <div class="fila">
        <span class="nombre">{a.nombre}</span>
        {@render llegan(categoriasDe(a.id))}
        <span class="acciones"><BotonCuadro icono="crear" ayuda="Editar área" onclick={() => alEditar(a)} /></span>
      </div>
    {/each}
  {/if}
  <div class="fila">
    <span class="mesero">
      <span class="nombre suave">Lo sirve el mesero</span>
      <span class="pista">No llega a ninguna pantalla</span>
    </span>
    {#if cargando}<span aria-hidden="true"><Esqueleto ancho="96px" alto="10px" /></span>{:else}{@render llegan(categoriasDe(null))}{/if}
    <span></span>
  </div>
</Tabla>

<style>
  /* 48, como la de Productos con su búsqueda: la tabla no brinca al cambiar de sección. */
  .herramientas {
    flex: none;
    min-height: 48px;
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .nota {
    margin: 0;
    font-size: 12.5px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .crece {
    flex-grow: 1;
  }

  .nombre {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 13.5px;
    font-weight: 700;
  }

  .nombre.suave {
    font-weight: 600;
    color: var(--suave);
  }

  .mesero {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .pista {
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .llegan {
    font-size: 12.5px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .vacio {
    color: var(--tenue);
  }

  .acciones {
    display: flex;
    justify-content: flex-end;
  }
</style>
