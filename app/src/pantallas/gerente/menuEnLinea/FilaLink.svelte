<!--
  La fila de «Tu link y tu QR» (maqueta UDArhiEZceT7rmSKxqRA5r v59): su nombre arriba y abajo, en un renglón, el link
  con «Copiar», «Ver» y el botón del QR. El QR sale de su botón (21dev, planes/trabajo/rediseno/21dev/): crece desde
  arriba, debajo y al centro (0.75 → 1, 0.3 s) al pasar el mouse, al llegarle con el teclado o al picarlo, y el mouse
  puede cruzar a su tarjeta; se va al salir o al picar afuera. Mientras la vista lee la primera vez, el link y sus
  botones van en esqueleto.
-->
<script lang="ts">
  import Boton from '../../../diseno/Boton.svelte';
  import Esqueleto from '../../../diseno/Esqueleto.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import { pista } from '../../../diseno/pista';
  import { HOST_MENU } from '../../../lib/vistaMenu';
  import Fila from './Fila.svelte';
  import QrMenu from './QrMenu.svelte';

  let {
    slug,
    link,
    cargando,
    alCopiar,
    alBajarQr,
  }: {
    slug: string;
    link: string;
    cargando: boolean;
    alCopiar: () => Promise<boolean>;
    alBajarQr: () => void;
  } = $props();

  const QR =
    '<rect width="5" height="5" x="3" y="3" rx="1"></rect><rect width="5" height="5" x="16" y="3" rx="1"></rect><rect width="5" height="5" x="3" y="16" rx="1"></rect><path d="M21 16h-3a2 2 0 0 0-2 2v3"></path><path d="M21 21v.01"></path><path d="M12 7v3a2 2 0 0 1-2 2H7"></path><path d="M3 12h.01"></path><path d="M12 3h.01"></path><path d="M12 16v.01"></path><path d="M16 12h1"></path><path d="M21 12v.01"></path><path d="M12 21v-1"></path>';

  let copiado = $state(false);
  let abierto = $state(false);
  let caja = $state<HTMLDivElement>();

  async function copiar() {
    if (!(await alCopiar())) return;
    copiado = true;
    setTimeout(() => (copiado = false), 1600);
  }

  function salir(e: MouseEvent) {
    if (!caja?.contains(e.relatedTarget as Node | null)) abierto = false;
  }
</script>

<svelte:window
  onpointerdown={(e) => {
    if (abierto && !caja?.contains(e.target as Node)) abierto = false;
  }}
  onkeydowncapture={(e) => {
    // Escape cierra el QR antes que lo abierto en el teléfono (la vista no hace nada si ya se usó).
    if (abierto && e.key === 'Escape' && !document.querySelector('dialog[open]')) {
      e.preventDefault();
      abierto = false;
    }
  }}
/>

<Fila clave="link" icono="celular" titulo="Tu link y tu QR" nota="Ponlo en tu Instagram, tu WhatsApp y Google Maps.">
  <div class="renglon">
    {#if cargando}
      <span class="crece"><Esqueleto ancho="100%" alto="40px" redondo="12px" /></span>
      <Esqueleto ancho="96px" alto="40px" redondo="12px" />
      <Esqueleto ancho="75px" alto="40px" redondo="12px" />
      <Esqueleto ancho="40px" alto="40px" redondo="12px" />
    {:else}
      <div class="link"><span class="mono">{HOST_MENU}/<b>{slug}</b></span></div>
      <Boton etiqueta={copiado ? 'Copiado' : 'Copiar'} icono="copiar" exito={copiado} onclick={copiar} />
      <Boton etiqueta="Ver" icono="afuera" onclick={() => window.open(link, '_blank', 'noopener')} />
      <!-- svelte-ignore a11y_no_static_element_interactions -->
      <div
        class="qr"
        class:abierto
        bind:this={caja}
        onmouseenter={() => (abierto = true)}
        onmouseleave={salir}
        onfocusin={() => (abierto = true)}
        onfocusout={(e) => {
          if (!caja?.contains(e.relatedTarget as Node | null)) abierto = false;
        }}
      >
        <button
          type="button"
          class="cuadro"
          aria-label="Ver el QR"
          aria-expanded={abierto}
          use:pista={abierto ? null : 'Ver el QR'}
          onclick={(e) => {
            // Con el mouse ya está abierto al picarlo: el clic lo cierra; con el teclado (detail 0), lo abre.
            abierto = e.detail ? !abierto : true;
          }}
        >
          <Icono nombre="qr" trazos={QR} tamano={16} />
        </button>
        <div class="tarjeta-qr" role="dialog" aria-label="El QR de tu menú" inert={!abierto}>
          <QrMenu texto={link} />
          <p>Imprime el QR para tus mesas: al escanearlo se abre tu menú.</p>
          <Boton etiqueta="Descargar QR" icono="exportar" tamano="chico" onclick={alBajarQr} />
        </div>
      </div>
    {/if}
  </div>
</Fila>

<style>
  .renglon {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .crece {
    flex: 1;
    min-width: 0;
    display: flex;
  }

  .link {
    flex: 1;
    min-width: 0;
    height: 40px;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 14px;
    border: 1px solid var(--linea);
    border-radius: 12px;
  }

  .link .mono {
    flex: 1;
    min-width: 0;
    font-size: 13.5px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .link b {
    font-weight: 600;
  }

  .qr {
    position: relative;
    flex: none;
  }

  /* Como BotonCuadro grande: 40 × 40, borde fino y esquinas de 12. */
  .cuadro {
    width: 40px;
    height: 40px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    padding: 0;
    border: 1px solid var(--linea);
    border-radius: 12px;
    background: transparent;
    color: var(--texto);
    transition: background-color 150ms;
  }

  .cuadro:hover,
  .abierto > .cuadro {
    background: var(--chip);
  }

  .tarjeta-qr {
    position: absolute;
    left: 50%;
    top: calc(100% + 12px);
    width: 236px;
    margin-left: -118px;
    z-index: 30;
    padding: 16px;
    box-sizing: border-box;
    background: var(--solido);
    border: 1px solid var(--borde-tarjeta);
    border-radius: 14px;
    box-shadow: 0 18px 40px var(--sombra-menu);
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 12px;
    text-align: center;
    opacity: 0;
    visibility: hidden;
    transform: scale(0.75);
    transform-origin: top center;
    pointer-events: none;
    transition:
      opacity 0.3s ease-in-out,
      transform 0.3s ease-in-out,
      visibility 0.3s ease-in-out;
  }

  /* El puente entre el botón y la tarjeta, para que el mouse cruce sin que se cierre. */
  .tarjeta-qr::before {
    content: '';
    position: absolute;
    left: 0;
    right: 0;
    top: -14px;
    height: 14px;
  }

  .abierto .tarjeta-qr {
    opacity: 1;
    visibility: visible;
    transform: scale(1);
    pointer-events: auto;
  }

  .tarjeta-qr :global(.qr) {
    width: 168px;
    height: 168px;
    padding: 10px;
  }

  .tarjeta-qr p {
    margin: 0;
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  @media (prefers-reduced-motion: reduce) {
    .tarjeta-qr {
      transition: none;
    }
  }
</style>
