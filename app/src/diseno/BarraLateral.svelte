<!--
  La barra lateral de los tres paneles (rediseño del 5 de noviembre de 2026; maqueta
  V64Pv4gmANPRZuJW5hTe5D): pegada al borde izquierdo con una línea de 1 px, de 248 de ancho o de 64 con
  solo íconos (el botón junto al logo; lo recuerda el Marco). Arriba, la estrella con FRAGMENTLESS, cuya
  línea de abajo queda a la altura de la de la barra de arriba. En medio, la búsqueda chica si el panel
  la tiene y las opciones, por grupos ({ grupo: 'OPERACIÓN' }), con la activa en gris. Abajo, las
  acciones (Ayuda, Ajustes) y la persona: su inicial, su nombre con una línea debajo y Cerrar sesión. Si
  el pie trae alPulsar, el nombre es un botón (el gerente abre ahí su Perfil).

  La cajita de cada botón (diseno/pista.ts, regla del 7 de noviembre de 2026) sale a su derecha y, en las
  opciones, la búsqueda y la persona, solo plegada: abierta ya se lee cada nombre.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import { alCambiarEstilo, estiloActual } from '../lib/estilo';
  import Estrella from './Estrella.svelte';
  import Icono from './Icono.svelte';
  import { pista } from './pista';
  import { vidrio } from './vidrio';

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

  const deLado = (texto: string, siempre = false) => ({ texto: siempre || plegada ? texto : null, lado: 'derecha' as const });

  // ─── La gota de Cristal (libreta 4, «El estilo Cristal»; maqueta FiHkjmT1meyTu7zuU3En2n, sección 7) ───
  // En Cristal, la opción activa no se pinta de gris: debajo va una gota de vidrio que se desliza a la que eliges, se
  // estira mientras viaja, se aplasta tantito al llegar y brilla. Al plegar la barra llega resbalando a su renglón
  // nuevo y, mientras el panel cambia de ancho, lo sigue cuadro por cuadro. En Simple no se ve ni se mueve.
  let nav: HTMLElement;
  let gota: HTMLDivElement;
  let enCristal = $state(estiloActual() === 'cristal');
  let brilla = $state(false);
  let hay = $state(false);
  let reloj = 0;

  const quieto = () => window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ?? false;

  // Pone la gota en el renglón activo y dice dónde quedó (relativo a la barra).
  function ponerGota() {
    const op = nav?.querySelector<HTMLElement>('.opcion[aria-current="page"]') ?? null;
    hay = !!op;
    if (!op || !gota || !enCristal) return null;
    // La barra puede ir escalada (el panelito de muestra de Ajustes, a un tercio): se mide en sus pixeles.
    const a = nav.getBoundingClientRect();
    const b = op.getBoundingClientRect();
    const s = a.width / nav.offsetWidth || 1;
    const lugar = { y: (b.top - a.top) / s, h: b.height / s };
    gota.style.left = `${(b.left - a.left) / s}px`;
    gota.style.top = `${lugar.y}px`;
    gota.style.width = `${b.width / s}px`;
    gota.style.height = `${lugar.h}px`;
    return lugar;
  }

  function animar(cuadros: Keyframe[], duracion: number) {
    gota.getAnimations().forEach((a) => a.cancel());
    return gota.animate(cuadros, { duration: duracion, easing: 'cubic-bezier(0.2, 0.8, 0.2, 1)' });
  }

  // Al elegir otra opción: viaja desde donde estaba.
  let antes: { y: number } | null = null;
  $effect(() => {
    void activa;
    if (!enCristal) return;
    const desde = antes;
    const ahora = ponerGota();
    antes = ahora;
    if (!ahora || !desde || quieto()) return;
    const dy = desde.y - ahora.y;
    if (Math.abs(dy) < 0.5) return;
    const estira = 1 + Math.min((Math.abs(dy) / ahora.h) * 0.16, 0.9);
    clearTimeout(reloj);
    brilla = true;
    const anim = animar(
      [
        { transform: `translateY(${dy}px) scale(1, 1)` },
        { transform: `translateY(${dy * 0.42}px) scale(0.93, ${estira})`, offset: 0.38 },
        { transform: 'translateY(0) scale(1.05, 0.94)', offset: 0.74 },
        { transform: 'translateY(0) scale(1, 1)' },
      ],
      Math.min(720, 420 + Math.abs(dy) * 0.6),
    );
    anim.onfinish = () => (reloj = window.setTimeout(() => (brilla = false), 120));
  });

  // Al plegar o abrir: los títulos de grupo se vuelven líneas y la gota salta de renglón; que llegue resbalando.
  let plegadaAntes: boolean | null = null;
  $effect(() => {
    const ahoraPlegada = plegada;
    if (plegadaAntes === null || ahoraPlegada === plegadaAntes) {
      plegadaAntes = ahoraPlegada;
      return;
    }
    plegadaAntes = ahoraPlegada;
    if (!enCristal || !gota) return;
    const arriba = gota.getBoundingClientRect().top;
    const ahora = ponerGota();
    antes = ahora;
    if (!ahora || quieto()) return;
    const dy = (arriba - gota.getBoundingClientRect().top) / (nav.getBoundingClientRect().width / nav.offsetWidth || 1);
    if (Math.abs(dy) > 0.5) animar([{ transform: `translateY(${dy}px)` }, { transform: 'translateY(0)' }], 520);
  });

  onMount(() => {
    antes = ponerGota();
    const deja = alCambiarEstilo((estilo) => {
      enCristal = estilo === 'cristal';
      queueMicrotask(() => (antes = ponerGota()));
    });
    // Mientras el panel cambia de ancho (plegar con resorte), la gota lo sigue; y si el cuerpo se desliza, también.
    const vigia = new ResizeObserver(() => ponerGota());
    vigia.observe(nav);
    const cuerpo = nav.querySelector('.cuerpo');
    const alDeslizar = () => ponerGota();
    cuerpo?.addEventListener('scroll', alDeslizar, { passive: true });
    document.fonts?.ready.then(() => (antes = ponerGota()));
    return () => {
      deja();
      vigia.disconnect();
      cuerpo?.removeEventListener('scroll', alDeslizar);
      clearTimeout(reloj);
    };
  });
