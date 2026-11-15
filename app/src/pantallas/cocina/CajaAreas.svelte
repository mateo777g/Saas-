<!--
  La cajita del área de la Cocina, en su barra de arriba (rediseño, 14 nov 2026; planes/trabajo/rediseno/cocina.md): como
  la de sucursales (gerente/CajaSucursales.svelte), con sus mismas medidas y sus mismos resortes. Dice qué área muestra
  esta pantalla y abre la lista de las áreas con cuántas comandas tiene cada una; elegir otra la cambia y este aparato la
  recuerda (Cocina.svelte). Con una sola área, lo dice.

  La lista cuelga del botón, 8 debajo de la barra y a ras de su orilla derecha. Se cierra al elegir, con un clic afuera o
  con Escape. Respeta «reducir movimiento».
-->
<script lang="ts">
  import { tick } from 'svelte';
  import { Tween } from 'svelte/motion';
  import { DURA_FLECHA, resorteFlecha, trazosFlecha } from '../../diseno/flecha';
  import Icono from '../../diseno/Icono.svelte';
  import { pica, vidrio } from '../../diseno/vidrio';
  import { plural } from '../../lib/formato';

  let {
    areas,
    actual,
    alElegir,
  }: { areas: { id: number; nombre: string; comandas: number }[]; actual: number; alElegir: (id: number) => void } = $props();

  let abierta = $state(false);
  let caja: HTMLDivElement;
  let boton: HTMLButtonElement;
  let lista = $state<HTMLDivElement>();
  let alto = $state(0);
  const idLista = $props.id();

  const area = $derived(areas.find((a) => a.id === actual) ?? areas[0]);

  const quieto = typeof matchMedia === 'function' ? matchMedia('(prefers-reduced-motion: reduce)') : null;
  const doblez = new Tween(0, { duration: DURA_FLECHA, easing: resorteFlecha });
  $effect(() => {
    doblez.set(abierta ? 1 : 0, quieto?.matches ? { duration: 0 } : undefined);
  });
  const trazos = $derived(trazosFlecha(doblez.current));

  // Cada renglón sale del botón: se mide cuánto le falta para llegar a él y se pone quieto antes de abrir.
  let desde = $state<number[]>([]);
  let midiendo = $state(false);
  async function alternar() {
    if (abierta) {
      abierta = false;
      return;
    }
    if (lista) {
      const arriba = lista.getBoundingClientRect().top - boton.getBoundingClientRect().top;
      desde = [...lista.querySelectorAll<HTMLElement>('.renglon')].map((f) => Math.max(0, arriba + f.offsetTop));
    }
    midiendo = true;
    await tick();
    void lista?.offsetHeight;
    midiendo = false;
    abierta = true;
  }

  function elegir(id: number) {
    abierta = false;
    if (id !== actual) alElegir(id);
  }
</script>

<svelte:window
  onclick={(e) => {
    if (abierta && !caja.contains(e.target as Node)) abierta = false;
  }}
  onkeydown={(e) => {
    if (abierta && e.key === 'Escape') {
      abierta = false;
      boton.focus();
    }
  }}
/>

