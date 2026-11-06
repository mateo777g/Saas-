<!--
  «Pensando…» (maqueta AyS4xUfa5XmDaPJG1iqSgw): los puntos en la orilla, el texto con su brillo que corre,
  los segundos a la derecha (el menú en línea no los lleva) y, debajo, los pasos. Lo usan el Agente IA y
  el asistente del menú; el menú cambia los colores con --pensando-*. Con `chicos`, los puntos van a la mitad
  (el Agente IA; planes/trabajo/rediseno/encuestas-carga.md).
-->
<script lang="ts">
  import type { Paso } from '../lib/pasos';
  import ListaPasos from './ListaPasos.svelte';
  import Puntos from './Puntos.svelte';

  let {
    texto,
    pasos,
    color,
    segundos = null,
    chicos = false,
  }: { texto: string; pasos: Paso[]; color: string; segundos?: number | null; chicos?: boolean } = $props();

  const ultimo = $derived(pasos.at(-1));
  const paraElLector = $derived(ultimo ? `${texto} ${ultimo.hecho ? ultimo.listo : ultimo.texto}` : texto);
</script>

<div class="piensa" class:chicos role="status" aria-label={paraElLector}>
  <Puntos {color} {chicos} />
  <div class="cuerpo">
    <div class="cabeza">
      <span class="brillo">{texto}</span>
      {#if segundos !== null}<span class="segundos">{segundos} s</span>{/if}
    </div>
    {#if pasos.length}<ListaPasos {pasos} entran />{/if}
  </div>
</div>

<style>
  .piensa {
    display: flex;
    gap: var(--pensando-hueco, 12px);
    flex: none;
    max-width: 620px;
  }

  /* Al centro del renglón de 30 px, que es lo que medían los puntos grandes. */
  .piensa.chicos {
    --puntos-arriba: 7.5px;
  }

  .cuerpo {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
  }

  .cabeza {
    height: 30px;
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .brillo {
    font-size: 14px;
    font-weight: 500;
    color: transparent;
    background: linear-gradient(
      90deg,
      var(--pensando-tenue, var(--tenue)) 0%,
      var(--pensando-tenue, var(--tenue)) 42%,
      var(--pensando-texto, var(--texto)) 50%,
      var(--pensando-tenue, var(--tenue)) 58%,
      var(--pensando-tenue, var(--tenue)) 100%
    );
    background-size: 250% 100%;
    -webkit-background-clip: text;
    background-clip: text;
    animation: brillo 1.8s linear infinite;
  }

  @keyframes brillo {
    from {
      background-position: 100% 0;
    }
    to {
      background-position: 0% 0;
    }
  }

  .segundos {
    margin-left: auto;
    font-family: var(--mono);
    font-size: 11px;
    color: var(--tenue);
    font-variant-numeric: tabular-nums;
    white-space: nowrap;
  }

  @media (prefers-reduced-motion: reduce) {
    .brillo {
      animation: none;
      color: var(--pensando-tenue, var(--tenue));
      background: none;
    }
  }
</style>
