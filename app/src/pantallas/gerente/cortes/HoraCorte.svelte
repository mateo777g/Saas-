<!--
  La hora de corte en Cortes y reportes (12 nov 2026; maqueta FiHkjmT1meyTu7zuU3En2n, «Vista: Cortes», versión 37,
  aprobada como provisional: cuando Cortes tenga su rediseño, el botón se puede mover). Salió de Ajustes por encuesta
  (planes/trabajo/estilo-cristal/ajustes.md): aquí se ve lo que hace, a qué día pertenece cada venta.

  Un botón en la barra de arriba, justo antes de la cajita de la sucursal y con su misma forma, «El día empieza a las
  6:00», que abre una cajita con lo que tenía la tarjeta «Hora de corte» de Ajustes: la lista de 0:00 a 23:00,
  «Guardar» en verde (apagado hasta que cambias la hora; al guardar, su palomita ~1.6 s), el ejemplo con la «i» y su pie.
  La guarda fijar_hora_corte (queda en la bitácora y también cambia a qué día pertenecen las ventas pasadas); al
  guardar, Cortes vuelve a leer, y cambian el botón y la fecha de la barra («Hoy · desde las 7:00»).

  Sale de su botón con los resortes de las listas y su flecha se dobla en ✕; se cierra con la ✕, con un clic afuera o
  con Escape. En Cristal el botón es vidrio, como la sucursal, y la cajita una hoja de vidrio grueso con rellenos
  transparentes adentro. Respeta «reducir movimiento».
-->
<script lang="ts">
  import { Tween } from 'svelte/motion';
  import Boton from '../../../diseno/Boton.svelte';
  import CajaError from '../../../diseno/CajaError.svelte';
  import Esqueleto from '../../../diseno/Esqueleto.svelte';
  import { DURA_FLECHA, resorteFlecha, trazosFlecha } from '../../../diseno/flecha';
  import Icono from '../../../diseno/Icono.svelte';
  import Lista from '../../../diseno/Lista.svelte';
  import { pica, quitarDeBarra, vidrio } from '../../../diseno/vidrio';
  import { ALGO_SALIO_PANEL, Fallo } from '../../../lib/errores';
  import { fijarHoraCorte } from '../../../lib/reportes';

  let {
    restauranteId,
    hora,
    alGuardar,
  }: {
    restauranteId: string;
    // La que dio Postgres en la última lectura de Cortes; null mientras llega la primera.
    hora: number | null;
    alGuardar: () => void;
  } = $props();

  // Lo de adentro de la cajita ya no es la barra de arriba: su «Guardar» no es vidrio.
  quitarDeBarra();

  const HORAS = Array.from({ length: 24 }, (_, h) => ({ valor: h, texto: `${h}:00` }));
  const idCaja = $props.id();

  let abierta = $state(false);
  let elegida = $state<number | null>(null);
  let paso = $state<'guardando' | 'listo' | null>(null);
  let error = $state<string | null>(null);
  let raiz: HTMLDivElement;
  let reloj: ReturnType<typeof setTimeout> | undefined;

  // Lo guardado se ve en el botón al momento, sin esperar a que Cortes vuelva a leer; cuando llega su lectura, manda ella.
  let guardada = $state<number | null>(null);
  $effect(() => {
    void hora;
    guardada = null;
  });
  const actual = $derived(guardada ?? hora);

  const quieto = typeof matchMedia === 'function' ? matchMedia('(prefers-reduced-motion: reduce)') : null;
  const doblez = new Tween(0, { duration: DURA_FLECHA, easing: resorteFlecha });
  $effect(() => {
    doblez.set(abierta ? 1 : 0, quieto?.matches ? { duration: 0 } : undefined);
  });
  const trazos = $derived(trazosFlecha(doblez.current));

  function alternar() {
    if (abierta) {
      abierta = false;
      return;
    }
    if (actual === null) return;
    elegida = actual;
    error = null;
    abierta = true;
  }

  async function guardar() {
    if (elegida === null || paso !== null) return;
    const nueva = elegida;
    paso = 'guardando';
    error = null;
    try {
      await fijarHoraCorte(restauranteId, nueva);
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[cortes] no se pudo guardar la hora de corte:', falla);
      error = falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL;
      paso = null;
      return;
    }
    guardada = nueva;
    paso = 'listo';
    alGuardar();
    clearTimeout(reloj);
    reloj = setTimeout(() => (paso = null), 1600);
  }

  // El ejemplo de la cajita, con la hora que está elegida (el mismo que tenía Ajustes).
  function ejemplo(h: number): { hora: string; resto: string } {
    if (h === 0) return { hora: '0:00', resto: ', cada día va de medianoche a medianoche.' };
    const cuenta = h > 1 ? '0:40' : '0:20';
    return {
      hora: `${h}:00`,
      resto: `, lo que se abre antes de las ${h}:00 cuenta en el día anterior: una cuenta del sábado a las ${cuenta} es del viernes.`,
    };
  }

  const muestra = $derived(ejemplo(elegida ?? actual ?? 0));
