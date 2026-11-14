<!--
  «Elige un estilo» (maqueta JQBw2yGFSiky1x9twUyYbe, ventana Estilos; sale de la de Estilos de la 7a):
  a la izquierda la muestra del elegido en el formato que eligió, su nombre, lo que dice su cuadro y
  lo que lleva; a la derecha los estilos que le salen hoy en cuadros, en sus dos grupos, con la
  muestra de post. Tocar un cuadro solo lo enseña; «Usar este estilo» lo elige y cierra.

  Con las reglas del rediseño (Crear anuncios por pasos, 13 nov 2026, planes/trabajo/rediseno/crear-anuncios.md):
  los que no van con cuántos productos eligió salen apagados con «Para 2 o 3 productos» (encuesta 2; para usarlo,
  «Atrás» y pica otro); los cuadros entran en cascada al abrirla (diseno/cascada.ts) y la lista se desliza con el
  desvanecido de las ventanas; el elegido lleva el azul del aro de las cajas (como los roles de Empleados), su
  palomita sale con el rebote y la muestra de la izquierda cambia con un desvanecido; «Usar este estilo» va en verde.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import { fade } from 'svelte/transition';
  import Boton from '../../../diseno/Boton.svelte';
  import { cascada } from '../../../diseno/cascada';
  import Icono from '../../../diseno/Icono.svelte';
  import Ventana from '../../../diseno/Ventana.svelte';
  import { cuantosLleva, formatoDe, loQuePinta, paraCuantos, vaCon, type EstiloDeHoy, type Formato } from '../../../lib/crearContenido';
  import { urlFoto } from '../../../lib/fotos';

  let {
    estilos,
    elegido,
    formato,
    productos,
    alUsar,
    alCerrar,
  }: {
    estilos: EstiloDeHoy[];
    elegido: number | null;
    formato: Formato;
    // Cuántos productos eligió: los estilos que no los llevan salen apagados.
    productos: number;
    alUsar: (estilo: EstiloDeHoy) => void;
    alCerrar: () => void;
  } = $props();

  // Entra enseñando el elegido; si no va (o no hay), el primero que sí va.
  // svelte-ignore state_referenced_locally
  let viendo = $state(
    estilos.find((e) => e.id === elegido && vaCon(e, productos))?.id ?? estilos.find((e) => vaCon(e, productos))?.id ?? estilos[0]?.id ?? null,
  );
  const estilo = $derived(estilos.find((e) => e.id === viendo) ?? estilos[0]);
  const sirve = $derived(vaCon(estilo, productos));
  const temporada = $derived(estilos.filter((e) => e.grupo === 'temporada'));
  const paraTodos = $derived(estilos.filter((e) => e.grupo === 'para_todos'));
  // La muestra cabe en 300 × 375, con la forma de su formato.
  const ancho = $derived(formato === 'historia' ? Math.round((375 * 9) / 16) : 300);
  const alto = $derived(formato === 'cartel' ? Math.round((300 * 9) / 16) : 375);

  // La lista de la derecha: el desvanecido de arriba y de abajo mientras hay más (el de diseno/Ventana.svelte).
  let lista: HTMLDivElement;
  let masArriba = $state(false);
  let masAbajo = $state(false);
  function sombras() {
    masArriba = lista.scrollTop > 1;
    masAbajo = lista.scrollTop + lista.clientHeight < lista.scrollHeight - 1;
  }

  onMount(() => {
    sombras();
    cascada(lista);
  });
</script>

