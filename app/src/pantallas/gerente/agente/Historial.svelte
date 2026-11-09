<!--
  La barra de chats del Agente IA, a la derecha de la vista (maqueta CWBFnVy5oDDkhgVD8x7aj9,
  planes/trabajo/rediseno/barra-ia.md): las conversaciones de esta sucursal guardadas en este navegador,
  la más nueva arriba y las fijadas en su grupo. Cada fila es solo su título; la abierta va en gris.

  Los 3 puntitos salen al pasar el mouse, al llegar con el teclado o siempre si no hay mouse (tableta).
  Su menú trae la fecha, Fijar, Cambiar nombre y Eliminar; se cierra con Esc, con un clic afuera o al hacer
  scroll. La barra corta lo que se sale (para abrirse de 0 a 288), así que lo que flota va fijo a la
  ventana: este menú y la lista de sucursales. Desde el 9 nov 2026 el menú se abre como la Lista (regla «Las listas que se
  abren»): el fondo crece desde los puntitos (220/28) y cada renglón sale de ellos, de 0.8 a 1, uno tras otro desde el
  más cercano (220/26, 45 ms; al cerrar, al revés y de 20 en 20 ms, y luego se quita). Al hacer scroll se va de una vez.

  La que todavía no se guarda (se guarda con su primera respuesta) ya sale en la lista, sin fecha ni
  puntitos: todavía no hay nada que fijar ni eliminar.
