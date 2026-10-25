<!--
  La parte «En inglés · opcional» al final de las ventanas de Mi menú (maqueta de la 6a
  Qx4C5CbKJYpeAsJCfw4ghn, sección 4): lo que Don Chuy escribe aquí sale en su menú en línea cuando la
  clienta elige EN; lo que deja vacío sale en español. Adentro van los campos de cada ventana.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';

  let { children }: { children: Snippet } = $props();
</script>

<div class="en-ingles">
  <div class="en-cabeza">
    <span class="etiqueta">EN INGLÉS · OPCIONAL</span>
    <span class="pista">Lo que dejes vacío sale en español.</span>
  </div>
  {@render children()}
</div>

<style>
  .en-ingles {
    margin-top: 4px;
    padding: 16px;
    border-radius: 16px;
    background: var(--chip);
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .en-cabeza {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
  }

  .pista {
    margin: 0;
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--tenue);
  }

  /* Los campos de adentro, sólidos sobre el gris del bloque. */
  .en-ingles :global(input),
  .en-ingles :global(textarea) {
    background: var(--solido);
  }
</style>
