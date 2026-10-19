<!--
  «Historial» de la barra del agente (maqueta Agente IA KznKZdgQbLTZGs1EwVMvga): las
  conversaciones de esta sucursal guardadas en este navegador, la más nueva arriba, cada una con
  su primera pregunta (o su idea) y el día y la hora del restaurante en que empezó. La que está
  abierta lleva la palomita. Se cierra con Escape o con un clic afuera.
-->
<script lang="ts">
  import Boton from '../../../diseno/Boton.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import type { Conversacion } from '../../../lib/agente';
  import { diaConNombre } from '../../../lib/formato';

  let {
    conversaciones,
    actual,
    hoy,
    alAbrir,
  }: {
    conversaciones: Conversacion[];
    actual: string | null;
    hoy: string; // la fecha de hoy en el restaurante (mis_sucursales)
    alAbrir: (c: Conversacion) => void;
  } = $props();

  let abierta = $state(false);
  let ancla: HTMLSpanElement;

  // «Hoy · 18:02», «Jueves 15 · 21:10»; de otro mes, con el mes.
  function cuando(c: Conversacion) {
    if (c.fecha === hoy) return `Hoy · ${c.hora}`;
    const dia = diaConNombre(c.fecha);
    return `${c.fecha.slice(0, 7) === hoy.slice(0, 7) ? dia.replace(/ de .*$/, '') : dia} · ${c.hora}`;
  }

  function abrir(c: Conversacion) {
    abierta = false;
    alAbrir(c);
  }

  $effect(() => {
    if (!abierta) return;
    const alClic = (e: MouseEvent) => {
      if (!ancla.contains(e.target as Node)) abierta = false;
    };
    const alTecla = (e: KeyboardEvent) => {
      if (e.key === 'Escape') abierta = false;
    };
    document.addEventListener('mousedown', alClic);
    document.addEventListener('keydown', alTecla);
    return () => {
      document.removeEventListener('mousedown', alClic);
      document.removeEventListener('keydown', alTecla);
    };
  });
</script>

<span class="ancla" bind:this={ancla}>
  <Boton etiqueta="Historial" icono="historial" chip={abierta} onclick={() => (abierta = !abierta)} />
  {#if abierta}
    <div class="lista" role="dialog" aria-label="Historial">
      <span class="etiqueta titulo">CONVERSACIONES DE ESTA SUCURSAL</span>
      {#if !conversaciones.length}
        <p class="vacio">Todavía no hay conversaciones en esta sucursal.</p>
      {/if}
      {#each conversaciones as c (c.id)}
        <button type="button" class="conv" aria-current={c.id === actual ? 'true' : undefined} onclick={() => abrir(c)}>
          <span class="t">
            <span class="nombre">{c.titulo}</span>
            <span class="cuando">{cuando(c)}</span>
          </span>
          {#if c.id === actual}<Icono nombre="check" tamano={16} />{/if}
        </button>
      {/each}
      <div class="pie">Se guardan en este navegador, solo en este aparato. Al cerrar sesión se borran.</div>
    </div>
  {/if}
</span>

<style>
  .ancla {
    position: relative;
    flex: none;
    display: inline-flex;
  }

  .lista {
    position: absolute;
    top: calc(100% + 14px);
    right: 0;
    z-index: 6;
    width: 360px;
    max-height: calc(100vh - 120px);
    overflow-y: auto;
    padding: 8px;
    display: flex;
    flex-direction: column;
    gap: 2px;
    border-radius: 18px;
    border: 1px solid var(--linea);
    background: var(--solido);
    box-shadow: 0 24px 60px var(--sombra);
  }

  .titulo {
    padding: 10px 10px 8px;
  }

  .vacio {
    margin: 0;
    padding: 6px 10px 8px;
    font-size: 13px;
    line-height: 1.45;
    color: var(--tenue);
  }

  .conv {
    width: 100%;
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 9px 10px;
    border: 0;
    border-radius: 12px;
    background: transparent;
    color: var(--texto);
    text-align: left;
    transition: background-color 150ms;
  }

  .conv:hover {
    background: var(--chip);
  }

  .t {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .nombre {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 13.5px;
    font-weight: 700;
  }

  .cuando {
    font-family: var(--mono);
    font-size: 11px;
    color: var(--tenue);
  }

  .pie {
    margin: 6px 4px 2px;
    padding: 10px 6px 4px;
    border-top: 1px solid var(--linea);
    font-size: 12px;
    line-height: 1.45;
    color: var(--tenue);
  }

  @media (prefers-reduced-motion: reduce) {
    .conv {
      transition: none;
    }
  }
</style>
