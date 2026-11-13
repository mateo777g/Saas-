<!--
  La caja de la pregunta del Agente IA (rediseño del 6 de noviembre de 2026; maqueta Cu768ereKMYRaYhhaAyMb4 y
  planes/trabajo/rediseno/pildora-agente.md). Es una píldora de 48 px con el «+» a la izquierda del texto y sin
  botón de mandar. Al picarle o escribir se hace rectangular, con resorte, y crece con lo escrito de 2 a 6
  renglones, ya sin resorte: abajo lleva el «+», «Enter envía · Shift+Enter salto» y mandar, que se prende con
  texto. Vuelve a ser píldora si sale vacía, con Esc estando vacía o al mandar. La forma y el movimiento son los
  del PromptInput de 21st.dev.

  `zona` es donde el foco la mantiene abierta (en la bienvenida, también las ideas); sin ella, la caja misma.
  `enfocar()` enfoca sin abrir: la píldora se queda y escribir la abre.

  Sin tope (`aviso`), en su lugar va el aviso de la libreta de Seguridad, con el icono de info y el «+» a
  su lado: el reporte no usa IA (planes/trabajo/rediseno/encuestas-agente.md). Ahí no hay píldora.

  Mientras piensa la pregunta de esta conversación (`alDetener`), el botón de mandar es «Detener»
  (maqueta AyS4xUfa5XmDaPJG1iqSgw) y se ve también en la píldora: es la única forma de detener. Si piensa
  la de otra (`ocupado`), la flecha se apaga.
