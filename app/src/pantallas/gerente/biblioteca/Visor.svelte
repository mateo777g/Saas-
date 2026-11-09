<!--
  Un anuncio en grande (maqueta de Mi biblioteca SMeWoa5ypbcVQmvBGyyytt, como el visor de Flet): el
  anuncio con flechas (también ← → del teclado; Escape cierra) que recorren lo que deja ver el
  filtro, y a un lado sus productos, su formato, Estilo, Tamaño, Creado y «Se borra en…»; abajo
  Descargar, «Ponerlo en mi menú» solo en los carteles, y Eliminar. Lo que pasa al tocar cada cosa
  lo lleva Mi biblioteca, así el cuadrito del collage y esta ventana dicen lo mismo.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import Boton from '../../../diseno/Boton.svelte';
  import BotonCuadro from '../../../diseno/BotonCuadro.svelte';
  import CajaError from '../../../diseno/CajaError.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import { pista } from '../../../diseno/pista';
  import { creado, FORMA, listaDe, seBorra, type AnuncioListo } from '../../../lib/biblioteca';
  import { urlFoto } from '../../../lib/fotos';

  let {
    anuncio,
    posicion,
    total,
    hoy,
    bajando,
    bajado,
    poniendo,
    puesto,
    error,
    alMover,
    alCerrar,
    alDescargar,
    alPoner,
    alEliminar,
  }: {
    anuncio: AnuncioListo;
    // Cuál es de los que deja ver el filtro («4 DE 16»).
    posicion: number;
    total: number;
    hoy: string;
    bajando: boolean;
    bajado: boolean;
    poniendo: boolean;
    puesto: boolean;
    error: string | null;
    alMover: (paso: 1 | -1) => void;
    alCerrar: () => void;
    alDescargar: () => void;
    alPoner: () => void;
    alEliminar: () => void;
  } = $props();

  let dialogo: HTMLDialogElement;
  const idTitulo = $props.id();
  const f = $derived(FORMA[anuncio.formato]);

  onMount(() => dialogo.showModal());

  function alCancelar(e: Event) {
    // Escape: no la cierra el navegador por su cuenta, la cierra Mi biblioteca.
    e.preventDefault();
    alCerrar();
  }

  // En la ventana entera: un botón que se apaga mientras trabaja (Descargar, «Ponerlo en mi menú»)
  // suelta el foco, y las flechas tienen que seguir sirviendo.
  function alTeclear(e: KeyboardEvent) {
    if (total < 2) return;
    if (e.key === 'ArrowLeft') {
      e.preventDefault();
      alMover(-1);
    } else if (e.key === 'ArrowRight') {
      e.preventDefault();
      alMover(1);
    }
  }
</script>

<svelte:window onkeydown={alTeclear} />

<!-- El clic en el velo es un atajo del ratón; con el teclado se cierra con Escape (oncancel). -->
<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_noninteractive_element_interactions -->
<dialog
  bind:this={dialogo}
  class="velo"
  aria-labelledby={idTitulo}
  oncancel={alCancelar}
  onclick={(e) => {
    if (e.target === dialogo) alCerrar();
  }}
