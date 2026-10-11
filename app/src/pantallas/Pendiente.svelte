<!--
  TEMPORAL: lo que ve el gerente después de entrar mientras no existe su panel (pieza 3 del
  punto 5). Solo sirve para probar su login y "Cerrar sesión"; se borra cuando llegue su panel.
-->
<script lang="ts">
  import Boton from '../diseno/Boton.svelte';
  import type { Panel } from '../lib/sesion';

  let {
    panel,
    alSalir,
  }: { panel: Extract<Panel, { tipo: 'gerente' }>; alSalir: () => void } = $props();
</script>

<main>
  <p class="etiqueta">PRUEBA</p>
  <p>
    Entraste como gerente de {panel.sucursales.map((s) => s.nombre).join(', ')}. Su panel llega en
    la pieza 3.
  </p>
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
