<!--
  Lo de arriba de las pantallas del punto de venta que no son una cuenta (maqueta Mesero y cocina):
  la marca, el restaurante y, debajo, quién está («Pepe Martínez · Mesero») o
  qué se ve («La cuenta · Mesa 4»). En el aparato la marca es el logo del restaurante (sin logo, solo el
  nombre; lib/marcaAparato.ts); en el panel del gerente, la estrella de Fragmentless.
-->
<script lang="ts">
  import Estrella from '../../diseno/Estrella.svelte';
  import LogoRestaurante from '../../diseno/LogoRestaurante.svelte';
  import { leerMarca } from '../../lib/marcaAparato';

  let { restaurante, linea }: { restaurante: string; linea: string } = $props();

  const marca = leerMarca();
</script>

<div class="cel-arriba">
  {#if !marca}
    <div class="cel-logo"><Estrella fondo="panel" tamano={22} /></div>
  {:else if marca.logo}
    <LogoRestaurante ruta={marca.logo} />
  {/if}
  <div class="cel-lugar">
    <b>{restaurante}</b>
    <span>{linea}</span>
  </div>
</div>
