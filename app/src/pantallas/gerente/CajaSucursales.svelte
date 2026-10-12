<!--
  La cajita de sucursales de la barra de arriba (maqueta del Inicio del gerente,
  5SVLK2avzLCq5TaW6mrqq6): muestra el nombre del restaurante en el que está y abre la lista de
  sus sucursales. Con una sola, dice «Solamente tienes una sucursal activa.» (libreta 4, decidido
  el 9 de octubre de 2026). Las que no funcionan salen igual, con su estado en lugar del slug
  (decidido el 11 de octubre de 2026); al elegirlas se ve su pantalla de suscripción.

  La lista se cuelga de la barra de arriba (su ancestro con posición): 8 debajo de ella y pegada
  a su borde derecho, como en la maqueta. Se cierra con un clic afuera o con Escape.
-->
<script lang="ts">
  import Icono from '../../diseno/Icono.svelte';
  import { fecha } from '../../lib/formato';
  import type { Sucursal } from '../../lib/gerente';

  let {
    sucursales,
    actual,
    alElegir,
  }: { sucursales: Sucursal[]; actual: Sucursal; alElegir: (sucursal: Sucursal) => void } = $props();

  let abierta = $state(false);
  let caja: HTMLDivElement;
  const idLista = $props.id();

  // Lo que dice debajo del nombre: el slug si funciona; si no, por qué.
  function debajo(s: Sucursal) {
    if (s.estado === 'pausada') return 'Pausada';
    if (s.estado === 'vencida') return `Venció el ${fecha(s.licencia_fin)}`;
    return s.slug;
  }

  function elegir(s: Sucursal) {
    abierta = false;
    if (s.id !== actual.id) alElegir(s);
  }
</script>

<svelte:window
  onclick={(e) => {
    if (abierta && !caja.contains(e.target as Node)) abierta = false;
  }}
  onkeydown={(e) => {
    if (abierta && e.key === 'Escape') abierta = false;
  }}
/>

<div class="caja" bind:this={caja}>
  <button
    type="button"
    class="boton"
    aria-expanded={abierta}
    aria-controls={idLista}
    onclick={() => (abierta = !abierta)}
  >
    <Icono nombre="tienda" tamano={16} />
    <span>{actual.nombre}</span>
    <span class="suave"><Icono nombre="abajo" tamano={14} /></span>
  </button>

  {#if abierta}
    <div class="lista" id={idLista}>
      <span class="etiqueta titulo">TUS SUCURSALES ACTIVAS</span>
      {#if sucursales.length === 1}
        <div class="sola">
          <span class="suave"><Icono nombre="info" tamano={16} /></span>
          Solamente tienes una sucursal activa.
        </div>
      {:else}
        {#each sucursales as s (s.id)}
          <button
            type="button"
            class="sucursal"
            aria-current={s.id === actual.id ? 'true' : undefined}
            onclick={() => elegir(s)}
          >
            <span class="cuadro-icono"><Icono nombre="tienda" tamano={16} /></span>
            <span class="nombres">
              <span class="nombre">{s.nombre}</span>
              <span class="debajo">{debajo(s)}</span>
            </span>
            {#if s.id === actual.id}<Icono nombre="check-delgado" tamano={16} />{/if}
          </button>
        {/each}
      {/if}
    </div>
  {/if}
</div>

<style>
  /* La caja no tiene posición propia: la lista se acomoda contra la barra de arriba. */
  .caja {
    display: flex;
  }

  /* boton() de diseno.py, el secundario: borde fino, sin relleno; abierto, con chip. */
  .boton {
    height: 40px;
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 0 14px;
    border: 1px solid var(--linea);
    border-radius: 12px;
    background: transparent;
    color: var(--texto);
    font-size: 13px;
    font-weight: 600;
    white-space: nowrap;
    transition: opacity 150ms;
  }

  .boton:hover {
    opacity: 0.86;
  }

  .boton[aria-expanded='true'] {
    background: var(--chip);
  }

  .suave {
    display: flex;
    color: var(--suave);
  }

  /* La barra tiene borde de 1 y el absoluto se mide desde adentro de él: 8 debajo de la barra
     y a ras de su borde derecho, como en la maqueta. */
  .lista {
    position: absolute;
    top: calc(100% + 1px + 8px);
    right: -1px;
    z-index: 4;
    width: 320px;
    padding: 8px;
    display: flex;
    flex-direction: column;
    gap: 2px;
    background: var(--solido);
    border: 1px solid var(--linea);
    border-radius: 18px;
    box-shadow: 0 24px 60px var(--sombra);
  }

  .titulo {
    padding: 10px 10px 8px;
  }

  .sucursal {
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
    transition: background-color 150ms;
  }

  .sucursal:hover {
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
    overflow: hidden;
    text-overflow: ellipsis;
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
</style>
