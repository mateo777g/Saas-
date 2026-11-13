<!--
  confirmar() de diseno.py, la ventana de eliminar un platillo en Flet: 420 de ancho, el icono en
  un chip de 44, el título de 18 y el texto debajo; abajo, Cancelar junto al botón principal. Sin
  rojo. Se usa para Dar de baja y Reactivar a un distribuidor.

  El botón sigue las reglas de siempre (libreta 4), como en Formulario: "Guardando…" con la rueda,
  el error en la caja sin rojo, el éxito en el mismo botón con la palomita verde y 1.6 s después
  se cierra. Se cierra también con Cancelar, Escape o un clic en el velo. Si el éxito debe hacer
  otra cosa que Cancelar (en Mi menú, Cancelar regresa a la ventana del producto y el éxito cierra
  las dos), va en `alTerminar`; `textoCargando` cambia el «Guardando…» («Eliminando…»).
  `miniatura` pone la imagen en lugar del icono: 72 de ancho y su alto (Eliminar un anuncio de Mi
  biblioteca).

  `peligro` es lo que borra, en el panel del gerente (Mi menú, versiones 1, 9 a 13; maqueta
  U9YqpsSb2PeB5pFXTPvh1C): el botón lleno en rojo (Boton peligro-lleno), «Cancelar» que se alarga hasta la
  orilla izquierda y, en lugar del icono, el bote de basura 3D (Bote.svelte), con el bote y los textos al
  centro; su tapa se abre solo sobre el botón rojo (mouse, foco o dedo) y se cierra al irse de ahí. Con
  `miniatura`, la imagen se queda en su lugar. Fragmentless y los distribuidores no lo pasan: se quedan igual.
-->
<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import Bote from './Bote.svelte';
  import Boton from './Boton.svelte';
  import CajaError from './CajaError.svelte';
  import Icono from './Icono.svelte';
  import { quitarDeBarra, vidrio } from './vidrio';
  import { seMueven, ventanaSale, veloSale } from './ventanaSeMueve';

  // En Cristal es vidrio casi sólido (tipo «ventana»), como Ventana; lo de adentro nunca es vidrio.
  quitarDeBarra();

  const ESPERA_EXITO = 1600;

  let {
    icono,
    miniatura,
    titulo,
    texto,
    boton,
    confirmar,
    alCerrar,
    alTerminar,
    textoCargando = 'Guardando…',
    peligro = false,
  }: {
    icono?: string;
    miniatura?: { src: string; alto: number };
    titulo: string;
    texto: string;
    boton: { etiqueta: string; icono: string };
    confirmar: () => Promise<{ listo: string } | { error: string }>;
    alCerrar: () => void;
    alTerminar?: () => void;
    textoCargando?: string;
    peligro?: boolean;
  } = $props();

  let dialogo: HTMLDialogElement;
  const idTitulo = $props.id();
  // En el panel del gerente se mueve como las ventanas (diseno/ventanaSeMueve.ts).
  const mueve = seMueven();
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

  // La tapa del bote: se abre con el mouse o el foco sobre el botón rojo, o mientras lo toca el dedo (y
  // 450 ms después); en cuanto se va de ahí, a donde sea, se cierra.
  let tapaAbierta = $state(false);
  let soltar: ReturnType<typeof setTimeout> | undefined;
  onDestroy(() => clearTimeout(soltar));
  function sobreElRojo(e: Event, abrir: boolean) {
    const destino = (e as MouseEvent | FocusEvent).relatedTarget as Node | null;
    if (destino && (e.currentTarget as Node).contains(destino)) return;
    tapaAbierta = abrir;
  }
  function alTocar(e: PointerEvent, abrir: boolean) {
    if (e.pointerType === 'mouse') return;
    clearTimeout(soltar);
    if (abrir) tapaAbierta = true;
    else soltar = setTimeout(() => (tapaAbierta = false), 450);
  }
</script>

<!-- El clic en el velo es un atajo del ratón; con el teclado se cierra con Escape (oncancel). -->
<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_noninteractive_element_interactions -->
<dialog
  bind:this={dialogo}
  class="velo"
  aria-labelledby={idTitulo}
  in:veloSale|global={mueve}
  out:veloSale|global={mueve}
  oncancel={alCancelar}
  onclick={(e) => {
    if (e.target === dialogo) cancelar();
  }}
>
  <div class="ventana" class:centrada={peligro && !miniatura} use:vidrio={'ventana'} in:ventanaSale|global={mueve} out:ventanaSale|global={mueve}>
    {#if miniatura}
      <img class="mini" src={miniatura.src} alt="" style:height="{miniatura.alto}px" />
    {:else if peligro}
      <div class="figura"><Bote abierta={tapaAbierta} /></div>
    {:else if icono}
      <div class="icono"><Icono nombre={icono} tamano={20} /></div>
    {/if}
    <h2 class="titulo" id={idTitulo}>{titulo}</h2>
    <p class="texto">{texto}</p>

    {#if error}
      <div class="error">
        <CajaError mensaje={error} />
      </div>
    {/if}

    <div class="pie" class:separado={peligro}>
      {#if peligro}
        <Boton tono="alarga" etiqueta="Cancelar" icono="cerrar" apagado={estado !== 'reposo'} onclick={cancelar} />
        <!-- Solo para saber si el mouse, el foco o el dedo están sobre el botón rojo (abre la tapa). -->
        <!-- svelte-ignore a11y_no_static_element_interactions, a11y_mouse_events_have_key_events -->
        <span
          class="rojo"
          onmouseover={(e) => sobreElRojo(e, true)}
          onmouseout={(e) => sobreElRojo(e, false)}
          onfocusin={(e) => sobreElRojo(e, true)}
          onfocusout={(e) => sobreElRojo(e, false)}
          onpointerdown={(e) => alTocar(e, true)}
          onpointerup={(e) => alTocar(e, false)}
          onpointercancel={(e) => alTocar(e, false)}
        >
          <Boton
            tono="peligro-lleno"
            icono={boton.icono}
            etiqueta={estado === 'guardando' ? textoCargando : estado === 'listo' ? textoListo : boton.etiqueta}
            cargando={estado === 'guardando'}
            exito={estado === 'listo'}
            onclick={enviar}
          />
        </span>
      {:else}
        <Boton etiqueta="Cancelar" icono="cerrar" apagado={estado !== 'reposo'} onclick={cancelar} />
        <Boton
          tono="tinta"
          icono={boton.icono}
          etiqueta={estado === 'guardando' ? textoCargando : estado === 'listo' ? textoListo : boton.etiqueta}
          cargando={estado === 'guardando'}
          exito={estado === 'listo'}
          onclick={enviar}
        />
      {/if}
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

  /* Cristal: la hoja de vidrio grueso (su receta en cristal.css) lleva su canto. */
  :global(:root[data-estilo='cristal']) .ventana {
    position: relative;
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

  .mini {
    display: block;
    width: 72px;
    border-radius: 10px;
    object-fit: cover;
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

  .pie.separado {
    justify-content: space-between;
  }

  .rojo {
    display: contents;
  }

  /* El bote y los textos, al centro; los botones se quedan a los lados. */
  .centrada {
    text-align: center;
  }

  .figura {
    margin: -6px auto 4px;
  }
</style>
