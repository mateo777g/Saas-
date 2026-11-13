<!--
  La cajita de sucursales de la barra de arriba (maqueta del Inicio del gerente,
  5SVLK2avzLCq5TaW6mrqq6): muestra el nombre del restaurante en el que está y abre la lista de
  sus sucursales. Con una sola, dice «Solamente tienes una sucursal activa.» (libreta 4, decidido
  el 9 de octubre de 2026). Las que no funcionan salen igual, con su estado en lugar del slug
  (decidido el 11 de octubre de 2026); al elegirlas se ve su pantalla de suscripción.

  La lista se cuelga de la barra de arriba (su ancestro con posición): 8 debajo de ella y pegada
  a su borde derecho, como en la maqueta. Se cierra con un clic afuera o con Escape.

  Desde el 9 nov 2026 se abre como la Lista (diseno/Lista.svelte; regla «Las listas que se abren»), igual que el filtro de
  Productos: el fondo crece desde debajo de la barra (220/28), cada sucursal sale del botón, de 0.8 a 1, una tras otra
  (220/26, 45 ms entre una y otra, máximo 8; al cerrar, al revés y de 20 en 20 ms) y la flecha se dobla en ✕ (260/22).
  Lo de adentro no cambió. Respeta «reducir movimiento».
-->
<script lang="ts">
  import { tick } from 'svelte';
  import { Tween } from 'svelte/motion';
  import { DURA_FLECHA, resorteFlecha, trazosFlecha } from '../../diseno/flecha';
  import Icono from '../../diseno/Icono.svelte';
  import { pica, vidrio } from '../../diseno/vidrio';
  import { fecha } from '../../lib/formato';
  import type { Sucursal } from '../../lib/gerente';

  let {
    sucursales,
    actual,
    alElegir,
  }: { sucursales: Sucursal[]; actual: Sucursal; alElegir: (sucursal: Sucursal) => void } = $props();

  let abierta = $state(false);
  let caja: HTMLDivElement;
  let boton: HTMLButtonElement;
  let lista = $state<HTMLDivElement>();
  let alto = $state(0);
  const idLista = $props.id();

  const quieto = typeof matchMedia === 'function' ? matchMedia('(prefers-reduced-motion: reduce)') : null;
  const doblez = new Tween(0, { duration: DURA_FLECHA, easing: resorteFlecha });
  $effect(() => {
    doblez.set(abierta ? 1 : 0, quieto?.matches ? { duration: 0 } : undefined);
  });
  const trazos = $derived(trazosFlecha(doblez.current));

  // Cuánto sube cada renglón para salir del botón: de su lugar hasta arriba del botón. Se pone quieto (sin transición)
  // justo antes de abrir, para que el resorte arranque en el botón (como «Agregar grupo» de la ventana del producto).
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
    use:vidrio={'boton'}
    use:pica={1.08}
    aria-expanded={abierta}
    aria-controls={idLista}
    bind:this={boton}
    onclick={alternar}
  >
    <Icono nombre="r-tienda" tamano={18} />
    <span>{actual.nombre}</span>
    <svg class="flecha" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"
      ><path d={trazos[0]}></path><path d={trazos[1]}></path></svg
    >
  </button>

  <div class="fondo" class:abierta aria-hidden="true" style:--alto="{alto}px" use:vidrio={'hoja'}></div>
  <div class="lista" class:abierta class:midiendo id={idLista} inert={!abierta} bind:this={lista} bind:offsetHeight={alto}>
      <span class="etiqueta titulo">TUS SUCURSALES ACTIVAS</span>
      {#if sucursales.length === 1}
        <div class="sola renglon" style:--y="{desde[0] ?? 0}px" style:--da="0ms" style:--dc="0ms">
          <span class="suave"><Icono nombre="info" tamano={16} /></span>
          Solamente tienes una sucursal activa.
        </div>
      {:else}
        {#each sucursales as s, j (s.id)}
          <button
            type="button"
            class="sucursal renglon"
            style:--y="{desde[j] ?? 0}px"
            style:--da="{Math.min(j, 8) * 45}ms"
            style:--dc="{(sucursales.length - 1 - j) * 20}ms"
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
</div>

<style>
  /* La caja no tiene posición propia: la lista se acomoda contra la barra de arriba. */
  .caja {
    display: flex;
  }

  /* El botón secundario, con las medidas de la barra de arriba; abierto, con chip. */
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

  /* Mide 14 aunque la barra de arriba agrande los íconos del botón. */
  .boton .flecha {
    width: 14px !important;
    height: 14px !important;
    flex: none;
    color: var(--suave);
  }

  /* 8 debajo de la barra y a ras de sus botones. El fondo crece hasta lo que mide la lista; los renglones van en su
     propia capa. */
  .fondo,
  .lista {
    position: absolute;
    top: calc(100% + 8px);
    right: 20px;
    width: 320px;
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

  .lista.abierta .sucursal:active {
    transform: scale(0.95);
    transition: transform 0.15s ease;
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

  @media (prefers-reduced-motion: reduce) {
    .caja,
    .caja * {
      transition: none !important;
    }
  }
</style>
