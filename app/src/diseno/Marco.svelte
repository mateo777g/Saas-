<!--
  El marco de los tres paneles (rediseño del 5 de noviembre de 2026; maqueta V64Pv4gmANPRZuJW5hTe5D): la
  barra lateral pegada al borde y, a su derecha, el lugar de la vista, sobre --fondo. Cada vista
  pone su barra de arriba y se acomoda contra ese lugar con --vista-arriba y compañía (colores.css).

  Lo plegado de la barra se recuerda en este navegador. --ancho-lateral es para lo que se acomoda contra
  la ventana y no contra el lugar de la vista (el aviso flotante).

  `plegarSola` (el Agente IA) la pliega mientras dure, sin tocar lo que la persona eligió: eso solo lo
  escribe el botón. Si la abre a mano ya no se vuelve a plegar en esa visita, y al salir se queda como
  la dejó; si no la tocó, regresa como estaba.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import type { ComponentProps } from 'svelte';
  import BarraLateral from './BarraLateral.svelte';

  type Barra = Omit<ComponentProps<typeof BarraLateral>, 'plegada' | 'alPlegar'>;

  let { children, plegarSola = false, ...barra }: Barra & { children: Snippet; plegarSola?: boolean } = $props();

  const LLAVE = 'fragmentless-barra-plegada';

  function leerPlegada() {
    try {
      return localStorage.getItem(LLAVE) === '1';
    } catch (error) {
      console.error('[marco] no se pudo leer si la barra iba plegada; se abre completa:', error);
      return false;
    }
  }

  let elegida = $state(leerPlegada());
  let sola = $state(false);
  const plegada = $derived(elegida || sola);

  // Solo corre cuando cambia plegarSola: abrirla a mano no la vuelve a plegar.
  $effect(() => {
    sola = plegarSola;
  });

  function alternar() {
    elegida = !plegada;
    sola = false;
    try {
      localStorage.setItem(LLAVE, elegida ? '1' : '0');
    } catch (error) {
      console.error('[marco] no se pudo recordar la barra plegada:', error);
    }
  }
</script>

<div class="marco" style:--ancho-lateral={plegada ? '64px' : '248px'}>
  <BarraLateral {...barra} {plegada} alPlegar={alternar} />
  <div class="lugar-vista">
    {@render children()}
  </div>
</div>

<style>
  .marco {
    height: 100vh;
    height: 100dvh;
    overflow: hidden;
    display: grid;
    grid-template-columns: var(--ancho-lateral) minmax(0, 1fr);
    background: var(--fondo);
    transition: grid-template-columns 200ms ease;
  }

  .lugar-vista {
    position: relative;
    min-width: 0;
    min-height: 0;
  }

  @media (prefers-reduced-motion: reduce) {
    .marco {
      transition: none;
    }
  }
</style>
