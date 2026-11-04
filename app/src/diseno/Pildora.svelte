<!--
  «Pensé 6 s ›» (maqueta AyS4xUfa5XmDaPJG1iqSgw): los pasos de una respuesta, doblados. Sale cerrada y se
  abre para verlos otra vez; no se recuerda abierta. Las conversaciones de antes no la llevan. La usan el
  Agente IA y el asistente del menú, que cambia los colores con --pensando-* y trae su texto en ES / EN.
-->
<script lang="ts">
  import Icono from './Icono.svelte';
  import ListaPasos from './ListaPasos.svelte';

  let { texto, pasos }: { texto: string; pasos: string[] } = $props();

  let abierta = $state(false);
  const lista = $derived(pasos.map((texto, clave) => ({ clave, icono: 'check', texto, listo: texto, hecho: true })));
</script>

<button type="button" class="pildora" aria-expanded={abierta} onclick={() => (abierta = !abierta)}>
  {texto}<Icono nombre="siguiente" tamano={14} />
</button>
{#if abierta}
  <div class="abierta"><ListaPasos pasos={lista} /></div>
{/if}

<style>
  .pildora {
    align-self: flex-start;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 28px;
    padding: 0 9px 0 12px;
    border-radius: 14px;
    border: 1px solid var(--pensando-linea, var(--linea));
    background: var(--pensando-chip, var(--chip));
    color: var(--pensando-suave, var(--suave));
    font-size: 12px;
    font-weight: 600;
    transition: color 150ms;
  }

  .pildora:hover {
    color: var(--pensando-texto, var(--texto));
  }

  .pildora :global(svg) {
    transition: transform 200ms cubic-bezier(0.22, 1, 0.36, 1);
  }

  .pildora[aria-expanded='true'] :global(svg) {
    transform: rotate(90deg);
  }

  .abierta {
    margin-top: -10px;
  }

  @media (prefers-reduced-motion: reduce) {
    .pildora,
    .pildora :global(svg) {
      transition: none;
    }
  }
</style>
