<!--
  La barra lateral de los tres paneles (rediseño del 5 de noviembre de 2026; maqueta
  V64Pv4gmANPRZuJW5hTe5D): pegada al borde izquierdo con una línea de 1 px, de 248 de ancho o de 64 con
  solo íconos (el botón junto al logo; lo recuerda el Marco). Arriba, la estrella con FRAGMENTLESS, cuya
  línea de abajo queda a la altura de la de la barra de arriba. En medio, la búsqueda chica si el panel
  la tiene y las opciones, con la activa en gris. Abajo, las acciones si el panel las trae y la persona:
  su inicial, su nombre con una línea debajo y Cerrar sesión. Si el pie trae alPulsar, el nombre es un
  botón (el gerente abre ahí su Perfil).

  Las opciones van de dos maneras:
  - Fragmentless y distribuidores (como estaban): sueltas con su ícono, bajo títulos en mono
    ({ grupo: 'CLIENTES' }), y Ajustes fijo abajo en `acciones`.
  - El gerente (13 nov 2026; maqueta T8xZcCNE3zdAwfE34GAsFU, barra-lateral-nueva.md): debajo de Inicio, grupos
    que se abren y se cierran ({ clave, nombre, icono, opciones }), varios a la vez. Solo Inicio y los grupos
    llevan ícono; el título, como una opción en semi-negrita con su flechita, y adentro las opciones corridas a
    la derecha con una línea que baja del ícono. Al abrir, la flechita gira con el resorte de las flechas de las
    listas y las opciones salen del título una tras otra con los resortes de las listas; al cerrar regresan, más
    rápido. La marca de dónde estás va en la opción o, si su grupo está cerrado, en el título del grupo, que
    cerrado lleva la `insignia` del grupo (el número de Pedidos). Al entrar se abre el grupo de la vista donde
    estás y el navegador recuerda cuáles dejaste abiertos. Plegada quedan los íconos y cada uno abre a su lado
    la lista del grupo (colgada de <body>; en Cristal, de vidrio), que se cierra al elegir, al picar afuera o
    con Esc. Si no caben a lo alto, se deslizan con una barrita propia de 6 px.

  La cajita de cada botón (diseno/pista.ts, regla del 7 de noviembre de 2026) sale a su derecha y, en las
  opciones, la búsqueda y la persona, solo plegada: abierta ya se lee cada nombre. Mientras está abierta la
  lista de un grupo no sale ninguna.
