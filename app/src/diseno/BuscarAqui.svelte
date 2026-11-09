<!--
  La búsqueda en la vista donde estás (9 nov 2026; maqueta 4JB7YePY2bdr2LVnhCuKm9, estilo A «Separadas»). Fuera de
  Inicio, la búsqueda chica de la barra lateral y Ctrl K ya no llevan a Inicio: oscurecen la vista con el velo de las
  ventanas y abren ahí mismo la búsqueda de Inicio (diseno/Buscador.svelte): la píldora con su brillo y, debajo y
  aparte, la tarjeta con los resultados. Sale como las ventanas del gerente (del centro, de 97 % a 100 % en 0.35 s;
  cierra en 0.2 s), en los tres paneles, y los resultados en fila como en Inicio. Se cierra con Esc, picando lo oscuro
  o al elegir algo. Es de 680 de ancho y va al centro de la pantalla (lo pidió el developer al verla): al abrir se mide
  con la píldora y sus resultados, y al escribir se queda donde está, para que no brinque cuando cambian.

  Es un <dialog> del navegador, como Ventana: mientras está abierta, lo de atrás no se toca ni recibe el foco. Quien la
  abre la quita con su {#if} (alCerrar) y el cierre espera a terminar (`|global`).
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import Buscador, { type RenglonBusqueda } from './Buscador.svelte';
  import { ventanaSale, veloSale } from './ventanaSeMueve';

  let {
    vistas,
    acciones,
    recientes,
    placeholder,
    alCerrar,
  }: {
    vistas: RenglonBusqueda[];
    acciones: RenglonBusqueda[];
    recientes: RenglonBusqueda[];
    placeholder?: string;
    alCerrar: () => void;
  } = $props();

  let dialogo: HTMLDialogElement;
  let caja: HTMLDivElement;
  let buscador: { enfocar: () => void };
  // Lo que mide al abrir: la píldora, el espacio y la tarjeta de los resultados (va con position: absolute).
  let bloque = 0;

  onMount(() => {
    dialogo.showModal();
    const lista = caja.querySelector<HTMLElement>('.lista');
    bloque = lista ? lista.offsetTop + lista.offsetHeight : caja.offsetHeight;
    centrar();
    buscador.enfocar();
  });

  function centrar() {
    dialogo.style.paddingTop = `${Math.max(16, Math.round((dialogo.clientHeight - bloque) / 2))}px`;
  }

  function alCancelar(e: Event) {
    // Escape: no la cierra el navegador por su cuenta, la cierra el panel.
    e.preventDefault();
    alCerrar();
  }
</script>

<svelte:window onresize={centrar} />

<!-- El clic en lo oscuro es un atajo del ratón; con el teclado se cierra con Escape. -->
<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_noninteractive_element_interactions -->
<dialog
  bind:this={dialogo}
  class="velo"
  aria-label="Buscar"
  in:veloSale|global={true}
  out:veloSale|global={true}
  oncancel={alCancelar}
  onclick={(e) => {
    if (e.target === dialogo) alCerrar();
  }}
>
  <div bind:this={caja} class="caja" in:ventanaSale|global={true} out:ventanaSale|global={true}>
    <Buscador bind:this={buscador} {vistas} {acciones} {recientes} {placeholder} {alCerrar} />
  </div>
</dialog>

<style>
  .velo[open] {
    position: fixed;
    inset: 0;
    width: 100%;
    height: 100%;
    max-width: none;
    max-height: none;
    margin: 0;
    padding: 16px;
    border: 0;
    background: var(--velo);
    color: var(--texto);
    overflow: hidden;
  }

  .velo::backdrop {
    background: transparent;
  }

  .caja {
    width: 680px;
    max-width: 100%;
    margin: 0 auto;
  }
</style>
