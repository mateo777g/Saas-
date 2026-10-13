<!--
  icono() de diseno.py: un icono de trazo de panel/assets/iconos, del tamaño pedido. Toma el
  color del texto que lo rodea (currentColor); para otro color, se le pone `color` al padre.
  Con `trazos` dibuja esos en lugar de los de iconos.ts (los íconos de las categorías del menú,
  IconoCategoria.svelte).
-->
<script lang="ts">
  import { ICONOS } from './iconos';

  let {
    nombre,
    tamano = 18,
    trazos: propios,
  }: { nombre: string; tamano?: number; trazos?: string } = $props();

  const trazos = $derived(propios ?? ICONOS[nombre]);
  $effect(() => {
    if (!trazos) console.error(`[icono] no existe el icono "${nombre}"`);
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
