<!--
  Una hoja que sube desde abajo sobre el velo (maqueta Mesero y cocina): su agarre, su título con
  una línea debajo y la X. Tocar el velo o la X la cierra; Escape también.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import Icono from '../../diseno/Icono.svelte';

  let {
    titulo,
    sub = '',
    alCerrar,
    children,
  }: { titulo: string; sub?: string; alCerrar: () => void; children: Snippet } = $props();
</script>

<svelte:window onkeydown={(e) => e.key === 'Escape' && alCerrar()} />

<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
<div class="hoja-velo" onclick={(e) => e.target === e.currentTarget && alCerrar()}>
  <div class="hoja" role="dialog" aria-modal="true" aria-label={titulo}>
    <span class="agarre"></span>
    <div class="hoja-cabeza">
      <div class="t">
        <h3>{titulo}</h3>
        {#if sub}<span>{sub}</span>{/if}
      </div>
      <button type="button" class="cuadro" aria-label="Cerrar" title="Cerrar" onclick={alCerrar}>
        <Icono nombre="cerrar" tamano={16} />
      </button>
    </div>
    {@render children()}
  </div>
</div>
