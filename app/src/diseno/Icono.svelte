<!--
  icono() de diseno.py: un icono de trazo de panel/assets/iconos, del tamaño pedido. Toma el
  color del texto que lo rodea (currentColor); para otro color, se le pone `color` al padre.
-->
<script lang="ts">
  import { ICONOS } from './iconos';

  let { nombre, tamano = 18 }: { nombre: string; tamano?: number } = $props();

  const trazos = $derived(ICONOS[nombre]);
  $effect(() => {
    if (!trazos) console.error(`[icono] no existe el icono "${nombre}" en src/diseno/iconos.ts`);
  });
</script>

<svg
  width={tamano}
  height={tamano}
  viewBox="0 0 24 24"
  fill="none"
  stroke="currentColor"
  stroke-width="1.7"
  stroke-linecap="round"
  stroke-linejoin="round"
  aria-hidden="true"
>
  {@html trazos ?? ''}
</svg>

<style>
  svg {
    display: block;
    flex: none;
  }
</style>
