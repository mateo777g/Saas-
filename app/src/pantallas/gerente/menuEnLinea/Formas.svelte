<!--
  Un grupo de formas de «Tu menú en línea» (maqueta UDArhiEZceT7rmSKxqRA5r v59, `formas()`): su etiqueta, las formas en
  rectángulos sobre el gris del selector (la elegida en blanco con su sombra) y su pista. Dos o tres formas van en un
  renglón; cuatro, de dos en dos; más, de tres en tres. Un grupo que no aplica a lo elegido se apaga y su pista dice por
  qué (con el logo al centro, la búsqueda, el idioma y la moneda van en la lupa y el engrane). Mientras la vista lee la
  primera vez, las formas van en un esqueleto de su mismo alto (la etiqueta y la pista salen de una vez).
-->
<script lang="ts" generics="T extends string | boolean">
  import Esqueleto from '../../../diseno/Esqueleto.svelte';
  import Icono from '../../../diseno/Icono.svelte';

  let {
    etiqueta,
    opciones,
    elegida,
    alElegir,
    pista,
    apagado = false,
    cargando = false,
  }: {
    etiqueta: string;
    opciones: { valor: T; texto: string; trazos?: string }[];
    elegida: T;
    alElegir: (valor: T) => void;
    pista?: string;
    apagado?: boolean;
    cargando?: boolean;
  } = $props();

  // Al llegar los datos, las formas aparecen con un desvanecido corto en lugar de su esqueleto.
  function aparece(_el: Element) {
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) return { duration: 0 };
    return { duration: 220, css: (x: number) => `opacity: ${x}` };
  }

  const columnas = $derived(opciones.length <= 3 ? opciones.length : opciones.length === 4 ? 2 : 3);
  const renglones = $derived(Math.ceil(opciones.length / columnas));
</script>

<div class="grupo" class:apagado>
  <span class="etiqueta">{etiqueta}</span>
  {#if cargando}
    <Esqueleto alto="{renglones * 40 + (renglones - 1) * 3 + 6}px" redondo="12px" />
  {:else}
    <div class="formas" role="group" aria-label={etiqueta} style:--n={columnas} in:aparece>
      {#each opciones as o (o.valor)}
        <button
          type="button"
          class="forma"
          aria-pressed={o.valor === elegida}
          disabled={apagado}
          onclick={() => {
            if (o.valor !== elegida) alElegir(o.valor);
          }}
        >
          {#if o.trazos}<Icono nombre={o.texto} trazos={o.trazos} tamano={15} />{/if}
          <span>{o.texto}</span>
        </button>
      {/each}
    </div>
  {/if}
  {#if pista !== undefined}
    <p class="pista">{pista}</p>
  {/if}
</div>

<style>
  .grupo {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .pista {
    margin: 0;
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--tenue);
  }

  /* Las formas: rectángulos en el gris del selector; la elegida en blanco con su sombra. */
  .formas {
    display: grid;
    grid-template-columns: repeat(var(--n), minmax(0, 1fr));
    gap: 3px;
    padding: 3px;
    border-radius: 12px;
    background: var(--chip);
  }

  .forma {
    position: relative;
    height: 40px;
    min-width: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 7px;
    padding: 0 8px;
    border: 0;
    border-radius: 9px;
    background: transparent;
    color: var(--suave);
    font: 600 12.5px var(--jakarta);
    white-space: nowrap;
    cursor: pointer;
    transition:
      background-color 0.18s ease,
      color 0.18s ease,
      box-shadow 0.18s ease,
      transform 0.15s ease;
  }

  .forma span {
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .forma :global(svg) {
    flex: none;
  }

  .forma:hover {
    color: var(--texto);
  }

  .forma:active {
    transform: scale(0.97);
  }

  .forma:focus-visible {
    outline: none;
    box-shadow: 0 0 0 2px var(--campo-aro);
  }

  .forma[aria-pressed='true'] {
    background: var(--solido);
    color: var(--texto);
    box-shadow: 0 1px 3px var(--sombra-segmento);
  }

  /* Un grupo que no aplica a la forma elegida: se ve apagado y su pista dice por qué. */
  .apagado .etiqueta,
  .apagado .formas {
    opacity: 0.45;
  }

  .apagado .forma {
    cursor: default;
  }

  .apagado .forma:hover {
    color: var(--suave);
  }

  .apagado .forma[aria-pressed='true'] {
    color: var(--texto);
  }

  @media (prefers-reduced-motion: reduce) {
    .forma {
      transition: none;
    }
  }
</style>