-->
<script lang="ts">
  import { tick } from 'svelte';
  import Confirmar from '../../../diseno/Confirmar.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import { pista } from '../../../diseno/pista';
  import type { Conversacion } from '../../../lib/agente';
  import { diaConNombre } from '../../../lib/formato';
  import type { Sucursal } from '../../../lib/gerente';
  import CajaSucursales from '../CajaSucursales.svelte';

  let {
    abierta,
    conversaciones,
    actual,
    sucursal,
    sucursales,
    alElegir,
    alAbrir,
    alNueva,
    alCerrar,
    alFijar,
    alRenombrar,
    alEliminar,
  }: {
    abierta: boolean;
    conversaciones: Conversacion[];
    actual: string | null;
    sucursal: Sucursal;
    sucursales: Sucursal[];
    alElegir: (sucursal: Sucursal) => void;
    alAbrir: (c: Conversacion) => void;
    alNueva: () => void;
    alCerrar: () => void;
    alFijar: (id: string) => void;
    alRenombrar: (id: string, titulo: string) => void;
    alEliminar: (id: string) => void;
  } = $props();

  let lista = $state<HTMLDivElement | null>(null);
  let cajaMenu = $state<HTMLDivElement | null>(null);
  // La conversación del menú abierto y dónde va.
  let menuDe = $state<Conversacion | null>(null);
  let lugarMenu = $state({ left: 0, top: 0 });
  // El movimiento del menú: visible, si salió hacia arriba, de dónde sale cada renglón y cuánto mide.
  let menuVisible = $state(false);
  let menuArriba = $state(false);
  let midiendo = $state(false);
  let desde = $state<number[]>([]);
  let altoMenu = $state(0);
  const RENGLONES_MENU = 4;

  // Lo regresa a los puntitos y luego lo quita (lo que tarda en irse el último renglón).
  function cerrarMenu() {
    if (!menuDe) return;
    menuVisible = false;
    const de = menuDe;
    setTimeout(() => {
      if (!menuVisible && menuDe === de) menuDe = null;
    }, 380);
  }
  let editando = $state<string | null>(null);
  let nombre = $state('');
  let porEliminar = $state<string | null>(null);

  const fijadas = $derived(conversaciones.filter((c) => c.fijada));
  const resto = $derived(conversaciones.filter((c) => !c.fijada));

  // «Hoy · 18:02», «Jueves 15 · 21:10»; de otro mes, con el mes.
  function cuando(c: Conversacion) {
    if (c.fecha === sucursal.hoy) return `Hoy · ${c.hora}`;
    const dia = diaConNombre(c.fecha);
    return `${c.fecha.slice(0, 7) === sucursal.hoy.slice(0, 7) ? dia.replace(/ de .*$/, '') : dia} · ${c.hora}`;
  }

  // Alineado a la derecha de los puntitos; si no cabe abajo, se abre arriba.
  async function abrirMenu(c: Conversacion, boton: HTMLElement) {
    if (menuDe?.id === c.id && menuVisible) {
      cerrarMenu();
      return;
    }
    menuVisible = false;
    midiendo = true;
    menuDe = c;
    await tick();
    if (!cajaMenu) return;
    const r = boton.getBoundingClientRect();
    const abajo = r.bottom + 4;
    menuArriba = abajo + cajaMenu.offsetHeight > window.innerHeight - 8;
    lugarMenu = { left: r.right - cajaMenu.offsetWidth, top: menuArriba ? r.top - cajaMenu.offsetHeight - 4 : abajo };
    desde = [...cajaMenu.querySelectorAll<HTMLElement>('.renglon')].map((f) => r.top - (lugarMenu.top + f.offsetTop));
    await tick();
    void cajaMenu.offsetHeight;
    midiendo = false;
    menuVisible = true;
    cajaMenu.querySelector('button')?.focus({ preventScroll: true });
  }

  async function enfocarFila(id: string, cual: 'conv-abrir' | 'conv-mas') {
    await tick();
    lista?.querySelector<HTMLElement>(`[data-conv="${id}"] .${cual}`)?.focus({ preventScroll: true });
  }

  function teclaDelMenu(e: KeyboardEvent) {
    if ((e.key !== 'ArrowDown' && e.key !== 'ArrowUp') || !cajaMenu) return;
    e.preventDefault();
    const botones = [...cajaMenu.querySelectorAll('button')];
    const i = botones.indexOf(document.activeElement as HTMLButtonElement);
    botones[(i + (e.key === 'ArrowDown' ? 1 : botones.length - 1)) % botones.length].focus();
  }

  function fijar(c: Conversacion) {
    cerrarMenu();
    alFijar(c.id);
    enfocarFila(c.id, 'conv-mas');
  }

  function cambiarNombre(c: Conversacion) {
    cerrarMenu();
    nombre = c.titulo;
    editando = c.id;
  }

  function enfocarCampo(campo: HTMLInputElement) {
    campo.focus();
    campo.select();
  }

  // Vacío deja el nombre de antes. La pregunta de la plática no cambia.
  function terminarNombre(guardar: boolean, conTeclado = false) {
    if (!editando) return;
    const id = editando;
    const titulo = nombre.trim();
    editando = null;
    if (guardar && titulo) alRenombrar(id, titulo);
    if (conTeclado) enfocarFila(id, 'conv-abrir');
  }

  function teclaDelNombre(e: KeyboardEvent) {
    if (e.key === 'Enter') {
      e.preventDefault();
      terminarNombre(true, true);
    }
    if (e.key === 'Escape') {
      e.stopPropagation();
      terminarNombre(false, true);
    }
  }
</script>

<svelte:window
  onclick={(e) => {
    const donde = e.target as Element;
    if (menuDe && !donde.closest('.menu-chat, .conv-mas')) cerrarMenu();
  }}
  onkeydown={(e) => {
    if (e.key !== 'Escape' || !menuDe) return;
    enfocarFila(menuDe.id, 'conv-mas');
    cerrarMenu();
  }}
  onresize={() => (menuDe = null)}
/>