-->
<script lang="ts">
  import { onMount, tick } from 'svelte';
  import { alCambiarEstilo, estiloActual } from '../lib/estilo';
  import Estrella from './Estrella.svelte';
  import { resorteFlecha } from './flecha';
  import Icono from './Icono.svelte';
  import { esconderPista, pista } from './pista';
  import { vidrio } from './vidrio';

  // `insignia` es la etiqueta del acento al final de la opción («IA» del Agente IA, «2» de Pedidos).
  type Opcion = { valor: string; texto: string; icono: string; insignia?: string };
  // Un título en mono entre opciones sueltas (Fragmentless y distribuidores).
  type Grupo = { grupo: string };
  // Un grupo que se abre (el gerente): sus opciones van sin ícono; `insignia` va en su título mientras está cerrado.
  type Hija = { valor: string; texto: string; insignia?: string };
  type GrupoQueSeAbre = { clave: string; nombre: string; icono: string; opciones: Hija[]; insignia?: string };

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
    opciones: (Opcion | Grupo | GrupoQueSeAbre)[];
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

  // Mientras está abierta la lista de un grupo (barra plegada), ningún botón de la barra saca su cajita.
  const deLado = (texto: string, siempre = false) => ({
    texto: (siempre || plegada) && !flotante ? texto : null,
    lado: 'derecha' as const,
  });

  const quieto = () => window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ?? false;

  // ─── Los grupos que se abren (el gerente) ───
  const grupos = $derived(opciones.filter((o): o is GrupoQueSeAbre => 'opciones' in o));
  const grupoDe = (valor: string) => grupos.find((g) => g.opciones.some((o) => o.valor === valor)) ?? null;

  // Los que dejaste abiertos, en este navegador (como lo plegado, que recuerda el Marco).
  const LLAVE_GRUPOS = 'fragmentless-barra-grupos';
  function leerAbiertos(): Record<string, boolean> {
    let guardados: unknown = [];
    try {
      guardados = JSON.parse(localStorage.getItem(LLAVE_GRUPOS) ?? '[]');
    } catch (error) {
      console.error('[barra] no se pudo leer qué grupos dejaste abiertos; se abre solo el de la vista:', error);
    }
    const abiertos: Record<string, boolean> = {};
    if (Array.isArray(guardados)) for (const c of guardados) if (typeof c === 'string') abiertos[c] = true;
    // Al entrar se abre el grupo de la vista donde estás (no se guarda: se guarda lo que abres o cierras tú).
    // svelte-ignore state_referenced_locally
    const deLaVista = opciones.find((o): o is GrupoQueSeAbre => 'opciones' in o && o.opciones.some((h) => h.valor === activa));
    if (deLaVista) abiertos[deLaVista.clave] = true;
    return abiertos;
  }
  let abiertos = $state(leerAbiertos());

  function alternar(clave: string) {
    abiertos[clave] = !abiertos[clave];
    try {
      localStorage.setItem(LLAVE_GRUPOS, JSON.stringify(Object.keys(abiertos).filter((c) => abiertos[c])));
    } catch (error) {
      console.error('[barra] no se pudo recordar qué grupos dejaste abiertos:', error);
    }
    // Lo de abajo se recorre mientras el grupo crece o se encoge: la gota lo sigue.
    seguir(700);
  }

  // Lo que lleva la marca: la opción donde estás, o el título de su grupo si está cerrado o la barra plegada.
  const marcada = $derived.by(() => {
    const g = grupoDe(activa);
    return g && (plegada || !abiertos[g.clave]) ? `grupo:${g.clave}` : activa;
  });

  // La flechita gira con el resorte de las flechas de las listas (diseno/flecha.ts: 260/22, 0.662 s), en CSS linear().
  const CURVA_FLECHA = `linear(${Array.from({ length: 49 }, (_, i) => +resorteFlecha(i / 48).toFixed(4)).join(', ')})`;

  // ─── La gota de Cristal (libreta 4, «El estilo Cristal»; maqueta FiHkjmT1meyTu7zuU3En2n, sección 7) ───
  // En Cristal, la opción activa no se pinta de gris: debajo va una gota de vidrio que se desliza a la que eliges, se
  // estira mientras viaja, se aplasta tantito al llegar y brilla. Al plegar la barra llega resbalando a su renglón
  // nuevo y, mientras el panel cambia de ancho o un grupo crece, lo sigue cuadro por cuadro. En Simple no se ve ni se
  // mueve.
  let nav: HTMLElement;
  let gota: HTMLDivElement;
  let marcoGota: HTMLDivElement;
  let enCristal = $state(estiloActual() === 'cristal');
  let brilla = $state(false);
  let hay = $state(false);
  let reloj = 0;
  let cuadro = 0;

  // Dónde está un renglón dentro de la barra, sin sus transformaciones (las opciones que salen de su título van
  // escaladas y corridas): con offsetTop hasta la barra, menos lo que se deslizó el cuerpo. Así tampoco importa si la
  // barra va escalada.
  function lugar(el: HTMLElement) {
    let x = 0;
    let y = 0;
    let e: HTMLElement | null = el;
    while (e && e !== nav) {
      x += e.offsetLeft;
      y += e.offsetTop;
      e = e.offsetParent as HTMLElement | null;
    }
    if (!e) return null;
    const cuerpo = el.closest('.cuerpo');
    if (cuerpo) y -= cuerpo.scrollTop;
    return { x, y, w: el.offsetWidth, h: el.offsetHeight };
  }

  // Pone la gota en el renglón activo y dice dónde quedó (relativo a la barra). Si la lista no cabe y se desliza, el
  // marco de la gota se recorta a la lista: la opción se esconde bajo la orilla y la gota con ella (el developer, 13 nov
  // 2026: con todos los grupos abiertos, la de Inicio se subía encima del logo). El recorte va en el marco y no en la
  // gota porque la gota se estira y se aplasta al viajar.
  function ponerGota() {
    const op = nav?.querySelector<HTMLElement>('.opcion[aria-current="page"]') ?? null;
    hay = !!op;
    if (!op || !gota || !enCristal) return null;
    const l = lugar(op);
    if (!l) return null;
    gota.style.left = `${l.x}px`;
    gota.style.top = `${l.y}px`;
    gota.style.width = `${l.w}px`;
    gota.style.height = `${l.h}px`;
    const cuerpo = op.closest<HTMLElement>('.cuerpo');
    if (cuerpo && cuerpo.scrollHeight > cuerpo.clientHeight + 1) {
      const abajo = nav.clientHeight - cuerpo.offsetTop - cuerpo.clientHeight;
      marcoGota.style.clipPath = `inset(${cuerpo.offsetTop}px 0 ${abajo}px 0)`;
    } else {
      marcoGota.style.clipPath = '';
    }
    return { y: l.y, h: l.h };
  }

  // Lo que se mueve sin cambiar la marca (un grupo que crece, el ancho al plegar, el cuerpo que se desliza): la gota
  // lo sigue y lo anota como su nuevo lugar.
  const acomodar = () => (antes = ponerGota());
  function seguir(ms: number) {
    if (!enCristal) return;
    cancelAnimationFrame(cuadro);
    const fin = performance.now() + ms;
    const paso = () => {
      acomodar();
      if (performance.now() < fin) cuadro = requestAnimationFrame(paso);
    };
    cuadro = requestAnimationFrame(paso);
  }

  function animar(cuadros: Keyframe[], duracion: number) {
    gota.getAnimations().forEach((a) => a.cancel());
    return gota.animate(cuadros, { duration: duracion, easing: 'cubic-bezier(0.2, 0.8, 0.2, 1)' });
  }

  // Al cambiar la marca (elegir otra opción, cerrar el grupo de la vista): viaja desde donde estaba. Al plegar o
  // abrir la barra, la marca salta de renglón: ahí llega resbalando, sin estirarse.
  let antes: { y: number; h: number } | null = null;
  let plegadaAntes: boolean | null = null;
  $effect(() => {
    void marcada;
    const p = plegada;
    const plegando = plegadaAntes !== null && p !== plegadaAntes;
    plegadaAntes = p;
    if (!enCristal) {
      antes = null;
      return;
    }
    const desde = antes;
    const ahora = ponerGota();
    antes = ahora;
    if (!ahora || !desde || quieto()) return;
    const dy = desde.y - ahora.y;
    if (Math.abs(dy) < 0.5) return;
    if (plegando) {
      animar([{ transform: `translateY(${dy}px)` }, { transform: 'translateY(0)' }], 520);
      return;
    }
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

  // ─── Plegada: la lista del grupo, a un lado de su ícono ───
  // Colgada de <body> (en Cristal la barra es vidrio y lo fijo de adentro se acomodaría contra ella), a 8 px de la
  // barra, con su tope al ícono menos 6 px (si no cabe abajo, sube). Cada renglón sale del ícono: antes de abrir se
  // mide cuánto le falta a cada uno, sin transición (reglas-diseno.md, «Las listas que se abren»).
  // raw: es el mismo grupo que llegó en las opciones (sin proxy), para compararlo con ===.
  let flotante = $state.raw<GrupoQueSeAbre | null>(null);
  let flotanteVisible = $state(false);
  let midiendo = $state(false);
  let lugarFlotante = $state({ left: 0, top: 0, alto: 0 });
  let desdeIcono = $state<{ x: number; y: number }[]>([]);
  let cajaFlotante = $state<HTMLDivElement | null>(null);
  let cabezaFlotante: HTMLButtonElement | null = null;

  async function abrirFlotante(g: GrupoQueSeAbre, cabeza: HTMLButtonElement) {
    if (flotante?.clave === g.clave && flotanteVisible) {
      cerrarFlotante();
      return;
    }
    cerrarFlotante(true);
    esconderPista();
    const r = cabeza.getBoundingClientRect();
    const n = nav.getBoundingClientRect();
    cabezaFlotante = cabeza;
    midiendo = true;
    flotante = g;
    await tick();
    const renglones = cajaFlotante?.querySelector<HTMLElement>('.flotante-renglones');
    if (!cajaFlotante || !renglones || flotante !== g) {
      midiendo = false;
      return;
    }
    const alto = renglones.offsetHeight;
    const left = n.right + 8;
    const top = Math.max(8, Math.min(r.top - 6, window.innerHeight - 8 - alto));
    lugarFlotante = { left, top, alto };
    desdeIcono = [...renglones.children].map((h) => {
      const e = h as HTMLElement;
      return {
        x: r.left + r.width / 2 - (left + e.offsetLeft + e.offsetWidth / 2),
        y: r.top + r.height / 2 - (top + e.offsetTop + e.offsetHeight / 2),
      };
    });
    await tick();
    void cajaFlotante.offsetHeight;
    midiendo = false;
    flotanteVisible = true;
    cajaFlotante.querySelector<HTMLButtonElement>('.renglon')?.focus({ preventScroll: true });
  }

  // Los renglones regresan a su ícono (0.2–0.3 s) y luego se quita; de golpe al abrir otra o con «reducir movimiento».
  function cerrarFlotante(deGolpe = false, volver = false) {
    if (!flotante) return;
    const g = flotante;
    flotanteVisible = false;
    if (volver) cabezaFlotante?.focus();
    if (deGolpe || quieto()) {
      flotante = null;
      return;
    }
    setTimeout(() => {
      if (!flotanteVisible && flotante === g) flotante = null;
    }, 320);
  }

  function elegirDelFlotante(valor: string) {
    cerrarFlotante();
    alElegir(valor);
  }

  function teclaFlotante(e: KeyboardEvent) {
    const botones = [...(cajaFlotante?.querySelectorAll<HTMLButtonElement>('.renglon') ?? [])];
    const i = botones.indexOf(document.activeElement as HTMLButtonElement);
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      botones[(i + (e.key === 'ArrowDown' ? 1 : botones.length - 1)) % botones.length]?.focus();
    } else if (e.key === 'Home' || e.key === 'End') {
      e.preventDefault();
      botones[e.key === 'Home' ? 0 : botones.length - 1]?.focus();
    } else if (e.key === 'Tab') {
      cerrarFlotante();
    }
  }

  // Se cierra al picar afuera (el ícono de un grupo ya hace lo suyo) o con Esc, y de golpe si se abre la barra.
  $effect(() => {
    if (!flotante) return;
    const fuera = (e: PointerEvent) => {
      const t = e.target as Element | null;
      if (cajaFlotante?.contains(t) || t?.closest?.('.lateral .cabeza')) return;
      cerrarFlotante();
    };
    const tecla = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && flotanteVisible) cerrarFlotante(false, true);
    };
    document.addEventListener('pointerdown', fuera, true);
    document.addEventListener('keydown', tecla);
    return () => {
      document.removeEventListener('pointerdown', fuera, true);
      document.removeEventListener('keydown', tecla);
    };
  });
  $effect(() => {
    if (!plegada) cerrarFlotante(true);
  });

  // La lista vive en <body>; al irse, Svelte la quita de ahí.
  function alCuerpo(nodo: HTMLElement) {
    document.body.append(nodo);
    return { destroy: () => nodo.remove() };
  }

  onMount(() => {
    antes = ponerGota();
    const deja = alCambiarEstilo((estilo) => {
      enCristal = estilo === 'cristal';
      queueMicrotask(acomodar);
    });
    // Mientras el panel cambia de ancho (plegar con resorte), la gota lo sigue; y si el cuerpo se desliza, también.
    const vigia = new ResizeObserver(acomodar);
    vigia.observe(nav);
    const cuerpo = nav.querySelector('.cuerpo');
    cuerpo?.addEventListener('scroll', acomodar, { passive: true });
    document.fonts?.ready.then(acomodar);
    return () => {
      deja();
      vigia.disconnect();
      cuerpo?.removeEventListener('scroll', acomodar);
      clearTimeout(reloj);
      cancelAnimationFrame(cuadro);
    };
  });
