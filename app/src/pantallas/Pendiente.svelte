<!--
  TEMPORAL: lo que se ve después de entrar mientras no existen los paneles (piezas 2 y 3 del
  punto 5). Solo sirve para probar el login y "Cerrar sesión"; se borra cuando llegue tu panel.
-->
<script lang="ts">
  import Boton from '../diseno/Boton.svelte';
  import type { Panel } from '../lib/sesion';

  let { panel, alSalir }: { panel: Panel; alSalir: () => void } = $props();
</script>

<main>
  <p class="etiqueta">PRUEBA</p>
  {#if panel.tipo === 'fragmentless'}
    <p>Entraste como Fragmentless. Tu panel llega en la pieza 2.</p>
  {:else}
    <p>
      Entraste como gerente de {panel.sucursales.map((s) => s.nombre).join(', ')}. Su panel llega
      en la pieza 3.
    </p>
  {/if}
  <Boton etiqueta="Cerrar sesión" icono="salir" onclick={alSalir} />
</main>

<style>
  main {
    padding: 48px;
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 12px;
  }
</style>
