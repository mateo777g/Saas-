<!--
  Una respuesta del agente (maqueta Agente IA KznKZdgQbLTZGs1EwVMvga): la ∫∫ a la izquierda y el
  Markdown como lo pinta, con el total en un renglón de texto debajo de la tabla (la barra negra
  «Total de hoy» de la maqueta de Flet no sale del Markdown). Las tablas van en su caja, con los
  números a la derecha y en mono y los encabezados en mayúsculas, como en Flet. Una respuesta
  nueva sale renglón por renglón; las del Historial, enteras. Abajo, «Copiar» (copia el Markdown
  tal cual) y, si la pregunta salió de una idea, sus dos seguimientos.
-->
<script lang="ts">
  import Icono from '../../../diseno/Icono.svelte';
  import Integral from '../../../diseno/Integral.svelte';
  import { acomodar, markdown, revelar } from '../../../lib/markdown';

  let {
    texto,
    nueva = false,
    seguimiento = [],
    apagado = false,
    alSeguir,
  }: {
    texto: string;
    nueva?: boolean;
    seguimiento?: { etiqueta: string; pregunta: string }[];
    apagado?: boolean;
    alSeguir: (s: { etiqueta: string; pregunta: string }) => void;
  } = $props();

  const html = $derived(markdown(texto));
  let cuerpo = $state<HTMLDivElement | null>(null);
  let copiado = $state(false);
  // Los botones salen al terminar de salir el texto, como en Flet.
  let esperaAcciones = $state(0);

  // svelte-ignore state_referenced_locally
  const animar = nueva;

  $effect(() => {
    void html;
    if (!cuerpo) return;
    acomodar(cuerpo);
    if (animar) esperaAcciones = revelar(cuerpo) * 110;
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

<div class="resp">
  <span class="logo"><Integral ancho={20} alto={22} /></span>
  <div class="cuerpo">
    <div class="md" bind:this={cuerpo}>{@html html}</div>
    <div class="acciones" class:aparece={animar} style:animation-delay={animar ? `${esperaAcciones}ms` : undefined}>
      <button type="button" class="chico suave" onclick={copiar} disabled={copiado}>
        {#if copiado}
          <span class="verde"><Icono nombre="check" tamano={14} /></span>Copiado
        {:else}
          <Icono nombre="copiar" tamano={14} />Copiar
        {/if}
      </button>
      {#each seguimiento as s (s.etiqueta)}
        <button type="button" class="chico" disabled={apagado} onclick={() => alSeguir(s)}>{s.etiqueta}</button>
      {/each}
    </div>
  </div>
</div>

<style>
  .resp {
    flex: none;
    display: flex;
    gap: 12px;
  }

  .logo {
    width: 30px;
    height: 30px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--acento);
  }

  .cuerpo {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 14px;
    padding-top: 2px;
  }

  .md {
    display: flex;
    flex-direction: column;
    gap: 12px;
    font-size: 16px;
    line-height: 1.6;
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
    font-size: 21px;
  }

  .md :global(h2) {
    font-size: 19px;
  }

  .md :global(h3) {
    font-size: 17px;
  }

  .md :global(h4) {
    font-size: 16px;
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
    font-size: 15px;
    color: var(--suave);
  }

  .md :global(blockquote p) {
    margin: 0;
  }

  .md :global(code) {
    font-family: var(--mono);
    font-size: 14px;
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
    border: 1px solid var(--linea);
    border-radius: 16px;
    overflow: hidden;
    overflow-x: auto;
    background: var(--solido);
  }

  .md :global(table) {
    width: 100%;
    border-collapse: collapse;
    font-size: 14px;
    line-height: normal;
  }

  .md :global(th) {
    padding: 10px 14px;
    text-align: left;
    font-family: var(--mono);
    font-size: 11px;
    font-weight: 500;
    letter-spacing: 0.1em;
    text-transform: uppercase;
    color: var(--tenue);
    background: var(--chip);
    white-space: nowrap;
  }

  .md :global(td) {
    padding: 11px 14px;
    border-top: 1px solid var(--linea);
    vertical-align: top;
  }

  .md :global(.n) {
    text-align: right;
    font-family: var(--mono);
    font-variant-numeric: tabular-nums;
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
    height: 32px;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 0 12px;
    border-radius: 10px;
    border: 1px solid var(--linea);
    background: var(--solido);
    color: var(--texto);
    font-size: 12.5px;
    font-weight: 600;
    transition: opacity 150ms;
  }

  .chico:hover:not(:disabled) {
    opacity: 0.86;
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