<div class="caja" bind:this={caja}>
  <button
    type="button"
    class="boton"
    use:vidrio={'boton'}
    use:pica={1.08}
    aria-expanded={abierta}
    aria-controls={idLista}
    aria-label="Área: {area?.nombre ?? ''}"
    bind:this={boton}
    onclick={alternar}
  >
    <Icono nombre="r-cocina" tamano={18} />
    <span class="nombre-boton">{area?.nombre}</span>
    <svg class="flecha" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"
      ><path d={trazos[0]}></path><path d={trazos[1]}></path></svg
    >
  </button>

  <div class="fondo" class:abierta aria-hidden="true" style:--alto="{alto}px" use:vidrio={'hoja'}></div>
  <div class="lista" class:abierta class:midiendo id={idLista} inert={!abierta} bind:this={lista} bind:offsetHeight={alto}>
    <span class="etiqueta titulo">ÁREA DE ESTA PANTALLA</span>
    {#if areas.length === 1}
      <div class="sola renglon" style:--y="{desde[0] ?? 0}px" style:--da="0ms" style:--dc="0ms">
        <span class="suave"><Icono nombre="info" tamano={16} /></span>
        Solamente hay un área.
      </div>
    {:else}
      {#each areas as a, j (a.id)}
        <button
          type="button"
          class="opcion renglon"
          style:--y="{desde[j] ?? 0}px"
          style:--da="{Math.min(j, 8) * 45}ms"
          style:--dc="{(areas.length - 1 - j) * 20}ms"
          aria-current={a.id === actual ? 'true' : undefined}
          onclick={() => elegir(a.id)}
        >
          <span class="cuadro-icono"><Icono nombre="cocina" tamano={16} /></span>
          <span class="nombres">
            <span class="nombre">{a.nombre}</span>
            <span class="debajo">{plural(a.comandas, 'comanda', 'comandas')}</span>
          </span>
          {#if a.id === actual}<Icono nombre="check-delgado" tamano={16} />{/if}
        </button>
      {/each}
    {/if}
  </div>
</div>

<style>
  .caja {
    position: relative;
    display: flex;
  }

  /* El botón secundario de la barra de arriba (el de la cajita de sucursales); abierto, con chip. */
  .boton {
    height: 34px;
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 0 13px;
    border: 1px solid var(--linea);
    border-radius: 9px;
    background: transparent;
    color: var(--texto);
    font-size: 13px;
    font-weight: 600;
    white-space: nowrap;
    transition:
      opacity 150ms,
      transform 0.2s ease;
  }

  .boton:hover {
    opacity: 0.86;
  }

  .boton[aria-expanded='true'] {
    background: var(--chip);
  }

  .boton:active {
    transform: scale(0.95);
  }

  .suave {
    display: flex;
    color: var(--suave);
  }

  .boton .flecha {
    width: 14px !important;
    height: 14px !important;
    flex: none;
    color: var(--suave);
  }

  /* 8 debajo de la barra (el botón de 34 va al centro de sus 56) y a ras de la orilla derecha del botón. */
  .fondo,
  .lista {
    position: absolute;
    top: calc(100% + 19px);
    right: 0;
    width: 300px;
  }

  .fondo {
    z-index: 3;
    height: 0;
    border: 1px solid var(--linea);
    border-radius: 18px;
    background: var(--solido);
    opacity: 0;
    pointer-events: none;
    transition:
      height 0.518s var(--resorte-fondo),
      opacity 0.25s ease,
      box-shadow 0.25s ease;
  }

  .fondo.abierta {
    height: var(--alto);
    opacity: 1;
    box-shadow: 0 24px 60px var(--sombra);
  }

  .lista {
    z-index: 4;
    padding: 8px;
    display: flex;
    flex-direction: column;
    gap: 2px;
    pointer-events: none;
  }

  .lista.abierta {
    pointer-events: auto;
  }

  .titulo {
    padding: 10px 10px 8px;
    opacity: 0;
    transition: opacity 0.2s ease;
  }

  .lista.abierta .titulo {
    opacity: 1;
    transition: opacity 0.3s ease 0.05s;
  }

  .renglon {
    opacity: 0;
    transform: translateY(calc(-1 * var(--y))) scale(0.8);
    transition:
      transform 0.607s var(--resorte-opcion) var(--dc),
      opacity 0.3s ease var(--dc),
      background-color 150ms;
  }

  .lista.abierta .renglon {
    opacity: 1;
    transform: none;
    transition:
      transform 0.607s var(--resorte-opcion) var(--da),
      opacity 0.3s ease var(--da),
      background-color 150ms;
  }

  .lista.midiendo .renglon {
    transition: none;
  }

  .lista.abierta .opcion:active {
    transform: scale(0.95);
    transition: transform 0.15s ease;
  }

  .opcion {
    width: 100%;
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 8px 10px;
    border: 0;
    border-radius: 12px;
    background: transparent;
    color: var(--texto);
    text-align: left;
  }

  .opcion:hover {
    background: var(--chip);
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
  }

  .nombres {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .nombre {
    font-size: 13.5px;
    font-weight: 700;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .debajo {
    font-family: var(--mono);
    font-size: 11px;
    color: var(--tenue);
    white-space: nowrap;
  }

  .sola {
    margin: 2px 4px 4px;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 11px 14px;
    border: 1px solid var(--linea);
    border-radius: 12px;
    background: var(--chip);
    font-size: 12.5px;
    font-weight: 500;
    line-height: 1.45;
  }

  /* En un celular, junto al dock, solo el ícono (Cocina.svelte esconde el chip y el reloj). */
  @media (max-width: 600px) {
    .nombre-boton {
      display: none;
    }

    .boton {
      padding: 0 10px;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .caja,
    .caja * {
      transition: none !important;
    }
  }
</style>
