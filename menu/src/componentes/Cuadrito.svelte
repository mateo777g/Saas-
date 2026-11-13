<!--
  El cuadrito del idioma o de la moneda («Tu menú en línea», 11 de noviembre de 2026, como el «EN» del
  menú de Krispis): un solo botón con las letras de lo que no se está viendo (en español dice EN; en
  pesos, USD). Al tocarlo, el menú cambia, el botón se hunde y sus letras nuevas entran de abajo.
-->
<script lang="ts">
  let { letras, etiqueta, alTocar }: { letras: string; etiqueta: string; alTocar: () => void } = $props();

  // Las letras solo entran de abajo después de un toque, no al abrir el menú.
  let entra = $state(false);
</script>

<button
  type="button"
  class="f-cuadro"
  class:entra
  aria-label={etiqueta}
  onclick={() => {
    entra = true;
    alTocar();
  }}
>
  {#key letras}<span>{letras}</span>{/key}
</button>
