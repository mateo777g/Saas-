<!--
  vidrio() de diseno.py: la superficie de vidrio. Blanco al 80 % en claro o casi negro al 78 %
  en oscuro, desenfoque 18, borde fino y, si lleva sombra, la del vidrio (blur 60, caída 24).
  La llevan la barra lateral, la barra de arriba y las tarjetas grandes de cada vista; lo que
  se lee o se escribe de cerca (tablas, campos) va en sólido, adentro.

  Dónde va, su relleno y cómo acomoda lo de adentro lo pone quien la usa con `class`, desde su
  propio <style> con :global() (el estilo de un componente no alcanza la raíz de otro).
-->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import type { HTMLAttributes } from 'svelte/elements';

  let {
    como = 'div',
    radio = 22,
    sombra = true,
    class: clase = '',
    children,
    ...resto
  }: {
    como?: 'div' | 'section' | 'nav' | 'header';
    radio?: number;
    sombra?: boolean;
    class?: string;
    children?: Snippet;
  } & Omit<HTMLAttributes<HTMLElement>, 'class'> = $props();
</script>

<svelte:element
  this={como}
  class="vidrio {clase}"
  class:sombra
  style:border-radius="{radio}px"
  {...resto}
>
  {@render children?.()}
</svelte:element>

<style>
  .vidrio {
    background: var(--vidrio);
    border: 1px solid var(--vidrio-linea);
    backdrop-filter: blur(18px) saturate(1.1);
    -webkit-backdrop-filter: blur(18px) saturate(1.1);
  }

  .sombra {
    box-shadow: 0 24px 60px var(--sombra);
  }
</style>