-->
<script lang="ts">
  import { tick } from 'svelte';
  import { Tween } from 'svelte/motion';
  import { DURA_FLECHA, resorteFlecha } from '../../../diseno/flecha';
  import Icono from '../../../diseno/Icono.svelte';
  import Metal from '../../../diseno/Metal.svelte';
  import { pista } from '../../../diseno/pista';
  import { vidrio } from '../../../diseno/vidrio';
  import { PERIODOS_REPORTE, type PeriodoReporte } from '../../../lib/reporte';

  let {
    modo,
    valor = $bindable(''),
    placeholder,
    ocupado = false,
    aviso = null,
    abierta = $bindable(false),
    zona = null,
    alEnviar,
    alDetener = null,
    alReporte,
  }: {
    modo: 'bienvenida' | 'chat';
    valor?: string;
    placeholder: string;
    ocupado?: boolean;
    aviso?: string | null;
    abierta?: boolean;
    zona?: HTMLElement | null;
    alEnviar: () => void;
    alDetener?: (() => void) | null;
    alReporte: (periodo: PeriodoReporte) => void;
  } = $props();

  const id = $props.id();
  // El campo va de dos renglones a seis (de 22.5 px, con su margen), y el pie mide lo mismo siempre.
  const ALTO_CAMPO = 68;
  const ALTO_MAXIMO = 160;
  const ALTO_PIE = 48;

  let caja = $state<HTMLDivElement | null>(null);
  let campo = $state<HTMLTextAreaElement | null>(null);
  let envoltura = $state<HTMLDivElement | null>(null);
  let menuAbierto = $state(false);
  // El botón de mandar, prendido: con algo que mandar, o «Detener».
  const prendido = $derived(alDetener ? true : !ocupado && !!valor.trim());
  // En la conversación el menú sale hacia arriba; su título y sus 3 periodos salen uno tras otro.
  const menuArriba = $derived(modo === 'chat');
  const N_MENU = PERIODOS_REPORTE.length + 1;
  // El menú del «+» se abre como la Lista (regla «Las listas que se abren», 9 nov 2026): el fondo crece desde el «+»
  // (220/28), cada renglón sale del «+», de 0.8 a 1, uno tras otro desde el más cercano (220/26, 45 ms; al cerrar, al
  // revés y de 20 en 20 ms) y el «+» gira a ✕ con el resorte de la flecha (260/22).
  let menu = $state<HTMLDivElement | null>(null);
  let botonMas = $state<HTMLButtonElement | null>(null);
  let altoMenu = $state(0);
  let desde = $state<number[]>([]);
  let midiendo = $state(false);
  const quieto = typeof matchMedia === 'function' ? matchMedia('(prefers-reduced-motion: reduce)') : null;
  const giro = new Tween(0, { duration: DURA_FLECHA, easing: resorteFlecha });
  $effect(() => {
    giro.set(menuAbierto ? 1 : 0, quieto?.matches ? { duration: 0 } : undefined);
  });

  // Pone, quieto, de dónde sale cada renglón (el «+») y luego abre, para que el resorte arranque ahí.
  async function abrirMenu() {
    if (menu && botonMas) {
      const b = botonMas.getBoundingClientRect().top;
      const m = menu.getBoundingClientRect().top;
      desde = [...menu.querySelectorAll<HTMLElement>('.renglon')].map((r) => b - (m + r.offsetTop));
    }
    midiendo = true;
    await tick();
    void menu?.offsetHeight;
    midiendo = false;
    menuAbierto = true;
  }
  // Mientras se escribe en la caja ya abierta, crece sin el resorte.
  let escribiendo = $state(false);
  let altoCampo = $state<number | null>(null);
  let desborda = $state(false);

  // Con texto se abre: también cuando una respuesta fallida o detenida vuelve a la caja.
  $effect(() => {
    if (valor.trim() && !aviso) abierta = true;
  });

  // Mide lo escrito sin que se note: el alto del campo se pone en 0 un momento y sin transición.
  $effect(() => {
    void valor;
    const c = campo;
    if (!c) return;
    if (!abierta) {
      escribiendo = false;
      altoCampo = null;
      desborda = false;
      c.scrollTop = 0;
      return;
    }
    const antes = c.style.height;
    c.style.transition = 'none';
    c.style.height = '0px';
    const lleno = c.scrollHeight;
    c.style.height = antes;
    void c.offsetHeight;
    c.style.transition = '';
    altoCampo = Math.max(ALTO_CAMPO, Math.min(lleno, ALTO_MAXIMO));
    desborda = lleno > ALTO_MAXIMO;
  });

  // Vacía, se vuelve píldora cuando el foco sale de su zona; no si solo se fue la ventana.
  $effect(() => {
    const lugar = zona ?? caja;
    if (!lugar) return;
    const alSalir = (e: FocusEvent) => {
      if (valor.trim()) return;
      if (e.relatedTarget instanceof Node && lugar.contains(e.relatedTarget)) return;
      if (document.activeElement === campo) return;
      // El navegador también avisa mientras Svelte quita la caja de la pantalla: ahí ya no hay nada que cerrar.
      queueMicrotask(() => {
        if (lugar.isConnected) abierta = false;
      });
    };
    lugar.addEventListener('focusout', alSalir);
    return () => lugar.removeEventListener('focusout', alSalir);
  });

  $effect(() => {
    if (!menuAbierto) return;
    const alClic = (e: MouseEvent) => {
      if (!envoltura?.contains(e.target as Node)) menuAbierto = false;
    };
    const alTecla = (e: KeyboardEvent) => {
      if (e.key === 'Escape') menuAbierto = false;
    };
    document.addEventListener('mousedown', alClic);
    document.addEventListener('keydown', alTecla);
    return () => {
      document.removeEventListener('mousedown', alClic);
      document.removeEventListener('keydown', alTecla);
    };
  });

  function abrir() {
    abierta = true;
    campo?.focus();
  }

  function mandar() {
    if (ocupado || !valor.trim()) return;
    alEnviar();
    abierta = false;
  }

  function alTeclear(e: KeyboardEvent) {
    if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
      e.preventDefault();
      mandar();
    }
    // Con el menú abierto, Esc solo cierra el menú.
    if (e.key === 'Escape' && !valor.trim() && !menuAbierto) {
      abierta = false;
      campo?.blur();
    }
  }

  // Picar lo demás de la caja abierta no le quita el foco al texto.
  function alApretar(e: MouseEvent) {
    if (!abierta || e.target === campo) return;
    e.preventDefault();
    campo?.focus();
  }

  // En la píldora, el «+» abre la caja con su menú (cuando la caja ya creció, para medir desde su lugar).
  async function picarMas() {
    if (!abierta && !aviso) {
      abrir();
      await tick();
      abrirMenu();
      return;
    }
    if (menuAbierto) menuAbierto = false;
    else abrirMenu();
  }

  function elegir(periodo: PeriodoReporte) {
    menuAbierto = false;
    alReporte(periodo);
  }

  export function enfocar() {
    campo?.focus();
  }
