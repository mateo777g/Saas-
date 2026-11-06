<!--
  La barra lateral de los tres paneles (rediseño del 5 de noviembre de 2026; maqueta
  V64Pv4gmANPRZuJW5hTe5D): pegada al borde izquierdo con una línea de 1 px, de 248 de ancho o de 64 con
  solo íconos (el botón junto al logo; lo recuerda el Marco). Arriba, la estrella con FRAGMENTLESS, cuya
  línea de abajo queda a la altura de la de la barra de arriba. En medio, la búsqueda chica si el panel
  la tiene y las opciones, por grupos ({ grupo: 'OPERACIÓN' }), con la activa en tinta. Abajo, las
  acciones (Ayuda, Ajustes) y la persona: su inicial, su nombre con una línea debajo y Cerrar sesión. Si
  el pie trae alPulsar, el nombre es un botón (el gerente abre ahí su Perfil).
-->
<script lang="ts">
  import Estrella from './Estrella.svelte';
  import Icono from './Icono.svelte';

  // `insignia` es la etiqueta del acento al final de la opción («IA» del Agente IA, «2» de Pedidos).
  type Opcion = { valor: string; texto: string; icono: string; insignia?: string };
  type Grupo = { grupo: string };

  let {
    opciones,
    acciones = [],
    activa,
    alElegir,
    pie,
    alSalir,
    alBuscar,
    plegada,
    alPlegar,
  }: {
    opciones: (Opcion | Grupo)[];
    acciones?: Opcion[];
    activa: string;
    alElegir: (valor: string) => void;
    pie: { inicial: string; nombre: string; linea: string; alPulsar?: () => void };
    alSalir: () => void;
    // El gerente y Fragmentless tienen búsqueda: te lleva a Inicio y abre la grande.
    alBuscar?: () => void;
    plegada: boolean;
    alPlegar: () => void;
  } = $props();
</script>

