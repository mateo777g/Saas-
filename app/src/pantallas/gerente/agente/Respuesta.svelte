<!--
  Una respuesta del agente (rediseño del 5 de noviembre de 2026; maqueta V64Pv4gmANPRZuJW5hTe5D; «Pensé 6 s ›»,
  maqueta AyS4xUfa5XmDaPJG1iqSgw): el Markdown en texto plano, con el total en un renglón de texto debajo de
  la tabla. Las tablas llevan los números a la derecha. Una respuesta nueva sale renglón por renglón, con el
  cursor y los puntitos, que bajan debajo del último renglón y al terminar se van
  (planes/trabajo/rediseno/encuestas-carga.md); las del Historial, enteras. Abajo, «Copiar» (copia el Markdown tal cual), «Lo que leí» (lo que el
  panel calculó para responder, que se abre debajo; planes/trabajo/rediseno/encuestas-agente.md) y, si la
  pregunta salió de una idea, sus dos seguimientos.

  Una pregunta detenida (`aviso`) no trae Markdown ni «Copiar»: solo lo que dice el aviso y, si alcanzó a leer
  algo, «Lo que leí».
-->
<script lang="ts">
  import Icono from '../../../diseno/Icono.svelte';
  import { ICONOS } from '../../../diseno/iconos';
  import Pildora from '../../../diseno/Pildora.svelte';
  import Puntos from '../../../diseno/Puntos.svelte';
  import type { Leido } from '../../../lib/agente';
  import { acomodar, DESPUES_DEL_ULTIMO, markdown, revelar } from '../../../lib/markdown';

  let {
    texto,
    aviso = null,
    nueva = false,
    segundos,
    pasos,
    leido,
    nota,
    seguimiento = [],
    apagado = false,
    alSeguir,
  }: {
    texto: string;
    aviso?: string | null;
    nueva?: boolean;
    segundos?: number;
    pasos?: string[];
    leido: Leido[];
    nota: string;
    seguimiento?: { etiqueta: string; pregunta: string }[];
    apagado?: boolean;
    alSeguir: (s: { etiqueta: string; pregunta: string }) => void;
  } = $props();

  const html = $derived(markdown(texto));
  let cuerpo = $state<HTMLDivElement | null>(null);
  let copiado = $state(false);
  let leyendo = $state(false);
  // Los botones salen al terminar de salir el texto, como en Flet.
  let esperaAcciones = $state(0);
  // Los puntitos mientras sale el texto: empiezan donde estaba el «Pensando…» y bajan con cada renglón.
  let puntitos = $state<'no' | 'bajan' | 'se-van'>('no');
  let altoPuntitos = $state<number | null>(null);
  let bajan = $state<HTMLSpanElement | null>(null);

  // svelte-ignore state_referenced_locally
  const animar = nueva;

  $effect(() => {
    void html;
    if (!cuerpo) return;
    acomodar(cuerpo);
    if (!animar) return;
    const conMovimiento = !matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (conMovimiento) puntitos = 'bajan';
    const espera =
      revelar(cuerpo, (pieza) => {
        // Para que el primer renglón también se vea bajar.
        void bajan?.offsetWidth;
        altoPuntitos = pieza.offsetTop + pieza.offsetHeight + 8;
      }) *
        110 +
      DESPUES_DEL_ULTIMO;
    esperaAcciones = espera;
    if (!conMovimiento) return;
    const seVan = setTimeout(() => (puntitos = 'se-van'), espera);
    const fuera = setTimeout(() => (puntitos = 'no'), espera + 150);
    return () => {
      clearTimeout(seVan);
      clearTimeout(fuera);
    };
  });

  async function copiar() {
    try {
      await navigator.clipboard.writeText(texto);
      copiado = true;
      setTimeout(() => (copiado = false), 1600);
    } catch (error) {
      console.error('[agente] no se pudo copiar la respuesta:', error);
    }
  }
</script>

