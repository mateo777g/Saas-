<!--
  La parte Opciones de la ventana del producto (maqueta de Opciones y áreas GhrEVWPmevfBZtWzi4exKi):
  cada grupo que lleva es una pastilla con cuántas se eligen y su X, en el orden de la pestaña
  Opciones (el mismo en todos los productos). «Agregar grupo» abre hacia arriba la lista de los que
  le faltan, cada uno con sus opciones debajo; se cierra al elegir, con un clic afuera o con Escape.
  Sin grupos en el restaurante, solo dice dónde se crean. Se guarda con el producto.

  Desde el 9 nov 2026 se abre como la Lista (diseno/Lista.svelte; regla «Las listas que se abren»), igual que el filtro de
  Productos: el fondo crece desde el botón hacia arriba (220/28), cada grupo sale del botón, de 0.8 a 1, una tras otro
  desde el más cercano (220/26, 45 ms entre uno y otro, máximo 8; al cerrar, al revés y de 20 en 20 ms) y la flecha se
  dobla en ✕ (260/22). Las pastillas van como las cajas de texto (diseno/Campo.svelte). Respeta «reducir movimiento».
-->
<script lang="ts">
  import { tick } from 'svelte';
  import { Tween } from 'svelte/motion';
  import { DURA_FLECHA, resorteFlecha, trazosFlecha } from '../../../diseno/flecha';
  import Icono from '../../../diseno/Icono.svelte';
  import { pista } from '../../../diseno/pista';
  import { vidrio } from '../../../diseno/vidrio';
  import { dinero } from '../../../lib/formato';
  import type { Grupo } from '../../../lib/menu';
  import { reglaCorta } from '../../../lib/opciones';

  let {
    grupos,
    elegidos = $bindable([]),
    apagado = false,
  }: {
    grupos: Grupo[];
    elegidos?: number[];
    apagado?: boolean;
  } = $props();

  let abierta = $state(false);
  let caja = $state<HTMLDivElement>();
  let boton = $state<HTMLButtonElement>();
  let lista = $state<HTMLDivElement>();
  let alto = $state(0);
  const idLista = $props.id();

  const puestos = $derived(grupos.filter((g) => elegidos.includes(g.id)));
  const libres = $derived(grupos.filter((g) => !elegidos.includes(g.id)));

  const quieto = typeof matchMedia === 'function' ? matchMedia('(prefers-reduced-motion: reduce)') : null;
  const doblez = new Tween(0, { duration: DURA_FLECHA, easing: resorteFlecha });
  $effect(() => {
    doblez.set(abierta ? 1 : 0, quieto?.matches ? { duration: 0 } : undefined);
  });
  const trazos = $derived(trazosFlecha(doblez.current));

  // Cuánto baja cada grupo para salir del botón: de su lugar hasta arriba del botón. Se mide con la lista cerrada (sus
  // opciones están, invisibles) justo antes de abrir, y otra vez si cambian los grupos o las pastillas. Con la ventana
  // todavía sin abrir no hay nada que medir (todo da 0).
  let desde = $state<number[]>([]);
  // Mientras se pone de dónde sale cada grupo, sin transición: si no, ese cambio también se animaba desde 0 y al abrir
  // el resorte arrancaba casi en su lugar (medido el 9 nov 2026).
  let midiendo = $state(false);
  function medir() {
    if (!lista || !boton || !lista.offsetParent) return;
    const arriba = boton.getBoundingClientRect().top - lista.getBoundingClientRect().top;
    desde = [...lista.querySelectorAll<HTMLElement>('.opcion')].map((f) => Math.max(0, arriba - f.offsetTop));
  }

  // Primero pone, quieto, de dónde sale cada grupo y luego abre, para que el resorte arranque en el botón.
  async function alternar() {
    if (abierta) {
      abierta = false;
      return;
    }
    midiendo = true;
    medir();
    await tick();
    void lista?.offsetHeight;
    midiendo = false;
    abierta = true;
  }

  // «Verde · Roja · Habanero (agotada)», con el precio extra cuando suma; las agotadas, en amarillo.
  function previa(g: Grupo) {
    return g.opciones.map((o) => ({
      id: o.id,
      agotada: !o.visible,
      texto: o.visible ? o.nombre + (o.precio_extra > 0 ? ` +${dinero(o.precio_extra)}` : '') : `${o.nombre} (agotada)`,
    }));
  }

  function poner(id: number) {
    elegidos = [...elegidos, id];
    abierta = false;
    boton?.focus();
  }

  function quitar(id: number) {
    elegidos = elegidos.filter((x) => x !== id);
  }
</script>

<svelte:window
  onclick={(e) => {
    if (abierta && caja && !caja.contains(e.target as Node)) abierta = false;
  }}
  onkeydown={(e) => {
    // Escape cierra la lista, no la ventana del producto.
    if (abierta && e.key === 'Escape') {
      e.preventDefault();
      e.stopPropagation();
      abierta = false;
      boton?.focus();
    }
  }}
/>

