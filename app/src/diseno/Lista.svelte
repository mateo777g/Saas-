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

  // La flecha: cada punta va de la V a la ✕ con el resorte de framer-motion (rigidez 260, freno 22, masa 1),
  // resuelto por tiempo, como la transición CSS de 0.662 s de la maqueta: rebasa 5 % y regresa. No va con el
  // `Spring` de Svelte porque ese suma su empuje en cada cuadro: en una pantalla de 120 Hz o más corre más
  // rápido y ya no rebota (medido el 7 de noviembre de 2026).
  const quieto = typeof matchMedia === 'function' ? matchMedia('(prefers-reduced-motion: reduce)') : null;
  const W0 = Math.sqrt(260);
  const Z = 22 / (2 * W0);
  const WD = W0 * Math.sqrt(1 - Z * Z);
  const DURA = 662;
  function resorte(p: number): number {
    if (p >= 1) return 1;
    const t = (p * DURA) / 1000;
    return 1 - Math.exp(-Z * W0 * t) * (Math.cos(WD * t) + ((Z * W0) / WD) * Math.sin(WD * t));
  }
  const doblez = new Tween(0, { duration: DURA, easing: resorte });
  $effect(() => {
    doblez.set(abierta ? 1 : 0, quieto?.matches ? { duration: 0 } : undefined);
  });
  const ir = (a: number, b: number) => (a + (b - a) * doblez.current).toFixed(2);
  const l1 = $derived(`M ${ir(6, 6)} ${ir(10, 6)} L ${ir(12, 18)} ${ir(16, 18)}`);
  const l2 = $derived(`M ${ir(12, 6)} ${ir(16, 18)} L ${ir(18, 18)} ${ir(10, 6)}`);

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
    --resorte-fondo: linear(0, 0.0116, 0.042, 0.0856, 0.138, 0.1957, 0.2562, 0.3173, 0.3775, 0.4357, 0.4912, 0.5435, 0.5922, 0.6372, 0.6785, 0.7161, 0.7502, 0.7808, 0.8084, 0.8329, 0.8548, 0.8742, 0.8912, 0.9063, 0.9194, 0.931, 0.941, 0.9497, 0.9573, 0.9638, 0.9694, 0.9743, 0.9784, 0.9819, 0.985, 0.9875, 0.9897, 0.9915, 0.9931, 0.9943, 0.9954, 0.9963, 0.9971, 0.9977, 0.9982, 0.9986, 0.9989, 0.9992, 1);
    --resorte-opcion: linear(0, 0.0158, 0.0565, 0.1141, 0.182, 0.2553, 0.3304, 0.4044, 0.4755, 0.5424, 0.6042, 0.6605, 0.7112, 0.7563, 0.7961, 0.8308, 0.8608, 0.8866, 0.9086, 0.9271, 0.9426, 0.9555, 0.9661, 0.9748, 0.9817, 0.9873, 0.9917, 0.9951, 0.9977, 0.9996, 1.001, 1.002, 1.0027, 1.0031, 1.0032, 1.0033, 1.0032, 1.0031, 1.0029, 1.0026, 1.0024, 1.0021, 1.0019, 1.0017, 1.0015, 1.0013, 1.0011, 1.0009, 1);
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
