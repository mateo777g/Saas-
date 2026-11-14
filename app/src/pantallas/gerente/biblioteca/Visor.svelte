<!--
  Un anuncio en grande. Desde el rediseño (13 nov 2026, planes/trabajo/rediseno/biblioteca.md, encuesta 2) es una ventana
  como las demás (diseno/Ventana.svelte): sale del centro con su resorte, con «Agrandar» y la X, y su cabeza al centro
  («2 DE 7», sus productos y su formato). Abajo, el anuncio con flechas (también ← → del teclado; Escape cierra) que
  recorren lo que deja ver el filtro, y a un lado la tarjeta del anuncio, como «Lo que pediste» de Crear anuncios
  (Estilo, Tamaño, Creado y «Se borra en…»), con Descargar en verde, «Ponerlo en mi menú» solo en los carteles y
  Eliminar en rojo de contorno. Lo que pasa al tocar cada cosa lo lleva Mi biblioteca, así el cuadrito del collage y
  esta ventana dicen lo mismo.
-->
<script lang="ts">
  import Boton from '../../../diseno/Boton.svelte';
  import CajaError from '../../../diseno/CajaError.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import { pista } from '../../../diseno/pista';
  import Ventana from '../../../diseno/Ventana.svelte';
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

  const f = $derived(FORMA[anuncio.formato]);

  // En la ventana entera: un botón que se apaga mientras trabaja (Descargar, «Ponerlo en mi menú») suelta el foco, y
  // las flechas tienen que seguir sirviendo.
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

<!-- Su alto: el de antes (el anuncio en 720 y su cabeza); en una pantalla más baja, la ventana se detiene en ella. -->
<Ventana
  centrado
  etiqueta="{posicion} DE {total}"
  titulo={listaDe(anuncio.productos)}
  texto={f.largo}
  ancho={1020}
  alto={840}
  alCerrar={alCerrar}
>
  <div class="adentro">
    <div class="zona">
      <div class="marco">
        {#key anuncio.id}
          <img src={urlFoto(anuncio.ruta)} alt="Tu anuncio de {anuncio.estilo}" />
        {/key}
      </div>
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
      <!-- La tarjeta del anuncio, como «Lo que pediste» de Crear anuncios. -->
      <aside class="tarjeta" aria-label="Este anuncio">
        <span class="etq">Este anuncio</span>
        <div class="renglon"><span class="nombre">Estilo</span><span class="valor">{anuncio.estilo}</span></div>
        <div class="renglon"><span class="nombre">Tamaño</span><span class="valor mono">{f.medida}</span></div>
        <div class="renglon"><span class="nombre">Creado</span><span class="valor">{creado(anuncio, hoy)}</span></div>
        <p class="vence" class:pronto={anuncio.dias_restantes <= 7}>
          <Icono nombre="reloj" tamano={16} /><span>{seBorra(anuncio.dias_restantes)}</span>
        </p>
      </aside>

      <div class="pie">
        {#if error}<CajaError mensaje={error} compacta />{/if}
        <Boton
          etiqueta={bajado ? 'Descargado' : 'Descargar'}
          tono="verde"
          cargando={bajando}
          exito={bajado}
          onclick={alDescargar}
        />
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
</Ventana>

<style>
  /* Lo de abajo de la cabeza llena el alto de la ventana: el anuncio a la izquierda y su tarjeta a la derecha. */
  .adentro {
    flex: 1;
    min-height: 0;
    margin-top: 20px;
    display: flex;
    gap: 24px;
  }

  .zona {
    position: relative;
    flex: 1;
    min-width: 0;
    border-radius: 18px;
    background: var(--chip);
    overflow: hidden;
  }

  .marco {
    position: absolute;
    inset: 24px;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .marco img {
    display: block;
    max-width: 100%;
    max-height: 100%;
    border-radius: 12px;
    box-shadow: 0 16px 40px var(--sombra-anuncio);
  }

  .flecha {
    position: absolute;
    top: 50%;
    width: 44px;
    height: 44px;
    margin-top: -22px;
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
    display: flex;
    flex-direction: column;
    gap: 16px;
  }

  /* «Lo que pediste» de Crear anuncios: una tarjeta del panel (blanca, su borde, 14), sin sombra. */
  .tarjeta {
    padding: 18px 20px;
    background: var(--solido);
    border: 1px solid var(--borde-tarjeta);
    border-radius: 14px;
    display: flex;
    flex-direction: column;
  }

  .etq {
    font-family: var(--mono);
    font-size: 10.5px;
    letter-spacing: 0.14em;
    color: var(--tenue);
    text-transform: uppercase;
    padding-bottom: 6px;
  }

  .renglon {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 11px 0;
    border-top: 1px solid var(--linea);
  }

  .nombre {
    font-size: 12px;
    font-weight: 500;
    color: var(--tenue);
  }

  .valor {
    margin-left: auto;
    min-width: 0;
    font-size: 13px;
    font-weight: 600;
  }

  .valor.mono {
    font-family: var(--mono);
    font-size: 12px;
    font-weight: 400;
  }

  /* «Se borra en…», como «Guardado en Mi biblioteca»: el pie de la tarjeta con su ícono. */
  .vence {
    margin: 0;
    padding-top: 12px;
    border-top: 1px solid var(--linea);
    display: flex;
    align-items: center;
    gap: 9px;
    font-size: 12.5px;
    font-weight: 500;
    color: var(--suave);
  }

  .vence :global(svg) {
    flex: none;
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
</style>
