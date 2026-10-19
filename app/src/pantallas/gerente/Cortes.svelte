<!--
  Cortes y reportes (pieza 5; libreta 5; decidido el 18 de octubre de 2026; maqueta
  7J6LvYWiktRnGxNugbuaoe). Se ordena por día de negocio: se abre en hoy y las flechas van a otros
  días. A la izquierda, el corte de cada turno que se abrió ese día (cortes/Turno). A la derecha, lo
  que se descontó y se canceló en las cuentas de ese día, con quién lo pidió y quién lo autorizó, y
  los otros cambios (mesas, juntas, descuentos quitados, la hora de corte). Todo sale de
  reporte_del_dia (migración reportes): los totales los suma Postgres. Solo el gerente lo ve.

  Se lee al abrir, al cambiar de día, al regresar a la pestaña y, mientras se ve hoy, cada vez que
  cambia una cuenta, un pago o el turno (tiempo real).
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import BarraArriba from '../../diseno/BarraArriba.svelte';
  import BotonCuadro from '../../diseno/BotonCuadro.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import Vidrio from '../../diseno/Vidrio.svelte';
  import { esDeRed, SIN_CONEXION } from '../../lib/errores';
  import { diaAnterior, diaConNombre, diaSiguiente, dinero, enZona, pesos, plural } from '../../lib/formato';
  import type { Sucursal } from '../../lib/gerente';
  import { escuchar } from '../../lib/pos';
  import { leerReporte, type Cancelacion, type Descuento, type OtroCambio, type ReporteDia } from '../../lib/reportes';
  import { supabase } from '../../lib/supabase';
  import CajaSucursales from './CajaSucursales.svelte';
  import { quienLoHizo } from './cortes/quien';
  import Turno from './cortes/Turno.svelte';

  let {
    sucursal,
    sucursales,
    alElegir,
  }: { sucursal: Sucursal; sucursales: Sucursal[]; alElegir: (sucursal: Sucursal) => void } = $props();

  type Lectura = { estado: 'leyendo' } | { estado: 'listo'; reporte: ReporteDia } | { estado: 'error'; deRed: boolean };

  // El día que se ve; vacío, hoy (lo decide Postgres con la hora de corte).
  let dia = $state<string | null>(null);
  let lectura = $state<Lectura>({ estado: 'leyendo' });

  const reporte = $derived(lectura.estado === 'listo' ? lectura.reporte : null);
  const esHoy = $derived(dia === null || (reporte !== null && reporte.dia === reporte.hoy));

  const estado = $derived.by(() => {
    if (lectura.estado === 'error') return { texto: lectura.deRed ? 'Sin conexión' : 'No se pudo leer', vivo: false };
    return null;
  });

  let vuelta = 0;

  async function leer() {
    const esta = ++vuelta;
    try {
      const r = await leerReporte(sucursal.id, dia);
      if (esta === vuelta) lectura = { estado: 'listo', reporte: r };
    } catch (error) {
      console.error('[cortes] no se pudo leer reporte_del_dia:', error);
      if (esta === vuelta) lectura = { estado: 'error', deRed: esDeRed(error) };
    }
  }

  function ir(nuevo: string | null) {
    dia = nuevo && reporte && nuevo >= reporte.hoy ? null : nuevo;
    lectura = { estado: 'leyendo' };
    leer();
  }

  let espera: ReturnType<typeof setTimeout> | undefined;
  function programar() {
    if (!esHoy) return;
    clearTimeout(espera);
    espera = setTimeout(leer, 400);
  }

  onMount(() => {
    leer();
    const dejar = escuchar(supabase, sucursal.id, ['ventas', 'pagos', 'turnos'], programar);
    const alVolver = () => {
      if (document.visibilityState === 'visible') leer();
    };
    document.addEventListener('visibilitychange', alVolver);
    return () => {
      clearTimeout(espera);
      dejar();
      document.removeEventListener('visibilitychange', alVolver);
    };
  });

  const hora = (momento: string | null) => (momento && reporte ? enZona(momento, reporte.zona).hora.replace(/^0(\d)/, '$1') : '');

  // «Mesa 4», «Para llevar · Sr. Ramírez», «Domicilio · Doña Mari».
  function cuentaDe(x: { tipo: string; cuenta: string }): string {
    if (x.tipo === 'para_llevar') return `Para llevar · ${x.cuenta}`;
    if (x.tipo === 'domicilio') return `Domicilio · ${x.cuenta}`;
    return x.cuenta;
  }

  const valor = (tipo: 'porcentaje' | 'pesos', v: number) => (tipo === 'porcentaje' ? `${v} %` : dinero(v));

  function textoDescuento(d: Descuento): { que: string; det: string } {
    return {
      que: `${d.renglon_id ? d.nombre : 'Toda la cuenta'} · ${valor(d.descuento_tipo, d.descuento_valor)}`,
      det: [
        cuentaDe(d),
        d.folio ? `Folio ${d.folio}` : '',
        `«${d.motivo}»`,
        quienLoHizo(d.pidio_id, d.pidio, d.autorizo_id, d.autorizo),
        hora(d.created_at),
      ].filter(Boolean).join(' · '),
    };
  }

  function textoCancelacion(c: Cancelacion): { que: string; det: string } {
    const quien = quienLoHizo(c.pidio_id, c.pidio, c.autorizo_id, c.autorizo);
    if (c.que === 'cuenta') {
      return {
        que: `Toda la cuenta · ${cuentaDe(c)}`,
        det: [`«${c.motivo}»`, quien, hora(c.created_at)].filter(Boolean).join(' · '),
      };
    }
    return {
      que: `${c.cantidad} ${c.nombre}`,
      det: [
        cuentaDe(c),
        c.folio ? `Folio ${c.folio}` : '',
        c.estado === 'abierta' ? 'abierta' : c.estado === 'cancelada' ? 'cancelada' : '',
        `«${c.motivo}»`,
        quien,
        hora(c.created_at),
      ].filter(Boolean).join(' · '),
    };
  }

  function textoOtro(o: OtroCambio): string {
    const d = o.detalle as Record<string, string | number | null | undefined>;
    if (o.accion === 'cambiar_mesa') return `Cambió de mesa: de ${d.de} a ${d.a}`;
    if (o.accion === 'juntar_mesas') return `Juntó ${d.de} con ${d.a}`;
    if (o.accion === 'cambiar_hora_corte') return `Cambió la hora de corte de ${d.de}:00 a ${d.a}:00`;
    const de = d.nombre ? `${d.nombre}${o.cuenta ? ` en ${o.cuenta}` : ''}` : (o.cuenta ?? 'la cuenta');
    return `Quitó el descuento de ${de}`;
  }

  function notaCancelaciones(r: ReporteDia): string {
    const { renglones, cuentas } = r.cancelaciones;
    const partes = [renglones ? plural(renglones, 'renglón', 'renglones') : '', cuentas ? plural(cuentas, 'cuenta', 'cuentas') : ''];
    return partes.filter(Boolean).join(' y ') || 'Ninguna';
  }

  const nada = $derived(
    reporte !== null && !reporte.descuentos.lista.length && !reporte.cancelaciones.lista.length && !reporte.otros.length,
  );
