<!--
  El logo del restaurante en las barras del aparato del equipo (/equipo): el de «Tu restaurante», con su forma y sin
  marco, como en el menú en línea pero más chico: hasta 32 de alto y lo ancho que pida, hasta 120, con las esquinas
  suaves del menú a esa escala (10 px). Va junto al nombre, que dice lo mismo: para el lector de pantalla no dice nada.
  Si no se pudo bajar, no se ve y se dice en la consola; queda el nombre.
-->
<script lang="ts">
  import { urlLogo } from '../lib/marcaAparato';

  let { ruta }: { ruta: string } = $props();

  let fallo = $state<string | null>(null); // la ruta que no se pudo bajar
</script>

{#if fallo !== ruta}
  <img
    class="logo-restaurante"
    src={urlLogo(ruta)}
    alt=""
    onerror={() => {
      console.error(`[aparato] no se pudo bajar el logo del restaurante (${ruta}); queda el nombre.`);
      fallo = ruta;
    }}
  />
{/if}

<style>
  .logo-restaurante {
    display: block;
    flex: none;
    max-width: 120px;
    max-height: 32px;
    border-radius: 10px;
  }
</style>
