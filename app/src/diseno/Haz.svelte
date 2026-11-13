<!--
  El brillo de border-beam alrededor de una caja de búsqueda (maqueta 4B6Qhre6dkK3pJgXtryyEV v3): prende al
  entrar a la caja (picarla o Ctrl K) en 0.6 s, sigue mientras escribes y se apaga en 0.5 s al salir. Azul en los
  dos temas: en claro, haz-cristal.css le pone el azul del oscuro con la sombra del claro (era naranja hasta el 13 nov
  2026). Su CSS vive en haz.css (border-beam, licencia MIT, Copyright (c) 2026 Jakub Antalik).
-->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import './haz.css';
  import './haz-cristal.css';
  import { pica } from './vidrio';

  let { children }: { children: Snippet } = $props();

  let activo = $state(false);
  let apagando = $state(false);
  let reloj = 0;

  $effect(() => () => clearTimeout(reloj));

  function alEntrar() {
    clearTimeout(reloj);
    apagando = false;
    activo = true;
  }

  function alSalir(e: FocusEvent) {
    // Si el foco se queda dentro de la caja (su botón de borrar, por ejemplo), el brillo sigue.
    const caja = e.currentTarget as HTMLElement;
    if (e.relatedTarget instanceof Node && caja.contains(e.relatedTarget)) return;
    activo = false;
    apagando = true;
    reloj = window.setTimeout(() => (apagando = false), 500);
  }
</script>

<!-- En Cristal, al picar la búsqueda crece tantito con resorte (1.5 %; diseno/vidrio.ts). -->
<div class="haz" class:activo class:apagando onfocusin={alEntrar} onfocusout={alSalir} use:pica={1.015}>
  {@render children()}
  <div class="haz-flor" aria-hidden="true"></div>
</div>

<style>
  .haz {
    flex: none;
  }
</style>