</script>

{#snippet mas()}
  <div class="mas-envoltura" bind:this={envoltura}>
    <button
      type="button"
      class="mas"
      aria-label="Más"
      aria-expanded={menuAbierto}
      disabled={ocupado}
      use:pista={menuAbierto ? null : 'Reporte en PDF'}
      bind:this={botonMas}
      onclick={picarMas}
    >
      <span class="giro" style:transform="rotate({giro.current * 45}deg)"><Icono nombre="r-mas" tamano={18} /></span>
    </button>
    <div
      class="menu-mas"
      class:arriba={menuArriba}
      class:a-la-derecha={!!aviso}
      class:abierto={menuAbierto}
      class:midiendo
      style:--alto="{altoMenu}px"
      inert={!menuAbierto}
    >
      <!-- En Cristal, una hoja de vidrio (su receta en cristal.css). -->
      <div class="menu-fondo" aria-hidden="true" use:vidrio={'hoja'}></div>
      <div class="menu-renglones" bind:this={menu} bind:offsetHeight={altoMenu}>
        {#each [null, ...PERIODOS_REPORTE] as p, j (p?.valor ?? 'titulo')}
          {@const k = menuArriba ? N_MENU - 1 - j : j}
          {#if p}
            <button
              type="button"
              class="opcion renglon"
              style:--y="{desde[j] ?? 0}px"
              style:--da="{k * 45}ms"
              style:--dc="{(N_MENU - 1 - k) * 20}ms"
              onclick={() => elegir(p.valor)}>{p.boton}</button
            >
          {:else}
            <div class="titulo-menu renglon" style:--y="{desde[j] ?? 0}px" style:--da="{k * 45}ms" style:--dc="{(N_MENU - 1 - k) * 20}ms">
              <Icono nombre="r-hoy" tamano={16} />Reporte en PDF
            </div>
          {/if}
        {/each}
      </div>
    </div>
  </div>
{/snippet}

{#if aviso}
  <div class="caja-pregunta tope" role="status">
    <span class="cuadro-icono"><Icono nombre="info" tamano={18} /></span>
    <p>{aviso}</p>
    {@render mas()}
  </div>
{:else}
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div
    class="caja-pregunta"
    class:pildora={!abierta}
    class:en-chat={modo === 'chat'}
    class:escribiendo
    style:height={altoCampo === null ? null : `${altoCampo + ALTO_PIE}px`}
    use:vidrio={'busqueda'}
    bind:this={caja}
    onmousedown={alApretar}
  >
    <button type="button" class="pildora-texto" tabindex={abierta ? -1 : 0} onclick={abrir}>{placeholder}</button>
    <label for={id} class="solo-lector">Tu pregunta</label>
    <textarea
      {id}
      bind:this={campo}
      bind:value={valor}
      rows={modo === 'chat' ? 1 : 2}
      {placeholder}
      tabindex={abierta ? 0 : -1}
      style:height={altoCampo === null ? null : `${altoCampo}px`}
      style:overflow-y={desborda ? 'auto' : null}
      onkeydown={alTeclear}
      oninput={() => {
        if (abierta) escribiendo = true;
      }}
    ></textarea>
    <div class="caja-pie">
      {@render mas()}
      <span class="hueco"></span>
      <span class="pista">Enter envía · Shift+Enter salto</span>
    </div>
    <button
      type="button"
      class="mandar"
      class:parando={!!alDetener}
      aria-label={alDetener ? 'Detener' : 'Mandar la pregunta'}
      use:pista={alDetener ? 'Detener' : 'Mandar'}
      disabled={!prendido}
      onclick={alDetener ?? mandar}
    >
      <Metal {prendido} />
      <span class="capa flecha"><Icono nombre="r-arriba" tamano={17} /></span>
      <span class="capa parar"><Icono nombre="detener" tamano={17} /></span>
    </button>
  </div>
{/if}

<style>
  .caja-pregunta {
    position: relative;
    flex: none;
    width: 100%;
    max-width: 656px;
    height: 116px;
    margin-inline: auto;
    border: 1px solid var(--borde-tarjeta);
    border-radius: 24px;
    background: var(--solido);
    cursor: text;
    transition:
      max-width 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275),
      height 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275);
  }

  .caja-pregunta.escribiendo {
    transition:
      max-width 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275),
      height 0.15s ease-out;
  }

  .caja-pregunta.pildora {
    max-width: 440px;
    height: 48px;
    overflow: hidden;
  }

  .caja-pregunta.pildora.en-chat {
    max-width: 656px;
  }

  .caja-pregunta:focus-within {
    border-color: var(--linea-fuerte);
  }

  /* Cristal: la caja es vidrio, como la búsqueda de Inicio que salió de ella (su receta en cristal.css). Como píldora
     recorta lo de adentro, así que su canto va por dentro. */
  :global(:root[data-estilo='cristal']) .caja-pregunta {
    --canto-fuera: 0px;
  }

  .pildora-texto {
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    display: block;
    height: 46px;
    padding: 0 52px 0 48px;
    border: 0;
    border-radius: 24px;
    background: none;
    color: var(--tenue);
    font-size: 15px;
    line-height: 1.5;
    text-align: left;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    cursor: text;
    transition:
      opacity 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275),
      transform 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275);
  }

  .pildora-texto:focus-visible {
    outline-offset: -3px;
  }

  .caja-pregunta:not(.pildora) .pildora-texto {
    opacity: 0;
    transform: translateY(4px) scale(1.05);
    pointer-events: none;
  }

  textarea {
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    width: 100%;
    height: 68px;
    padding: 12px 52px 11px 20px;
    border: 0;
    outline: none;
    resize: none;
    overflow-y: hidden;
    background: none;
    color: var(--texto);
    font: inherit;
    font-size: 15px;
    line-height: 1.5;
    transition:
      opacity 0.3s ease-out,
      transform 0.3s ease-out,
      height 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275);
  }

  .escribiendo textarea {
    transition: height 0.15s ease-out;
  }

  .pildora textarea {
    opacity: 0;
    transform: translateY(-4px) scale(0.95);
    pointer-events: none;
  }

  textarea::placeholder {
    color: var(--tenue);
    opacity: 1;
  }

  .caja-pie {
    position: absolute;
    left: 12px;
    right: 52px;
    bottom: 7px;
    height: 32px;
    display: flex;
    align-items: center;
    gap: 12px;
  }

  /* En la píldora solo se queda el «+», a la izquierda del texto. */
  .pildora .caja-pie {
    pointer-events: none;
  }

  .pildora .mas {
    pointer-events: auto;
  }

  .hueco {
    flex: 1;
  }

  .pista {
    font-family: var(--mono);
    font-size: 10.5px;
    color: var(--tenue);
    white-space: nowrap;
    transition:
      opacity 0.3s ease,
      filter 0.3s ease,
      transform 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275);
  }

  .pildora .pista {
    opacity: 0;
    filter: blur(4px);
    transform: translateY(8px);
  }

  .mandar {
    position: absolute;
    right: 7px;
    bottom: 7px;
    width: 32px;
    height: 32px;
    display: grid;
    place-items: center;
    padding: 0;
    border: 0;
    /* Redondo en Simple y en Cristal, también como «Detener» (el developer, 13 nov 2026): la excepción a «ningún botón
       es círculo» (planes/trabajo/rediseno/reglas-diseno.md, «Los botones»). */
    border-radius: 50%;
    background: var(--mandar);
    color: var(--sobre-mandar);
    transition:
      background 0.15s ease,
      opacity 0.3s ease,
      filter 0.3s ease,
      transform 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275);
  }

  .mandar:disabled {
    background: var(--chip);
    color: var(--tenue);
    cursor: default;
  }

  /* Cristal, prendido: el «Metallic button» (diseno/Metal.svelte pone el metal, la cara y la onda; aquí, su aro de
     sombras quieto, encima y picado, y la flecha blanca con sombra encima del metal). Apagado sigue gris, como en
     Simple. */
  :global(:root[data-estilo='cristal']) .mandar:not(:disabled) {
    background: transparent;
    color: #ffffff;
    border: 0;
    overflow: hidden;
    box-shadow:
      0 0 0 1px rgba(0, 0, 0, 0.3),
      0 36px 14px 0 rgba(0, 0, 0, 0.02),
      0 20px 12px 0 rgba(0, 0, 0, 0.08),
      0 9px 9px 0 rgba(0, 0, 0, 0.12),
      0 2px 5px 0 rgba(0, 0, 0, 0.15);
    transition:
      box-shadow 0.15s cubic-bezier(0.4, 0, 0.2, 1),
      transform 0.8s cubic-bezier(0.34, 1.56, 0.64, 1);
  }

  :global(:root[data-estilo='cristal']) .mandar:not(:disabled):hover {
    box-shadow:
      0 0 0 1px rgba(0, 0, 0, 0.4),
      0 12px 6px 0 rgba(0, 0, 0, 0.05),
      0 8px 5px 0 rgba(0, 0, 0, 0.1),
      0 4px 4px 0 rgba(0, 0, 0, 0.15),
      0 1px 2px 0 rgba(0, 0, 0, 0.2);
  }

  :global(:root[data-estilo='cristal']) .mandar:not(:disabled):active {
    box-shadow:
      0 0 0 1px rgba(0, 0, 0, 0.5),
      0 1px 2px 0 rgba(0, 0, 0, 0.3);
    transform: translateY(1px) scale(0.98);
  }

  :global(:root[data-estilo='cristal']) .mandar:not(:disabled) .capa {
    z-index: 1;
  }

  :global(:root[data-estilo='cristal']) .mandar:not(:disabled) .capa :global(svg) {
    filter: drop-shadow(0 1px 2px rgba(0, 0, 0, 0.5));
  }

  /* Cristal oscuro: el «Aro» (el MetalButton de Spectrum UI), con un halo suave del color del metal; como su botón, al
     80 % con el mouse encima y a 0.97 al picar. */
  :global(:root[data-estilo='cristal'][data-tema='oscuro']) .mandar:not(:disabled) {
    box-shadow: 0 0 14px -3px rgba(136, 204, 255, 0.35);
    transition:
      transform 0.2s ease-out,
      opacity 0.2s ease-out;
  }

  :global(:root[data-estilo='cristal'][data-tema='oscuro']) .mandar:not(:disabled):hover {
    box-shadow: 0 0 14px -3px rgba(136, 204, 255, 0.35);
    opacity: 0.8;
  }

  :global(:root[data-estilo='cristal'][data-tema='oscuro']) .mandar:not(:disabled):active {
    box-shadow: 0 0 14px -3px rgba(136, 204, 255, 0.35);
    transform: scale(0.97);
  }

  /* En la píldora no se ve, salvo «Detener». */
  .pildora .mandar:not(.parando) {
    opacity: 0;
    filter: blur(4px);
    transform: translateY(8px);
    pointer-events: none;
  }

  .capa {
    position: absolute;
    inset: 0;
    display: grid;
    place-items: center;
    transition:
      opacity 200ms,
      transform 200ms;
  }

  .capa.parar,
  .parando .capa.flecha {
    opacity: 0;
    transform: scale(0.75);
  }

  .parando .capa.parar {
    opacity: 1;
    transform: none;
  }

  .mas-envoltura {
    position: relative;
    flex: none;
  }

  .mas {
    width: 32px;
    height: 32px;
    display: grid;
    place-items: center;
    padding: 0;
    border: 0;
    border-radius: 10px; /* rectángulo como los botones de ícono (9 nov 2026) */
    background: none;
    color: var(--suave);
  }

  .mas:hover:not(:disabled),
  .mas[aria-expanded='true'] {
    background: var(--chip);
    color: var(--texto);
  }

  .mas:disabled {
    opacity: 0.45;
    cursor: default;
  }

  .giro {
    display: grid;
    place-items: center;
  }

  .menu-mas {
    position: absolute;
    left: 0;
    top: calc(100% + 8px);
    z-index: 30;
    min-width: 220px;
    text-align: left;
    cursor: default;
    pointer-events: none;
  }

  .menu-mas.abierto {
    pointer-events: auto;
  }

  /* El fondo crece desde el «+» hasta lo que miden los renglones; hacia arriba en la conversación. */
  .menu-fondo {
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
      height 0.518s var(--resorte-fondo),
      opacity 0.25s ease,
      box-shadow 0.25s ease;
  }

  .menu-mas.arriba .menu-fondo {
    top: auto;
    bottom: 0;
  }

  .menu-mas.abierto .menu-fondo {
    height: var(--alto);
    opacity: 1;
    box-shadow: 0 14px 34px var(--sombra-menu);
  }

  .menu-renglones {
    position: relative;
    padding: 6px;
  }

  .renglon {
    opacity: 0;
    transform: translateY(var(--y)) scale(0.8);
    transition:
      transform 0.607s var(--resorte-opcion) var(--dc),
      opacity 0.3s ease var(--dc),
      background-color 150ms;
  }

  .menu-mas.abierto .renglon {
    opacity: 1;
    transform: none;
    transition:
      transform 0.607s var(--resorte-opcion) var(--da),
      opacity 0.3s ease var(--da),
      background-color 150ms;
  }

  .menu-mas.midiendo .renglon {
    transition: none;
  }

  .menu-mas.abierto .opcion:active {
    transform: scale(0.95);
    transition: transform 0.15s ease;
  }

  .menu-mas.arriba {
    top: auto;
    bottom: calc(100% + 8px);
  }

  .menu-mas.a-la-derecha {
    left: auto;
    right: 0;
  }

  .titulo-menu {
    display: flex;
    align-items: center;
    gap: 9px;
    padding: 8px 10px 6px;
    font-size: 13px;
    font-weight: 700;
  }

  .titulo-menu :global(svg) {
    color: var(--suave);
  }

  .opcion {
    display: block;
    width: 100%;
    padding: 8px 10px 8px 35px;
    border: 0;
    border-radius: 8px;
    background: none;
    color: var(--texto);
    font-size: 13.5px;
    text-align: left;
  }

  .opcion:hover {
    background: var(--chip);
  }

  /* Sin tope: el aviso, rectangular y del alto de su texto. */
  .caja-pregunta.tope {
    height: auto;
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 14px 14px 14px 18px;
    cursor: default;
  }

  .tope p {
    flex: 1;
    min-width: 0;
    margin: 0;
    font-size: 14.5px;
    font-weight: 500;
    line-height: 1.5;
  }

  .cuadro-icono {
    width: 32px;
    height: 32px;
    flex: none;
    display: grid;
    place-items: center;
    border-radius: 9px;
    background: var(--chip);
  }

  @media (prefers-reduced-motion: reduce) {
    .caja-pregunta,
    .caja-pregunta.escribiendo,
    .pildora-texto,
    textarea,
    .escribiendo textarea,
    .pista,
    .mandar,
    :global(:root[data-estilo='cristal']) .mandar:not(:disabled),
    .capa,
    .menu-fondo,
    .renglon,
    .menu-mas.abierto .renglon {
      transition: none;
    }
  }
</style>
