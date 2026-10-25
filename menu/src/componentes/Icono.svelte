<!--
  Un ícono de trazo del menú, del tamaño pedido y del color del texto que lo rodea. En el menú el
  trazo es de 1.8 (en el panel, 1.7), como en la maqueta. Con `categoria` dibuja uno de los 28 de las
  categorías de Mi menú.
-->
<script lang="ts">
  import { trazosCategoria } from '@app/diseno/iconosCategorias';
  import { trazosIcono } from '../lib/iconos';

  let { nombre = '', categoria, tamano = 18 }: { nombre?: string; categoria?: string; tamano?: number } = $props();

  const trazos = $derived(categoria ? trazosCategoria(categoria) : trazosIcono(nombre));
  $effect(() => {
    if (!trazos && !categoria) console.error(`[menu] no existe el ícono "${nombre}"`);
  });
</script>

<svg
  width={tamano}
  height={tamano}
  viewBox="0 0 24 24"
  fill="none"
  stroke="currentColor"
  stroke-width="1.8"
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
