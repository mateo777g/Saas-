<!--
  La caja de la pregunta del Agente IA (maqueta Agente IA KznKZdgQbLTZGs1EwVMvga): el texto, el
  selector Hoy · Semana · Mes, «Enter envía · Shift+Enter salto» y el botón de mandar. En la
  bienvenida abre con dos renglones y en la conversación con uno; crece mientras se escribe, hasta
  seis. El periodo solo se le dice al modelo cuando la pregunta no trae el suyo (lo pone el
  Worker, como en Flet).

  Sin tope (`aviso`), en su lugar va el aviso de la libreta de Seguridad, con el icono de info.

  Mientras piensa la pregunta de esta conversación (`alDetener`), el botón de mandar es «Detener»
  (maqueta AyS4xUfa5XmDaPJG1iqSgw). Si piensa la de otra (`ocupado`), la flecha se apaga.
-->
<script lang="ts">
  import Icono from '../../../diseno/Icono.svelte';
  import Selector from '../../../diseno/Selector.svelte';
  import type { Periodo } from '../../../lib/agente';

  let {
    modo,
    valor = $bindable(''),
    periodo = $bindable<Periodo>('hoy'),
    placeholder,
    ocupado = false,
    aviso = null,
    alEnviar,
    alDetener = null,
  }: {
    modo: 'bienvenida' | 'chat';
    valor?: string;
    periodo?: Periodo;
    placeholder: string;
    ocupado?: boolean;
    aviso?: string | null;
    alEnviar: () => void;
    alDetener?: (() => void) | null;
  } = $props();

  const PERIODOS: { valor: Periodo; texto: string }[] = [
    { valor: 'hoy', texto: 'Hoy' },
    { valor: 'semana', texto: 'Semana' },
    { valor: 'mes', texto: 'Mes' },
  ];
  const id = $props.id();
  let campo = $state<HTMLTextAreaElement | null>(null);

  // Crece con lo escrito, de su alto inicial hasta seis renglones (24 px cada uno).
  $effect(() => {
    void valor;
    const c = campo;
    if (!c) return;
    c.style.height = 'auto';
    c.style.height = `${Math.min(c.scrollHeight, 24 * 6)}px`;
  });

  function alTeclear(e: KeyboardEvent) {
    if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
      e.preventDefault();
      if (!ocupado) alEnviar();
    }
  }

  export function enfocar() {
    campo?.focus();
  }

  // De dónde sale la burbuja de la pregunta al mandarla.
  export function medir(): DOMRect | null {
    return campo?.getBoundingClientRect() ?? null;
  }
</script>

{#if aviso}
  <div class="caja tope" role="status">
    <span class="cuadro-icono"><Icono nombre="info" tamano={18} /></span>
    <p>{aviso}</p>
  </div>
{:else}
  <div class="caja" class:en-chat={modo === 'chat'}>
    <label for={id} class="solo-lector">Tu pregunta</label>
    <textarea
      {id}
      bind:this={campo}
      bind:value={valor}
      rows={modo === 'chat' ? 1 : 2}
      {placeholder}
      onkeydown={alTeclear}
    ></textarea>
    <div class="fila">
      <Selector opciones={PERIODOS} elegida={periodo} alElegir={(p) => (periodo = p)} etiqueta="Periodo" />
      <span class="atajo">Enter envía · Shift+Enter salto</span>
      <span class="crece"></span>
      <button
        type="button"
        class="enviar"
        class:parando={!!alDetener}
        aria-label={alDetener ? 'Detener' : 'Enviar'}
        disabled={ocupado && !alDetener}
        onclick={alDetener ?? alEnviar}
      >
        <span class="capa mandar"><Icono nombre="flecha" tamano={20} /></span>
        <span class="capa parar"><Icono nombre="detener" tamano={20} /></span>
      </button>
    </div>
  </div>
{/if}

<style>
  .caja {
    position: relative;
    display: flex;
    flex-direction: column;
    gap: 18px;
    padding: 16px 16px 12px 20px;
    border-radius: 22px;
    border: 1px solid var(--linea);
    background: var(--solido);
    box-shadow: 0 10px 30px var(--sombra-caja);
  }

  .caja.en-chat {
    gap: 10px;
  }

  textarea {
    width: 100%;
    padding: 0;
    border: 0;
    outline: none;
    resize: none;
    background: transparent;
    color: var(--texto);
    font: inherit;
    font-size: 16px;
    line-height: 1.5;
  }

  textarea::placeholder {
    color: var(--tenue);
    opacity: 1;
  }

  .fila {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .atajo {
    font-family: var(--mono);
    font-size: 11px;
    color: var(--tenue);
    white-space: nowrap;
  }

  .crece {
    flex-grow: 1;
  }

  .enviar {
    position: relative;
    width: 44px;
    height: 44px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    border: 0;
    border-radius: 14px;
    background: var(--acento);
    color: var(--sobre-acento);
    transition: opacity 150ms;
  }

  .enviar:hover:not(:disabled) {
    opacity: 0.86;
  }

  .enviar:disabled {
    opacity: 0.4;
    cursor: default;
  }

  .capa {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    transition:
      opacity 200ms,
      transform 200ms;
  }

  .capa.parar,
  .parando .capa.mandar {
    opacity: 0;
    transform: scale(0.75);
  }

  .parando .capa.parar {
    opacity: 1;
    transform: none;
  }

  .caja.tope {
    flex-direction: row;
    align-items: center;
    gap: 14px;
    padding: 18px 20px;
  }

  .tope p {
    margin: 0;
    font-size: 15px;
    font-weight: 500;
    line-height: 1.5;
  }

  .cuadro-icono {
    width: 36px;
    height: 36px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 11px;
    background: var(--chip);
  }

  @media (prefers-reduced-motion: reduce) {
    .enviar,
    .capa {
      transition: none;
    }
  }
</style>
