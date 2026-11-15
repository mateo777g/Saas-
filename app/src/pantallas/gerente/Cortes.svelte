<!--
  Cortes y reportes (pieza 5; libreta 5; decidido el 18 de octubre de 2026). Se ordena por día de negocio: se abre en
  hoy y las flechas van a otros días. Todo sale de reporte_del_dia (migración reportes): los totales los suma Postgres.
  Solo el gerente lo ve. Se lee al abrir, al cambiar de día, al regresar a la pestaña y, mientras se ve hoy, cada vez que
  cambia una cuenta, un pago o el turno (tiempo real).

  Con la estructura de la Caja a lo ancho (14 nov 2026; caja/Caja.svelte y caja/caja/, maqueta de la adaptabilidad
  GBWEGCsQFcwKkWm7Qe9FPA v4, pantalla «Caja»; notas en planes/trabajo/rediseno/cortes.md). Arriba, la barra del panel con
  el día y sus flechas, «Hoy» (en otro día), la hora de corte (cortes/HoraCorte) y la sucursal. A la izquierda la
  búsqueda con el filtro Todo el día · Turnos · Descuentos · Cancelaciones · Otros cambios y la tabla de Mi menú: primero
  cada turno que se abrió ese día con su sello, luego lo que pasó en sus cuentas, por hora (cortes/TablaDia). A la
  derecha la tarjeta de 400: sin nada elegido, lo descontado y lo cancelado del día (cortes/Resumen); un turno, su corte
  (cortes/Turno); lo demás, su detalle con quién lo pidió y quién lo autorizó (cortes/Detalle). Abajo la barra de Crear
  anuncios dice lo que se ve. Las piezas de pos/ancho/ se usan tal cual, sin tocarlas.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import BarraArriba from '../../diseno/BarraArriba.svelte';
  import Boton from '../../diseno/Boton.svelte';
  import BotonCuadro from '../../diseno/BotonCuadro.svelte';
  import CajaError from '../../diseno/CajaError.svelte';
  import Esqueleto from '../../diseno/Esqueleto.svelte';
  import { ALGO_SALIO_PANEL, esDeRed, SIN_CONEXION } from '../../lib/errores';
  import { filasDeLaUltimaVez, recordarFilas } from '../../lib/esqueletos';
  import { diaAnterior, diaConNombre, diaSiguiente, plural } from '../../lib/formato';
  import type { Sucursal } from '../../lib/gerente';
  import { escuchar } from '../../lib/pos';
  import { leerReporte, type ReporteDia } from '../../lib/reportes';
  import { supabase } from '../../lib/supabase';
  import Lado from '../pos/ancho/Lado.svelte';
  import '../pos/ancho/ancho.css';
  import CajaSucursales from './CajaSucursales.svelte';
  import Detalle from './cortes/Detalle.svelte';
  import { cuantosDe, filasDelDia, filtrar, resumenAbajo, type FilaCortes, type FiltroCortes } from './cortes/filas';
  import HoraCorte from './cortes/HoraCorte.svelte';
  import Resumen from './cortes/Resumen.svelte';
  import TablaDia from './cortes/TablaDia.svelte';
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
  // La hora de corte de la sucursal, de la última lectura: el botón de la barra no la pierde al cambiar de día.
  let horaCorte = $state<number | null>(null);
  // El último día que se leyó, para que las flechas sigan sirviendo si una lectura falla.
  let ultimo = $state<{ dia: string; hoy: string } | null>(null);

  let filtro = $state<FiltroCortes>('todo');
  let busqueda = $state('');
  // La clave del renglón que se ve en la tarjeta de la derecha; vacía, el resumen del día.
  let elegida = $state<string | null>(null);

  const reporte = $derived(lectura.estado === 'listo' ? lectura.reporte : null);
  const leyendo = $derived(lectura.estado === 'leyendo');
  const todas = $derived(reporte ? filasDelDia(reporte) : []);
  const filas = $derived(filtrar(todas, filtro, busqueda));
  const cuantos = $derived(cuantosDe(todas));
  const fila = $derived(elegida ? (todas.find((f) => f.clave === elegida) ?? null) : null);
  // svelte-ignore state_referenced_locally
  const filasAntes = filasDeLaUltimaVez(`cortes-${sucursal.id}`);

  const estado = $derived.by(() => {
    if (lectura.estado === 'leyendo') return { texto: 'Cargando el día…', vivo: true };
    if (lectura.estado === 'error') return { texto: lectura.deRed ? 'Sin conexión' : 'No se pudo leer', vivo: false };
    return null;
  });

  // Lo que dice abajo del día. Antes de la hora de corte el día de negocio sigue siendo el de ayer: ahí no dice «Hoy»,
  // porque Inicio ya enseña la fecha del calendario (detalle visto en la prueba de la pieza 5).
  const subtitulo = $derived.by(() => {
    if (!reporte) return '';
    const h = reporte.hora_corte;
    if (reporte.dia !== reporte.hoy) return `Día de negocio · de ${h}:00 a ${h}:00`;
    if (sucursal.hoy > reporte.hoy) return `En curso · hasta hoy a las ${h}:00`;
    return `Hoy · desde las ${h}:00`;
  });

  const vacio = $derived.by(() => {
    if (busqueda.trim()) return { titulo: 'Nada con eso', texto: 'Prueba con otra palabra, o con otro filtro.' };
    if (filtro === 'turnos') return { titulo: 'Este día no se abrió la caja.', texto: 'Los cortes salen aquí cuando alguien de la caja o un gerente abre y cierra un turno.' };
    if (filtro === 'descuentos') return { titulo: 'Ninguna cuenta cerrada lleva descuento.', texto: 'Aquí salen con quién los pidió y quién los autorizó.' };
    if (filtro === 'cancelaciones') return { titulo: 'Nada se canceló.', texto: 'Aquí salen con quién lo pidió y quién lo autorizó.' };
    if (filtro === 'otros') return { titulo: 'Ningún otro cambio.', texto: 'Aquí salen los cambios de mesa, las mesas juntas, los descuentos quitados y la hora de corte.' };
    return {
      titulo: 'Nada pasó este día.',
      texto: 'Aquí salen los cortes de cada turno, los descuentos, las cancelaciones y los cambios de mesa, con quién los pidió y quién los autorizó.',
    };
  });

  // Lo que dice la barra de abajo.
  const abajo = $derived.by(() => {
    if (fila) return { fuerte: fila.titulo, chico: [fila.tipo, fila.sub, fila.quien].filter(Boolean).join(' · ') };
    if (!reporte) return null;
    const { fuerte } = resumenAbajo(reporte);
    const cosas = [
      cuantos.descuentos ? plural(cuantos.descuentos, 'descuento', 'descuentos') : '',
      cuantos.cancelaciones ? plural(cuantos.cancelaciones, 'cancelación', 'cancelaciones') : '',
      cuantos.otros ? plural(cuantos.otros, 'otro cambio', 'otros cambios') : '',
    ].filter(Boolean);
    return { fuerte, chico: cosas.length ? cosas.join(' · ') : 'Nada se descontó ni se canceló' };
  });

  let vuelta = 0;

  async function leer() {
    const esta = ++vuelta;
    try {
      const r = await leerReporte(sucursal.id, dia);
      if (esta !== vuelta) return;
      lectura = { estado: 'listo', reporte: r };
      horaCorte = r.hora_corte;
      ultimo = { dia: r.dia, hoy: r.hoy };
      const nuevas = filasDelDia(r);
      recordarFilas(`cortes-${sucursal.id}`, nuevas.length);
      // Si lo que se veía a la derecha ya no está (otra lectura), regresa al resumen.
      if (elegida && !nuevas.some((f) => f.clave === elegida)) elegida = null;
    } catch (error) {
      console.error('[cortes] no se pudo leer reporte_del_dia:', error);
      if (esta === vuelta) lectura = { estado: 'error', deRed: esDeRed(error) };
    }
  }

  function ir(nuevo: string | null) {
    dia = nuevo && ultimo && nuevo >= ultimo.hoy ? null : nuevo;
    elegida = null;
    lectura = { estado: 'leyendo' };
    leer();
  }

  // Tocar un renglón lo enseña a la derecha; tocarlo otra vez regresa al resumen del día.
  function alElegirFila(f: FilaCortes) {
    elegida = elegida === f.clave ? null : f.clave;
  }

  let espera: ReturnType<typeof setTimeout> | undefined;
  function programar() {
    if (dia !== null && reporte && reporte.dia !== reporte.hoy) return;
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
</script>

<div class="pos-ancho cortes">
  <BarraArriba titulo="Cortes y reportes" {estado}>
    {#snippet junto()}
      <div class="dia">
        <BotonCuadro icono="anterior" ayuda="Día anterior" apagado={!ultimo || leyendo} onclick={() => ultimo && ir(diaAnterior(ultimo.dia))} />
        <span class="dia-texto">
          {#if leyendo || !reporte}
            <span class="linea"><Esqueleto ancho="150px" alto="12px" /></span>
            <small><Esqueleto ancho="132px" alto="9px" /></small>
          {:else}
            <span class="linea">{diaConNombre(reporte.dia)}</span>
            <small>{subtitulo}</small>
          {/if}
        </span>
        <BotonCuadro
          icono="siguiente"
          ayuda="Día siguiente"
          apagado={!ultimo || leyendo || ultimo.dia >= ultimo.hoy}
          onclick={() => ultimo && ir(diaSiguiente(ultimo.dia))}
        />
      </div>
    {/snippet}
    {#if dia !== null}
      <Boton etiqueta="Hoy" icono="hoy" onclick={() => ir(null)} />
    {/if}
    <!-- La hora de corte vive aquí desde el 12 nov 2026 (salió de Ajustes): justo antes de la sucursal. -->
    <HoraCorte restauranteId={sucursal.id} hora={horaCorte} alGuardar={leer} />
    <CajaSucursales {sucursales} actual={sucursal} {alElegir} />
  </BarraArriba>

  {#if lectura.estado === 'error'}
    <div class="cuerpo-ancho sin-abajo">
      <div class="medio-ancho">
        <CajaError mensaje={lectura.deRed ? SIN_CONEXION : ALGO_SALIO_PANEL} />
        <Boton etiqueta="Intentar de nuevo" icono="actualizar" onclick={() => ((lectura = { estado: 'leyendo' }), leer())} />
      </div>
    </div>
  {:else}
    <div class="cuerpo-ancho">
      <div class="dos">
        <TablaDia
          {filas}
          bind:busqueda
          filtroElegido={filtro}
          {cuantos}
          cargando={leyendo}
          filasEsqueleto={filasAntes}
          {elegida}
          {vacio}
          alFiltro={(f) => (filtro = f)}
          alElegir={alElegirFila}
        />

        {#if leyendo || !reporte}
          <Lado clave="leyendo"><Resumen reporte={null} cargando /></Lado>
        {:else if fila?.que === 'turno'}
          <Lado clave={fila.clave}><Turno turno={fila.turno} sello={fila.sello} zona={reporte.zona} /></Lado>
        {:else if fila}
          <Lado clave={fila.clave}><Detalle {fila} zona={reporte.zona} /></Lado>
        {:else}
          <Lado clave="resumen-{reporte.dia}"><Resumen {reporte} /></Lado>
        {/if}
      </div>
    </div>

    <!-- La barra de abajo de Crear anuncios: dice lo que se ve a la derecha. -->
    <footer class="barra-abajo">
      {#key `${leyendo}-${elegida ?? ''}`}
        <div class="barra-contenido">
          {#if leyendo || !abajo}
            <div class="estado" aria-hidden="true"><b><Esqueleto ancho="96px" alto="13px" /></b><small><Esqueleto ancho="220px" alto="11px" /></small></div>
          {:else}
            <div class="estado" role="status"><b>{abajo.fuerte}</b><small>{abajo.chico}</small></div>
            {#if fila}<Boton etiqueta="Cerrar" icono="cerrar" onclick={() => (elegida = null)} />{/if}
          {/if}
        </div>
      {/key}
    </footer>
  {/if}
</div>

<style>
  .dia {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .dia-texto {
    min-width: 196px;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 3px;
    text-align: center;
    white-space: nowrap;
  }

  .dia-texto .linea {
    font-size: 13.5px;
    font-weight: 700;
    line-height: 17px;
  }

  .dia-texto small {
    font-family: var(--mono);
    font-size: 10px;
    font-weight: 400;
    line-height: 12px;
    letter-spacing: 0.1em;
    color: var(--tenue);
    text-transform: uppercase;
  }
</style>
