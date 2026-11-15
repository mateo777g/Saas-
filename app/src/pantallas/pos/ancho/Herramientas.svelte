<!--
  La fila de herramientas de Mi menú, a lo ancho (adaptabilidad; maqueta GBWEGCsQFcwKkWm7Qe9FPA v4): la búsqueda en
  píldora con su brillo azul (diseno/Haz.svelte), junto el filtro que le pasen y, a la derecha, el conteo en mono
  («15 PRODUCTOS»), con su esqueleto mientras se lee la primera vez.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import Esqueleto from '../../../diseno/Esqueleto.svelte';
  import Haz from '../../../diseno/Haz.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import { vidrio } from '../../../diseno/vidrio';

  let {
    busqueda = $bindable(''),
    placeholder,
    aria,
    conteo,
    cargando = false,
    filtro,
  }: {
    busqueda?: string;
    placeholder: string;
    aria: string;
    conteo: string;
    cargando?: boolean;
    filtro?: Snippet;
  } = $props();
</script>

<div class="herramientas">
  <Haz>
    <label class="buscador" use:vidrio={'control'}>
      <Icono nombre="buscar" tamano={18} />
      <input type="search" aria-label={aria} {placeholder} bind:value={busqueda} autocomplete="off" />
    </label>
  </Haz>
  {@render filtro?.()}
  <span class="crece"></span>
  <span class="etiqueta">{#if cargando}<Esqueleto ancho="80px" alto="10px" />{:else}{conteo}{/if}</span>
</div>
