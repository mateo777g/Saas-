<!--
  La página de un platillo o de una preparación (maqueta DFVTWEB3eZBEKctyxWjGjg v1, «Taco al pastor», «Salsa verde» y
  las de la cocina; encuestas 5 y 7): se abre en la misma vista, en lugar de los cuadros, con «‹ Recetario» para regresar.
  Arriba, la foto de cómo se sirve, lo que lleva y «Para más porciones»; abajo, «Cómo se hace»: los pasos numerados, cada
  uno en su tarjeta con su foto a la derecha. Es la misma para Don Chuy y para Chente; en el panel, «Editar» y «Cambiar lo
  que lleva» van en la barra de arriba. Los pasos entran en cascada cuando llega la página. Mientras lee, su esqueleto:
  la foto, su tarjeta y tres pasos.
-->
<script lang="ts">
  import './recetario.css';
  import Boton from '../../diseno/Boton.svelte';
  import Esqueleto from '../../diseno/Esqueleto.svelte';
  import NotaTabla from '../../diseno/NotaTabla.svelte';
  import { urlDe, type Pagina } from '../../lib/recetario';
  import Cabeza from './Cabeza.svelte';

  let {
    pagina,
    cargando = false,
    error = null,
    icono = null,
    enAparato = false,
    alVolver,
    alAbrirPreparacion,
  }: {
    pagina: Pagina | null; // null: ya no está (o, en la cocina, se quedó sin pasos)
    cargando?: boolean;
    error?: { titulo: string; texto: string } | null;
    icono?: string | null;
    enAparato?: boolean;
    alVolver: () => void;
    alAbrirPreparacion: (id: number) => void;
  } = $props();
</script>

<div class="rec-desliza">
  <div class="rec-pagina">
    <span class="rec-volver"><Boton etiqueta="Recetario" icono="anterior" onclick={alVolver} /></span>
    {#if cargando}
      <span class="solo-lector">Cargando el recetario…</span>
      <div class="rec-esqueleto" aria-hidden="true">
        <div class="rec-cabeza">
          <div class="rec-foto"><Esqueleto alto="100%" redondo="14px" /></div>
          <div class="rec-info">
            <Esqueleto ancho="84px" alto="24px" redondo="8px" />
            <Esqueleto ancho="260px" alto="26px" />
            <Esqueleto ancho="120px" alto="12px" />
            <div class="tarjeta rec-tarjeta rec-lleva">
              {#each [180, 150, 200, 130] as w (w)}<Esqueleto ancho="{w}px" alto="12px" />{/each}
            </div>
          </div>
        </div>
        {#each [0, 1, 2] as i (i)}
          <div class="tarjeta rec-tarjeta rec-paso"><Esqueleto ancho="28px" alto="28px" redondo="8px" /><Esqueleto ancho="420px" alto="12px" /></div>
        {/each}
      </div>
    {:else if error}
      <NotaTabla relleno={48} angosta titulo={error.titulo} texto={error.texto} />
    {:else if !pagina}
      <NotaTabla
        relleno={48}
        angosta
        titulo="Este recetario ya no está."
        texto={enAparato ? 'Se borró o ya no tiene pasos. Regresa al Recetario.' : 'Se borró su platillo o su preparación. Regresa al Recetario.'}
      />
    {:else}
      <Cabeza {pagina} {icono} pasos={pagina.pasos.length} {enAparato} {alAbrirPreparacion} />
      <h3 class="rec-pasos-titulo"><span class="rec-etq">CÓMO SE HACE</span><span class="rec-cuenta">{pagina.pasos.length}</span></h3>
      {#if pagina.pasos.length}
        <ol class="rec-pasos">
          {#each pagina.pasos as p (p.orden)}
            {@const foto = urlDe(p.imagen_ruta)}
            <li class="tarjeta rec-tarjeta rec-paso">
              <span class="rec-num">{p.orden}</span>
              <p class="rec-paso-texto">{p.texto}</p>
              {#if foto}<span class="rec-paso-foto" style:background-image="url({foto})"></span>{/if}
            </li>
          {/each}
        </ol>
      {:else}
        <p class="rec-pista sin-pasos">Todavía no tiene pasos. Escríbelos con «Editar»: la cocina lo ve en cuanto tenga uno.</p>
      {/if}
    {/if}
  </div>
</div>

<style>
  .sin-pasos {
    margin: 0 4px;
  }
</style>
