<!--
  La barra de chats del Agente IA, a la derecha de la vista (maqueta CWBFnVy5oDDkhgVD8x7aj9,
  planes/trabajo/rediseno/barra-ia.md): las conversaciones de esta sucursal guardadas en este navegador,
  la más nueva arriba y las fijadas en su grupo. Cada fila es solo su título; la abierta va en gris.

  Los 3 puntitos salen al pasar el mouse, al llegar con el teclado o siempre si no hay mouse (tableta).
  Su menú trae la fecha, Fijar, Cambiar nombre y Eliminar; se cierra con Esc, con un clic afuera o al hacer
  scroll. La barra corta lo que se sale (para abrirse de 0 a 288), así que lo que flota va fijo a la
  ventana: este menú y la lista de sucursales.

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
    if (menuDe?.id === c.id) {
      menuDe = null;
      return;
    }
    menuDe = c;
    await tick();
    if (!cajaMenu) return;
    const r = boton.getBoundingClientRect();
    const abajo = r.bottom + 4;
    lugarMenu = {
      left: r.right - cajaMenu.offsetWidth,
      top: abajo + cajaMenu.offsetHeight > window.innerHeight - 8 ? r.top - cajaMenu.offsetHeight - 4 : abajo,
    };
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
    menuDe = null;
    alFijar(c.id);
    enfocarFila(c.id, 'conv-mas');
  }

  function cambiarNombre(c: Conversacion) {
    menuDe = null;
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
    if (menuDe && !donde.closest('.menu-chat, .conv-mas')) menuDe = null;
  }}
  onkeydown={(e) => {
    if (e.key !== 'Escape' || !menuDe) return;
    enfocarFila(menuDe.id, 'conv-mas');
    menuDe = null;
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
    <div
      class="menu-chat"
      role="menu"
      tabindex="-1"
      aria-label="Opciones de la conversación"
      bind:this={cajaMenu}
      style:left="{lugarMenu.left}px"
      style:top="{lugarMenu.top}px"
      onkeydown={teclaDelMenu}
    >
      <div class="fecha">{cuando(c)}</div>
      <hr />
      <button type="button" role="menuitem" onclick={() => fijar(c)}>{c.fijada ? 'Desfijar' : 'Fijar'}</button>
      <button type="button" role="menuitem" onclick={() => cambiarNombre(c)}>Cambiar nombre</button>
      <hr />
      <button
        type="button"
        role="menuitem"
        class="rojo"
        onclick={() => {
          porEliminar = c.id;
          menuDe = null;
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
    background: var(--solido);
    border: 1px solid var(--linea-fuerte);
    border-radius: 12px;
    box-shadow: 0 14px 34px var(--sombra-menu);
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
    .conv {
      transition: none;
    }
  }
</style>
