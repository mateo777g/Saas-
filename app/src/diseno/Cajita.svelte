<!--
  La cajita que se abre (Ajustes, 12 nov 2026; maqueta FiHkjmT1meyTu7zuU3En2n, «Vista: Ajustes», aprobada en su versión
  36): una tarjeta del panel con su cabecera, que la abre y la cierra. La cabecera lleva el cuadrito del ícono, el título
  y su nota, y a la derecha cómo está (`resumen`, aunque esté cerrada: «Claro · Cristal», «● Conectado») y la flechita.
  Al abrir crece con el rebote de la caja del agente (0.4 s) y lo de adentro baja de la cabecera y aparece; al cerrar,
  0.2 s, de regreso a la cabecera; la flechita gira con el resorte de las listas. En Cristal es material (la tarjeta), y
  lo de adentro, rellenos transparentes. Respeta «reducir movimiento». Para las cajitas que vengan en Ajustes.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import Icono from './Icono.svelte';
  import Tarjeta from './Tarjeta.svelte';

  let {
    icono,
    titulo,
    nota,
    abierta = $bindable(false),
    resumen,
    children,
  }: {
    icono: string;
    titulo: string;
    nota: string;
    abierta?: boolean;
    resumen?: Snippet;
    children: Snippet;
  } = $props();

  const id = $props.id();
</script>

<Tarjeta como="section" class="cajita {abierta ? 'abierta' : ''}" aria-labelledby="{id}-titulo">
  <button type="button" class="cabecera" aria-expanded={abierta} aria-controls="{id}-cuerpo" onclick={() => (abierta = !abierta)}>
    <span class="cuadro-icono"><Icono nombre={icono} tamano={18} /></span>
    <span class="titulos">
      <span class="titulo" id="{id}-titulo">{titulo}</span>
      <span class="nota">{nota}</span>
    </span>
    {#if resumen}<span class="resumen">{@render resumen()}</span>{/if}
    <span class="flecha" aria-hidden="true"><Icono nombre="abajo" tamano={18} /></span>
  </button>
  <div class="cuerpo" id="{id}-cuerpo" role="region" aria-labelledby="{id}-titulo" inert={!abierta}>
    <div class="dentro">
      <div class="contenido">{@render children()}</div>
    </div>
  </div>
</Tarjeta>

<style>
  :global(.cajita) {
    position: relative;
    flex: none;
  }

  .cabecera {
    width: 100%;
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 16px 16px 16px 20px;
    border: 0;
    border-radius: inherit;
    background: none;
    color: inherit;
    font: inherit;
    text-align: left;
    cursor: pointer;
  }

  .cabecera:focus-visible {
    outline: none;
    box-shadow: inset 0 0 0 2px var(--campo-aro);
  }

  .cuadro-icono {
    width: 36px;
    height: 36px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 11px;
    background: var(--chip);
    color: var(--texto);
  }

  .titulos {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .titulo {
    font-size: 14.5px;
    font-weight: 700;
    color: var(--texto);
  }

  .nota {
    font-size: 12.5px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
    text-wrap: pretty;
  }

  .resumen {
    flex: none;
    display: inline-flex;
    align-items: center;
    gap: 8px;
    font-size: 12.5px;
    font-weight: 600;
    color: var(--suave);
  }

  .flecha {
    width: 32px;
    height: 32px;
    flex: none;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    border-radius: 10px;
    color: var(--suave);
    transition:
      transform 0.5s var(--resorte-opcion),
      background-color 0.15s ease,
      color 0.15s ease;
  }

  .cabecera:hover .flecha {
    background: var(--chip);
    color: var(--texto);
  }

  :global(.cajita.abierta) .flecha {
    transform: rotate(180deg);
  }

  /* Abrir: crece con el rebote de la caja del agente y lo de adentro baja y aparece; cerrar es más rápido. */
  .cuerpo {
    display: grid;
    grid-template-rows: 0fr;
    transition: grid-template-rows 0.2s ease;
  }

  :global(.cajita.abierta) .cuerpo {
    grid-template-rows: 1fr;
    transition: grid-template-rows 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275);
  }

  .dentro {
    min-height: 0;
    overflow: hidden;
  }

  .contenido {
    margin: 0 20px 20px;
    padding-top: 18px;
    border-top: 1px solid var(--linea);
    opacity: 0;
    transform: translateY(-8px);
    transition:
      opacity 0.15s ease,
      transform 0.2s ease;
  }

  :global(.cajita.abierta) .contenido {
    opacity: 1;
    transform: none;
    transition:
      opacity 0.3s ease 0.05s,
      transform 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275);
  }

  /* Cristal: la cajita es material (la tarjeta); lo de adentro, rellenos transparentes. */
  :global(:root[data-estilo='cristal'][data-tema='oscuro']) .cuadro-icono {
    background: rgba(255, 255, 255, 0.08);
  }

  :global(:root[data-estilo='cristal'][data-tema='oscuro']) .cabecera:hover .flecha {
    background: rgba(255, 255, 255, 0.08);
  }

  :global(:root[data-estilo='cristal'][data-tema='oscuro']) .contenido {
    border-top-color: rgba(255, 255, 255, 0.08);
  }

  :global(:root[data-estilo='cristal'][data-tema='claro']) .cuadro-icono,
  :global(:root[data-estilo='cristal'][data-tema='claro']) .cabecera:hover .flecha {
    background: rgba(118, 118, 128, 0.12);
  }

  :global(:root[data-estilo='cristal'][data-tema='claro']) .contenido {
    border-top-color: rgba(0, 0, 0, 0.07);
  }

  @media (prefers-reduced-motion: reduce) {
    .cuerpo,
    :global(.cajita.abierta) .cuerpo,
    .contenido,
    :global(.cajita.abierta) .contenido,
    .flecha {
      transition: none !important;
    }
  }
</style>