{#snippet cuadros(grupo: EstiloDeHoy[])}
  <div class="cuerpo cuadros">
    {#each grupo as e (e.id)}
      {@const va = vaCon(e, productos)}
      <button
        type="button"
        class="fila cuadro-estilo"
        class:elegido={e.id === estilo.id}
        class:apagado={!va}
        aria-pressed={e.id === estilo.id}
        disabled={!va}
        onclick={() => (viendo = e.id)}
      >
        <span class="ce-img" style:background-image="url({urlFoto(e.muestras.post)})"></span>
        <span class="ce-textos">
          <span class="ce-nombre">{e.nombre}</span>
          {#if va}
            <span class="ce-desc">{e.descripcion}</span>
          {:else}
            <span class="ce-para"><Icono nombre="combinar" tamano={13} />{paraCuantos(e)}</span>
          {/if}
        </span>
        {#if e.id === estilo.id}<span class="ce-check"><Icono nombre="check" tamano={12} /></span>{/if}
      </button>
    {/each}
  </div>
{/snippet}

<Ventana centrado etiqueta="Estilo · se ve en {formatoDe(formato).texto.toLowerCase()}" titulo="Elige un estilo" ancho={1000} alto={720} relleno="24px 28px" {alCerrar}>
  <div class="cuerpo-ventana">
    <div class="izq">
      {#key estilo.id}
        <div class="muestra" style:width="{ancho}px" style:height="{alto}px" in:fade={{ duration: 300 }}>
          <img src={urlFoto(estilo.muestras[formato])} alt="" />
        </div>
      {/key}
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
    <div class="der" class:mas-arriba={masArriba} class:mas-abajo={masAbajo} bind:this={lista} onscroll={sombras}>
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
    <Boton etiqueta="Cancelar" icono="cerrar" tono="alarga" onclick={alCerrar} />
    <span class="crece"></span>
    <Boton etiqueta="Usar este estilo" tono="verde" apagado={!sirve} onclick={() => alUsar(estilo)} />
  </div>
</Ventana>

<style>
  .cuerpo-ventana {
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

  /* La lista se desliza sola (la ventana es de alto fijo), con el desvanecido de las ventanas mientras hay más. */
  .der {
    flex: 1;
    min-width: 0;
    overflow-y: auto;
    scrollbar-width: thin;
    padding: 2px 8px 12px 2px;
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .der.mas-arriba {
    -webkit-mask-image: linear-gradient(to bottom, transparent 0, #000 32px);
    mask-image: linear-gradient(to bottom, transparent 0, #000 32px);
  }

  .der.mas-abajo {
    -webkit-mask-image: linear-gradient(to top, transparent 0, #000 32px);
    mask-image: linear-gradient(to top, transparent 0, #000 32px);
  }

  .der.mas-arriba.mas-abajo {
    -webkit-mask-image: linear-gradient(to bottom, transparent 0, #000 32px, #000 calc(100% - 32px), transparent 100%);
    mask-image: linear-gradient(to bottom, transparent 0, #000 32px, #000 calc(100% - 32px), transparent 100%);
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

  /* Cada estilo es una tarjeta: el borde de las tarjetas, 14 de esquina. */
  .cuadro-estilo {
    position: relative;
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 6px 6px 10px;
    border-radius: 14px;
    border: 1px solid var(--borde-tarjeta);
    background: var(--solido);
    color: var(--texto);
    text-align: left;
    min-width: 0;
    cursor: pointer;
    transition:
      box-shadow 0.2s ease,
      border-color 0.2s ease,
      transform 0.15s ease;
  }

  .cuadro-estilo:not(:disabled):active {
    transform: scale(0.98);
  }

  .cuadro-estilo:focus-visible {
    outline: none;
    box-shadow: 0 0 0 2px var(--campo-aro);
  }

  .cuadro-estilo.elegido {
    box-shadow: 0 0 0 2px var(--campo-aro);
    border-color: transparent;
  }

  .cuadro-estilo.apagado {
    cursor: default;
  }

  .cuadro-estilo.apagado .ce-img,
  .cuadro-estilo.apagado .ce-nombre {
    opacity: 0.4;
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

  .ce-para {
    display: flex;
    align-items: center;
    gap: 5px;
    font-size: 11.5px;
    font-weight: 600;
    color: var(--suave);
  }

  /* La palomita del elegido sale con el rebote de lo que se abre (el de la caja del agente). */
  .ce-check {
    position: absolute;
    top: 12px;
    right: 12px;
    width: 22px;
    height: 22px;
    border-radius: 7px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--campo-aro);
    color: #ffffff;
    animation: sale 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275) both;
  }

  @keyframes sale {
    from {
      opacity: 0;
      transform: scale(0.4);
    }
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

  @media (prefers-reduced-motion: reduce) {
    .cuadro-estilo {
      transition: none;
    }

    .ce-check {
      animation: none;
    }
  }
</style>
