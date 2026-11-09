<!--
  La lista para elegir del panel del gerente, en lugar de la del navegador: la «Animated Select» de Great
  UI (React + framer-motion), hecha en Svelte sin paquetes (maqueta de Mi menú U9YqpsSb2PeB5pFXTPvh1C,
  versiones 5 y 6). Con sus mismos resortes, pasados a CSS linear(): el fondo crece (220/28, 0.52 s);
  cada opción sale de debajo del campo, de 0.8 a 1, hasta su lugar (220/26, 0.61 s, 45 ms entre una y
  otra, máximo 8; al cerrar, al revés, 20 ms). La flecha se dobla en ✕ con un `Tween` de Svelte que sigue
  el resorte 260/22 de framer-motion (0.662 s), porque Safari no anima `d` de CSS. Las de más de 6 opciones se deslizan por dentro
  y abren en la elegida. La elegida lleva palomita; una categoría, su ícono. Con el teclado: Enter o las
  flechas la abren, las flechas recorren, Enter elige y Escape cierra. Respeta «reducir movimiento».
  Mientras no hay nada elegido, enseña `placeholder` en gris. Fragmentless sigue con CampoLista.
-->
<script lang="ts" generics="V extends string | number">
  import { tick } from 'svelte';
  import { Tween } from 'svelte/motion';
  import { DURA_FLECHA, resorteFlecha, trazosFlecha } from './flecha';
  import IconoCategoria from './IconoCategoria.svelte';

  let {
    valor = $bindable(),
    opciones,
    id,
    placeholder = '',
    apagado = false,
    'aria-label': nombre,
    etiqueta,
    pista,
  }: {
    valor?: V | '' | null;
    opciones: { valor: V; texto: string; icono?: string | null }[];
    id?: string;
    placeholder?: string;
    apagado?: boolean;
    'aria-label'?: string;
    /** Con etiqueta va como un campo de CampoLista: la etiqueta encima y la pista debajo. */
    etiqueta?: string;
    pista?: string;
  } = $props();

  let raiz = $state<HTMLDivElement>();
  let caja = $state<HTMLDivElement>();
  let boton = $state<HTMLButtonElement>();
  let abierta = $state(false);

  const n = $derived(opciones.length);
  const elegida = $derived(opciones.find((o) => o.valor === valor));

  // La flecha se dobla en ✕ con el resorte 260/22 (diseno/flecha.ts).
  const quieto = typeof matchMedia === 'function' ? matchMedia('(prefers-reduced-motion: reduce)') : null;
  const doblez = new Tween(0, { duration: DURA_FLECHA, easing: resorteFlecha });
  $effect(() => {
    doblez.set(abierta ? 1 : 0, quieto?.matches ? { duration: 0 } : undefined);
  });
  const trazos = $derived(trazosFlecha(doblez.current));
  const l1 = $derived(trazos[0]);
  const l2 = $derived(trazos[1]);

  function opcionesDom(): HTMLButtonElement[] {
    return caja ? [...caja.querySelectorAll<HTMLButtonElement>('.lista-opcion')] : [];
  }

  async function abrir(enfocar: boolean) {
    if (apagado) return;
    abierta = true;
    await tick();
    const lista = opcionesDom();
    const i = Math.max(0, opciones.findIndex((o) => o.valor === valor));
    const la = lista[i];
    if (caja && la) caja.scrollTop = Math.max(0, la.offsetTop - caja.clientHeight / 2 + la.offsetHeight / 2);
    if (enfocar) la?.focus({ preventScroll: true });
  }

  function cerrar(volver = false) {
    abierta = false;
    if (volver) boton?.focus();
  }

  function elegir(v: V) {
    valor = v;
    cerrar(true);
  }

  function teclaBoton(e: KeyboardEvent) {
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      abrir(true);
    } else if (e.key === 'Escape' && abierta) {
      e.preventDefault();
      e.stopPropagation();
      cerrar();
    }
  }

  function teclaOpcion(e: KeyboardEvent) {
    const lista = opcionesDom();
    const i = lista.indexOf(e.currentTarget as HTMLButtonElement);
    let j = -1;
    if (e.key === 'ArrowDown') j = Math.min(lista.length - 1, i + 1);
    else if (e.key === 'ArrowUp') j = Math.max(0, i - 1);
    else if (e.key === 'Home') j = 0;
    else if (e.key === 'End') j = lista.length - 1;
    else if (e.key === 'Escape') {
      // Escape cierra la lista, no la ventana en la que está.
      e.preventDefault();
      e.stopPropagation();
      cerrar(true);
      return;
    } else if (e.key === 'Tab') {
      cerrar();
      return;
    }
    if (j >= 0) {
      e.preventDefault();
      lista[j]?.focus();
    }
  }

  // Se cierra al picar fuera o si el foco se va a otra parte.
  $effect(() => {
    if (!abierta) return;
    const fuera = (e: PointerEvent) => {
      if (raiz && !raiz.contains(e.target as Node)) cerrar();
    };
    document.addEventListener('pointerdown', fuera, true);
    return () => document.removeEventListener('pointerdown', fuera, true);
  });
  function sinFoco(e: FocusEvent) {
    const destino = e.relatedTarget as Node | null;
    if (abierta && destino && raiz && !raiz.contains(destino)) cerrar();
  }