</script>

<BarraArriba titulo="Cortes y reportes" {estado}>
  {#snippet junto()}
    <div class="dia">
      <BotonCuadro
        icono="anterior"
        ayuda="Día anterior"
        apagado={!reporte}
        onclick={() => reporte && ir(diaAnterior(reporte.dia))}
      />
      <span class="dia-texto">
        {reporte ? diaConNombre(reporte.dia) : '—'}
        <small>
          {#if reporte}
            {reporte.dia === reporte.hoy ? `Hoy · desde las ${reporte.hora_corte}:00` : `Día de negocio · de ${reporte.hora_corte}:00 a ${reporte.hora_corte}:00`}
          {/if}
        </small>
      </span>
      <BotonCuadro
        icono="siguiente"
        ayuda="Día siguiente"
        apagado={!reporte || reporte.dia === reporte.hoy}
        onclick={() => reporte && ir(diaSiguiente(reporte.dia))}
      />
    </div>
    {#if reporte && reporte.dia !== reporte.hoy}
      <button type="button" class="boton-chico" onclick={() => ir(null)}><Icono nombre="hoy" tamano={14} />Hoy</button>
    {/if}
  {/snippet}
  <CajaSucursales {sucursales} actual={sucursal} {alElegir} />
</BarraArriba>

<main class="columnas">
  <Vidrio como="section" class="tarjeta-cortes" radio={26} aria-label="Cortes de caja">
    <div class="fila-titulo">
      <div>
        <span class="titulo-tarjeta">Cortes de caja</span>
        <span class="nota">Cada turno que se abrió este día, con su corte.</span>
      </div>
      {#if reporte}<span class="etiqueta">{plural(reporte.turnos.length, 'TURNO', 'TURNOS')}</span>{/if}
    </div>
    <div class="desliza">
      {#if lectura.estado === 'leyendo'}
        <div class="vacio"><b>Cargando…</b></div>
      {:else if lectura.estado === 'error'}
        <div class="vacio">
          <b>{lectura.deRed ? 'Sin conexión.' : 'No se pudo leer este día.'}</b>
          <span>{lectura.deRed ? SIN_CONEXION : 'Intenta de nuevo en un momento.'}</span>
        </div>
      {:else if reporte && !reporte.turnos.length}
        <div class="vacio">
          <b>Este día no se abrió la caja.</b>
          <span>Los cortes salen aquí cuando alguien de la caja o un gerente abre y cierra un turno.</span>
        </div>
      {:else if reporte}
        {#each reporte.turnos as t (t.id)}
          <Turno turno={t} zona={reporte.zona} />
        {/each}
      {/if}
    </div>
  </Vidrio>

  <Vidrio como="section" class="tarjeta-cortes" radio={26} aria-label="Descuentos y cancelaciones">
    <div class="fila-titulo">
      <div>
        <span class="titulo-tarjeta">Descuentos y cancelaciones</span>
        <span class="nota">De las cuentas de este día, con quién lo pidió y quién lo autorizó.</span>
      </div>
    </div>
    <div class="desliza">
      {#if reporte && nada}
        <div class="vacio">
          <b>Nada se descontó ni se canceló este día.</b>
          <span>Aquí salen los descuentos, las cancelaciones y los cambios de mesa, con quién los pidió y quién los autorizó.</span>
        </div>
      {:else if reporte}
        <div class="resumen">
          <div class="cifra">
            <span class="etiqueta">DESCUENTOS</span>
            <span class="cifra-valor">{pesos(reporte.descuentos.total)}</span>
            <span class="cifra-nota">
              {reporte.descuentos.cuentas ? `En ${plural(reporte.descuentos.cuentas, 'cuenta cerrada', 'cuentas cerradas')}` : 'En ninguna cuenta cerrada'}
            </span>
          </div>
          <div class="cifra">
            <span class="etiqueta">CANCELACIONES</span>
            <span class="cifra-valor">{pesos(reporte.cancelaciones.total)}</span>
            <span class="cifra-nota">{notaCancelaciones(reporte)}</span>
          </div>
        </div>

        <div class="bloque">
          <span class="etiqueta">DESCUENTOS</span>
          <div class="lista">
            {#each reporte.descuentos.lista as d (`${d.venta_id}-${d.renglon_id}`)}
              {@const x = textoDescuento(d)}
              <div class="f"><span><b>{x.que}</b><small>{x.det}</small></span><span class="n">−{pesos(d.descuento)}</span></div>
            {:else}
              <p class="vacia">Ninguna cuenta cerrada de este día lleva descuento.</p>
            {/each}
          </div>
        </div>

        <div class="bloque">
          <span class="etiqueta">CANCELACIONES</span>
          <div class="lista">
            {#each reporte.cancelaciones.lista as c (`${c.que}-${c.venta_id}-${c.renglon_id}`)}
              {@const x = textoCancelacion(c)}
              <div class="f"><span><b>{x.que}</b><small>{x.det}</small></span><span class="n tachado">{pesos(c.importe)}</span></div>
            {:else}
              <p class="vacia">Nada se canceló.</p>
            {/each}
          </div>
        </div>

        <div class="bloque">
          <span class="etiqueta">OTROS CAMBIOS</span>
          <div class="lista">
            {#each reporte.otros as o, i (i)}
              <div class="f"><span><b>{textoOtro(o)}</b><small>{[o.quien, hora(o.created_at)].filter(Boolean).join(' · ')}</small></span></div>
            {:else}
              <p class="vacia">Ninguno.</p>
            {/each}
          </div>
        </div>
      {/if}
    </div>
  </Vidrio>
</main>

<style>
  .dia {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .dia-texto {
    min-width: 196px;
    text-align: center;
    font-size: 13.5px;
    font-weight: 700;
    white-space: nowrap;
  }

  .dia-texto small {
    display: block;
    font-family: var(--mono);
    font-size: 10px;
    font-weight: 400;
    letter-spacing: 0.1em;
    color: var(--tenue);
    text-transform: uppercase;
  }

  .boton-chico {
    height: 32px;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 0 11px;
    border-radius: 11px;
    border: 1px solid var(--linea);
    background: transparent;
    color: var(--texto);
    font-size: 12.5px;
    font-weight: 600;
    white-space: nowrap;
    transition: opacity 150ms;
  }

  .boton-chico:hover {
    opacity: 0.86;
  }

  /* Debajo de la barra de arriba (16 + 60 + 16) y a la derecha de la lateral (16 + 244 + 16). */
  .columnas {
    position: absolute;
    left: 276px;
    right: 16px;
    top: 92px;
    bottom: 16px;
    display: grid;
    grid-template-columns: minmax(0, 1.18fr) minmax(0, 1fr);
    gap: 16px;
  }

  .columnas > :global(.tarjeta-cortes) {
    min-width: 0;
    min-height: 0;
    padding: 20px;
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  .fila-titulo {
    flex: none;
    display: flex;
    align-items: flex-end;
    justify-content: space-between;
    gap: 16px;
  }

  .fila-titulo > div {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .titulo-tarjeta {
    font-size: 14.5px;
    font-weight: 700;
  }

  .nota {
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--tenue);
  }

  .desliza {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    display: flex;
    flex-direction: column;
    gap: 14px;
    scrollbar-width: thin;
  }

  .vacio {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 6px;
    padding: 24px;
    text-align: center;
  }

  .vacio b {
    font-size: 14.5px;
    font-weight: 700;
  }

  .vacio span {
    max-width: 40ch;
    font-size: 12.5px;
    line-height: 1.45;
    color: var(--suave);
  }

  .resumen {
    flex: none;
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 12px;
  }

  .cifra {
    min-width: 0;
    padding: 14px 16px;
    border-radius: 18px;
    background: var(--solido);
    border: 1px solid var(--linea);
    display: flex;
    flex-direction: column;
    gap: 5px;
  }

  .cifra-valor {
    font-size: 24px;
    font-weight: 800;
    letter-spacing: -0.5px;
    line-height: 30px;
    font-variant-numeric: tabular-nums;
    white-space: nowrap;
  }

  .cifra-nota {
    font-size: 12px;
    font-weight: 500;
    color: var(--suave);
  }

  .bloque {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .bloque > .etiqueta {
    display: block;
    min-height: 18px;
    padding: 0 2px;
  }

  .lista {
    display: flex;
    flex-direction: column;
    border: 1px solid var(--linea);
    border-radius: 14px;
  }

  .lista .f {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 12px;
    padding: 10px 12px;
    border-top: 1px solid var(--linea);
    font-size: 12.5px;
  }

  .lista .f:first-child {
    border-top: 0;
  }

  .lista .f > span:first-child {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .lista b {
    font-weight: 700;
  }

  .lista small {
    font-size: 11px;
    line-height: 1.45;
    color: var(--tenue);
  }

  .n {
    font-family: var(--mono);
    font-variant-numeric: tabular-nums;
    white-space: nowrap;
  }

  .tachado {
    text-decoration: line-through;
    text-decoration-color: var(--tenue);
  }

  .vacia {
    margin: 0;
    padding: 12px;
    font-size: 12px;
    color: var(--tenue);
  }

  @media (prefers-reduced-motion: reduce) {
    .boton-chico {
      transition: none;
    }
  }
</style>
