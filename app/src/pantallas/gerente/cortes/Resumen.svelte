<!--
  La tarjeta de la derecha de Cortes y reportes sin nada elegido (14 nov 2026), como «Toca una cuenta para cobrarla» de la
  Caja a lo ancho: la cabeza que dice qué hacer y, debajo, lo que sumó Postgres en el día: lo descontado en las cuentas
  cerradas y lo cancelado, cada uno en su gris (las dos cifras de arriba de la pieza 5). Con `cargando`, la misma forma
  en esqueleto, para que nada brinque al llegar.
-->
<script lang="ts">
  import Esqueleto from '../../../diseno/Esqueleto.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import { pesos, plural } from '../../../lib/formato';
  import type { ReporteDia } from '../../../lib/reportes';

  let { reporte, cargando = false }: { reporte: ReporteDia | null; cargando?: boolean } = $props();

  function notaCancelaciones(r: ReporteDia): string {
    const { renglones, cuentas } = r.cancelaciones;
    const partes = [renglones ? plural(renglones, 'renglón', 'renglones') : '', cuentas ? plural(cuentas, 'cuenta', 'cuentas') : ''];
    return partes.filter(Boolean).join(' y ') || 'Ninguna';
  }
</script>

{#if cargando || !reporte}
  <span class="solo-lector" role="status">Cargando este día…</span>
  <div class="encabezado" aria-hidden="true">
    <Esqueleto ancho="36px" alto="36px" redondo="11px" />
    <div class="titulos"><Esqueleto ancho="230px" alto="15px" /><Esqueleto ancho="268px" alto="12px" /></div>
  </div>
  <div class="cifras" aria-hidden="true">
    {#each ['Descuentos', 'Cancelaciones'] as e (e)}
      <div class="cifra">
        <span class="etiqueta-c">{e}</span>
        <Esqueleto ancho="96px" alto="22px" />
        <Esqueleto ancho="120px" alto="11px" />
      </div>
    {/each}
  </div>
{:else}
  <div class="encabezado">
    <span class="cuadro-c"><Icono nombre="corte" tamano={18} /></span>
    <div class="titulos">
      <span class="titulo">Toca un renglón para ver su detalle</span>
      <span class="sub">El corte de un turno, o con quién se pidió y autorizó cada cosa. La lista se queda a la vista.</span>
    </div>
  </div>
  <div class="cifras">
    <div class="cifra">
      <span class="etiqueta-c">Descuentos</span>
      <b>{pesos(reporte.descuentos.total)}</b>
      <small>
        {reporte.descuentos.cuentas ? `En ${plural(reporte.descuentos.cuentas, 'cuenta cerrada', 'cuentas cerradas')}` : 'En ninguna cuenta cerrada'}
      </small>
    </div>
    <div class="cifra">
      <span class="etiqueta-c">Cancelaciones</span>
      <b>{pesos(reporte.cancelaciones.total)}</b>
      <small>{notaCancelaciones(reporte)}</small>
    </div>
  </div>
{/if}

<style>
  .cifras {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 10px;
  }

  .cifra {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 6px;
    padding: 14px 16px;
    border-radius: 12px;
    background: var(--fondo);
  }

  .cifra b {
    font-family: var(--mono);
    font-size: 20px;
    font-weight: 600;
    letter-spacing: -0.4px;
    line-height: 26px;
    white-space: nowrap;
  }

  .cifra small {
    font-size: 12px;
    font-weight: 500;
    color: var(--suave);
  }
</style>