</script>

{#if etiqueta}
  <div class="campo">
    <label class="etiqueta" for={id}>{etiqueta}</label>
    {@render control()}
    {#if pista}<p class="pista">{pista}</p>{/if}
  </div>
{:else}
  {@render control()}
{/if}

{#snippet control()}
<div
  class="lista"
  class:abierta
  class:larga={n > 6}
  style:--alto="{Math.min(44 * n + 4, 272)}px"
  bind:this={raiz}
  onfocusout={sinFoco}
>
  <button
    type="button"
    class="lista-boton"
    {id}
    aria-haspopup="listbox"
    aria-expanded={abierta}
    aria-label={nombre}
    disabled={apagado}
    bind:this={boton}
    onclick={() => (abierta ? cerrar() : abrir(false))}
    onkeydown={teclaBoton}
  >
    <span class="lista-valor" class:vacia={!elegida}>{elegida ? elegida.texto : placeholder}</span>
    <svg class="lista-flecha" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"
      ><path d={l1}></path><path d={l2}></path></svg
    >
  </button>
  <div class="lista-fondo"></div>
  <div class="lista-opciones" role="listbox" aria-label={nombre} bind:this={caja} inert={!abierta}>
    {#each opciones as o, j (o.valor)}
      {@const si = o.valor === valor}
      <button
        type="button"
        role="option"
        class="lista-opcion"
        class:elegida={si}
        aria-selected={si}
        tabindex="-1"
        style:--i={j}
        style:--y="{47 + Math.min(j, 8) * 44}px"
        style:--dc="{(n - 1 - j) * 20}ms"
        onclick={() => elegir(o.valor)}
        onkeydown={teclaOpcion}
      >
        {#if o.icono}<span class="lista-icono"><IconoCategoria id={o.icono} tamano={16} /></span>{/if}
        <span class="lista-texto">{o.texto}</span>
        {#if si}
          <svg class="lista-marca" viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"
            ><path d="M5 12.5l4.5 4.5L19 7.5"></path></svg
          >
        {/if}
      </button>
    {/each}
  </div>
</div>
{/snippet}

<style>
  .campo {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .pista {
    margin: 0;
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--tenue);
  }

  .lista {
    position: relative;
    min-width: 0;
  }

  .lista-boton {
    position: relative;
    z-index: 42;
    width: 100%;
    height: 44px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    padding: 0 12px 0 14px;
    box-sizing: border-box;
    border: 1px solid var(--linea);
    border-radius: 12px;
    background: var(--solido);
    color: var(--texto);
    font: 500 13.5px var(--jakarta);
    text-align: left;
    cursor: pointer;
    transition:
      border-radius 0.2s ease,
      border-color 0.2s ease,
      transform 0.2s ease,
      background 0.2s ease;
  }

  .lista-boton:not(:disabled):hover {
    border-color: var(--linea-fuerte);
  }

  .lista-boton:not(:disabled):active {
    transform: scale(0.95);
  }

  /* Con el mismo peso que el hover y después de él: con el teclado gana la orilla oscura, como en la maqueta. */
  .lista-boton:not(:disabled):focus-visible {
    outline: none;
    border-color: var(--suave);
  }

  .lista-boton:disabled {
    opacity: 0.6;
    cursor: default;
  }

  .lista-valor {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .lista-valor.vacia {
    color: var(--tenue);
  }

  .lista-flecha {
    width: 16px;
    height: 16px;
    flex: none;
    color: var(--suave);
  }

  .lista.abierta .lista-boton {
    border-radius: 12px 12px 0 0;
    border-color: var(--linea-fuerte);
  }

  .lista-fondo {
    position: absolute;
    left: 0;
    right: 0;
    top: 43px;
    z-index: 40;
    height: 0;
    min-width: 170px;
    box-sizing: border-box;
    border: 1px solid var(--linea-fuerte);
    border-top: 0;
    border-radius: 0 0 12px 12px;
    background: var(--solido);
    opacity: 0;
    pointer-events: none;
    transition:
      height 0.518s var(--resorte-fondo),
      opacity 0.25s ease;
  }

  .lista.abierta .lista-fondo {
    height: var(--alto);
    opacity: 1;
    box-shadow: 0 16px 32px var(--sombra-menu, rgba(0, 0, 0, 0.14));
  }

  .lista-opciones {
    position: absolute;
    left: 0;
    right: 0;
    top: 43px;
    z-index: 41;
    min-width: 170px;
    box-sizing: border-box;
    padding: 4px;
    display: flex;
    flex-direction: column;
    gap: 4px;
    pointer-events: none;
  }

  .lista.larga .lista-opciones {
    max-height: 272px;
    overflow-y: auto;
  }

  /* Cerrada no lleva barra de scroll: sus opciones se esconden, pero la caja no, y con las barras de Windows la
     barra se quedaba pintada debajo del botón (el developer la vio en Ajustes, 7 nov 2026). */
  .lista.larga:not(.abierta) .lista-opciones {
    overflow-y: hidden;
  }

  .lista.abierta .lista-opciones {
    pointer-events: auto;
  }

  .lista-opcion {
    height: 40px;
    flex: none;
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 0 12px;
    border: 0;
    border-radius: 12px;
    background: transparent;
    color: var(--texto);
    font: 600 13px var(--jakarta);
    letter-spacing: 0.01em;
    text-align: left;
    cursor: pointer;
    opacity: 0;
    transform: translateY(calc(-1 * var(--y))) scale(0.8);
    transition:
      transform 0.607s var(--resorte-opcion) var(--dc),
      opacity 0.3s ease var(--dc),
      background 0.15s ease;
  }

  .lista.abierta .lista-opcion {
    opacity: 1;
    transform: none;
    transition:
      transform 0.607s var(--resorte-opcion) calc(min(var(--i), 8) * 45ms),
      opacity 0.3s ease calc(min(var(--i), 8) * 45ms),
      background 0.15s ease;
  }

  .lista-opcion:hover,
  .lista-opcion:focus-visible {
    background: var(--chip);
    outline: none;
  }

  .lista.abierta .lista-opcion:active {
    transform: scale(0.95);
    transition: transform 0.15s ease;
  }

  .lista-texto {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .lista-icono {
    width: 16px;
    height: 16px;
    flex: none;
    display: flex;
    color: var(--suave);
  }

  .lista-marca {
    margin-left: auto;
    flex: none;
    color: var(--texto);
  }

  @media (prefers-reduced-motion: reduce) {
    .lista,
    .lista * {
      transition: none !important;
    }
  }
</style>