</script>

{#snippet opcion(o: Opcion)}
  <button
    type="button"
    class="opcion"
    aria-current={o.valor === activa ? 'page' : undefined}
    aria-label={plegada ? o.texto : undefined}
    use:pista={deLado(o.texto)}
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

<nav class="lateral" class:plegada aria-label="Menú del panel" bind:this={nav} use:vidrio={'menu'}>
  <div class="gota" class:brilla class:hay bind:this={gota} aria-hidden="true"></div>
  <div class="marca">
    {#if !plegada}
      <Estrella fondo="panel" tamano={22} />
      <span class="logo">FRAGMENTLESS</span>
    {/if}
    <button
      type="button"
      class="cuadro"
      aria-label={plegada ? 'Abrir la barra lateral' : 'Plegar la barra lateral'}
      use:pista={deLado(plegada ? 'Abrir la barra lateral' : 'Plegar la barra lateral', true)}
      onclick={alPlegar}
    >
      <Icono nombre="r-plegar" tamano={18} />
    </button>
  </div>

  <div class="cuerpo">
    {#if alBuscar}
      <button type="button" class="buscar-mini" aria-label="Buscar" use:pista={deLado('Buscar')} onclick={alBuscar}>
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
        <button type="button" class="persona-boton" use:pista={deLado(pie.nombre)} onclick={pie.alPulsar}>
          {@render persona()}
        </button>
      {:else}
        <div class="persona-boton">{@render persona()}</div>
      {/if}
      {#if !plegada}
        <button type="button" class="cuadro" aria-label="Cerrar sesión" use:pista={deLado('Cerrar sesión', true)} onclick={alSalir}>
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

  /* La activa, en el gris del dock de Mi menú (8 nov 2026; antes iba en tinta). */
  .opcion[aria-current='page'] {
    background: var(--chip);
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

  /* Plegada, cada botón se mueve como los del dock de Mi menú (8 nov 2026): al pasar el mouse crece a
     1.1 y sube 2 px con sus resortes (base.css), y se aprieta a 0.95 al picarle. Abierta, lo mismo pero
     solo el ícono (y la inicial de la persona): el renglón se queda quieto. */
  .plegada :is(.opcion, .buscar-mini, .cuadro, button.persona-boton) {
    transition:
      background-color 0.15s cubic-bezier(0.4, 0, 0.2, 1),
      color 0.15s cubic-bezier(0.4, 0, 0.2, 1),
      scale 0.548s var(--resorte-escala),
      translate 0.65s var(--resorte-sube);
  }

  .plegada :is(.opcion, .buscar-mini, .cuadro, button.persona-boton):is(:hover, :focus-visible) {
    scale: 1.1;
    translate: 0 -2px;
  }

  .plegada :is(.opcion, .buscar-mini, .cuadro, button.persona-boton):active {
    scale: 0.95;
  }

  .lateral:not(.plegada) :is(.opcion, .buscar-mini, .cuadro) > :global(svg),
  .lateral:not(.plegada) .inicial {
    transition:
      scale 0.548s var(--resorte-escala),
      translate 0.65s var(--resorte-sube);
  }

  .lateral:not(.plegada) :is(.opcion, .buscar-mini, .cuadro):is(:hover, :focus-visible) > :global(svg),
  .lateral:not(.plegada) button.persona-boton:is(:hover, :focus-visible) .inicial {
    scale: 1.1;
    translate: 0 -2px;
  }

  .lateral:not(.plegada) :is(.opcion, .buscar-mini, .cuadro):active > :global(svg),
  .lateral:not(.plegada) button.persona-boton:active .inicial {
    scale: 0.95;
  }

  /* ─── Cristal: la barra flota, como la pide Apple (guías Sidebars, WWDC25) ───
     Un panel de vidrio (su receta, data-vidrio="menu", en cristal.css) con 10 px de aire alrededor y esquinas de 18.
     Va encima del desvanecido de la barra de arriba, que corre por detrás (z-index 3 sobre su 2). La opción activa es
     la gota; plegada, deja 5 px a los lados de los íconos para que quepan dentro del vidrio. */
  :global(:root[data-estilo='cristal']) .lateral {
    position: relative;
    z-index: 3;
    margin: 10px 0 10px 10px;
    border-radius: 18px;
  }

  :global(:root[data-estilo='cristal']) .opcion {
    position: relative;
    z-index: 1;
  }

  :global(:root[data-estilo='cristal']) .opcion[aria-current='page'] {
    background: transparent;
  }

  :global(:root[data-estilo='cristal']) .plegada :is(.cuerpo, .pie) {
    padding-left: 5px;
    padding-right: 5px;
  }

  :global(:root[data-estilo='cristal'][data-tema='oscuro']) kbd {
    background: rgba(255, 255, 255, 0.06);
    border-color: rgba(255, 255, 255, 0.12);
  }

  :global(:root[data-estilo='cristal'][data-tema='claro']) kbd {
    background: rgba(255, 255, 255, 0.5);
    border-color: rgba(0, 0, 0, 0.08);
  }

  /* En Cristal claro, la estrella y las insignias en el azul fuerte del oscuro, no en el naranja del claro. */
  :global(:root[data-estilo='cristal'][data-tema='claro']) .marca {
    --estrella-1: #1b3fb5;
    --estrella-2: #1f5ef0;
    --estrella-3: #4fa3ff;
    --estrella-4: #9fe6ff;
  }

  :global(:root[data-estilo='cristal'][data-tema='claro']) .insignia {
    background: #1355e8;
  }

  .gota {
    display: none;
  }

  :global(:root[data-estilo='cristal']) .gota.hay {
    display: block;
    position: absolute;
    z-index: 0;
    pointer-events: none;
    border-radius: 9px;
    transform-origin: 50% 50%;
    transition:
      background 0.35s ease,
      box-shadow 0.35s ease;
  }

  :global(:root[data-estilo='cristal'][data-tema='oscuro']) .gota {
    background: linear-gradient(180deg, rgba(255, 255, 255, 0.14), rgba(255, 255, 255, 0.05));
    box-shadow:
      inset 0 1px 0 rgba(255, 255, 255, 0.3),
      inset 0 -1px 0 rgba(255, 255, 255, 0.06),
      inset 0 0 0 1px rgba(255, 255, 255, 0.1),
      0 6px 16px -6px rgba(0, 0, 0, 0.6);
  }

  :global(:root[data-estilo='cristal'][data-tema='oscuro']) .gota.brilla {
    background: linear-gradient(180deg, rgba(255, 255, 255, 0.24), rgba(255, 255, 255, 0.09));
    box-shadow:
      inset 0 1px 0 rgba(255, 255, 255, 0.5),
      inset 0 -1px 0 rgba(255, 255, 255, 0.1),
      inset 0 0 0 1px rgba(255, 255, 255, 0.18),
      0 0 22px rgba(255, 255, 255, 0.08),
      0 6px 16px -6px rgba(0, 0, 0, 0.6);
  }

  :global(:root[data-estilo='cristal'][data-tema='claro']) .gota {
    background: linear-gradient(180deg, rgba(255, 255, 255, 0.88), rgba(255, 255, 255, 0.55));
    box-shadow:
      inset 0 1px 0 #ffffff,
      inset 0 0 0 1px rgba(255, 255, 255, 0.75),
      0 6px 16px -6px rgba(36, 52, 80, 0.3);
  }

  :global(:root[data-estilo='cristal'][data-tema='claro']) .gota.brilla {
    background: linear-gradient(180deg, #ffffff, rgba(255, 255, 255, 0.75));
    box-shadow:
      inset 0 1px 0 #ffffff,
      inset 0 0 0 1px #ffffff,
      0 0 22px rgba(255, 255, 255, 0.7),
      0 6px 16px -6px rgba(36, 52, 80, 0.3);
  }

  @media (prefers-reduced-motion: reduce) {
    .lateral * {
      transition: none !important;
    }
  }
</style>
