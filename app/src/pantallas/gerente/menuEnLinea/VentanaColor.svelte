<!--
  «Color de tu menú» (maqueta de la 6a Qx4C5CbKJYpeAsJCfw4ghn, estado «Eligiendo color»; libreta 6,
  decidido el 20 de octubre de 2026): el selector de los flyers de Flet. El cuadro cambia la
  saturación y el brillo, la barra el tono, y el código se puede escribir. Debajo, la barra de su menú
  con ese color; avisa cuando las letras van oscuras y cuando el color casi no se ve en su tema.
  «Usar este color» todavía no guarda: lo guarda el «Guardar» de Cómo se ve.
-->
<script lang="ts">
  import Boton from '../../../diseno/Boton.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import Ventana from '../../../diseno/Ventana.svelte';
  import { casiNoSeVe, esClaro, hexAHsv, hsvAHex, leerCodigo, type TemaMenu } from '../../../lib/color';
  import Muestra from './Muestra.svelte';

  let {
    inicial,
    tema,
    slug,
    tipoCambio,
    alUsar,
    alCerrar,
  }: {
    inicial: string | null;
    tema: TemaMenu;
    slug: string;
    tipoCambio: number | null;
    alUsar: (color: string | null) => void;
    alCerrar: () => void;
  } = $props();

  // svelte-ignore state_referenced_locally
  let hsv = $state<[number, number, number]>(hexAHsv(inicial ?? '#B3261E'));
  // svelte-ignore state_referenced_locally
  let codigo = $state(inicial ?? '#B3261E');

  const hex = $derived(hsvAHex(hsv[0], hsv[1], hsv[2]));
  const claro = $derived(esClaro(hex));
  const casi = $derived(casiNoSeVe(hex, tema));

  // Arrastrar en el cuadro o en la barra; el código se pone al color que sale.
  function arrastrar(e: PointerEvent, al: (x: number, y: number) => void) {
    const el = e.currentTarget as HTMLElement;
    el.setPointerCapture(e.pointerId);
    const mover = (ev: PointerEvent) => {
      const r = el.getBoundingClientRect();
      al(Math.max(0, Math.min(1, (ev.clientX - r.left) / r.width)), Math.max(0, Math.min(1, (ev.clientY - r.top) / r.height)));
      codigo = hsvAHex(hsv[0], hsv[1], hsv[2]);
    };
    const soltar = () => {
      el.removeEventListener('pointermove', mover);
      el.removeEventListener('pointerup', soltar);
      el.removeEventListener('pointercancel', soltar);
    };
    mover(e);
    el.addEventListener('pointermove', mover);
    el.addEventListener('pointerup', soltar);
    el.addEventListener('pointercancel', soltar);
  }

  function alEscribir() {
    const v = leerCodigo(codigo);
    if (v) hsv = hexAHsv(v);
  }
</script>

<Ventana titulo="Color de tu menú" nota="Pinta la barra de arriba, la raya de la categoría y los botones." ancho={440} {alCerrar}>
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div class="sv" style:background={hsvAHex(hsv[0], 1, 1)} onpointerdown={(e) => arrastrar(e, (x, y) => (hsv = [hsv[0], x, 1 - y]))}>
    <div class="blanco"></div>
    <div class="negro"></div>
    <span class="perilla" style:left="{hsv[1] * 100}%" style:top="{(1 - hsv[2]) * 100}%" style:background={hex}></span>
  </div>
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div class="tono" onpointerdown={(e) => arrastrar(e, (x) => (hsv = [x * 359.9, hsv[1], hsv[2]]))}>
    <span class="perilla" style:left="{(hsv[0] / 360) * 100}%" style:background={hsvAHex(hsv[0], 1, 1)}></span>
  </div>
  <div class="codigo-fila">
    <span class="gota" style:background={hex}></span>
    <input bind:value={codigo} oninput={alEscribir} maxlength="7" aria-label="Código del color" autocomplete="off" spellcheck="false" />
    <span class="nota">Escríbelo si ya lo tienes, como el de tu logo.</span>
  </div>
  <div class="probar">
    <Muestra {slug} como="barra" muestra={{ tema, color: hex, tipo_cambio_usd: tipoCambio }} />
  </div>
  {#if claro}
    <p class="aviso"><Icono nombre="info" tamano={16} /><span>Sobre este color las letras van <b>oscuras</b>, para que se lean.</span></p>
  {/if}
  {#if casi}
    <p class="aviso">
      <Icono nombre="alerta" tamano={16} /><span
        ><b>Este color casi no se ve en tu menú {tema}.</b> Escoge uno más {tema === 'claro' ? 'oscuro' : 'claro'} o cambia el tema.</span
      >
    </p>
  {/if}
  <div class="pie">
    <Boton etiqueta="Quitar color" onclick={() => alUsar(null)} />
    <span class="crece"></span>
    <Boton etiqueta="Usar este color" icono="check-delgado" tono="tinta" onclick={() => alUsar(hex)} />
  </div>
</Ventana>

<style>
  .sv {
    position: relative;
    margin-top: 22px;
    height: 196px;
    border-radius: 14px;
    overflow: hidden;
    cursor: crosshair;
    touch-action: none;
  }

  .blanco {
    position: absolute;
    inset: 0;
    background: linear-gradient(to right, #fff, rgba(255, 255, 255, 0));
  }

  .negro {
    position: absolute;
    inset: 0;
    background: linear-gradient(to top, #000, rgba(0, 0, 0, 0));
  }

  .perilla {
    position: absolute;
    width: 18px;
    height: 18px;
    margin: -9px 0 0 -9px;
    border-radius: 50%;
    border: 2.5px solid #fff;
    box-shadow:
      0 0 0 1px rgba(0, 0, 0, 0.35),
      0 2px 6px rgba(0, 0, 0, 0.3);
    pointer-events: none;
  }

  .tono {
    position: relative;
    margin-top: 14px;
    height: 14px;
    border-radius: 7px;
    background: linear-gradient(to right, #f00, #ff0, #0f0, #0ff, #00f, #f0f, #f00);
    cursor: pointer;
    touch-action: none;
  }

  .tono .perilla {
    top: 7px;
  }

  .codigo-fila {
    margin-top: 16px;
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .gota {
    width: 44px;
    height: 44px;
    border-radius: 12px;
    border: 1px solid var(--linea-fuerte);
    flex: none;
  }

  input {
    height: 44px;
    width: 130px;
    flex: none;
    padding: 0 14px;
    border: 1px solid var(--linea);
    border-radius: 12px;
    background: transparent;
    color: var(--texto);
    font-family: var(--mono);
    font-size: 14px;
    text-transform: uppercase;
    outline: none;
  }

  input:focus {
    border-color: var(--suave);
  }

  .nota {
    margin: 0;
    font-size: 12.5px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .probar {
    margin-top: 16px;
    border-radius: 16px;
    border: 1px solid var(--linea);
    overflow: hidden;
  }

  .aviso {
    display: flex;
    align-items: flex-start;
    gap: 10px;
    margin: 12px 0 0;
    padding: 11px 14px;
    border-radius: 12px;
    background: var(--chip);
    font-size: 12.5px;
    line-height: 1.5;
    color: var(--suave);
  }

  .aviso :global(svg) {
    flex: none;
    margin-top: 2px;
  }

  .aviso b {
    color: var(--texto);
    font-weight: 600;
  }

  .pie {
    margin-top: 20px;
    display: flex;
    gap: 10px;
  }

  .crece {
    flex-grow: 1;
  }
</style>
