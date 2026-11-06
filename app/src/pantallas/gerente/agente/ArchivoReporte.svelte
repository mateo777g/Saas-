<!--
  El «Reporte en PDF» en la plática (encuesta 18 del rediseño; maqueta V64Pv4gmANPRZuJW5hTe5D): llega como
  respuesta del agente, con su archivo. «Descargar» lo vuelve a armar con las fechas guardadas, también
  desde el Historial. Sin ventas cerradas en el periodo no hay archivo: solo lo dice.
-->
<script lang="ts">
  import CajaError from '../../../diseno/CajaError.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import { esDeRed, SIN_CONEXION } from '../../../lib/errores';
  import { bajarReporte, nombreDelArchivo, textoEntrega, textoSinVentas, type ReporteGuardado } from '../../../lib/reporte';

  let {
    reporte,
    restauranteId,
    restaurante,
  }: { reporte: ReporteGuardado; restauranteId: string; restaurante: string } = $props();

  let estado = $state<'listo' | 'armando' | 'bajado'>('listo');
  let error = $state<string | null>(null);

  async function descargar() {
    estado = 'armando';
    error = null;
    try {
      await bajarReporte(restauranteId, restaurante, reporte);
      estado = 'bajado';
      setTimeout(() => (estado = 'listo'), 1600);
    } catch (e) {
      console.error('[agente] no se pudo armar el reporte en PDF:', e);
      estado = 'listo';
      error = esDeRed(e) ? SIN_CONEXION : 'No se pudo armar el reporte. Inténtalo otra vez.';
    }
  }
</script>

<div class="respuesta">
  {#if reporte.sin_ventas}
    <p>{textoSinVentas(reporte.periodo)}</p>
  {:else}
    <p>{textoEntrega(reporte.periodo)}</p>
    <div class="archivo">
      <span class="doc">PDF</span>
      <span class="arch-textos">
        <span class="nombre-arch">{nombreDelArchivo(reporte.periodo, restaurante)}</span>
        <span class="det">{reporte.detalle}</span>
      </span>
      <button type="button" class="boton-chico" disabled={estado !== 'listo'} onclick={descargar}>
        {#if estado === 'armando'}
          Armando…
        {:else if estado === 'bajado'}
          <span class="verde"><Icono nombre="check" tamano={14} /></span>Listo
        {:else}
          Descargar
        {/if}
      </button>
    </div>
    {#if error}<CajaError mensaje={error} />{/if}
  {/if}
</div>

<style>
  .respuesta {
    flex: none;
    display: flex;
    flex-direction: column;
    gap: 12px;
    font-size: 14.5px;
    line-height: 1.6;
  }

  p {
    margin: 0;
  }

  .archivo {
    display: flex;
    align-items: center;
    gap: 12px;
    max-width: 480px;
    padding: 12px 14px;
    border: 1px solid var(--borde-tarjeta);
    border-radius: 12px;
  }

  .doc {
    width: 36px;
    height: 44px;
    flex: none;
    display: grid;
    place-items: center;
    border-radius: 6px;
    background: var(--chip);
    font-family: var(--mono);
    font-size: 9.5px;
    font-weight: 500;
    color: var(--rojo);
  }

  .arch-textos {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .nombre-arch {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 13.5px;
    font-weight: 600;
    line-height: 1.6;
  }

  .det {
    font-size: 12px;
    line-height: 1.6;
    color: var(--suave);
  }

  .boton-chico {
    height: 30px;
    flex: none;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 0 11px;
    border: 1px solid var(--linea);
    border-radius: 8px;
    background: none;
    color: var(--texto);
    font-size: 12.5px;
    font-weight: 600;
  }

  .boton-chico:hover:not(:disabled) {
    border-color: var(--linea-fuerte);
  }

  .boton-chico:disabled {
    cursor: default;
  }

  .verde {
    display: flex;
    color: var(--verde);
  }
</style>
