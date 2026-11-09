<!--
  Los campos que van juntos en una ventana (Nombre y Descripción, Categoría y Precio…), sobre el gris del fondo de las
  vistas (--fondo), como el bloque de «Ver inglés»: así la caja de texto blanca se distingue de la ventana blanca y se ve
  qué campos son del mismo tema. Radio 12, relleno 14 arriba y 16 a los lados y abajo, 14 entre campo y campo.
  Maqueta XQ5Ao76KBAoFbdrPrNTMuJ (aprobada el 9 nov 2026, «Gris del fondo»); va en las ventanas del panel del gerente.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';

  let { children }: { children: Snippet } = $props();
</script>

<div class="grupo-campos">
  {@render children()}
</div>

<style>
  .grupo-campos {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 14px;
    padding: 14px 16px 16px;
    border-radius: 12px;
    background: var(--fondo);
  }
</style>
