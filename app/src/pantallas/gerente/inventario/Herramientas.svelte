<!--
  Lo de arriba de cada tabla del inventario (maqueta BBBNJST5w9qZfHWNdovGgb v3): la búsqueda en píldora con su brillo y,
  junto, el filtro, como en Productos de Mi menú; a la derecha, cuántos salen («16 INGREDIENTES»). Mientras lee por
  primera vez, la cuenta es un esqueleto.
-->
<script lang="ts">
  import Esqueleto from '../../../diseno/Esqueleto.svelte';
  import Haz from '../../../diseno/Haz.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import { vidrio } from '../../../diseno/vidrio';
  import type { OpcionFiltro } from '../../../lib/inventario';
  import Filtro from './Filtro.svelte';

  let {
    busqueda = $bindable(''),
    placeholder,
    cuenta,
    cargando = false,
    filtro,
  }: {
    busqueda?: string;
    placeholder: string; // «Busca un ingrediente…»
    cuenta: string; // «16 INGREDIENTES»
    cargando?: boolean;
    filtro: {
      titulo: string;
      todas: { boton: string; nombre: string; icono: string };
      opciones: OpcionFiltro[];
      total: number;
      elegida: string | null;
      alElegir: (valor: string | null) => void;
    };
  } = $props();
</script>

<div class="herramientas">
  <Haz>
    <label class="buscador" use:vidrio={'control'}>
      <Icono nombre="buscar" tamano={18} />
      <input type="search" aria-label={placeholder} {placeholder} bind:value={busqueda} />
    </label>
  </Haz>
  <Filtro {...filtro} />
  <span class="crece"></span>
  <span class="etiqueta cuenta">
    {#if cargando}<Esqueleto ancho="80px" alto="10px" />{:else}{cuenta}{/if}
  </span>
</div>

<style>
  .herramientas {
    position: relative;
    flex: none;
    min-height: 48px;
    display: flex;
    align-items: center;
    gap: 12px;
  }

  /* Píldora con el brillo de Haz, como la de Inicio (maqueta 4B6Qhre6dkK3pJgXtryyEV v3) y de su tamaño desde la
     tabla nueva: 48 de alto y hasta 780 de ancho; si no cabe, se angosta. */
  .herramientas > :global(div.haz) {
    flex: 0 1 780px;
    min-width: 0;
  }

  .buscador {
    width: 100%;
    height: 48px;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 14px 0 18px;
    border: 1px solid var(--borde-tarjeta);
    border-radius: 999px;
    background: var(--solido);
    color: var(--tenue);
  }

  .buscador:focus-within {
    border-color: var(--linea-fuerte);
  }

  /* Cristal: la búsqueda es vidrio (su receta en cristal.css), con su canto. */
  :global(:root[data-estilo='cristal']) .buscador {
    position: relative;
  }

  .buscador input {
    flex: 1;
    min-width: 0;
    border: 0;
    background: transparent;
    color: var(--texto);
    font-size: 15px;
    font-weight: 400;
    outline: none;
  }

  .buscador input::placeholder {
    color: var(--tenue);
  }

  .crece {
    flex-grow: 1;
  }

  .cuenta {
    white-space: nowrap;
  }
</style>