</script>

<svelte:window
  onpointerdown={(e) => {
    if (abierta && !raiz.contains(e.target as Node)) abierta = false;
  }}
  onkeydown={(e) => {
    if (abierta && e.key === 'Escape') abierta = false;
  }}
/>

<div class="hora" class:abierta bind:this={raiz}>
  <button
    type="button"
    class="boton"
    use:vidrio={'boton'}
    use:pica={1.08}
    aria-expanded={abierta}
    aria-controls={idCaja}
    disabled={actual === null}
    onclick={alternar}
  >
    <Icono nombre="reloj" tamano={18} />
    <span class="texto">
      El día empieza a las
      {#if actual === null}
        <span class="esqueleto-hora" aria-hidden="true"><Esqueleto ancho="30px" alto="10px" /></span>
      {:else}
        <b>{actual}:00</b>
      {/if}
    </span>
    <svg class="flecha" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"
      ><path d={trazos[0]}></path><path d={trazos[1]}></path></svg
    >
  </button>

  <div class="hoja" id={idCaja} role="dialog" aria-label="Hora de corte" inert={!abierta} use:vidrio={'hoja'}>
    <label class="etiqueta" for="{idCaja}-lista">EL DÍA EMPIEZA A LAS</label>
    <div class="fila">
      <div class="lista">
        <Lista id="{idCaja}-lista" bind:valor={elegida} apagado={paso !== null} opciones={HORAS} />
      </div>
      <span class="guardar">
        <Boton
          etiqueta={paso === 'guardando' ? 'Guardando…' : paso === 'listo' ? 'Guardado' : 'Guardar'}
          tono="verde"
          cargando={paso === 'guardando'}
          exito={paso === 'listo'}
          apagado={paso === null && elegida === actual}
          onclick={guardar}
        />
      </span>
    </div>
    {#if error}<CajaError mensaje={error} />{/if}
    <p class="ejemplo">
      <Icono nombre="info" tamano={16} />
      <span>Con <b>{muestra.hora}</b>{muestra.resto}</span>
    </p>
    <p class="pie">Es de esta sucursal y vale para todo tu equipo. Si la cambias, también cambia a qué día pertenecen las ventas pasadas.</p>
  </div>
</div>

<style>
  .hora {
    position: relative;
    flex: none;
    display: flex;
  }

  /* El de la cajita de la sucursal (CajaSucursales.svelte): sus medidas, su forma y su chip abierto. */
  .boton {
    height: 34px;
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 0 13px;
    border: 1px solid var(--linea);
    border-radius: 9px;
    background: transparent;
    color: var(--texto);
    font-size: 13px;
    font-weight: 600;
    white-space: nowrap;
    transition:
      opacity 150ms,
      transform 0.2s ease;
  }

  .boton:hover:not(:disabled) {
    opacity: 0.86;
  }

  .boton:disabled {
    cursor: default;
  }

  .boton[aria-expanded='true'] {
    background: var(--chip);
  }

  .boton:active:not(:disabled) {
    transform: scale(0.95);
  }

  .texto {
    display: inline-flex;
    align-items: center;
    gap: 4px;
  }

  .texto b {
    font-weight: 700;
  }

  .esqueleto-hora {
    display: inline-flex;
  }

  /* Mide 14 aunque la barra de arriba agrande los íconos del botón. */
  .boton .flecha {
    width: 14px !important;
    height: 14px !important;
    flex: none;
    color: var(--suave);
  }

  /* 8 debajo del botón y a ras de su borde derecho; sale de él con el resorte del fondo de las listas. */
  .hoja {
    position: absolute;
    right: 0;
    top: calc(100% + 8px);
    z-index: 30;
    width: 372px;
    box-sizing: border-box;
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 10px;
    border: 1px solid var(--borde-tarjeta);
    border-radius: 14px;
    background: var(--solido);
    box-shadow:
      0 18px 40px -12px var(--sombra-menu),
      0 2px 6px var(--sombra-menu);
    transform-origin: calc(100% - 60px) 0;
    opacity: 0;
    transform: translateY(-6px) scale(0.96);
    visibility: hidden;
    transition:
      opacity 0.15s ease,
      transform 0.2s ease,
      visibility 0s linear 0.2s;
  }

  .hora.abierta .hoja {
    opacity: 1;
    transform: none;
    visibility: visible;
    transition:
      opacity 0.2s ease,
      transform 0.5s var(--resorte-fondo),
      visibility 0s;
  }

  .hoja > * {
    margin: 0;
  }

  .fila {
    display: flex;
    align-items: flex-start;
    gap: 10px;
    margin-top: 2px;
  }

  .lista {
    flex: 1;
    min-width: 0;
  }

  /* El verde no se encoge: la lista se queda con lo que sobra. La cajita cuelga de la barra de arriba, que les pone su
     tamaño (34 de alto) a sus botones: aquí lleva el suyo, el de las ventanas. */
  .guardar {
    flex: none;
    display: flex;
  }

  .guardar :global(.boton.verde) {
    height: 44px;
    padding: var(--bf-pad);
    border-radius: 12px;
  }

  .ejemplo {
    display: flex;
    align-items: flex-start;
    gap: 10px;
    padding: 11px 14px;
    border-radius: 12px;
    background: var(--chip);
    font-size: 12.5px;
    line-height: 1.5;
    color: var(--suave);
  }

  .ejemplo :global(svg) {
    flex: none;
    margin-top: 2px;
  }

  .ejemplo b {
    font-weight: 600;
    color: var(--texto);
  }

  .pie {
    font-size: 12px;
    font-weight: 500;
    line-height: 1.5;
    color: var(--tenue);
    text-wrap: pretty;
  }

  /* Cristal: el botón ya es vidrio (su receta en cristal.css, como la sucursal) y la cajita una hoja de vidrio grueso;
     adentro, rellenos transparentes. Los valores son los de la maqueta. */
  :global(:root[data-estilo='cristal']) .boton {
    position: relative;
  }

  :global(:root[data-estilo='cristal'][data-tema='oscuro']) .ejemplo {
    background: rgba(255, 255, 255, 0.06);
  }

  :global(:root[data-estilo='cristal'][data-tema='oscuro']) .hora.abierta .boton {
    background: rgba(255, 255, 255, 0.1);
  }

  :global(:root[data-estilo='cristal'][data-tema='claro']) .ejemplo {
    background: var(--cl-relleno);
  }

  :global(:root[data-estilo='cristal'][data-tema='claro']) .hora.abierta .boton {
    background: rgba(255, 255, 255, 0.75);
  }

  @media (prefers-reduced-motion: reduce) {
    .hoja,
    .hora.abierta .hoja,
    .boton {
      transition: none !important;
    }
  }
</style>
