<!--
  «Elige un estilo» (maqueta JQBw2yGFSiky1x9twUyYbe, ventana Estilos; sale de la de Estilos de la 7a):
  a la izquierda la muestra del elegido en el formato que eligió, su nombre, lo que dice su cuadro y
  lo que lleva; a la derecha los estilos que le salen hoy en cuadros, en sus dos grupos, con la
  muestra de post. Tocar un cuadro solo lo enseña; «Usar este estilo» lo elige y cierra.
-->
<script lang="ts">
  import Boton from '../../../diseno/Boton.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import Ventana from '../../../diseno/Ventana.svelte';
  import { cuantosLleva, formatoDe, loQuePinta, type EstiloDeHoy, type Formato } from '../../../lib/crearContenido';
  import { urlFoto } from '../../../lib/fotos';

  let {
    estilos,
    elegido,
    formato,
    alUsar,
    alCerrar,
  }: {
    estilos: EstiloDeHoy[];
    elegido: number | null;
    formato: Formato;
    alUsar: (estilo: EstiloDeHoy) => void;
    alCerrar: () => void;
  } = $props();

  // svelte-ignore state_referenced_locally
  let viendo = $state(elegido ?? estilos[0]?.id ?? null);
  const estilo = $derived(estilos.find((e) => e.id === viendo) ?? estilos[0]);
  const temporada = $derived(estilos.filter((e) => e.grupo === 'temporada'));
  const paraTodos = $derived(estilos.filter((e) => e.grupo === 'para_todos'));
  // La muestra cabe en 300 × 375, con la forma de su formato.
  const ancho = $derived(formato === 'historia' ? Math.round((375 * 9) / 16) : 300);
  const alto = $derived(formato === 'cartel' ? Math.round((300 * 9) / 16) : 375);
</script>

{#snippet cuadros(lista: EstiloDeHoy[])}
  <div class="cuadros">
    {#each lista as e (e.id)}
      <button type="button" class="cuadro-estilo" class:elegido={e.id === estilo.id} aria-pressed={e.id === estilo.id} onclick={() => (viendo = e.id)}>
        <span class="ce-img" style:background-image="url({urlFoto(e.muestras.post)})"></span>
        <span class="ce-textos"><span class="ce-nombre">{e.nombre}</span><span class="ce-desc">{e.descripcion}</span></span>
        {#if e.id === estilo.id}<span class="ce-check"><Icono nombre="check" tamano={12} /></span>{/if}
      </button>
    {/each}
  </div>
{/snippet}

<Ventana etiqueta="Estilo · se ve en {formatoDe(formato).texto.toLowerCase()}" titulo="Elige un estilo" ancho={1000} alto={720} relleno="24px 28px" {alCerrar}>
  <div class="cuerpo">
    <div class="izq">
      <div class="muestra" style:width="{ancho}px" style:height="{alto}px">
        <img src={urlFoto(estilo.muestras[formato])} alt="" />
      </div>
      <h3 class="nombre">{estilo.nombre}</h3>
      <p class="desc">{estilo.descripcion}</p>
      <ul class="datos">
        <li><Icono nombre="combinar" tamano={15} />{cuantosLleva(estilo)}</li>
        <li>
          <Icono nombre="contraste" tamano={15} />{estilo.color
            ? loQuePinta(estilo)
              ? `Con tu color: ${loQuePinta(estilo)}`
              : 'Con tu color'
            : 'Sale con sus colores'}
        </li>
        <li><Icono nombre="crear" tamano={15} />{estilo.mensaje ? `Tu mensaje, hasta ${estilo.mensaje} letras` : 'No lleva mensaje'}</li>
      </ul>
    </div>
    <div class="der">
      {#if temporada.length}
        <div class="grupo"><span class="etq">De temporada</span><span class="cuenta">{temporada.length}</span></div>
        {@render cuadros(temporada)}
      {/if}
      {#if paraTodos.length}
        <div class="grupo"><span class="etq">Para todos</span><span class="cuenta">{paraTodos.length}</span></div>
        {@render cuadros(paraTodos)}
      {/if}
    </div>
  </div>
  <div class="pie">
    <Boton etiqueta="Cancelar" icono="cerrar" onclick={alCerrar} />
    <span class="crece"></span>
    <Boton etiqueta="Usar este estilo" icono="check-fino" tono="tinta" onclick={() => alUsar(estilo)} />
  </div>
</Ventana>

<style>
  .cuerpo {
    flex: 1;
    min-height: 0;
    display: flex;
    gap: 28px;
    margin-top: 18px;
  }

  .izq {
    width: 300px;
    flex: none;
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .muestra {
    position: relative;
    flex: none;
    border-radius: 14px;
    overflow: hidden;
    background: #000000;
  }

  .muestra img {
    display: block;
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .nombre {
    margin: 4px 0 0;
    font-size: 18px;
    font-weight: 800;
    letter-spacing: -0.3px;
  }

  .desc {
    margin: 0;
    font-size: 13px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .datos {
    margin: 0;
    padding: 0;
    list-style: none;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .datos li {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 12.5px;
    font-weight: 500;
    color: var(--suave);
  }

  .datos li :global(svg) {
    color: var(--tenue);
  }

  .der {
    flex: 1;
    min-width: 0;
    overflow-y: auto;
    padding: 2px 8px 2px 2px;
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .grupo {
    display: flex;
    align-items: baseline;
    gap: 10px;
    padding-top: 4px;
  }

  .etq {
    font-family: var(--mono);
    font-size: 10.5px;
    letter-spacing: 0.14em;
    color: var(--tenue);
    text-transform: uppercase;
  }

  .cuenta {
    font-family: var(--mono);
    font-size: 11px;
    color: var(--tenue);
  }

  .cuadros {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 12px;
  }

  .cuadro-estilo {
    position: relative;
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 6px 6px 10px;
    border-radius: 14px;
    border: 1px solid var(--linea);
    background: var(--solido);
    color: var(--texto);
    text-align: left;
    min-width: 0;
    cursor: pointer;
  }

  .cuadro-estilo.elegido {
    box-shadow: 0 0 0 2px var(--tinta);
    border-color: transparent;
  }

  .ce-img {
    aspect-ratio: 4 / 5;
    border-radius: 10px;
    background: #000000 center / cover no-repeat;
  }

  .ce-textos {
    padding: 0 4px;
    display: flex;
    flex-direction: column;
    gap: 3px;
    min-width: 0;
  }

  .ce-nombre {
    font-size: 13px;
    font-weight: 700;
  }

  .ce-desc {
    font-size: 11.5px;
    font-weight: 500;
    line-height: 1.4;
    color: var(--tenue);
    overflow: hidden;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
  }

  .ce-check {
    position: absolute;
    top: 12px;
    right: 12px;
    width: 22px;
    height: 22px;
    border-radius: 11px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--tinta);
    color: var(--sobre-tinta);
  }

  .pie {
    display: flex;
    align-items: center;
    gap: 10px;
    flex: none;
    margin-top: 18px;
  }

  .crece {
    flex-grow: 1;
  }
</style>