<div class="campo" bind:this={caja}>
  <span class="etiqueta">OPCIONES</span>
  {#if !grupos.length}
    <p class="pista">Todavía no tienes grupos de opciones, como Salsa o Tamaño. Los creas en la pestaña Opciones.</p>
  {:else}
    <div class="pastillas">
      {#each puestos as g (g.id)}
        <span class="pastilla">
          {g.nombre}<span class="regla">{reglaCorta(g.minimo, g.maximo)}</span>
          <button
            type="button"
            class="quitar"
            aria-label="Quitar {g.nombre}"
            use:pista={'Quitar'}
            disabled={apagado}
            onclick={() => quitar(g.id)}
          >
            <Icono nombre="cerrar" tamano={14} />
          </button>
        </span>
      {/each}
      {#if libres.length}
        <button
          type="button"
          class="agregar"
          bind:this={boton}
          aria-expanded={abierta}
          aria-controls={idLista}
          disabled={apagado}
          onclick={alternar}
        >
          <Icono nombre="mas" tamano={14} />
          Agregar grupo
          <svg class="flecha" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"
            ><path d={trazos[0]}></path><path d={trazos[1]}></path></svg
          >
        </button>
      {/if}
    </div>
    <p class="pista">
      {puestos.length
        ? 'Se eligen en este orden al agregarlo. El orden se cambia en la pestaña Opciones.'
        : 'Sin opciones: se agrega con un solo toque.'}
    </p>

    {#if libres.length}
      <!-- En Cristal, una hoja de vidrio (su receta en cristal.css). -->
      <div class="fondo" class:abierta aria-hidden="true" style:--alto="{Math.min(alto, 300)}px" use:vidrio={'hoja'}></div>
      <div class="lista" class:abierta class:midiendo id={idLista} inert={!abierta} bind:this={lista} bind:offsetHeight={alto}>
        <span class="etiqueta titulo">TUS GRUPOS</span>
        {#each libres as g, j (g.id)}
          {@const k = libres.length - 1 - j}
          <button
            type="button"
            class="opcion"
            style:--y="{desde[j] ?? 0}px"
            style:--da="{Math.min(k, 8) * 45}ms"
            style:--dc="{j * 20}ms"
            onclick={() => poner(g.id)}
          >
            <span class="textos">
              <span class="nombre">{g.nombre}</span>
              <span class="sub"
                >{#each previa(g) as o, j (o.id)}{#if j > 0}{' · '}{/if}{#if o.agotada}<span class="agotada-texto">{o.texto}</span
                    >{:else}{o.texto}{/if}{/each}</span
              >
            </span>
            <span class="cuenta">{reglaCorta(g.minimo, g.maximo)}</span>
          </button>
        {/each}
      </div>
    {/if}
  {/if}
</div>

<style>
  /* La lista sale hacia arriba, pegada al campo, para no salirse de la ventana. */
  .campo {
    position: relative;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .pastillas {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 8px;
  }

  .pastilla {
    height: 34px;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 0 4px 0 12px;
    border-radius: 10px;
    background: var(--campo-fondo);
    box-shadow: var(--campo-sombra);
    font-size: 12.5px;
    font-weight: 700;
    white-space: nowrap;
  }

  .regla {
    font-weight: 500;
    color: var(--tenue);
  }

  .quitar {
    width: 26px;
    height: 26px;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0;
    border: 0;
    border-radius: 7px;
    background: transparent;
    color: var(--suave);
  }

  .quitar:hover:not(:disabled) {
    background: var(--chip);
    color: var(--texto);
  }

  /* El botón chico de la maqueta. */
  .agregar {
    height: 34px;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 0 12px;
    border: 1px solid var(--linea);
    border-radius: 12px;
    background: transparent;
    color: var(--texto);
    font-size: 12.5px;
    font-weight: 600;
    white-space: nowrap;
    transition:
      opacity 150ms,
      transform 0.2s ease;
  }

  .agregar:hover:not(:disabled) {
    opacity: 0.86;
  }

  .agregar:not(:disabled):active {
    transform: scale(0.95);
  }

  .agregar[aria-expanded='true'] {
    background: var(--chip);
  }

  .flecha {
    width: 14px;
    height: 14px;
    flex: none;
    color: var(--suave);
  }

  .agregar:disabled,
  .quitar:disabled {
    opacity: 0.4;
  }

  .pista {
    margin: 0;
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--tenue);
  }

  /* El fondo crece desde el botón hacia arriba hasta lo que mide la lista; los grupos van en su propia capa. */
  .fondo,
  .lista {
    position: absolute;
    bottom: calc(100% + 8px);
    left: 0;
    width: 340px;
  }

  .fondo {
    z-index: 50; /* encima del botón de las Listas de la ventana (42) */
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
    z-index: 51;
    max-height: 300px;
    overflow-y: hidden;
    padding: 8px;
    display: flex;
    flex-direction: column;
    gap: 2px;
    pointer-events: none;
  }

  .lista.abierta {
    overflow-y: auto;
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

  .opcion {
    width: 100%;
    flex: none;
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 6px 10px;
    border: 0;
    border-radius: 12px;
    background: transparent;
    color: var(--texto);
    text-align: left;
    opacity: 0;
    transform: translateY(var(--y)) scale(0.8);
    transition:
      transform 0.607s var(--resorte-opcion) var(--dc),
      opacity 0.3s ease var(--dc),
      background-color 150ms;
  }

  .lista.abierta .opcion {
    opacity: 1;
    transform: none;
    transition:
      transform 0.607s var(--resorte-opcion) var(--da),
      opacity 0.3s ease var(--da),
      background-color 150ms;
  }

  .lista.midiendo .opcion {
    transition: none;
  }

  .opcion:hover {
    background: var(--chip);
  }

  .lista.abierta .opcion:active {
    transform: scale(0.95);
    transition: transform 0.15s ease;
  }

  .textos {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .nombre {
    font-size: 13.5px;
    font-weight: 700;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .sub {
    font-size: 11.5px;
    font-weight: 500;
    color: var(--suave);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .agotada-texto {
    color: var(--amarillo-texto);
    font-weight: 600;
  }

  .cuenta {
    font-family: var(--mono);
    font-size: 11px;
    color: var(--tenue);
  }

  @media (prefers-reduced-motion: reduce) {
    .campo,
    .campo * {
      transition: none !important;
    }
  }
</style>