>
  <div class="ventana">
    <div class="zona">
      {#key anuncio.id}
        <img src={urlFoto(anuncio.ruta)} alt="Tu anuncio de {anuncio.estilo}" />
      {/key}
      {#if total > 1}
        <button type="button" class="flecha izq" aria-label="Anterior" use:pista={'Anterior'} onclick={() => alMover(-1)}
          ><Icono nombre="anterior" tamano={18} /></button
        >
        <button type="button" class="flecha der" aria-label="Siguiente" use:pista={'Siguiente'} onclick={() => alMover(1)}
          ><Icono nombre="siguiente" tamano={18} /></button
        >
      {/if}
    </div>

    <div class="lado">
      <div class="lado-cabeza">
        <span class="etq">{posicion} DE {total}</span>
        <BotonCuadro icono="cerrar" ayuda="Cerrar" onclick={alCerrar} />
      </div>
      <h2 class="nombre" id={idTitulo}>{listaDe(anuncio.productos)}</h2>
      <p class="formato">{f.largo}</p>
      <div class="datos">
        <div class="dato"><span>Estilo</span><b>{anuncio.estilo}</b></div>
        <div class="dato"><span>Tamaño</span><b class="mono">{f.medida}</b></div>
        <div class="dato"><span>Creado</span><b>{creado(anuncio, hoy)}</b></div>
      </div>
      <p class="vence" class:pronto={anuncio.dias_restantes <= 7}>
        <Icono nombre="reloj" tamano={15} />{seBorra(anuncio.dias_restantes)}
      </p>

      <div class="pie">
        {#if error}<CajaError mensaje={error} compacta />{/if}
        <div class="descargar">
          <Boton
            etiqueta={bajado ? 'Descargado' : 'Descargar'}
            icono="exportar"
            tono="tinta"
            cargando={bajando}
            exito={bajado}
            onclick={alDescargar}
          />
        </div>
        {#if anuncio.formato === 'cartel'}
          <Boton
            etiqueta={puesto ? 'En tu menú' : poniendo ? 'Poniéndolo en tu menú…' : 'Ponerlo en mi menú'}
            icono="cartel"
            cargando={poniendo}
            exito={puesto}
            onclick={alPoner}
          />
        {/if}
        <Boton etiqueta="Eliminar" icono="eliminar" tono="peligro" onclick={alEliminar} />
      </div>
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
    width: 1020px;
    max-width: 100%;
    margin: auto;
    padding: 24px 28px;
    display: flex;
    gap: 24px;
    background: var(--solido);
    border: 1px solid var(--linea);
    border-radius: 26px;
    box-shadow: 0 24px 60px var(--sombra);
  }

  .zona {
    position: relative;
    flex: 1;
    min-width: 0;
    height: 720px;
    border-radius: 18px;
    background: var(--chip);
    display: flex;
    align-items: center;
    justify-content: center;
    overflow: hidden;
  }

  .zona img {
    display: block;
    max-width: calc(100% - 48px);
    max-height: 664px;
    border-radius: 12px;
    box-shadow: 0 16px 40px var(--sombra-anuncio);
  }

  .flecha {
    position: absolute;
    top: 338px;
    width: 44px;
    height: 44px;
    padding: 0;
    border-radius: 12px; /* rectángulo como los botones del panel (9 nov 2026; antes, círculo) */
    border: 1px solid var(--linea);
    background: var(--solido);
    color: var(--texto);
    display: flex;
    align-items: center;
    justify-content: center;
    box-shadow: 0 6px 18px var(--sombra-segmento);
  }

  .izq {
    left: 14px;
  }

  .der {
    right: 14px;
  }

  .lado {
    width: 300px;
    flex: none;
    height: 720px;
    display: flex;
    flex-direction: column;
  }

  .lado-cabeza {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
  }

  .etq {
    flex: 1;
    font-family: var(--mono);
    font-size: 10.5px;
    letter-spacing: 0.14em;
    color: var(--tenue);
    text-transform: uppercase;
  }

  .nombre {
    margin: 18px 0 0;
    font-size: 24px;
    font-weight: 800;
    letter-spacing: -0.5px;
    line-height: 1.15;
    text-wrap: balance;
  }

  .formato {
    margin: 8px 0 0;
    font-size: 13px;
    font-weight: 500;
    color: var(--suave);
  }

  .datos {
    margin-top: 24px;
    border-top: 1px solid var(--linea);
  }

  .dato {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding: 12px 0;
    border-bottom: 1px solid var(--linea);
    font-size: 12.5px;
  }

  .dato span {
    font-weight: 500;
    color: var(--tenue);
  }

  .dato b {
    font-weight: 600;
  }

  .dato b.mono {
    font-family: var(--mono);
    font-size: 12px;
    font-weight: 400;
  }

  .vence {
    margin: 14px 0 0;
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 12.5px;
    font-weight: 500;
    color: var(--suave);
  }

  .vence.pronto {
    color: var(--texto);
    font-weight: 600;
  }

  .pie {
    margin-top: auto;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .pie :global(.boton) {
    width: 100%;
  }

  .descargar :global(.boton) {
    height: 46px;
  }
</style>
