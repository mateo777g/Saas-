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
  import Icono from '../../../diseno/Icono.svelte';
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

  // En la píldora, el «+» abre la caja con su menú.
  function picarMas() {
    if (!abierta && !aviso) {
      menuAbierto = true;
      abrir();
      return;
    }
    menuAbierto = !menuAbierto;
  }

  function elegir(periodo: PeriodoReporte) {
    menuAbierto = false;
    alReporte(periodo);
  }

  export function enfocar() {
    campo?.focus();
  }

  // De dónde sale la burbuja de la pregunta al mandarla.
  export function medir(): DOMRect | null {
    return (abierta ? campo : caja)?.getBoundingClientRect() ?? null;
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
      onclick={picarMas}
    >
      <Icono nombre="r-mas" tamano={18} />
    </button>
    {#if menuAbierto}
      <div class="menu-mas" class:arriba={modo === 'chat'} class:a-la-derecha={!!aviso}>
        <div class="titulo-menu"><Icono nombre="r-hoy" tamano={16} />Reporte en PDF</div>
        {#each PERIODOS_REPORTE as p (p.valor)}
          <button type="button" class="opcion" onclick={() => elegir(p.valor)}>{p.boton}</button>
        {/each}
      </div>
    {/if}
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
      disabled={alDetener ? false : ocupado || !valor.trim()}
      onclick={alDetener ?? mandar}
    >
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
    border-radius: 10px; /* rectángulo como los botones de ícono (9 nov 2026) */
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

  .menu-mas {
    position: absolute;
    left: 0;
    top: calc(100% + 8px);
    z-index: 30;
    min-width: 220px;
    padding: 6px;
    border: 1px solid var(--linea-fuerte);
    border-radius: 12px;
    background: var(--solido);
    box-shadow: 0 14px 34px var(--sombra-menu);
    text-align: left;
    cursor: default;
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
    .capa {
      transition: none;
    }
  }
</style>
