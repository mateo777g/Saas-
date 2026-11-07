<!--
  El cuadro «Foto de tu menú» de la ventana de producto (maqueta de Mi menú U9YqpsSb2PeB5pFXTPvh1C,
  versiones 2, 3 y 13): a la derecha de los campos, para arrastrar la foto o picarle y elegirla. Sin foto
  lleva la figura Riffle de @lucasmarkes/hairline (se trae solo aquí, con import dinámico); sus tarjetas se
  mueven solas mientras arrastras una foto encima, y con «reducir movimiento» se queda quieta. Con foto,
  la foto llena el cuadro (se recorta lo que sobra, como en el menú en línea) y abajo a la derecha sale
  «Cambiar foto», siempre claro, que se alarga hacia la izquierda con el mouse en cualquier parte de la
  foto (toda la foto es el botón). Un envío no lleva foto: el cuadro se queda en gris y lo dice, para que
  la ventana no brinque.
-->
<script lang="ts">
  import { onDestroy, onMount } from 'svelte';

  let {
    src,
    envio = false,
    apagado = false,
    alElegir,
  }: { src: string | null; envio?: boolean; apagado?: boolean; alElegir: (archivo: File) => void } = $props();

  let caja = $state<HTMLDivElement>();
  let entrada = $state<HTMLInputElement>();
  let figura = $state<HTMLDivElement>();
  let arrastrando = $state(false);
  let texto = $state<HTMLSpanElement>();
  let ancho = $state(150);

  type Figura = { update(o: { theme?: 'light' | 'dark'; play?: boolean }): void; destroy(): void };
  let riffle: Figura | null = null;
  let montando = false;

  const temaFigura = () => (document.documentElement.dataset.tema === 'oscuro' ? 'dark' : 'light');

  // La figura va mientras no haya foto; se quita al poner una.
  $effect(() => {
    const el = figura;
    if (!el || riffle || montando) return;
    montando = true;
    import('../../../lib/riffle')
      .then((m) => {
        montando = false;
        if (!el.isConnected) return;
        riffle = m.riffle(el, { theme: temaFigura(), label: 'Tus archivos', play: arrastrando });
        el.tabIndex = -1;
      })
      .catch((falla) => {
        montando = false;
        console.error('[menu] no cargó la figura de la foto:', falla);
      });
  });
  $effect(() => {
    if (!figura && riffle) {
      riffle.destroy();
      riffle = null;
    }
  });
  $effect(() => {
    riffle?.update({ play: arrastrando });
  });

  // Sigue al tema del panel (su «auto» no lee data-tema).
  let vigia: MutationObserver | undefined;
  onMount(() => {
    vigia = new MutationObserver(() => riffle?.update({ theme: temaFigura() }));
    vigia.observe(document.documentElement, { attributes: true, attributeFilter: ['data-tema'] });
  });
  // «Cambiar foto» se alarga justo lo que mide su texto (12 + 32 + texto + 8 + 12 px), como Boton.
  (() => {
    const el = texto;
    if (!el) return;
    const medir = () => (ancho = Math.ceil(el.getBoundingClientRect().width - 8) + 64);
    medir();
    document.fonts?.ready.then(medir).catch((falla) => console.error('[menu] no se pudieron medir las letras', falla));
  });
  onDestroy(() => {
    vigia?.disconnect();
    riffle?.destroy();
    riffle = null;
  });

  function elegir() {
    if (!apagado && !envio) entrada?.click();
  }

  function alTeclear(e: KeyboardEvent) {
    if (e.target !== caja) return;
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      elegir();
    }
  }

  function alCambiar(e: Event & { currentTarget: HTMLInputElement }) {
    const archivo = e.currentTarget.files?.[0];
    e.currentTarget.value = '';
    if (archivo) alElegir(archivo);
  }

  function encima(e: DragEvent) {
    if (envio || apagado) return;
    e.preventDefault();
    arrastrando = true;
  }

  function fuera(e: DragEvent) {
    if (caja && !caja.contains(e.relatedTarget as Node | null)) arrastrando = false;
  }

  function soltar(e: DragEvent) {
    if (envio || apagado) return;
    e.preventDefault();
    arrastrando = false;
    const archivo = e.dataTransfer?.files[0];
    if (archivo) alElegir(archivo);
  }
</script>