<div class="respuesta">
  {#if puntitos !== 'no'}
    <span
      class="bajan"
      class:se-van={puntitos === 'se-van'}
      style:top={altoPuntitos === null ? null : `${altoPuntitos}px`}
      aria-hidden="true"
      bind:this={bajan}
    >
      <Puntos chicos color="var(--punto-panel)" />
    </span>
  {/if}
  {#if segundos && pasos && (!aviso || pasos.length)}<Pildora texto="Pensé {segundos} s" {pasos} plana />{/if}
  {#if aviso}
    <p class="aviso">{aviso}</p>
  {:else}
    <div class="md" bind:this={cuerpo}>{@html html}</div>
  {/if}
  {#if !aviso || leido.length}
    <div class="acciones" class:aparece={animar} style:animation-delay={animar ? `${esperaAcciones}ms` : undefined}>
      {#if !aviso}
        <button type="button" class="chico suave" onclick={copiar} disabled={copiado}>
          {#if copiado}
            <span class="verde"><Icono nombre="check" tamano={14} /></span>Copiado
          {:else}
            <Icono nombre="copiar" tamano={14} />Copiar
          {/if}
        </button>
      {/if}
      <button type="button" class="chico suave" aria-expanded={leyendo} onclick={() => (leyendo = !leyendo)}>
        <Icono nombre="datos" tamano={14} />Lo que leí
      </button>
      {#each seguimiento as s (s.etiqueta)}
        <button type="button" class="chico" disabled={apagado} onclick={() => alSeguir(s)}>{s.etiqueta}</button>
      {/each}
    </div>
    {#if leyendo}
      <div class="leido">
        {#each leido as l (l.texto)}
          <div class="leido-fila">
            <span class="leido-icono"><Icono nombre={l.icono in ICONOS ? l.icono : 'datos'} tamano={16} /></span>
            <span>{l.texto}</span>
          </div>
        {:else}
          <p class="leido-vacio">Para esta respuesta no hice cálculos.</p>
        {/each}
        <p class="leido-nota">{nota}</p>
      </div>
    {/if}
  {/if}
</div>

<style>
  .respuesta {
    position: relative;
    flex: none;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 12px;
    font-size: 14.5px;
    line-height: 1.6;
  }

  .bajan {
    position: absolute;
    left: 0;
    top: 7.5px;
    transition:
      top 0.26s cubic-bezier(0.22, 1, 0.36, 1),
      opacity 0.15s ease;
  }

  .bajan.se-van {
    opacity: 0;
  }

  .aviso {
    margin: 0;
    color: var(--suave);
  }

  .md :global(.cursor) {
    display: inline-block;
    width: 4px;
    height: 14px;
    margin-left: 4px;
    border-radius: 2px;
    background: var(--acento);
    vertical-align: -2px;
    animation: latido 1s ease-in-out infinite;
  }

  @keyframes latido {
    0%,
    100% {
      opacity: 1;
    }
    50% {
      opacity: 0.35;
    }
  }

  .md {
    display: flex;
    flex-direction: column;
    gap: 12px;
    overflow-wrap: anywhere;
  }

  .md :global(p) {
    margin: 0;
  }

  .md :global(strong) {
    font-weight: 700;
  }

  .md :global(h1),
  .md :global(h2),
  .md :global(h3),
  .md :global(h4) {
    margin: 0;
    font-weight: 700;
    line-height: 1.3;
  }

  .md :global(h1) {
    font-size: 19px;
  }

  .md :global(h2) {
    font-size: 17px;
  }

  .md :global(h3) {
    font-size: 15.5px;
  }

  .md :global(h4) {
    font-size: 14.5px;
    color: var(--suave);
  }

  .md :global(ul),
  .md :global(ol) {
    margin: 0;
    padding-left: 22px;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .md :global(li > ul),
  .md :global(li > ol) {
    margin-top: 6px;
  }

  .md :global(li::marker) {
    color: var(--suave);
  }

  .md :global(blockquote) {
    margin: 0;
    padding: 10px 14px;
    border-radius: 10px;
    background: var(--chip);
    font-size: 14px;
    color: var(--suave);
  }

  .md :global(blockquote p) {
    margin: 0;
  }

  .md :global(code) {
    font-family: var(--mono);
    font-size: 13px;
  }

  .md :global(pre) {
    margin: 0;
    padding: 10px 12px;
    border-radius: 10px;
    background: var(--chip);
    overflow-x: auto;
  }

  .md :global(hr) {
    width: 100%;
    height: 1px;
    margin: 0;
    border: 0;
    background: var(--linea);
  }

  .md :global(a) {
    color: inherit;
  }

  .md :global(.md-tabla) {
    overflow-x: auto;
  }

  .md :global(table) {
    width: 100%;
    border-collapse: collapse;
    font-size: 13.5px;
    font-variant-numeric: tabular-nums;
  }

  .md :global(th) {
    padding: 7px 24px 7px 0;
    border-bottom: 1px solid var(--linea-fuerte);
    text-align: left;
    font-weight: 600;
  }

  .md :global(td) {
    padding: 7px 24px 7px 0;
    border-bottom: 1px solid var(--linea);
    vertical-align: top;
  }

  .md :global(th.n),
  .md :global(td.n) {
    padding-right: 0;
    text-align: right;
    white-space: nowrap;
  }

  .md :global(.aparece),
  .acciones.aparece {
    animation: aparecer 330ms ease-out both;
  }

  @keyframes aparecer {
    from {
      opacity: 0;
      transform: translateY(6px);
    }
    to {
      opacity: 1;
      transform: none;
    }
  }

  .acciones {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }

  .chico {
    height: 30px;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 0 11px;
    border-radius: 8px;
    border: 1px solid var(--linea);
    background: none;
    color: var(--texto);
    font-size: 12.5px;
    font-weight: 600;
    transition: border-color 150ms;
  }

  .chico:hover:not(:disabled),
  .chico[aria-expanded='true'] {
    border-color: var(--linea-fuerte);
  }

  .chico:disabled {
    cursor: default;
  }

  .chico.suave {
    color: var(--suave);
  }

  .verde {
    color: var(--verde);
  }

  .leido {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .leido-fila {
    display: flex;
    align-items: flex-start;
    gap: 10px;
    font-size: 13px;
    line-height: 1.45;
  }

  .leido-icono {
    margin-top: 1px;
    color: var(--tenue);
  }

  .leido-nota {
    margin: 0;
    font-size: 12.5px;
    line-height: 1.5;
    color: var(--suave);
  }

  .leido-vacio {
    margin: 0;
    font-size: 13px;
    line-height: 1.45;
    color: var(--tenue);
  }

  @media (prefers-reduced-motion: reduce) {
    .md :global(.aparece),
    .acciones.aparece {
      animation: none;
    }

    .chico {
      transition: none;
    }
  }
</style>
