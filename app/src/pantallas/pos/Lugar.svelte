<!--
  Lo de arriba de las pantallas del punto de venta que no son una cuenta (maqueta Mesero y cocina):
  la marca, el restaurante y, debajo, quién está («Pepe Martínez · Mesero») o
  qué se ve («La cuenta · Mesa 4»). En el aparato la marca es el logo del restaurante (sin logo, solo el
  nombre; lib/marcaAparato.ts); en el panel del gerente, la estrella de Fragmentless. En el aparato, a la derecha, el
  botón «Cómo se ve» (aparato/ComoSeVe.svelte), salvo en las pantallas de adentro (`comoSeVe={false}`).
-->
<script lang="ts">
  import Estrella from '../../diseno/Estrella.svelte';
  import LogoRestaurante from '../../diseno/LogoRestaurante.svelte';
  import { leerMarca } from '../../lib/marcaAparato';
  import ComoSeVe from '../aparato/ComoSeVe.svelte';

  let { restaurante, linea, comoSeVe = true }: { restaurante: string; linea: string; comoSeVe?: boolean } = $props();

  const marca = leerMarca();
  const enAparato = document.documentElement.dataset.puerta === 'equipo';
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
  {#if enAparato && comoSeVe}<ComoSeVe />{/if}
</div>
