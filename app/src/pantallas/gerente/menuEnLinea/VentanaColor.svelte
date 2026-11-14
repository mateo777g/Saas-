<!--
  La ventana del color de «Tu menú en línea» (maqueta UDArhiEZceT7rmSKxqRA5r v59, abrirColor; antes, la de la 6a
  Qx4C5CbKJYpeAsJCfw4ghn): el selector de los flyers de Flet para el color de tu menú, el de la barra o el fondo. El
  cuadro cambia la saturación y el brillo, la barra el tono, y el código se puede escribir. Debajo, su menú con ese
  color (Muestra.svelte, la tira) y el aviso si casi no se ve. Como las ventanas del gerente: lo que quita en el rojo de
  contorno y lo que usa en verde. «Usar este color» todavía no guarda: lo guarda la barra de guardar.
-->
<script lang="ts">
  import Boton from '../../../diseno/Boton.svelte';
  import GrupoCampos from '../../../diseno/GrupoCampos.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import Ventana from '../../../diseno/Ventana.svelte';
  import { hexAHsv, hsvAHex, leerCodigo } from '../../../lib/color';
  import type { Formas } from '../../../lib/formasMenu';
  import { avisoDeColor, type ClaveColor, type Colores } from './colores';
  import Muestra from './Muestra.svelte';

  let {
    clave,
    colores,
    formas,
    slug,
    alUsar,
    alCerrar,
  }: {
    clave: ClaveColor;
    // Lo que va hoy en el teléfono (sin guardar): el color que se prueba se pone encima.
    colores: Colores;
    formas: Formas;
    slug: string;
    alUsar: (color: string | null) => void;
    alCerrar: () => void;
  } = $props();

  // svelte-ignore state_referenced_locally
  const TEXTOS = {
    color: { titulo: 'Color de tu menú', nota: 'Pinta lo que está elegido, el «+» y los botones.', quitar: 'Quitar color', usar: 'Usar este color' },
    colorBarra: { titulo: 'Color de la barra', nota: 'La barra de arriba y las cajas de tu menú.', quitar: 'Usar el de tu menú', usar: 'Usar este color' },
    fondo: { titulo: 'Fondo de tu menú', nota: 'El fondo de todo tu menú. Las letras siguen al tema.', quitar: 'Quitar fondo', usar: 'Usar este fondo' },
  }[clave];

  // Sin color todavía, el selector arranca en uno de muestra (el de la barra, en el de tu menú).
  // svelte-ignore state_referenced_locally
  const inicial = colores[clave] ?? (clave === 'fondo' ? '#F4EBDD' : clave === 'colorBarra' ? (colores.color ?? '#121212') : '#B3261E');
  let hsv = $state<[number, number, number]>(hexAHsv(inicial));
  let codigo = $state(inicial);

  const hex = $derived(hsvAHex(hsv[0], hsv[1], hsv[2]));
  const probando = $derived({ ...colores, [clave]: hex } as Colores);
  const aviso = $derived(avisoDeColor(clave, probando));

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

<Ventana centrado titulo={TEXTOS.titulo} nota={TEXTOS.nota} ancho={440} {alCerrar}>
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
  <div class="codigo-grupo">
    <GrupoCampos>
      <div class="codigo-fila">
        <span class="gota" style:background={hex}></span>
        <input bind:value={codigo} oninput={alEscribir} maxlength="7" aria-label="Código del color" autocomplete="off" spellcheck="false" />
        <span class="nota">Escríbelo si ya lo tienes, como el de tu logo.</span>
      </div>
    </GrupoCampos>
  </div>
  <div class="probar">
    <Muestra {slug} tira={clave} muestra={{ tema: probando.tema, color: probando.color, colorBarra: probando.colorBarra, fondo: probando.fondo, formas }} />
  </div>
  {#if aviso}
    <p class="aviso"><Icono nombre="alerta" tamano={16} /><span><b>{aviso.fuerte}</b> {aviso.texto}</span></p>
  {/if}
  <div class="pie">
    <Boton etiqueta={TEXTOS.quitar} icono="cerrar" tono="peligro" onclick={() => alUsar(null)} />
    <span class="crece"></span>
    <Boton etiqueta={TEXTOS.usar} tono="verde" onclick={() => alUsar(hex)} />
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

  /* El código va en su gris (GrupoCampos, 9 nov 2026); el espacio de arriba pasa al grupo. */
  .codigo-grupo {
    margin-top: 16px;
  }

  .codigo-fila {
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
    border: 0;
    border-radius: 12px;
    background: var(--campo-fondo);
    box-shadow: var(--campo-sombra);
    color: var(--texto);
    font-family: var(--mono);
    font-size: 14px;
    text-transform: uppercase;
    outline: none;
    transition:
      background-color 0.15s ease,
      box-shadow 0.15s ease-out;
  }

  /* Como las cajas de texto (diseno/Campo.svelte, el Input de HeroUI), desde el 9 nov 2026. */
  input:hover:not(:focus) {
    background: var(--campo-encima);
  }

  input:focus {
    box-shadow: 0 0 0 2px var(--campo-aro);
  }

  @media (prefers-reduced-motion: reduce) {
    input {
      transition: none;
    }
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
  }

  .aviso {
    display: flex;
    align-items: flex-start;
    gap: 10px;
    margin: 12px 0 0;
    padding: 11px 14px;
    border-radius: 12px;
    background: var(--amarillo-fondo);
    font-size: 12.5px;
    line-height: 1.5;
    color: var(--suave);
  }

  .aviso :global(svg) {
    flex: none;
    margin-top: 2px;
    color: var(--amarillo-texto);
  }

  .aviso b {
    color: var(--texto);
    font-weight: 600;
  }

  .pie {
    margin-top: 24px;
    display: flex;
    gap: 10px;
  }

  .crece {
    flex-grow: 1;
  }
</style>
