<!--
  Los pasos de Crear anuncios, al centro de la barra de arriba (13 nov 2026, encuesta 9 de
  planes/trabajo/rediseno/crear-anuncios.md): «1 Productos › 2 Tu anuncio › 3 Listo». El de ahorita en tinta; los hechos
  con su palomita verde (sale con el rebote) y se pican para regresar; los que faltan, en gris, y solo se pican cuando
  se puede (el 2 con al menos un producto, el 3 con un anuncio). Va centrado como el dock de Mi menú, para que no se
  recorra al cambiar el chip de la izquierda.
-->
<script module lang="ts">
  export type Paso = 1 | 2 | 3;
</script>

<script lang="ts">
  import Icono from '../../../diseno/Icono.svelte';

  let { actual, puede, alIr }: { actual: Paso; puede: (paso: Paso) => boolean; alIr: (paso: Paso) => void } = $props();

  const PASOS: { n: Paso; texto: string }[] = [
    { n: 1, texto: 'Productos' },
    { n: 2, texto: 'Tu anuncio' },
    { n: 3, texto: 'Listo' },
  ];
</script>

<nav class="pasos" aria-label="Pasos para crear tu anuncio">
  {#each PASOS as p, i (p.n)}
    {@const hecho = p.n < actual}
    {#if i}<span class="entre" aria-hidden="true"><Icono nombre="derecha" tamano={14} /></span>{/if}
    <button
      type="button"
      class="paso"
      class:actual={p.n === actual}
      class:hecho
      aria-current={p.n === actual ? 'step' : undefined}
      disabled={p.n === actual || !puede(p.n)}
      onclick={() => alIr(p.n)}
    >
      <span class="numero">
        {#if hecho}<span class="palomita"><Icono nombre="check" tamano={12} /></span>{:else}{p.n}{/if}
      </span>
      {p.texto}
    </button>
  {/each}
</nav>

<style>
  .pasos {
    position: absolute;
    left: 50%;
    top: 50%;
    transform: translate(-50%, -50%);
    display: flex;
    align-items: center;
    gap: 2px;
  }

  .entre {
    display: flex;
    color: var(--tenue);
  }

  .paso {
    height: 34px;
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 0 10px 0 7px;
    border: 0;
    border-radius: 10px;
    background: transparent;
    color: var(--suave);
    font: 600 13px var(--jakarta);
    white-space: nowrap;
    cursor: pointer;
    transition:
      background-color 0.15s ease,
      color 0.2s ease;
  }

  .paso:not(:disabled):hover {
    background: var(--chip);
    color: var(--texto);
  }

  .paso:disabled {
    cursor: default;
  }

  .paso:disabled:not(.actual) {
    color: var(--tenue);
  }

  .paso.actual {
    color: var(--texto);
    font-weight: 700;
  }

  .paso:focus-visible {
    outline: none;
    box-shadow: 0 0 0 2px var(--campo-aro);
  }

  .numero {
    width: 22px;
    height: 22px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 7px;
    background: var(--chip);
    color: var(--tenue);
    font: 500 11px var(--mono);
    transition:
      background-color 0.2s ease,
      color 0.2s ease;
  }

  .actual .numero {
    background: var(--tinta);
    color: var(--sobre-tinta);
  }

  .hecho .numero {
    background: var(--verde);
    color: #ffffff;
  }

  .palomita {
    display: flex;
    animation: sale 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275) both;
  }

  @keyframes sale {
    from {
      opacity: 0;
      transform: scale(0.4);
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .paso,
    .numero {
      transition: none;
    }

    .palomita {
      animation: none;
    }
  }
</style>