{#snippet fila(c: Conversacion)}
  <div class="conv" class:menu-abierto={menuDe?.id === c.id} data-conv={c.id} aria-current={c.id === actual ? 'true' : undefined}>
    {#if c.id === editando}
      <input
        class="campo"
        type="text"
        aria-label="Nombre de la conversación"
        bind:value={nombre}
        use:enfocarCampo
        onkeydown={teclaDelNombre}
        onblur={() => terminarNombre(true)}
      />
    {:else}
      <button type="button" class="conv-abrir" onclick={() => alAbrir(c)}><span class="nombre">{c.titulo}</span></button>
      {#if c.fecha}
        <button
          type="button"
          class="conv-mas"
          aria-label="Más opciones"
          use:pista={'Más opciones'}
          aria-haspopup="menu"
          aria-expanded={menuDe?.id === c.id}
          onclick={(e) => abrirMenu(c, e.currentTarget)}
        >
          <Icono nombre="puntos" tamano={18} />
        </button>
      {/if}
    {/if}
  </div>
{/snippet}

<aside class="barra-ia" aria-label="Conversaciones" inert={!abierta}>
  <div class="dentro">
    <div class="cabeza">
      <CajaSucursales {sucursales} actual={sucursal} {alElegir} />
      <button type="button" class="cuadro" aria-label="Cerrar las conversaciones" use:pista={'Cerrar las conversaciones'} onclick={alCerrar}>
        <Icono nombre="r-reloj" tamano={18} />
      </button>
    </div>
    <div class="arriba">
      <button type="button" class="nueva" onclick={alNueva}>
        <Icono nombre="r-mas" tamano={18} />
        Nueva conversación
      </button>
    </div>
    <div class="chats" bind:this={lista} onscroll={() => (menuDe = null)}>
      {#if fijadas.length}
        <span class="etiqueta titulo">FIJADAS</span>
        {#each fijadas as c (c.id)}{@render fila(c)}{/each}
      {/if}
      {#if resto.length || !fijadas.length}
        <span class="etiqueta titulo">CONVERSACIONES DE ESTA SUCURSAL</span>
      {/if}
      {#if !conversaciones.length}
        <p class="vacio">Todavía no hay conversaciones en esta sucursal.</p>
      {/if}
      {#each resto as c (c.id)}{@render fila(c)}{/each}
      <div class="pie">Se guardan en este navegador, solo en este aparato. Al cerrar sesión se borran.</div>
    </div>
  </div>

  {#if menuDe}
    {@const c = menuDe}
    <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
    {@const salida = (j: number) => {
      const k = menuArriba ? RENGLONES_MENU - 1 - j : j;
      return { y: `${desde[j] ?? 0}px`, da: `${k * 45}ms`, dc: `${(RENGLONES_MENU - 1 - k) * 20}ms` };
    }}
    <div
      class="menu-chat"
      class:visible={menuVisible}
      class:arriba={menuArriba}
      class:midiendo
      role="menu"
      tabindex="-1"
      aria-label="Opciones de la conversación"
      bind:this={cajaMenu}
      bind:offsetHeight={altoMenu}
      style:left="{lugarMenu.left}px"
      style:top="{lugarMenu.top}px"
      style:--alto="{altoMenu}px"
      inert={!menuVisible && !midiendo}
      onkeydown={teclaDelMenu}
    >
      <div class="menu-fondo" aria-hidden="true"></div>
      <div class="fecha renglon" style:--y={salida(0).y} style:--da={salida(0).da} style:--dc={salida(0).dc}>{cuando(c)}</div>
      <hr />
      <button type="button" role="menuitem" class="renglon" style:--y={salida(1).y} style:--da={salida(1).da} style:--dc={salida(1).dc} onclick={() => fijar(c)}
        >{c.fijada ? 'Desfijar' : 'Fijar'}</button
      >
      <button type="button" role="menuitem" class="renglon" style:--y={salida(2).y} style:--da={salida(2).da} style:--dc={salida(2).dc} onclick={() => cambiarNombre(c)}
        >Cambiar nombre</button
      >
      <hr />
      <button
        type="button"
        role="menuitem"
        class="rojo renglon"
        style:--y={salida(3).y}
        style:--da={salida(3).da}
        style:--dc={salida(3).dc}
        onclick={() => {
          porEliminar = c.id;
          cerrarMenu();
        }}>Eliminar</button
      >
    </div>
  {/if}
</aside>

{#if porEliminar}
  {@const id = porEliminar}
  <Confirmar
    peligro
    icono="eliminar"
    titulo="¿Eliminar esta conversación?"
    texto="Se borra de este navegador y no se puede deshacer."
    boton={{ etiqueta: 'Eliminar', icono: 'eliminar' }}
    textoCargando="Eliminando…"
    confirmar={async () => {
      alEliminar(id);
      return { listo: 'Eliminada' };
    }}
    alCerrar={() => (porEliminar = null)}
  />
{/if}

<style>
  .barra-ia {
    min-width: 0;
    overflow: hidden;
    font-weight: 400;
  }

  .dentro {
    width: 288px;
    height: 100%;
    display: flex;
    flex-direction: column;
    background: var(--solido);
    border-left: 1px solid var(--linea);
  }

  /* La sucursal se pasa aquí, junto al reloj; si su nombre no cabe, se corta. */
  .cabeza {
    height: 56px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: flex-end;
    gap: 6px;
    padding: 0 12px;
    border-bottom: 1px solid var(--linea);
  }

  .cabeza :global(.caja),
  .cabeza :global(.caja > .boton) {
    min-width: 0;
  }

  .cabeza :global(.caja > .boton > svg),
  .cabeza :global(.caja > .boton > .flecha) {
    flex: none;
  }

  .cabeza :global(.caja > .boton > span:not(.flecha)) {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  /* Fija a la ventana para que la barra no la corte: 8 debajo de la cabeza y a ras del reloj. */
  .cabeza :global(.caja > .lista) {
    position: fixed;
    top: 64px;
    right: 12px;
  }

  .cuadro {
    width: 32px;
    height: 32px;
    flex: none;
    display: grid;
    place-items: center;
    padding: 0;
    border: 0;
    border-radius: 8px;
    background: transparent;
    color: var(--suave);
  }

  .cuadro:hover {
    background: var(--chip);
    color: var(--texto);
  }

  /* «Nueva conversación», como los renglones de la barra lateral */
  .arriba {
    flex: none;
    padding: 12px 10px 0;
  }

  .nueva {
    width: 100%;
    height: 38px;
    display: flex;
    align-items: center;
    gap: 11px;
    padding: 0 10px;
    border: 0;
    border-radius: 9px;
    background: transparent;
    font-size: 14px;
    font-weight: 500;
    text-align: left;
  }

  .nueva:hover {
    background: var(--chip);
  }

  .chats {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    padding: 8px 10px 12px;
    display: flex;
    flex-direction: column;
    gap: 2px;
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
    position: relative;
    flex: none;
    display: flex;
    min-height: 38px;
    border-radius: 9px;
    transition: background-color 150ms;
  }

  .conv:hover,
  .conv.menu-abierto {
    background: var(--chip);
  }

  .conv[aria-current='true'] {
    background: var(--fila-abierta);
  }

  .conv-abrir {
    flex: 1;
    min-width: 0;
    display: flex;
    align-items: center;
    padding: 0 10px;
    border: 0;
    border-radius: 9px;
    background: transparent;
    text-align: left;
  }

  .conv:hover .conv-abrir,
  .conv.menu-abierto .conv-abrir,
  .conv:has(:focus-visible) .conv-abrir {
    padding-right: 38px;
  }

  .nombre {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 13.5px;
    font-weight: 700;
  }

  .conv-mas {
    position: absolute;
    right: 6px;
    top: 6px;
    width: 26px;
    height: 26px;
    display: grid;
    place-items: center;
    padding: 0;
    border: 0;
    border-radius: 7px;
    background: transparent;
    color: var(--suave);
    opacity: 0;
    pointer-events: none;
  }

  .conv:hover .conv-mas,
  .conv.menu-abierto .conv-mas,
  .conv:has(:focus-visible) .conv-mas {
    opacity: 1;
    pointer-events: auto;
  }

  .conv-mas:hover,
  .conv-mas[aria-expanded='true'] {
    background: var(--fila-abierta);
    color: var(--texto);
  }

  /* Sin mouse (tableta), siempre a la vista. */
  @media (hover: none) {
    .conv-mas {
      opacity: 1;
      pointer-events: auto;
    }

    .conv-abrir {
      padding-right: 38px;
    }
  }

  .campo {
    flex: 1;
    min-width: 0;
    height: 38px;
    padding: 0 9px;
    border: 1px solid var(--linea-fuerte);
    border-radius: 9px;
    background: var(--solido);
    color: var(--texto);
    font-size: 13.5px;
    font-weight: 700;
  }

  .pie {
    margin: 6px 4px 2px;
    padding: 10px 6px 4px;
    border-top: 1px solid var(--linea);
    font-size: 12px;
    line-height: 1.45;
    color: var(--tenue);
  }

  /* Como el menú del «+» del agente, lo que flota en el panel nuevo. */
  .menu-chat {
    position: fixed;
    z-index: 30;
    min-width: 200px;
    padding: 6px;
    outline: none;
    pointer-events: none;
  }

  .menu-chat.visible {
    pointer-events: auto;
  }

  /* El fondo crece desde los puntitos hasta lo que mide el menú (hacia arriba si salió arriba). */
  .menu-fondo {
    position: absolute;
    left: 0;
    right: 0;
    top: 0;
    z-index: -1;
    height: 0;
    background: var(--solido);
    border: 1px solid var(--linea-fuerte);
    border-radius: 12px;
    opacity: 0;
    transition:
      height 0.518s var(--resorte-fondo),
      opacity 0.25s ease,
      box-shadow 0.25s ease;
  }

  .menu-chat.arriba .menu-fondo {
    top: auto;
    bottom: 0;
  }

  .menu-chat.visible .menu-fondo {
    height: var(--alto);
    opacity: 1;
    box-shadow: 0 14px 34px var(--sombra-menu);
  }

  .menu-chat {
    isolation: isolate;
  }

  .renglon {
    position: relative;
    opacity: 0;
    transform: translateY(var(--y)) scale(0.8);
    transition:
      transform 0.607s var(--resorte-opcion) var(--dc),
      opacity 0.3s ease var(--dc),
      background-color 150ms;
  }

  .menu-chat.visible .renglon {
    opacity: 1;
    transform: none;
    transition:
      transform 0.607s var(--resorte-opcion) var(--da),
      opacity 0.3s ease var(--da),
      background-color 150ms;
  }

  .menu-chat hr {
    opacity: 0;
    transition: opacity 0.2s ease;
  }

  .menu-chat.visible hr {
    opacity: 1;
    transition: opacity 0.3s ease 0.1s;
  }

  .menu-chat.midiendo .renglon {
    transition: none;
  }

  .menu-chat.visible button.renglon:active {
    transform: scale(0.95);
    transition: transform 0.15s ease;
  }

  .fecha {
    padding: 7px 10px 6px;
    font-family: var(--mono);
    font-size: 11px;
    color: var(--tenue);
    white-space: nowrap;
  }

  .menu-chat hr {
    height: 1px;
    margin: 5px 4px;
    border: 0;
    background: var(--linea);
  }

  .menu-chat button {
    display: block;
    width: 100%;
    padding: 8px 10px;
    border: 0;
    border-radius: 8px;
    background: transparent;
    text-align: left;
    font-size: 13.5px;
  }

  .menu-chat button:hover {
    background: var(--chip);
  }

  .menu-chat button.rojo {
    color: var(--rojo);
  }

  @media (prefers-reduced-motion: reduce) {
    .conv,
    .menu-fondo,
    .renglon,
    .menu-chat hr,
    .menu-chat.visible .renglon,
    .menu-chat.visible hr {
      transition: none;
    }
  }
</style>
