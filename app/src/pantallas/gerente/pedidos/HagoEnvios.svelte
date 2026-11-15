<!--
  «Hago envíos» en la barra de arriba de Pedidos, junto a «Pausar pedidos» (14 nov 2026; se fue de Tu restaurante por la
  encuesta del 13 nov: planes/trabajo/rediseno/pedidos-vista.md). Las dos dicen lo que pueden pedir tus clientes desde tu
  menú. Es el riel de diseno/Interruptor dentro de un botón con la forma de los de la barra (34 de alto, radio 9, su línea;
  en Cristal, vidrio como «Pausar pedidos»). Al picarlo cambia en ese momento y se guarda; si no se pudo, regresa y el
  error sale en la caja de errores de Pedidos (lo decide gerente/Pedidos.svelte).

  `prendido` vacío = todavía no se sabe: mientras se lee la primera vez, el riel es un esqueleto (regla «Los
  esqueletos»); si no se pudo leer, el riel apagado y el botón sin picarse.
-->
<script lang="ts">
  import Esqueleto from '../../../diseno/Esqueleto.svelte';
  import { enBarra, pica, vidrio } from '../../../diseno/vidrio';

  let {
    prendido,
    leyendo = false,
    guardando = false,
    alCambiar,
  }: { prendido: boolean | null; leyendo?: boolean; guardando?: boolean; alCambiar: (prendido: boolean) => void } = $props();

  const deBarra = enBarra();
</script>

<button
  type="button"
  class="envios"
  role="switch"
  aria-checked={prendido === true}
  aria-busy={guardando}
  disabled={prendido === null || guardando}
  use:vidrio={deBarra ? 'control' : null}
  use:pica={deBarra ? 1.05 : null}
  onclick={() => prendido !== null && alCambiar(!prendido)}
>
  {#if prendido === null && leyendo}
    <Esqueleto ancho="34px" alto="20px" redondo="10px" />
  {:else}
    <span class="riel" class:prendido></span>
  {/if}
  <span>Hago envíos</span>
</button>

<style>
  /* La forma de los botones de la barra (BarraArriba: 34 de alto, radio 9, relleno 13) con la letra de Boton. */
  .envios {
    height: 34px;
    padding: 0 13px 0 9px;
    display: inline-flex;
    align-items: center;
    gap: 9px;
    flex: none;
    border: 1px solid var(--linea);
    border-radius: 9px;
    background: transparent;
    color: var(--texto);
    font-size: 13px;
    font-weight: 600;
    white-space: nowrap;
    transition: opacity 150ms;
  }

  .envios:hover:not(:disabled) {
    opacity: 0.86;
  }

  .envios:disabled {
    cursor: default;
  }

  /* Guardando, o sin saber todavía: más tenue (el esqueleto ya late solo). */
  .envios:disabled .riel {
    opacity: 0.5;
  }

  /* El riel de diseno/Interruptor: 34 × 20, en tinta al prenderse. */
  .riel {
    width: 34px;
    height: 20px;
    border-radius: 10px;
    background: var(--linea-fuerte);
    position: relative;
    flex: none;
    transition: background-color 150ms;
  }

  .riel::after {
    content: '';
    position: absolute;
    top: 2px;
    left: 2px;
    width: 16px;
    height: 16px;
    border-radius: 8px;
    background: var(--solido);
    box-shadow: 0 1px 2px var(--sombra-segmento);
    transition: transform 150ms;
  }

  .riel.prendido {
    background: var(--tinta);
  }

  .riel.prendido::after {
    transform: translateX(14px);
  }

  @media (prefers-reduced-motion: reduce) {
    .envios,
    .riel,
    .riel::after {
      transition: none;
    }
  }
</style>
