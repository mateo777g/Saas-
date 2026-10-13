<!--
  El ícono de una categoría del menú (uno de los 28 de iconosCategorias.ts), con el mismo trazo
  que los demás iconos del panel.
-->
<script lang="ts">
  import Icono from './Icono.svelte';
  import { trazosCategoria } from './iconosCategorias';

  let { id, tamano = 18 }: { id: string; tamano?: number } = $props();
</script>

<Icono nombre={id} {tamano} trazos={trazosCategoria(id)} />