{#if envio}
  <div class="caja-foto sin-foto">
    <span class="cf-icono"
      ><svg viewBox="0 0 24 24" width="28" height="28" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"
        ><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"></path><path d="M14 3v5h5"></path></svg
      ></span
    >
    <b>Un envío no lleva foto</b>
  </div>
{:else}
  <div
    class="caja-foto"
    class:arrastrando
    class:apagado
    role="button"
    tabindex="0"
    aria-label="Foto de tu menú"
    aria-disabled={apagado}
    bind:this={caja}
    onclick={elegir}
    onkeydown={alTeclear}
    ondragenter={encima}
    ondragover={encima}
    ondragleave={fuera}
    ondrop={soltar}
  >
    {#if src}
      <img {src} alt="" />
      <span class="cf-cambiar boton-alarga" style:--ba-ancho="{ancho}px">
        <svg class="ba-icono" viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"
          ><rect x="3" y="3" width="18" height="18" rx="2"></rect><circle cx="9" cy="9" r="2"></circle><path d="M21 15l-5-5L5 21"></path></svg
        >
        <span class="ba-texto" bind:this={texto}>Cambiar foto</span>
      </span>
    {:else}
      <div class="cf-riffle" aria-hidden="true" bind:this={figura}></div>
      <b>Foto de tu menú</b>
      <span class="cf-texto">{arrastrando ? 'Suéltala aquí.' : 'Arrástrala aquí o haz clic para elegirla.'}</span>
      <span class="cf-pista">JPG o PNG · se optimiza automáticamente</span>
    {/if}
    <input bind:this={entrada} type="file" accept="image/*" hidden onchange={alCambiar} />
  </div>
{/if}

<style>
  .caja-foto {
    position: relative;
    min-height: 420px;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 8px;
    padding: 24px;
    box-sizing: border-box;
    overflow: hidden;
    border: 1.5px dashed var(--linea-fuerte);
    border-radius: 16px;
    background: var(--chip);
    color: var(--texto);
    text-align: center;
    cursor: pointer;
    transition:
      border-color 0.15s ease,
      background 0.15s ease;
  }

  .caja-foto:hover {
    border-color: var(--suave);
  }

  .caja-foto:focus-visible {
    outline: 2px solid var(--acento);
    outline-offset: 2px;
  }

  .caja-foto.apagado {
    cursor: default;
  }

  .caja-foto b {
    font-size: 15px;
    font-weight: 700;
  }

  .cf-icono {
    width: 60px;
    height: 60px;
    margin-bottom: 6px;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 16px;
    background: var(--solido);
    border: 1px solid var(--borde-tarjeta);
    color: var(--suave);
  }

  .cf-texto {
    font-size: 13px;
    font-weight: 500;
    color: var(--suave);
  }

  .cf-pista {
    margin-top: 4px;
    font-size: 12px;
    font-weight: 500;
    color: var(--tenue);
  }

  .caja-foto.arrastrando {
    border-style: solid;
    border-color: var(--acento);
    background: color-mix(in srgb, var(--acento) 10%, transparent);
  }

  .caja-foto:has(img) {
    padding: 0;
    border-style: solid;
    border-color: var(--borde-tarjeta);
  }

  .caja-foto img {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    max-width: none;
    object-fit: cover;
  }

  .caja-foto.sin-foto {
    cursor: default;
    border-style: solid;
    border-color: var(--linea);
    color: var(--suave);
  }

  .caja-foto.sin-foto:hover {
    border-color: var(--linea);
  }

  .caja-foto.sin-foto b {
    font-weight: 600;
    font-size: 14px;
  }

  .cf-riffle {
    width: 250px;
    aspect-ratio: 5 / 4;
    margin-bottom: 2px;
    color: var(--suave);
  }

  .cf-riffle:focus,
  .cf-riffle :global(*:focus) {
    outline: none;
  }

  /* «Cambiar foto», el botón que se alarga (como Boton alarga), siempre claro y con su sombrita. */
  .boton-alarga {
    --ba-fondo: #ffffff;
    --ba-letra: #0b0b0b;
    --ba-curva: cubic-bezier(0.4, 0, 0.2, 1);
    position: absolute;
    right: 12px;
    bottom: 12px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    box-sizing: border-box;
    width: 40px;
    height: 40px;
    padding: 0 12px;
    overflow: hidden;
    border: 0;
    border-radius: 999px;
    background: var(--ba-fondo);
    color: var(--ba-letra);
    font: 600 13.5px var(--jakarta);
    white-space: nowrap;
    box-shadow: 0 2px 10px rgba(0, 0, 0, 0.18);
    transition: width 0.3s var(--ba-curva);
  }

  .ba-icono {
    position: absolute;
    top: 50%;
    left: 50%;
    width: 16px;
    height: 16px;
    transform: translate(-50%, -50%);
    transition: transform 0.3s var(--ba-curva);
  }

  .ba-texto {
    margin-left: 32px;
    padding-right: 8px;
    white-space: nowrap;
    opacity: 0;
    transition: opacity 0.3s var(--ba-curva);
  }

  .caja-foto:not(.apagado):hover .boton-alarga,
  .caja-foto:focus-visible .boton-alarga {
    width: var(--ba-ancho);
    background: color-mix(in srgb, var(--ba-fondo) 90%, transparent);
  }

  .caja-foto:not(.apagado):hover .ba-icono,
  .caja-foto:focus-visible .ba-icono {
    left: 12px;
    transform: translate(0, -50%);
  }

  .caja-foto:not(.apagado):hover .ba-texto,
  .caja-foto:focus-visible .ba-texto {
    opacity: 1;
  }

  @media (prefers-reduced-motion: reduce) {
    .boton-alarga,
    .boton-alarga * {
      transition: none !important;
    }
  }
</style>
