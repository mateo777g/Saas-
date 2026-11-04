<!--
  Lo de arriba de las pantallas del punto de venta que no son una cuenta (maqueta Mesero y cocina):
  la estrella, el restaurante y, debajo, quién está («Pepe Martínez · Mesero») o
  qué se ve («La cuenta · Mesa 4»).
-->
<script lang="ts">
  import Estrella from '../../diseno/Estrella.svelte';

  let { restaurante, linea }: { restaurante: string; linea: string } = $props();
</script>

<div class="cel-arriba">
  <div class="cel-logo"><Estrella fondo="panel" tamano={22} /></div>
  <div class="cel-lugar">
    <b>{restaurante}</b>
    <span>{linea}</span>
  </div>
</div>
