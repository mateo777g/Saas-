<!--
  Lo de arriba de las pantallas del punto de venta que no son una cuenta (maqueta Mesero y cocina):
  el ∫∫ en su cuadro de acento, el restaurante y, debajo, quién está («Pepe Martínez · Mesero») o
  qué se ve («La cuenta · Mesa 4»).
-->
<script lang="ts">
  import Integral from '../../diseno/Integral.svelte';

  let { restaurante, linea }: { restaurante: string; linea: string } = $props();
</script>

<div class="cel-arriba">
  <div class="cel-logo"><Integral ancho={20} alto={22} /></div>
  <div class="cel-lugar">
    <b>{restaurante}</b>
    <span>{linea}</span>
  </div>
</div>
