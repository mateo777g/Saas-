<!--
  confirmar() de diseno.py, la ventana de eliminar un platillo en Flet: 420 de ancho, el icono en
  un chip de 44, el título de 18 y el texto debajo; abajo, Cancelar junto al botón principal. Sin
  rojo. Se usa para Dar de baja y Reactivar a un distribuidor.

  El botón sigue las reglas de siempre (libreta 4), como en Formulario: "Guardando…" con la rueda,
  el error en la caja sin rojo, el éxito en el mismo botón con la palomita verde y 1.6 s después
  se cierra. Se cierra también con Cancelar, Escape o un clic en el velo. Si el éxito debe hacer
  otra cosa que Cancelar (en Mi menú, Cancelar regresa a la ventana del producto y el éxito cierra
  las dos), va en `alTerminar`; `textoCargando` cambia el «Guardando…» («Eliminando…»).
-->
<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import Boton from './Boton.svelte';
  import CajaError from './CajaError.svelte';
  import Icono from './Icono.svelte';

  const ESPERA_EXITO = 1600;

  let {
    icono,
    titulo,
    texto,
    boton,
    confirmar,
    alCerrar,
    alTerminar,
    textoCargando = 'Guardando…',
  }: {
    icono: string;
    titulo: string;
    texto: string;
    boton: { etiqueta: string; icono: string };
    confirmar: () => Promise<{ listo: string } | { error: string }>;
    alCerrar: () => void;
    alTerminar?: () => void;
    textoCargando?: string;
  } = $props();

  let dialogo: HTMLDialogElement;
  const idTitulo = $props.id();
  let estado = $state<'reposo' | 'guardando' | 'listo'>('reposo');
  let textoListo = $state('');
  let error = $state<string | null>(null);
  let temporizador: ReturnType<typeof setTimeout> | undefined;

  onMount(() => dialogo.showModal());
  onDestroy(() => clearTimeout(temporizador));

  async function enviar() {
    if (estado !== 'reposo') return;
    error = null;
    estado = 'guardando';
    const resultado = await confirmar();
    if ('error' in resultado) {
      error = resultado.error;
      estado = 'reposo';
      return;
    }
    textoListo = resultado.listo;
    estado = 'listo';
    temporizador = setTimeout(alTerminar ?? alCerrar, ESPERA_EXITO);
  }

  // Mientras trabaja o ya terminó, no se cancela a medias (como _cerrar() de Flet).
  function cancelar() {
    if (estado === 'reposo') alCerrar();
  }

  function alCancelar(e: Event) {
    e.preventDefault();
    cancelar();
  }
</script>

<!-- El clic en el velo es un atajo del ratón; con el teclado se cierra con Escape (oncancel). -->
<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_noninteractive_element_interactions -->
<dialog
  bind:this={dialogo}
  class="velo"
  aria-labelledby={idTitulo}
  oncancel={alCancelar}
  onclick={(e) => {
    if (e.target === dialogo) cancelar();
  }}
>
  <div class="ventana">
    <div class="icono"><Icono nombre={icono} tamano={20} /></div>
    <h2 class="titulo" id={idTitulo}>{titulo}</h2>
    <p class="texto">{texto}</p>

    {#if error}
      <div class="error">
        <CajaError mensaje={error} />
      </div>
    {/if}

    <div class="pie">
      <Boton etiqueta="Cancelar" icono="cerrar" apagado={estado !== 'reposo'} onclick={cancelar} />
      <Boton
        tono="tinta"
        icono={boton.icono}
        etiqueta={estado === 'guardando' ? textoCargando : estado === 'listo' ? textoListo : boton.etiqueta}
        cargando={estado === 'guardando'}
        exito={estado === 'listo'}
        onclick={enviar}
      />
    </div>
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
    display: flex;
    align-items: center;
    justify-content: center;
    overflow: auto;
  }

  .velo::backdrop {
    background: transparent;
  }

  .ventana {
    width: 420px;
    max-width: 100%;
    margin: auto;
    padding: 28px;
    display: flex;
    flex-direction: column;
    background: var(--solido);
    border: 1px solid var(--linea);
    border-radius: 26px;
    box-shadow: 0 24px 60px var(--sombra);
  }

  .icono {
    width: 44px;
    height: 44px;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 12px;
    background: var(--chip);
  }

  .titulo {
    margin: 16px 0 0;
    font-size: 18px;
    font-weight: 800;
    letter-spacing: -0.3px;
  }

  .texto {
    margin: 6px 0 0;
    font-size: 13px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .error {
    margin-top: 14px;
  }

  .pie {
    margin-top: 24px;
    display: flex;
    justify-content: flex-end;
    gap: 10px;
  }
</style>
