<!--
  El aviso de una ventana: una caja de chip con borde fino, radio 12, letra 12.5 («Su licencia
  termina el 8 nov 2026…» en Sumar meses; «Hoy es cliente de Lupita Gómez…» al asignar).
-->
<script lang="ts">
  import type { Snippet } from 'svelte';

  let { children }: { children: Snippet } = $props();
</script>

<div class="aviso">{@render children()}</div>

<style>
  .aviso {
    padding: 11px 14px;
    border: 1px solid var(--linea);
    border-radius: 12px;
    background: var(--chip);
    font-size: 12.5px;
    font-weight: 500;
    line-height: 1.45;
  }
</style>
