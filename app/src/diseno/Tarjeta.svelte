<!--
  La tarjeta del panel (rediseño del 5 de noviembre de 2026; antes era el vidrio de Flet): del color del
  fondo, se separa solo por su borde de 1 px, con esquinas de 14 y sin sombra. Solo lo que flota
  (ventanas, menús, la lista de la búsqueda) lleva sombra.

  Dónde va, su relleno y cómo acomoda lo de adentro lo pone quien la usa con `class`, desde su
  propio <style> con :global() (el estilo de un componente no alcanza la raíz de otro).
-->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import type { HTMLAttributes } from 'svelte/elements';

  let {
    como = 'div',
    class: clase = '',
    children,
    ...resto
  }: {
    como?: 'div' | 'section' | 'main';
    class?: string;
    children?: Snippet;
  } & Omit<HTMLAttributes<HTMLElement>, 'class'> = $props();
</script>

<svelte:element this={como} class="tarjeta-panel {clase}" {...resto}>
  {@render children?.()}
</svelte:element>

<style>
  .tarjeta-panel {
    background: var(--solido);
    border: 1px solid var(--borde-tarjeta);
    border-radius: 14px;
  }
</style>
