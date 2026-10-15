<!--
  La sección Áreas de Mi menú (maqueta de Opciones y áreas GhrEVWPmevfBZtWzi4exKi): dónde se prepara
  lo que se manda a cocina, en el orden en que se crearon, cada una con las categorías que le llegan
  y el lápiz. Al final, sin lápiz, «Lo sirve el mesero» con sus categorías: lo que no llega a
  ninguna pantalla. El área de cada categoría se elige en Categorías.
-->
<script lang="ts">
  import BotonCuadro from '../../../diseno/BotonCuadro.svelte';
  import Tabla from '../../../diseno/Tabla.svelte';
  import { plural } from '../../../lib/formato';
  import type { Area, Menu } from '../../../lib/menu';

  let { menu, alEditar }: { menu: Menu; alEditar: (a: Area) => void } = $props();

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
  <span class="etiqueta">{plural(menu.areas.length, 'ÁREA', 'ÁREAS')}</span>
</div>

<Tabla
  columnas="1.4fr 3fr 88px"
  relleno="0 16px"
  altoFila={64}
  encabezados={[{ texto: 'ÁREA' }, { texto: 'LE LLEGAN' }, { texto: '' }]}
>
  {#each menu.areas as a (a.id)}
    <div class="fila">
      <span class="nombre">{a.nombre}</span>
      {@render llegan(categoriasDe(a.id))}
      <span class="acciones"><BotonCuadro icono="crear" ayuda="Editar área" onclick={() => alEditar(a)} /></span>
    </div>
  {/each}
  <div class="fila">
    <span class="mesero">
      <span class="nombre suave">Lo sirve el mesero</span>
      <span class="pista">No llega a ninguna pantalla</span>
    </span>
    {@render llegan(categoriasDe(null))}
    <span></span>
  </div>
</Tabla>

<style>
  .herramientas {
    flex: none;
    min-height: 40px;
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
