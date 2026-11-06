<!--
  La caja de la pregunta del Agente IA (rediseño del 5 de noviembre de 2026; maqueta V64Pv4gmANPRZuJW5hTe5D):
  el texto, el «+» con «Reporte en PDF», «Enter envía · Shift+Enter salto» y el botón de mandar, que se
  prende en el acento cuando hay texto. En la bienvenida abre con dos renglones y en la conversación con
  uno; crece mientras se escribe, hasta seis.

  Sin tope (`aviso`), en su lugar va el aviso de la libreta de Seguridad, con el icono de info y el «+» a
  su lado: el reporte no usa IA (planes/trabajo/rediseno/encuestas-agente.md).

  Mientras piensa la pregunta de esta conversación (`alDetener`), el botón de mandar es «Detener»
  (maqueta AyS4xUfa5XmDaPJG1iqSgw). Si piensa la de otra (`ocupado`), la flecha se apaga.
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
    alEnviar,
    alDetener = null,
    alReporte,
  }: {
    modo: 'bienvenida' | 'chat';
    valor?: string;
    placeholder: string;
    ocupado?: boolean;
    aviso?: string | null;
    alEnviar: () => void;
    alDetener?: (() => void) | null;
    alReporte: (periodo: PeriodoReporte) => void;
  } = $props();

  const id = $props.id();
  // Seis renglones de 22.5 px.
  const ALTO_MAXIMO = 135;

  let campo = $state<HTMLTextAreaElement | null>(null);
  let envoltura = $state<HTMLDivElement | null>(null);
  let menuAbierto = $state(false);

  // Crece con lo escrito, de su alto inicial hasta seis renglones.
  $effect(() => {
    void valor;
    const c = campo;
    if (!c) return;
    c.style.height = 'auto';
    c.style.height = `${Math.min(c.scrollHeight, ALTO_MAXIMO)}px`;
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

  function alTeclear(e: KeyboardEvent) {
    if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
      e.preventDefault();
      if (!ocupado) alEnviar();
    }
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
    return campo?.getBoundingClientRect() ?? null;
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
      onclick={() => (menuAbierto = !menuAbierto)}
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
  <div class="caja-pregunta">
    <label for={id} class="solo-lector">Tu pregunta</label>
    <textarea
      {id}
      bind:this={campo}
      bind:value={valor}
      rows={modo === 'chat' ? 1 : 2}
      {placeholder}
      onkeydown={alTeclear}
    ></textarea>
    <div class="caja-pie">
      {@render mas()}
      <span class="hueco"></span>
      <span class="pista">Enter envía · Shift+Enter salto</span>
      <button
        type="button"
        class="mandar"
        class:parando={!!alDetener}
        aria-label={alDetener ? 'Detener' : 'Mandar la pregunta'}
        disabled={alDetener ? false : ocupado || !valor.trim()}
        onclick={alDetener ?? alEnviar}
      >
        <span class="capa flecha"><Icono nombre="r-arriba" tamano={17} /></span>
        <span class="capa parar"><Icono nombre="detener" tamano={17} /></span>
      </button>
    </div>
  </div>
{/if}

<style>
  .caja-pregunta {
    position: relative;
    display: flex;
    flex-direction: column;
    gap: 10px;
    padding: 14px 14px 12px 18px;
    border: 1px solid var(--linea-fuerte);
    border-radius: 18px;
    background: var(--solido);
  }

  .caja-pregunta:focus-within {
    border-color: var(--texto);
  }

  textarea {
    width: 100%;
    min-height: 48px;
    padding: 2px;
    border: 0;
    outline: none;
    resize: none;
    background: none;
    color: var(--texto);
    font: inherit;
    font-size: 15px;
    line-height: 1.5;
  }

  textarea::placeholder {
    color: var(--tenue);
    opacity: 1;
  }

  .caja-pie {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .hueco {
    flex: 1;
  }

  .pista {
    font-family: var(--mono);
    font-size: 10.5px;
    color: var(--tenue);
    white-space: nowrap;
  }

  .mandar {
    position: relative;
    width: 36px;
    height: 36px;
    flex: none;
    display: grid;
    place-items: center;
    padding: 0;
    border: 0;
    border-radius: 10px;
    background: var(--acento);
    color: var(--sobre-acento);
    transition: background 0.15s ease;
  }

  .mandar:disabled {
    background: var(--chip);
    color: var(--tenue);
    cursor: default;
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
    width: 34px;
    height: 34px;
    display: grid;
    place-items: center;
    padding: 0;
    border: 1px solid var(--linea);
    border-radius: 10px;
    background: none;
    color: var(--suave);
  }

  .mas:hover:not(:disabled),
  .mas[aria-expanded='true'] {
    border-color: var(--linea-fuerte);
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

  .caja-pregunta.tope {
    flex-direction: row;
    align-items: center;
    gap: 14px;
    padding: 14px 14px 14px 18px;
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
    .mandar,
    .capa {
      transition: none;
    }
  }
</style>