{#snippet opcion(o: Opcion)}
  <button
    type="button"
    class="opcion"
    aria-current={o.valor === activa ? 'page' : undefined}
    title={o.texto}
    onclick={() => alElegir(o.valor)}
  >
    <Icono nombre={o.icono} tamano={18} />
    {#if !plegada}
      <span class="texto">{o.texto}</span>
      {#if o.insignia}<span class="insignia">{o.insignia}</span>{/if}
    {/if}
  </button>
{/snippet}

{#snippet persona()}
  <span class="inicial">{pie.inicial}</span>
  {#if !plegada}
    <span class="quien">
      <span class="nombre">{pie.nombre}</span>
      <span class="linea">{pie.linea}</span>
    </span>
  {/if}
{/snippet}

<nav class="lateral" class:plegada aria-label="Menú del panel">
  <div class="marca">
    {#if !plegada}
      <Estrella fondo="panel" tamano={22} />
      <span class="logo">FRAGMENTLESS</span>
    {/if}
    <button
      type="button"
      class="cuadro"
      aria-label={plegada ? 'Abrir la barra lateral' : 'Plegar la barra lateral'}
      title={plegada ? 'Abrir la barra lateral' : 'Plegar la barra lateral'}
      onclick={alPlegar}
    >
      <Icono nombre="r-plegar" tamano={18} />
    </button>
  </div>

  <div class="cuerpo">
    {#if alBuscar}
      <button type="button" class="buscar-mini" aria-label="Buscar" title="Buscar" onclick={alBuscar}>
        <Icono nombre="r-buscar" tamano={18} />
        {#if !plegada}
          <span class="texto">Busca algo…</span>
          <kbd>Ctrl K</kbd>
        {/if}
      </button>
    {/if}
    {#each opciones as o ('grupo' in o ? `grupo-${o.grupo}` : o.valor)}
      {#if 'grupo' in o}
        {#if plegada}
          <div class="grupo-linea"></div>
        {:else}
          <span class="etiqueta grupo">{o.grupo}</span>
        {/if}
      {:else}
        {@render opcion(o)}
      {/if}
    {/each}
  </div>

  <div class="pie">
    {#each acciones as o (o.valor)}
      {@render opcion(o)}
    {/each}
    <div class="persona">
      {#if pie.alPulsar}
        <button type="button" class="persona-boton" title={pie.nombre} onclick={pie.alPulsar}>
          {@render persona()}
        </button>
      {:else}
        <div class="persona-boton">{@render persona()}</div>
      {/if}
      {#if !plegada}
        <button type="button" class="cuadro" aria-label="Cerrar sesión" title="Cerrar sesión" onclick={alSalir}>
          <Icono nombre="r-salir" tamano={18} />
        </button>
      {/if}
    </div>
  </div>
</nav>

<style>
  .lateral {
    min-width: 0;
    min-height: 0;
    display: flex;
    flex-direction: column;
    overflow: hidden;
    background: var(--solido);
    border-right: 1px solid var(--linea);
  }

  .marca {
    height: 56px;
    flex: none;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 12px 0 18px;
    border-bottom: 1px solid var(--linea);
  }

  .logo {
    flex: 1;
    font-size: 14.5px;
    font-weight: 800;
    letter-spacing: 0.14em;
    white-space: nowrap;
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

  .cuerpo {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    padding: 12px 10px;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .buscar-mini {
    height: 36px;
    flex: none;
    display: flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 8px;
    padding: 0 10px;
    border: 1px solid var(--linea);
    border-radius: 9px;
    background: transparent;
    color: var(--tenue);
    font-size: 13px;
    font-weight: 400;
    text-align: left;
  }

  .buscar-mini:hover {
    border-color: var(--linea-fuerte);
  }

  kbd {
    padding: 1px 5px;
    border: 1px solid var(--linea);
    border-radius: 5px;
    background: var(--suelo);
    font-family: var(--mono);
    font-size: 10.5px;
    color: var(--tenue);
  }

  .grupo {
    margin: 14px 0 4px 10px;
    letter-spacing: 0.08em;
  }

  .grupo-linea {
    height: 1px;
    flex: none;
    margin: 10px 8px;
    background: var(--linea);
  }

  .opcion {
    width: 100%;
    height: 38px;
    flex: none;
    display: flex;
    align-items: center;
    gap: 11px;
    padding: 0 10px;
    border: 0;
    border-radius: 9px;
    background: transparent;
    color: var(--texto);
    font-size: 14px;
    font-weight: 500;
    text-align: left;
  }

  .opcion:hover {
    background: var(--chip);
  }

  .opcion[aria-current='page'] {
    background: var(--tinta);
    color: var(--sobre-tinta);
    font-weight: 600;
  }

  .texto {
    flex: 1;
    overflow: hidden;
    white-space: nowrap;
  }

  .insignia {
    padding: 4px 6px;
    border-radius: 6px;
    background: var(--acento);
    color: var(--sobre-acento);
    font-family: var(--mono);
    font-size: 10px;
    font-weight: 500;
    line-height: 1;
  }

  .pie {
    flex: none;
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: 8px 10px 10px;
  }

  .persona {
    display: flex;
    align-items: center;
    gap: 10px;
    margin-top: 6px;
    padding: 12px 6px 2px 8px;
    border-top: 1px solid var(--linea);
  }

  .persona-boton {
    flex: 1;
    min-width: 0;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0;
    border: 0;
    background: transparent;
    color: var(--texto);
    text-align: left;
  }

  button.persona-boton:hover {
    opacity: 0.7;
  }

  .inicial {
    width: 32px;
    height: 32px;
    flex: none;
    display: grid;
    place-items: center;
    border-radius: 50%;
    background: var(--chip);
    font-size: 13px;
    font-weight: 700;
  }

  .quien {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
  }

  .nombre {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 13.5px;
    font-weight: 600;
  }

  .linea {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 11.5px;
    font-weight: 400;
    color: var(--tenue);
  }

  /* Plegada: solo íconos, al centro. */
  .plegada .marca {
    padding: 0;
    justify-content: center;
  }

  .plegada .opcion,
  .plegada .buscar-mini {
    justify-content: center;
    padding: 0;
  }

  .plegada .persona {
    justify-content: center;
    padding: 12px 0 2px;
  }

  .plegada .persona-boton {
    flex: none;
  }
</style>
