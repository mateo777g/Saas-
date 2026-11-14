<!--
  El iPhone de Crear anuncios (13 nov 2026, planes/trabajo/rediseno/crear-anuncios.md): el marco del iPhone 16 Pro de la
  maqueta del menú digital (planes/trabajo/rediseno/maqueta-tu-menu/partes/guion.js, MARCO_CUERPO y MARCO_ISLA, tal
  cual), a 375 × 750; la pantalla va en su rectángulo (left 26.4, top 24.02, 322.46 × 701.94, esquinas de 46.16) con la
  hora arriba. Lo de adentro lo pone quien lo usa; `oscura` pinta la hora en blanco (la historia).
-->
<script lang="ts">
  import type { Snippet } from 'svelte';

  // `conReloj` false: lo de adentro ya trae su hora (el menú en línea de verdad).
  let { oscura = false, conReloj = true, children }: { oscura?: boolean; conReloj?: boolean; children: Snippet } = $props();

  const CUERPO = '<svg class="tel-cuerpo" viewBox="0 0 200 400" fill="none" aria-hidden="true"><path fill="#303333" d="M196.11,128.09c0-.25-.2-.45-.45-.45-.11.04-.37.03-.69,0V36.69c0-17.84-14.46-32.31-32.31-32.31H37.48C19.63,4.39,5.17,18.85,5.17,36.69v48.99c-.3.02-.55.03-.66-.02-.25,0-.45.2-.45.45,0,0,0,17.29,0,17.29-.03.41.5.49,1.11.48v13.63c-.61,0-1.14.08-1.11.48,0,0,0,28.54,0,28.54-.03.42.5.49,1.11.48v7.95c-.61,0-1.14.08-1.11.48,0,0,0,28.54,0,28.54-.03.42.5.49,1.11.48v178.86c0,17.84,14.46,32.31,32.31,32.31h125.2c17.84,0,32.31-14.46,32.31-32.31v-188.87c.32-.02.58-.03.69.04,1.26.1.03-45.94.45-46.38ZM186.07,362.63c0,13.56-10.99,24.56-24.56,24.56H38.64c-13.56,0-24.56-10.99-24.56-24.56V37.37c0-13.56,10.99-24.56,24.56-24.56h122.87c13.56,0,24.56,10.99,24.56,24.56v325.26Z"></path><path fill="#000000" d="M161.38,7.29H38.78c-16.54,0-29.95,13.41-29.95,29.95v325.52c0,16.54,13.41,29.95,29.95,29.95h122.6c16.54,0,29.95-13.41,29.95-29.95V37.24c0-16.54-13.41-29.95-29.95-29.95ZM186.07,362.57c0,13.6-11.02,24.62-24.62,24.62H38.7c-13.6,0-24.62-11.02-24.62-24.62V37.43c0-13.6,11.02-24.62,24.62-24.62h122.75c13.6,0,24.62,11.02,24.62,24.62v325.14Z"></path></svg>';
  const ISLA = '<svg class="tel-isla-svg" viewBox="0 0 200 400" fill="none" aria-hidden="true"><path fill="#000000" d="M119.61,33.86h-38.93c-10.48-.18-10.5-15.78,0-15.96,0,0,38.93,0,38.93,0,4.41,0,7.98,3.57,7.98,7.98,0,4.41-3.57,7.98-7.98,7.98Z"></path><path fill="#080d4c" d="M118.78,29.21c-4.32.06-4.32-6.73,0-6.66,4.32-.06,4.32,6.73,0,6.66Z"></path></svg>';
</script>

<div class="tel-marco">
  {@html CUERPO}
  <div class="tel" class:oscura>
    {@render children()}
    {#if conReloj}<span class="reloj" aria-hidden="true">9:41</span>{/if}
  </div>
  {@html ISLA}
</div>

<style>
  .tel-marco {
    position: relative;
    width: 375px;
    height: 750px;
    flex: none;
  }

  .tel-marco > :global(svg) {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    pointer-events: none;
  }

  .tel-marco > :global(.tel-cuerpo) {
    filter: drop-shadow(0 18px 26px var(--sombra));
  }

  .tel-marco > :global(.tel-isla-svg) {
    z-index: 30;
  }

  .tel {
    position: absolute;
    left: 26.4px;
    top: 24.02px;
    width: 322.46px;
    height: 701.94px;
    border-radius: 46.16px;
    overflow: hidden;
    background: var(--solido);
    color: var(--texto);
  }

  .tel.oscura {
    background: #000000;
    color: #ffffff;
  }

  .reloj {
    position: absolute;
    left: 34px;
    top: 17px;
    z-index: 3;
    font: 700 14px var(--jakarta);
    color: var(--texto);
    pointer-events: none;
  }

  .oscura .reloj {
    color: #ffffff;
  }
</style>