</script>

{#snippet opcion(o: Opcion)}
  <button
    type="button"
    class="opcion"
    aria-current={o.valor === marcada ? 'page' : undefined}
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

{#snippet grupo(g: GrupoQueSeAbre)}
  {@const abierto = !plegada && !!abiertos[g.clave]}
  <div class="seccion" class:abierto>
    {#if plegada}
      <button
        type="button"
        class="opcion cabeza"
        aria-current={marcada === `grupo:${g.clave}` ? 'page' : undefined}
        aria-label={g.nombre}
        aria-haspopup="menu"
        aria-expanded={flotante?.clave === g.clave && flotanteVisible}
        use:pista={deLado(g.nombre)}
        onclick={(e) => abrirFlotante(g, e.currentTarget)}
      >
        <Icono nombre={g.icono} tamano={18} />
      </button>
    {:else}
      <button
        type="button"
        class="opcion cabeza"
        aria-current={marcada === `grupo:${g.clave}` ? 'page' : undefined}
        aria-expanded={abierto}
        aria-controls="barra-grupo-{g.clave}"
        onclick={() => alternar(g.clave)}
      >
        <Icono nombre={g.icono} tamano={18} />
        <span class="texto">{g.nombre}</span>
        {#if g.insignia && !abierto}<span class="insignia">{g.insignia}</span>{/if}
        <span class="flecha"><Icono nombre="r-derecha" tamano={16} /></span>
      </button>
      <!-- Cada opción sale del título: 38 de alto + 2 de espacio por renglón; la caja mide 40 por opción + 4. -->
      <div class="sub" id="barra-grupo-{g.clave}" style:--alto="{g.opciones.length * 40 + 4}px" inert={!abierto}>
        <div class="renglones">
          {#each g.opciones as o, i (o.valor)}
            <button
              type="button"
              class="opcion hija"
              aria-current={o.valor === marcada ? 'page' : undefined}
              style:--i={i}
              style:--n={g.opciones.length}
              style:--y="{(i + 1) * 40}px"
              onclick={() => alElegir(o.valor)}
            >
              <span class="texto">{o.texto}</span>
              {#if o.insignia}<span class="insignia">{o.insignia}</span>{/if}
            </button>
          {/each}
        </div>
      </div>
    {/if}
  </div>
{/snippet}

<nav
  class="lateral"
  class:plegada
  class:con-grupos={grupos.length > 0}
  aria-label="Menú del panel"
  style:--resorte-flecha={CURVA_FLECHA}
  bind:this={nav}
  use:vidrio={'menu'}
>
  <div class="marco-gota" bind:this={marcoGota} aria-hidden="true">
    <div class="gota" class:brilla class:hay bind:this={gota}></div>
  </div>
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
    {#each opciones as o ('grupo' in o ? `grupo-${o.grupo}` : 'opciones' in o ? `abre-${o.clave}` : o.valor)}
      {#if 'grupo' in o}
        {#if plegada}
          <div class="grupo-linea"></div>
        {:else}
          <span class="etiqueta grupo">{o.grupo}</span>
        {/if}
      {:else if 'opciones' in o}
        {@render grupo(o)}
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

{#if flotante}
  {@const n = flotante.opciones.length + 1}
  <div
    class="flotante"
    class:visible={flotanteVisible}
    class:midiendo
    role="menu"
    tabindex="-1"
    aria-label={flotante.nombre}
    data-vidrio-detras
    style:left="{lugarFlotante.left}px"
    style:top="{lugarFlotante.top}px"
    style:--alto="{lugarFlotante.alto}px"
    inert={!flotanteVisible && !midiendo}
    bind:this={cajaFlotante}
    use:alCuerpo
    onkeydown={teclaFlotante}
  >
    <!-- En Cristal, una hoja de vidrio (su receta en cristal.css), como las demás listas que se abren. -->
    <div class="flotante-fondo" aria-hidden="true" use:vidrio={'hoja'}></div>
    <div class="flotante-renglones">
      <span
        class="etiqueta flotante-titulo"
        aria-hidden="true"
        style:--i={0}
        style:--n={n}
        style:--x="{desdeIcono[0]?.x ?? 0}px"
        style:--y="{desdeIcono[0]?.y ?? 0}px">{flotante.nombre.toUpperCase()}</span
      >
      {#each flotante.opciones as o, j (o.valor)}
        <button
          type="button"
          role="menuitem"
          class="renglon"
          aria-current={o.valor === activa ? 'page' : undefined}
          style:--i={j + 1}
          style:--n={n}
          style:--x="{desdeIcono[j + 1]?.x ?? 0}px"
          style:--y="{desdeIcono[j + 1]?.y ?? 0}px"
          onclick={() => elegirDelFlotante(o.valor)}
        >
          <span class="texto">{o.texto}</span>
          {#if o.insignia}<span class="insignia">{o.insignia}</span>{/if}
        </button>
      {/each}
    </div>
  </div>
{/if}

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

  /* ─── Los grupos que se abren (el gerente; barra-lateral-nueva.md) ───
     El título, como una opción en semi-negrita, con su flechita a la derecha. */
  .cabeza {
    font-weight: 600;
  }

  .flecha {
    width: 16px;
    height: 16px;
    flex: none;
    display: grid;
    place-items: center;
    color: var(--tenue);
    transition: rotate 0.3s ease;
  }

  .seccion.abierto .flecha {
    rotate: 90deg;
    transition: rotate 0.662s var(--resorte-flecha);
  }

  /* Lo de adentro: la caja crece con el resorte del fondo de las listas; las opciones salen del título una tras
     otra (cada una corrida hacia arriba hasta el título y en 0.8) y al cerrar regresan ahí, de la última a la
     primera, más rápido. */
  .sub {
    position: relative;
    height: 0;
    overflow: hidden;
    flex: none;
    transition: height 0.3s ease;
  }

  .seccion.abierto .sub {
    height: var(--alto);
    transition: height 0.518s var(--resorte-fondo);
  }

  .renglones {
    position: relative;
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: 2px 0 4px;
  }

  /* La línea que las junta: baja desde el ícono del grupo. */
  .renglones::before {
    content: '';
    position: absolute;
    left: 18.5px;
    top: 0;
    bottom: 4px;
    width: 1px;
    background: var(--linea);
  }

  .opcion.hija {
    width: calc(100% - 29px);
    margin-left: 29px;
    opacity: 0;
    transform: translateY(calc(-1 * var(--y))) scale(0.8);
    transition:
      transform 0.2s ease calc((var(--n) - 1 - var(--i)) * 25ms),
      opacity 0.15s ease calc((var(--n) - 1 - var(--i)) * 25ms),
      background-color 0.15s ease;
  }

  .seccion.abierto .opcion.hija {
    opacity: 1;
    transform: none;
    transition:
      transform 0.607s var(--resorte-opcion) calc(min(var(--i), 8) * 45ms),
      opacity 0.3s ease calc(min(var(--i), 8) * 45ms),
      background-color 0.15s ease;
  }

  /* La barrita para bajar, sencilla (el developer, 13 nov 2026: la del navegador «se ve mal»): 6 px, redonda, en el
     gris de la barrita de las tablas, sin carril ni flechas, con 6 px de aire arriba y abajo. Solo sale si la lista no
     cabe. Firefox no deja quitarla del todo: ahí va su delgada, en el mismo gris. */
  .con-grupos .cuerpo::-webkit-scrollbar {
    width: 6px;
  }

  .con-grupos .cuerpo::-webkit-scrollbar-track {
    margin: 6px 0;
    background: transparent;
  }

  .con-grupos .cuerpo::-webkit-scrollbar-thumb {
    border-radius: 3px;
    background: var(--barrita);
  }

  .con-grupos .cuerpo::-webkit-scrollbar-button {
    display: none;
    width: 0;
    height: 0;
  }

  @supports not selector(::-webkit-scrollbar) {
    .con-grupos .cuerpo {
      scrollbar-width: thin;
      scrollbar-color: var(--barrita) transparent;
    }
  }

  /* ─── Plegada: la lista del grupo, a un lado de su ícono ───
     Sólida con borde y la sombra de los menús en Simple; en Cristal, la hoja de vidrio de cristal.css (por eso la
     sombra de Simple no se escribe para Cristal: ganaría a la de la hoja). */
  .flotante {
    position: fixed;
    z-index: 50;
    width: 216px;
    outline: none;
  }

  .flotante-fondo {
    position: absolute;
    left: 0;
    right: 0;
    top: 0;
    height: 0;
    border: 1px solid var(--linea-fuerte);
    border-radius: 12px;
    background: var(--solido);
    opacity: 0;
    transition:
      height 0.25s ease,
      opacity 0.2s ease,
      box-shadow 0.2s ease;
  }

  .flotante.visible .flotante-fondo {
    height: var(--alto);
    opacity: 1;
    transition:
      height 0.518s var(--resorte-fondo),
      opacity 0.25s ease,
      box-shadow 0.25s ease;
  }

  :global(:root:not([data-estilo='cristal'])) .flotante.visible .flotante-fondo {
    box-shadow: 0 14px 34px var(--sombra-menu);
  }

  .flotante-renglones {
    position: relative;
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: 6px;
  }

  .flotante-titulo {
    padding: 8px 10px 6px;
    letter-spacing: 0.08em;
  }

  .flotante-renglones > * {
    opacity: 0;
    transform: translate(var(--x), var(--y)) scale(0.8);
    transition:
      transform 0.2s ease calc((var(--n) - 1 - var(--i)) * 25ms),
      opacity 0.15s ease calc((var(--n) - 1 - var(--i)) * 25ms),
      background-color 0.15s ease;
  }

  .flotante.visible .flotante-renglones > * {
    opacity: 1;
    transform: none;
    transition:
      transform 0.607s var(--resorte-opcion) calc(min(var(--i), 8) * 45ms),
      opacity 0.3s ease calc(min(var(--i), 8) * 45ms),
      background-color 0.15s ease;
  }

  .flotante.midiendo .flotante-renglones > * {
    transition: none;
  }

  .renglon {
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

  .renglon:hover,
  .renglon:focus-visible {
    background: var(--chip);
    outline: none;
  }

  .renglon[aria-current='page'] {
    background: var(--chip);
    font-weight: 600;
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

  .marco-gota,
  .gota {
    display: none;
  }

  /* El marco cubre la barra entera y no se mueve: ahí va el recorte a la lista cuando se desliza (ponerGota). */
  :global(:root[data-estilo='cristal']) .marco-gota {
    display: block;
    position: absolute;
    inset: 0;
    z-index: 0;
    pointer-events: none;
  }

  :global(:root[data-estilo='cristal']) .gota.hay {
    display: block;
    position: absolute;
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
    .lateral *,
    .flotante * {
      transition: none !important;
    }
  }
</style>
