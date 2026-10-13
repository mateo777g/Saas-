<!--
  Lo de adentro de una ventana que guarda algo: los campos, la caja de error y el botón
  principal abajo a la derecha. Las reglas de siempre (libreta 4): el error sale en la caja, sin
  rojo, y se quita al volver a escribir; mientras guarda, el botón dice "Guardando…" con la
  rueda; el éxito se ve en el mismo botón, con la palomita verde, y 1.6 s después se cierra.
  Enter en un campo también guarda.

  `guardar` hace la llamada y regresa el texto del éxito ("Gerente ligado") o el del error, ya
  listo para leerse. Con `sinAviso` la ventana se cierra en cuanto guarda, sin palomita, como
  Perfil en Flet. `espacio` (entre campos) y `antesDelBoton` son 14 y 20 en las ventanas del
  panel de Fragmentless, 18 y 24 en Perfil. Quien necesite quitar el error desde otro control (un Selector) enlaza
  `error` con bind:error. `izquierda` va abajo a la izquierda, frente al botón principal
  («Eliminar producto»).
-->
<script lang="ts">
  import { onDestroy, type Snippet } from 'svelte';
  import Boton from './Boton.svelte';
  import CajaError from './CajaError.svelte';

  const ESPERA_EXITO = 1600;

  let {
    boton,
    guardar,
    alTerminar,
    error = $bindable(null),
    sinAviso = false,
    espacio = 14,
    antesDelBoton = 20,
    izquierda,
    children,
  }: {
    boton: { etiqueta: string; icono: string };
    guardar: () => Promise<{ listo: string } | { error: string }>;
    alTerminar: () => void;
    error?: string | null;
    sinAviso?: boolean;
    espacio?: number;
    antesDelBoton?: number;
    izquierda?: Snippet;
    children: Snippet;
  } = $props();

  let estado = $state<'reposo' | 'guardando' | 'listo'>('reposo');
  let textoListo = $state('');
  let temporizador: ReturnType<typeof setTimeout> | undefined;

  async function enviar(e: SubmitEvent) {
    e.preventDefault();
    if (estado !== 'reposo') return;
    error = null;
    estado = 'guardando';
    const resultado = await guardar();
    if ('error' in resultado) {
      error = resultado.error;
      estado = 'reposo';
      return;
    }
    if (sinAviso) {
      alTerminar();
      return;
    }
    textoListo = resultado.listo;
    estado = 'listo';
    temporizador = setTimeout(alTerminar, ESPERA_EXITO);
  }

  onDestroy(() => clearTimeout(temporizador));
</script>

<form onsubmit={enviar} oninput={() => (error = null)} novalidate>
  <div class="campos" style:gap="{espacio}px">
    {@render children()}
  </div>

  {#if error}
    <div class="error">
      <CajaError mensaje={error} />
    </div>
  {/if}

  <div class="pie" style:margin-top="{antesDelBoton}px">
    {#if izquierda}
      {@render izquierda()}
      <span class="crece"></span>
    {/if}
    <Boton
      tipo="submit"
      tono="tinta"
      icono={boton.icono}
      etiqueta={estado === 'guardando' ? 'Guardando…' : estado === 'listo' ? textoListo : boton.etiqueta}
      cargando={estado === 'guardando'}
      exito={estado === 'listo'}
    />
  </div>
</form>

<style>
  .campos {
    margin-top: 22px;
    display: flex;
    flex-direction: column;
  }

  /* Dos campos lado a lado (INICIO y MESES, INICIO y FIN). */
  .campos :global(.par) {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 12px;
  }

  /* La pista suelta debajo de los campos, como la de "Nace con la licencia prendida…". */
  .campos :global(.pista) {
    margin: 0;
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--tenue);
  }

  .error {
    margin-top: 14px;
  }

  .pie {
    display: flex;
    align-items: center;
    justify-content: flex-end;
    gap: 10px;
  }

  .crece {
    flex-grow: 1;
  }
</style>
