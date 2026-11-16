<!--
  La caja (parte 4b; maqueta La caja FKj5RPPYE1tz6dcaU6F4kX; libreta 5, «Cobrar y cerrar la cuenta»
  y «El día de negocio y la caja»). Lupita o Don Chuy abren la caja con el fondo (ya trae el del
  turno pasado); sin caja abierta nadie anota pagos. «Por cobrar» son todas las cuentas abiertas,
  primero las que pidieron la cuenta; tocar una abre la hoja de cobro. «Cobradas» son las del
  turno, con su folio. Arriba: entradas y salidas de efectivo, pagar propinas y cerrar la caja con
  el corte a ciegas: se escribe lo contado y, ya cerrada, se ve la diferencia de cada método.

  Tiene el ancho del celular, también en la tableta del mostrador, como el punto de venta. La abre
  el aparato de quien tiene el rol de caja (pestaña Caja) y el panel del gerente con su sesión; por
  eso recibe la conexión y nunca importa la del panel. En el panel no lleva el restaurante arriba:
  ya lo dice la barra del panel. Las cuentas, los pagos y el turno llegan
  solos con el tiempo real.

  Con la parte 4c (maqueta Cancelaciones y descuentos): en Cobradas, tocar una cuenta enseña sus
  pagos, y cada pago del turno abierto se cancela con su motivo. Si la cuenta estaba cerrada, se
  reabre con el mismo folio y sale primero en Por cobrar como «Reabierta», sin ocupar su mesa. Quien
  usa la caja es de la caja o gerente: lo que cancela o descuenta queda a su nombre, sin otro PIN.

  Con la adaptabilidad (3c; maqueta GBWEGCsQFcwKkWm7Qe9FPA v4, pantalla «Caja»; encuestas 16 de encuestas.md y 5 a 7 de
  cobro-caja.md), con `ancho` y su `anfitrion` (≥ ~900 px, lo decide quien la abre) pinta su propia barra de arriba,
  como el punto de venta: el chip «Caja abierta desde las 08:00» y, con turno, «Entrada o salida», «Propinas» y «Cerrar
  caja». A la izquierda la búsqueda con el filtro Por cobrar · Cobradas · Todas y la tabla de Mi menú (caja/caja/); a la
  derecha la tarjeta de 400: «Toca una cuenta para cobrarla», el cobro (pos/cobro/, el mismo de Vender), la cobrada,
  abrir la caja, el corte a ciegas y su resultado, sin tapar la lista. Abajo la barra de Crear anuncios. Las hojas de
  siempre (entrada o salida, propinas, cancelar un pago) salen al centro. Más angosto, la columna de hoy sin cambios.
-->
<script lang="ts">
  import type { SupabaseClient } from '@supabase/supabase-js';
  import { onDestroy, onMount, type Snippet } from 'svelte';
  import Boton from '../../diseno/Boton.svelte';
  import CajaError from '../../diseno/CajaError.svelte';
  import Esqueleto from '../../diseno/Esqueleto.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import Selector from '../../diseno/Selector.svelte';
  import { filasDeLaUltimaVez, recordarFilas } from '../../lib/esqueletos';
  import { pesos, plural } from '../../lib/formato';
  import Barra from '../pos/ancho/Barra.svelte';
  import type { Anfitrion } from '../pos/ancho/barra';
  import { sinAcentos } from '../pos/ancho/buscar';
  import Lado from '../pos/ancho/Lado.svelte';
  import '../pos/ancho/ancho.css';
  import Abajo from '../pos/cobro/Abajo.svelte';
  import CobradaVista from '../pos/cobro/Cobrada.svelte';
  import { Cobro } from '../pos/cobro/cobro.svelte';
  import Encima from '../pos/cobro/Encima.svelte';
  import Tarjeta from '../pos/cobro/Tarjeta.svelte';
  import AbrirCaja from './caja/AbrirCaja.svelte';
  import CobradaLado from './caja/CobradaLado.svelte';
  import Corte from './caja/Corte.svelte';
  import type { FilaCaja, FiltroCaja } from './caja/filas';
  import Resultado from './caja/Resultado.svelte';
  import TablaCuentas from './caja/TablaCuentas.svelte';
  import {
    abrirTurno,
    cerrarTurno,
    faltaDe,
    leerCobradas,
    leerMonto,
    leerPagos,
    leerTurno,
    movimientoCaja,
    NOMBRE_METODO,
    resumenTurno,
    type Cobrada,
    type Metodo,
    type Pago,
    type PropinaDe,
    type ResumenTurno,
    type Turno,
  } from '../../lib/caja';
  import { ALGO_SALIO_PANEL, esDeRed, SIN_CONEXION } from '../../lib/errores';
  import { dinero, enZona } from '../../lib/formato';
  import {
    escuchar,
    FalloPos,
    ICONO_DE_TIPO,
    TIPO_EN_PALABRAS,
    leerAbiertas,
    leerNombres,
    leerZona,
    nombreDeCuenta,
    type Comanda,
    type Renglon,
    type Venta,
  } from '../../lib/pos';
  import Hoja from '../pos/Hoja.svelte';
  import HojaCancelarPago from '../pos/HojaCancelarPago.svelte';
  import HojaCobrar from '../pos/HojaCobrar.svelte';
  import Lugar from '../pos/Lugar.svelte';
  import MarcaEstado from '../pos/MarcaEstado.svelte';
  import PagoHecho from '../pos/PagoHecho.svelte';
  import '../pos/pos.css';

  let {
    cliente,
    restauranteId,
    restaurante,
    linea = '',
    enPanel = false,
    pestanas,
    ancho = false,
    anfitrion = null,
  }: {
    cliente: SupabaseClient;
    restauranteId: string;
    restaurante: string;
    linea?: string; // quién está: «Lupita Hernández · Caja»; en el panel no se pinta
    enPanel?: boolean;
    pestanas?: Snippet;
    ancho?: boolean; // a lo ancho (≥ ~900 px): lo decide quien la abre
    anfitrion?: Anfitrion | null; // quién la abre, para la barra de arriba a lo ancho
  } = $props();

  type Hojas =
    | { tipo: 'cobrar'; venta: Venta }
    | { tipo: 'mov'; clave: string; sale: boolean; monto: string; motivo: string }
    | { tipo: 'propinas'; clave: string; propinas: PropinaDe[] | null; elegida: PropinaDe | null; monto: string }
    | { tipo: 'folio'; cobrada: Cobrada; pagos: Pago[] | null }
    | { tipo: 'cancelarPago'; cobrada: Cobrada; pago: Pago };

  // ─── Lo que llega de Postgres ───
  let carga = $state<{ estado: 'leyendo' } | { estado: 'listo' } | { estado: 'error'; mensaje: string }>({ estado: 'leyendo' });
  let turno = $state<Turno | null>(null);
  let ultimoFondo = $state<number | null>(null);
  let ventas = $state<Venta[]>([]);
  let comandas = $state<Comanda[]>([]);
  let renglones = $state<Renglon[]>([]);
  let cobradas = $state<Cobrada[]>([]);
  let nombres = $state(new Map<number, string>());
  let zona = $state('America/Mexico_City');

  // ─── Lo que se ve ───
  let pantalla = $state<'caja' | 'corte' | 'resultado'>('caja');
  let vista = $state<'porcobrar' | 'cobradas'>('porcobrar');
  let hoja = $state<Hojas | null>(null);
  let fondo = $state('');
  let fondoTocado = $state(false);
  let contado = $state<Record<Metodo, string>>({ efectivo: '', tarjeta: '', transferencia: '' });
  let resultado = $state<ResumenTurno | null>(null);
  let error = $state<string | null>(null);
  let errorHoja = $state<string | null>(null);
  let ocupado = $state(false);
  let globo = $state<string | null>(null);

  const quien = (id: number | null) => (id === null ? '—' : (nombres.get(id) ?? '—'));
  const hora = (momento: string) => enZona(momento, zona).hora;
  const pila = (nombre: string | null) => (nombre ?? '—').trim().split(/\s+/)[0];

  function avisar(texto: string) {
    globo = texto;
    setTimeout(() => {
      if (globo === texto) globo = null;
    }, 1600);
  }

  function mensaje(falla: unknown, contexto: string): string {
    if (falla instanceof FalloPos) return falla.message;
    console.error(`[caja] ${contexto}:`, falla);
    return esDeRed(falla) ? SIN_CONEXION : ALGO_SALIO_PANEL;
  }

  // ─── Leer ───
  let leyendo: Promise<void> | null = null;
  let otraVez = false;
  async function leer(): Promise<void> {
    if (leyendo) {
      otraVez = true;
      return leyendo;
    }
    leyendo = (async () => {
      do {
        otraVez = false;
        const [t, abiertas, n, z] = await Promise.all([
          leerTurno(cliente, restauranteId),
          leerAbiertas(cliente, restauranteId),
          leerNombres(cliente, restauranteId),
          leerZona(cliente, restauranteId),
        ]);
        turno = t.abierto;
        ultimoFondo = t.ultimoFondo;
        ventas = abiertas.ventas;
        comandas = abiertas.comandas;
        renglones = abiertas.renglones;
        nombres = n;
        zona = z;
        cobradas = t.abierto ? await leerCobradas(cliente, restauranteId, t.abierto.id) : [];
        if (!fondoTocado) fondo = ultimoFondo === null ? '' : ultimoFondo.toFixed(2);
      } while (otraVez);
    })().finally(() => (leyendo = null));
    return leyendo;
  }

  async function leerTodo() {
    try {
      await leer();
      carga = { estado: 'listo' };
      recordarFilas(`caja-${restauranteId}`, ventas.length);
    } catch (falla) {
      console.error('[caja] no se pudo leer la caja:', falla);
      if (carga.estado !== 'listo') carga = { estado: 'error', mensaje: esDeRed(falla) ? SIN_CONEXION : ALGO_SALIO_PANEL };
    }
  }

  function recargar() {
    leer().catch((falla) => console.error('[caja] no se pudo volver a leer la caja:', falla));
  }

  // Primero las reabiertas, luego las que pidieron la cuenta; después, en el orden en que se abrieron.
  const prioridad = (v: Venta) => (v.folio !== null ? 0 : v.cuenta_pedida_at ? 1 : 2);
  const porCobrar = $derived([...ventas].sort((a, b) => prioridad(a) - prioridad(b)));
  // «En cocina» mientras alguna comanda espera con algo que no se canceló.
  const enCocina = (v: Venta) =>
    comandas.some(
      (k) => k.venta_id === v.id && k.estado === 'pendiente' && renglones.some((r) => r.comanda_id === k.id && r.estado === 'activo'),
    );
  const estadoDe = (v: Venta): 'reabierta' | 'cuenta' | 'cocina' | 'ocupada' =>
    v.folio !== null ? 'reabierta' : v.cuenta_pedida_at ? 'cuenta' : enCocina(v) ? 'cocina' : 'ocupada';

  // ─── Los pagos de una cuenta cobrada ───
  async function abrirFolio(c: Cobrada) {
    hoja = { tipo: 'folio', cobrada: c, pagos: null };
    errorHoja = null;
    try {
      const pagos = await leerPagos(cliente, restauranteId, [c.id]);
      if (hoja?.tipo === 'folio' && hoja.cobrada.id === c.id) hoja.pagos = pagos;
    } catch (falla) {
      errorHoja = mensaje(falla, 'no se pudieron leer los pagos de la cuenta');
    }
  }

  // ─── Abrir la caja ───
  async function abrir() {
    const n = leerMonto(fondo);
    if (n === null) {
      error = 'Escribe el fondo en pesos, como «500».';
      return;
    }
    ocupado = true;
    error = null;
    try {
      await abrirTurno(cliente, restauranteId, n);
      fondoTocado = false;
      vista = 'porcobrar';
      await leer();
      avisar('Caja abierta');
    } catch (falla) {
      error = mensaje(falla, 'no se pudo abrir la caja');
    } finally {
      ocupado = false;
    }
  }

  // ─── Entradas, salidas y propinas ───
  async function anotarMovimiento() {
    if (hoja?.tipo !== 'mov') return;
    const h = hoja;
    const n = leerMonto(h.monto);
    if (n === null || n <= 0) {
      errorHoja = 'Escribe el monto en pesos, como «300».';
      return;
    }
    ocupado = true;
    errorHoja = null;
    try {
      await movimientoCaja(cliente, restauranteId, { clave: h.clave, tipo: h.sale ? 'retiro' : 'ingreso', monto: n, motivo: h.motivo, mesero: null });
      hoja = null;
      avisar(h.sale ? 'Salida anotada' : 'Entrada anotada');
    } catch (falla) {
      errorHoja = mensaje(falla, 'no se pudo anotar el movimiento');
    } finally {
      ocupado = false;
    }
  }

  async function abrirPropinas() {
    if (!turno) return;
    hoja = { tipo: 'propinas', clave: crypto.randomUUID(), propinas: null, elegida: null, monto: '' };
    errorHoja = null;
    try {
      const r = await resumenTurno(cliente, turno.id);
      if (hoja?.tipo === 'propinas') hoja.propinas = r.propinas;
    } catch (falla) {
      errorHoja = mensaje(falla, 'no se pudieron leer las propinas');
    }
  }

  async function pagarPropina() {
    if (hoja?.tipo !== 'propinas' || !hoja.elegida) return;
    const h = hoja;
    const n = leerMonto(h.monto);
    if (n === null || n <= 0) {
      errorHoja = 'Escribe el monto en pesos, como «70».';
      return;
    }
    ocupado = true;
    errorHoja = null;
    try {
      await movimientoCaja(cliente, restauranteId, { clave: h.clave, tipo: 'retiro', monto: n, motivo: '', mesero: h.elegida!.miembro_id });
      hoja = null;
      avisar(`Propinas pagadas a ${pila(h.elegida!.nombre)}`);
    } catch (falla) {
      errorHoja = mensaje(falla, 'no se pudieron pagar las propinas');
    } finally {
      ocupado = false;
    }
  }

  // ─── El corte ───
  const contadoListo = $derived((['efectivo', 'tarjeta', 'transferencia'] as const).every((m) => leerMonto(contado[m]) !== null));

  async function cerrar() {
    if (!contadoListo) return;
    ocupado = true;
    error = null;
    try {
      const id = await cerrarTurno(cliente, restauranteId, {
        efectivo: leerMonto(contado.efectivo)!,
        tarjeta: leerMonto(contado.tarjeta)!,
        transferencia: leerMonto(contado.transferencia)!,
      });
      resultado = await resumenTurno(cliente, id);
      pantalla = 'resultado';
      contado = { efectivo: '', tarjeta: '', transferencia: '' };
      recargar();
    } catch (falla) {
      error = mensaje(falla, 'no se pudo cerrar la caja');
    } finally {
      ocupado = false;
    }
  }

  function diferencia(d: number): { texto: string; clase: string } {
    if (d === 0) return { texto: 'Cuadra', clase: 'cuadra' };
    if (d < 0) return { texto: `Faltan ${dinero(-d)}`, clase: 'falta' };
    return { texto: `Sobran ${dinero(d)}`, clase: '' };
  }

  // ─── A lo ancho (adaptabilidad 3c; maqueta GBWEGCsQFcwKkWm7Qe9FPA v4) ───
  let filtro = $state<FiltroCaja>('porcobrar');
  let busqueda = $state('');
  // Lo que enseña la tarjeta de la derecha: nada (encuesta 5: «Toca una cuenta para cobrarla»), el cobro de una cuenta
  // por cobrar o una cobrada de la lista. El corte y Abrir caja salen por `pantalla` y por el turno.
  let elegida = $state<string | null>(null);
  let cobro = $state.raw<Cobro | null>(null);
  // La cuenta que se cobra, como estaba al tocarla: al cerrarse ya no sale en Por cobrar, y su Cobrada la sigue nombrando.
  let cobroDe = $state.raw<{ id: number; titulo: string; tipo: Venta['tipo']; abrio: string | null; como: string; desde: string } | null>(null);
  // svelte-ignore state_referenced_locally
  const filasAntes = filasDeLaUltimaVez(`caja-${restauranteId}`);

  const comoDe = (tipo: Venta['tipo']) => (tipo === 'mesa' ? 'Mesa' : TIPO_EN_PALABRAS[tipo]);
  const filaDeVenta = (v: Venta): FilaCaja => {
    const titulo = nombreDeCuenta(v);
    const quienAbrio = v.abierta_por === null ? 'En línea' : quien(v.abierta_por);
    return {
      clave: `v${v.id}`,
      id: v.id,
      cobrada: false,
      titulo,
      icono: ICONO_DE_TIPO[v.tipo],
      como: comoDe(v.tipo),
      abrio: `${quienAbrio} · ${hora(v.created_at)}`,
      total: v.total,
      falta: v.pagado > 0 || v.folio !== null ? faltaDe(v) : null,
      whatsapp: v.origen === 'menu_en_linea',
      marca: v.folio !== null ? 'Reabierta' : v.cuenta_pedida_at ? 'Pidió la cuenta' : null,
      buscar: sinAcentos(`${titulo} ${v.pedido_numero ?? ''} ${v.folio ?? ''}`),
    };
  };
  const filaDeCobrada = (c: Cobrada): FilaCaja => ({
    clave: `c${c.id}`,
    id: c.id,
    cobrada: true,
    titulo: c.titulo,
    icono: ICONO_DE_TIPO[c.tipo],
    como: comoDe(c.tipo),
    abrio: `${c.abierta_por === null ? 'En línea' : quien(c.abierta_por)} · ${hora(c.abierta_at)}`,
    total: c.total,
    falta: null,
    whatsapp: c.whatsapp,
    marca: null,
    buscar: sinAcentos(`${c.titulo} ${c.folio}`),
  });
  const filasCaja = $derived.by(() => {
    const q = sinAcentos(busqueda);
    const filas = [
      ...(filtro !== 'cobradas' ? porCobrar.map(filaDeVenta) : []),
      ...(filtro !== 'porcobrar' ? cobradas.map(filaDeCobrada) : []),
    ];
    return q ? filas.filter((f) => f.buscar.includes(q.replace(/^#/, ''))) : filas;
  });
  const vacioCaja = $derived(
    busqueda.trim()
      ? { titulo: 'Nada con ese número o nombre', texto: 'Prueba con otro, o con otro filtro.' }
      : filtro === 'cobradas'
        ? { titulo: 'Nada cobrado todavía', texto: 'Las cuentas que se cierren en este turno salen aquí, con su folio.' }
        : { titulo: 'Nada por cobrar', texto: 'Las cuentas abiertas salen aquí.' },
  );
  const sumaPorCobrar = $derived(ventas.reduce((t, v) => t + faltaDe(v), 0));
  const cobradaElegida = $derived(elegida?.[0] === 'c' ? (cobradas.find((c) => `c${c.id}` === elegida) ?? null) : null);

  function soltarCobro() {
    cobro?.destruir();
    cobro = null;
    cobroDe = null;
  }

  // Tocar una cuenta por cobrar abre su cobro a la derecha, sin tapar la lista.
  function cobrarVenta(v: Venta) {
    soltarCobro();
    const venta = { id: v.id, titulo: nombreDeCuenta(v), tipo: v.tipo, abrio: v.abierta_por === null ? null : quien(v.abierta_por) };
    cobroDe = { ...venta, como: comoDe(v.tipo), desde: hora(v.created_at) };
    cobro = new Cobro(() => ({
      cliente,
      restauranteId,
      venta,
      cuenta: ventas.find((x) => x.id === venta.id) ?? null,
      turnoId: turno?.id ?? null,
      nombres,
      autorizan: null,
      zona,
      renglones,
      alAviso: avisar,
    }));
    elegida = `v${v.id}`;
    pantalla = 'caja';
    error = null;
  }

  function alElegirFila(f: FilaCaja) {
    if (f.cobrada) {
      soltarCobro();
      elegida = f.clave;
      pantalla = 'caja';
      error = null;
      return;
    }
    const v = ventas.find((x) => x.id === f.id);
    if (v) cobrarVenta(v);
  }

  function irAlCorte() {
    soltarCobro();
    elegida = null;
    pantalla = 'corte';
    error = null;
  }

  // Cancelar un pago de una cobrada la reabre con su folio: a lo ancho, sale en Por cobrar con su cobro abierto.
  async function alReabrir(ventaId: number) {
    filtro = 'porcobrar';
    soltarCobro();
    elegida = null;
    await leer().catch((falla) => console.error('[caja] no se pudo volver a leer la caja:', falla));
    const v = ventas.find((x) => x.id === ventaId);
    if (v) cobrarVenta(v);
  }

  const chipCaja = $derived(
    carga.estado === 'leyendo'
      ? { texto: 'Cargando la caja…', vivo: true }
      : carga.estado === 'error'
        ? { texto: 'No se pudo leer', vivo: false }
        : turno
          ? { texto: `Caja abierta desde las ${hora(turno.created_at)}`, vivo: true }
          : { texto: 'Caja sin abrir', vivo: false, pausa: true },
  );

  onDestroy(soltarCobro);

  // ─── Al abrir ───
  onMount(() => {
    leerTodo();
    const dejar = escuchar(cliente, restauranteId, ['ventas', 'comandas', 'pagos', 'turnos'], () => {
      if (carga.estado === 'listo') recargar();
    });
    const alVolver = () => {
      if (document.visibilityState === 'visible') leerTodo();
    };
    document.addEventListener('visibilitychange', alVolver);
    return () => {
      dejar();
      document.removeEventListener('visibilitychange', alVolver);
    };
  });
</script>

{#snippet caraAncha(a: Anfitrion)}
  <div class="pos-ancho">
    <Barra anfitrion={a} titulo="Caja" chip={chipCaja}>
      {#if turno && carga.estado === 'listo'}
        <Boton
          etiqueta="Entrada o salida"
          icono="cambiar"
          onclick={() => ((hoja = { tipo: 'mov', clave: crypto.randomUUID(), sale: true, monto: '', motivo: '' }), (errorHoja = null))}
        />
        <Boton etiqueta="Propinas" icono="propina" onclick={abrirPropinas} />
        <Boton etiqueta="Cerrar caja" icono="corte" tono="tinta" apagado={pantalla === 'corte'} onclick={irAlCorte} />
      {/if}
    </Barra>

    {#if carga.estado === 'error'}
      <div class="cuerpo-ancho sin-abajo">
        <div class="medio-ancho">
          <CajaError mensaje={carga.mensaje} />
          <Boton etiqueta="Intentar de nuevo" icono="actualizar" onclick={() => ((carga = { estado: 'leyendo' }), leerTodo())} />
        </div>
      </div>
    {:else}
      {@const leyendo = carga.estado === 'leyendo'}
      <div class="cuerpo-ancho">
        <div class="dos">
          <TablaCuentas
            filas={filasCaja}
            bind:busqueda
            filtroElegido={filtro}
            cuentas={{ porcobrar: ventas.length, cobradas: cobradas.length }}
            cargando={leyendo}
            filasEsqueleto={filasAntes}
            {elegida}
            vacio={vacioCaja}
            alFiltro={(f) => (filtro = f)}
            alElegir={alElegirFila}
          />

          {#if leyendo}
            <!-- Con la forma de «Toca una cuenta para cobrarla», lo que sale casi siempre, para que nada brinque. -->
            <Lado clave="leyendo">
              <span class="solo-lector" role="status">Abriendo la caja…</span>
              <div class="encabezado" aria-hidden="true">
                <Esqueleto ancho="36px" alto="36px" redondo="11px" />
                <div class="titulos"><Esqueleto ancho="210px" alto="15px" /><Esqueleto ancho="268px" alto="12px" /></div>
              </div>
              <div class="datos-c" aria-hidden="true">
                <span><Esqueleto ancho="150px" alto="12px" /></span>
                <span><Esqueleto ancho="96px" alto="12px" /></span>
              </div>
            </Lado>
          {:else if pantalla === 'corte' && turno}
            <Lado clave="corte">
              <Corte
                turno="Turno de {quien(turno.abierto_por)} · desde las {hora(turno.created_at)}"
                bind:contado
                abiertas={ventas.length}
                {error}
              />
            </Lado>
          {:else if pantalla === 'resultado' && resultado}
            <Lado clave="resultado"><Resultado r={resultado} {hora} /></Lado>
          {:else if !turno}
            <Lado clave="abrir">
              <AbrirCaja
                {fondo}
                {ultimoFondo}
                {error}
                {ocupado}
                alFondo={(v) => ((fondo = v), (fondoTocado = true), (error = null))}
                alAbrir={abrir}
              />
            </Lado>
          {:else if cobro && cobroDe}
            {@const de = cobroDe}
            {#if cobro.cerrada}
              {@const x = cobro.cerrada}
              <Lado clave="cerrada-{de.id}">
                <CobradaVista
                  titulo="{de.titulo.split(' · ')[0]} cerrada"
                  folio={x.folio}
                  lineas={x.lineas}
                  subtotal={x.subtotal}
                  descuento={x.descuento}
                  total={x.total}
                  pagos={x.pagos}
                />
              </Lado>
            {:else}
              <Lado clave="cobro-{de.id}">
                <Tarjeta {cobro} titulo={de.tipo === 'mesa' ? de.titulo : `${de.titulo} · ${de.como}`} />
              </Lado>
            {/if}
          {:else if cobradaElegida}
            {@const c = cobradaElegida}
            <Lado clave="cobrada-{c.id}">
              <CobradaLado
                {cliente}
                {restauranteId}
                cobrada={c}
                turnoId={turno.id}
                {nombres}
                {zona}
                alCancelar={(p) => ((hoja = { tipo: 'cancelarPago', cobrada: c, pago: p }), (errorHoja = null))}
              />
            </Lado>
          {:else}
            <Lado clave="nada">
              <div class="encabezado">
                <span class="cuadro-c"><Icono nombre="billete" tamano={18} /></span>
                <div class="titulos">
                  <span class="titulo">Toca una cuenta para cobrarla</span>
                  <span class="sub">Su cobro sale aquí y la lista se queda a la vista.</span>
                </div>
              </div>
              <div class="datos-c">
                <span><Icono nombre="reloj" tamano={14} /><span>Abrió {quien(turno.abierto_por)} a las {hora(turno.created_at)}</span></span>
                <span><Icono nombre="billete" tamano={14} /><span>Fondo <span class="mono">{pesos(turno.fondo_inicial)}</span></span></span>
              </div>
            </Lado>
          {/if}
        </div>
      </div>

      <!-- La barra de abajo de Crear anuncios: cambia con lo que hay en la tarjeta. -->
      <footer class="barra-abajo">
        {#key `${leyendo}-${pantalla}-${cobro && cobroDe ? `c${cobroDe.id}-${!!cobro.cerrada}` : (elegida ?? '')}-${!!turno}`}
          <div class="barra-contenido">
            {#if leyendo}
              <div class="estado" aria-hidden="true"><b><Esqueleto ancho="120px" alto="13px" /></b><small><Esqueleto ancho="140px" alto="11px" /></small></div>
            {:else if pantalla === 'corte' && turno}
              <div class="estado"><b>Cerrar caja</b><small>Es a ciegas: lo esperado sale al cerrar.</small></div>
              <Boton etiqueta="Atrás" icono="anterior" apagado={ocupado} onclick={() => ((pantalla = 'caja'), (error = null))} />
              <Boton etiqueta="Cerrar caja" tono="tinta" apagado={!contadoListo} cargando={ocupado} onclick={cerrar} />
            {:else if pantalla === 'resultado' && resultado}
              <div class="estado"><b>Caja cerrada</b>{#if resultado.cerrado_at}<small>Corte de las {hora(resultado.cerrado_at)}</small>{/if}</div>
              <Boton etiqueta="Listo" tono="tinta" onclick={() => ((pantalla = 'caja'), (filtro = 'porcobrar'), (resultado = null))} />
            {:else if turno && cobro && cobroDe}
              <Abajo
                {cobro}
                fuerte={cobro.cerrada ? `${cobroDe.titulo.split(' · ')[0]} cerrada` : cobroDe.titulo}
                chico={cobro.cerrada
                  ? 'Toca otra cuenta para cobrarla'
                  : `${cobroDe.tipo === 'mesa' ? '' : `${cobroDe.como} · `}${cobroDe.abrio ? `abrió ${cobroDe.abrio} a las ${cobroDe.desde}` : `llegó en línea a las ${cobroDe.desde}`}`}
              />
            {:else if turno && cobradaElegida}
              <div class="estado"><b>{cobradaElegida.titulo}</b><small>Folio {cobradaElegida.folio} · cerrada a las {hora(cobradaElegida.cerrada_at)}</small></div>
            {:else}
              <div class="estado" role="status">
                {#if ventas.length}
                  <b>{plural(ventas.length, 'cuenta por cobrar', 'cuentas por cobrar')}</b><small>Suman {pesos(sumaPorCobrar)}</small>
                {:else}
                  <b>Nada por cobrar</b>
                {/if}
              </div>
            {/if}
          </div>
        {/key}
      </footer>
    {/if}

    <div class="pos capa-hojas">
      {@render hojas()}
      {#if cobro}<Encima {cobro} />{/if}
    </div>

    {#if globo}
      <div class="globo-a" role="status"><Icono nombre="check" tamano={14} />{globo}</div>
    {/if}
  </div>
{/snippet}

{#if ancho && anfitrion}
  {@render caraAncha(anfitrion)}
{:else}
<div class="pos">
  {#if carga.estado !== 'listo'}
    {#if !enPanel}<Lugar {restaurante} {linea} />{/if}
    {@render pestanas?.()}
    <div class="desliza">
      {#if carga.estado === 'error'}
        <CajaError mensaje={carga.mensaje} />
      {:else}
        <div class="vacio"><span>Abriendo la caja…</span></div>
      {/if}
    </div>
    {#if carga.estado === 'error'}
      <div class="cel-pie">
        <button type="button" class="cel-boton contorno crece" onclick={() => ((carga = { estado: 'leyendo' }), leerTodo())}>
          Intentar de nuevo
        </button>
      </div>
    {/if}
  {:else if pantalla === 'corte' && turno}
    <div class="cel-arriba">
      <button type="button" class="cel-volver" onclick={() => ((pantalla = 'caja'), (error = null))}>
        <Icono nombre="anterior" tamano={16} />Caja
      </button>
      <div class="cuenta-titulo">
        <b>Cerrar caja</b>
        <span>Turno de {quien(turno.abierto_por)} · desde las {hora(turno.created_at)}</span>
      </div>
    </div>
    <div class="desliza">
      <p class="cel-texto">Cuenta lo que hay y escríbelo. Lo esperado sale cuando cierres.</p>
      {#each [{ m: 'efectivo', etq: 'Efectivo en el cajón', pista: 'Billetes y monedas, con el fondo.' }, { m: 'tarjeta', etq: 'Cierre de la terminal', pista: 'Lo que dice el corte de la terminal de tarjeta.' }, { m: 'transferencia', etq: 'Transferencias', pista: 'Lo que llegó a la cuenta del restaurante.' }] as const as c (c.m)}
        <div class="campo">
          <label class="etq" for="corte-{c.m}">{c.etq}</label>
          <input id="corte-{c.m}" inputmode="decimal" autocomplete="off" placeholder="$0.00" bind:value={contado[c.m]} />
          <p class="pista">{c.pista}</p>
        </div>
      {/each}
      {#if ventas.length}
        <CajaError
          mensaje={ventas.length === 1
            ? 'Queda una cuenta abierta. La cobra el siguiente turno.'
            : `Quedan ${ventas.length} cuentas abiertas. Las cobra el siguiente turno.`}
        />
      {/if}
      {#if error}<CajaError mensaje={error} />{/if}
    </div>
    <div class="cel-pie">
      <button type="button" class="cel-boton" disabled={!contadoListo || ocupado} onclick={cerrar}>Cerrar caja</button>
    </div>
  {:else if pantalla === 'resultado' && resultado}
    {@const r = resultado}
    <div class="cel-arriba">
      <div class="cuenta-titulo">
        <b>Corte de caja</b>
        <span>
          Turno de {pila(r.abierto_por)} · {hora(r.abierto_at)} a {r.cerrado_at ? hora(r.cerrado_at) : '—'} · cerró {pila(r.cerrado_por)}
        </span>
      </div>
    </div>
    <div class="desliza">
      <div class="bloque">
        <div class="bloque-cabeza"><span class="etq">Lo contado contra lo esperado</span></div>
        <div class="tabla-corte">
          <div class="f cab"><span>Método</span><span class="n">Esperado</span><span class="n">Contado</span></div>
          {#each r.cortes ?? [] as k (k.metodo)}
            {@const d = diferencia(k.diferencia)}
            <div class="f">
              <span>{NOMBRE_METODO[k.metodo]}</span>
              <span class="n">{dinero(k.esperado)}</span>
              <span class="n">{dinero(k.contado)}</span>
              <span class="dif {d.clase}">{d.texto}</span>
            </div>
          {/each}
        </div>
        <p class="pista">En efectivo, lo esperado es el fondo más lo cobrado y las entradas, menos las salidas. Las propinas cuentan.</p>
      </div>
      {#if r.por_persona?.length}
        <div class="bloque">
          <div class="bloque-cabeza"><span class="etq">Quién cobró</span></div>
          <div class="lista-simple">
            {#each r.por_persona as q (q.miembro_id)}
              <div class="f">
                <span>
                  {pila(q.nombre)}
                  <small>{(['efectivo', 'tarjeta', 'transferencia'] as const).filter((m) => q[m] > 0).map((m) => `${NOMBRE_METODO[m]} ${dinero(q[m])}`).join(' · ')}</small>
                </span>
                <span class="n">{dinero(q.total)}</span>
              </div>
            {/each}
          </div>
        </div>
      {/if}
      {#if r.propinas.length}
        <div class="bloque">
          <div class="bloque-cabeza"><span class="etq">Propinas</span></div>
          <div class="lista-simple">
            {#each r.propinas as p (p.miembro_id)}
              <div class="f">
                <span>{pila(p.nombre)}<small>Pagado {dinero(p.pagado)}{p.falta > 0 ? ` · falta ${dinero(p.falta)}` : ' · al corriente'}</small></span>
                <span class="n">{dinero(p.total)}</span>
              </div>
            {/each}
          </div>
        </div>
      {/if}
      {#if r.movimientos?.length}
        <div class="bloque">
          <div class="bloque-cabeza"><span class="etq">Entradas y salidas</span></div>
          <div class="lista-simple">
            {#each r.movimientos as m, i (i)}
              <div class="f">
                <span>{m.motivo}<small>{m.tipo === 'retiro' ? 'Salida' : 'Entrada'} · {pila(m.registrado_por)} · {hora(m.created_at)}</small></span>
                <span class="n">{m.tipo === 'retiro' ? '−' : '+'}{dinero(m.monto)}</span>
              </div>
            {/each}
          </div>
        </div>
      {/if}
      {#if r.cuentas_abiertas}
        <p class="pista">
          {r.cuentas_abiertas === 1
            ? 'Quedó una cuenta abierta para el siguiente turno.'
            : `Quedaron ${r.cuentas_abiertas} cuentas abiertas para el siguiente turno.`}
        </p>
      {/if}
    </div>
    <div class="cel-pie">
      <button type="button" class="cel-boton" onclick={() => ((pantalla = 'caja'), (vista = 'porcobrar'), (resultado = null))}>Listo</button>
    </div>
  {:else}
    {#if !enPanel}<Lugar {restaurante} {linea} />{/if}
    {@render pestanas?.()}
    {#if !turno}
      <div class="abrir-caja">
        <div class="turno-cabeza">
          <span class="punto apagado"></span>
          <div class="t"><b>La caja está cerrada</b><span>Ábrela con el efectivo que hay en el cajón.</span></div>
        </div>
        <div class="campo">
          <label class="etq" for="fondo">Fondo</label>
          <input
            id="fondo"
            inputmode="decimal"
            autocomplete="off"
            placeholder="$0.00"
            value={fondo}
            oninput={(e) => ((fondo = e.currentTarget.value), (fondoTocado = true), (error = null))}
          />
        </div>
        <p class="pista">
          {ultimoFondo === null ? '¿Con cuánto efectivo arranca la caja?' : 'Es el fondo del turno pasado. Cámbialo si hoy dejas otro.'}
        </p>
        {#if error}<CajaError mensaje={error} />{/if}
        <button type="button" class="cel-boton fijo" disabled={!fondo.trim() || ocupado} onclick={abrir}>Abrir caja</button>
      </div>
    {:else}
      <div class="turno">
        <div class="turno-cabeza">
          <span class="punto"></span>
          <div class="t">
            <b>Caja abierta</b>
            <span>Desde las {hora(turno.created_at)} · abrió {quien(turno.abierto_por)} · fondo {dinero(turno.fondo_inicial)}</span>
          </div>
        </div>
        <div class="turno-botones">
          <button
            type="button"
            class="boton-chico"
            onclick={() => ((hoja = { tipo: 'mov', clave: crypto.randomUUID(), sale: true, monto: '', motivo: '' }), (errorHoja = null))}
          >
            <Icono nombre="cambiar" tamano={14} />Entrada o salida
          </button>
          <button type="button" class="boton-chico" onclick={abrirPropinas}><Icono nombre="propina" tamano={14} />Propinas</button>
          <button type="button" class="boton-chico tinta" onclick={() => ((pantalla = 'corte'), (error = null))}>
            <Icono nombre="corte" tamano={14} />Cerrar caja
          </button>
        </div>
      </div>
    {/if}

    <div class="arriba-vista">
      <Selector
        vidrio
        etiqueta="Qué cuentas"
        lleno
        alto={30}
        opciones={[
          { valor: 'porcobrar', texto: `Por cobrar · ${ventas.length}` },
          { valor: 'cobradas', texto: `Cobradas · ${cobradas.length}` },
        ]}
        elegida={turno ? vista : 'porcobrar'}
        alElegir={(v) => (vista = turno ? v : 'porcobrar')}
      />
    </div>

    <div class="desliza lista">
      {#if vista === 'porcobrar' || !turno}
        {#each porCobrar as v (v.id)}
          <button type="button" class="fila-cobro" onclick={() => (hoja = { tipo: 'cobrar', venta: v })}>
            <span class="cuadro-icono"><Icono nombre={ICONO_DE_TIPO[v.tipo]} tamano={18} /></span>
            <span class="t">
              {#if v.folio !== null}<span class="etq">Folio {v.folio}</span>{/if}
              <b>{nombreDeCuenta(v)}</b>
              <span class="tipo">
                {v.tipo === 'mesa' ? '' : `${TIPO_EN_PALABRAS[v.tipo]} · `}Abrió {quien(v.abierta_por)} · {hora(v.created_at)}
              </span>
              <MarcaEstado estado={estadoDe(v)} whatsapp={v.origen === 'menu_en_linea'} />
            </span>
            <span class="der">
              <span class="mesa-total">{dinero(v.total)}</span>
              {#if v.pagado > 0 || v.folio !== null}<span class="falta-chica">Falta {dinero(faltaDe(v))}</span>{/if}
            </span>
          </button>
        {:else}
          <div class="vacio"><b>Nada por cobrar</b><span>Las cuentas abiertas salen aquí.</span></div>
        {/each}
      {:else}
        {#each cobradas as c (c.id)}
          <button type="button" class="fila-cobro cobrada" onclick={() => abrirFolio(c)}>
            <span class="cuadro-icono"><Icono nombre={c.tipo === 'mesa' ? 'mesas' : c.tipo === 'domicilio' ? 'moto' : 'bolsa'} tamano={18} /></span>
            <span class="t">
              <span class="etq">Folio {c.folio}</span>
              <b>{c.titulo}</b>
              <span class="tipo">{c.metodos.map((m) => NOMBRE_METODO[m]).join(' + ')} · {hora(c.cerrada_at)}</span>
              {#if c.whatsapp}<MarcaEstado estado="ocupada" whatsapp />{/if}
            </span>
            <span class="der"><span class="mesa-total">{dinero(c.total)}</span></span>
          </button>
        {:else}
          <div class="vacio"><b>Nada cobrado todavía</b><span>Las cuentas que se cierren en este turno salen aquí, con su folio.</span></div>
        {/each}
      {/if}
    </div>
  {/if}

  {@render hojas()}

  {#if globo}
    <div class="globo" role="status"><Icono nombre="check" tamano={14} />{globo}</div>
  {/if}
</div>
{/if}

{#snippet hojas()}
  {#if hoja?.tipo === 'cobrar'}
    {@const v = hoja.venta}
    <HojaCobrar
      {cliente}
      {restauranteId}
      venta={{ id: v.id, titulo: nombreDeCuenta(v), tipo: v.tipo, abrio: v.abierta_por === null ? null : quien(v.abierta_por) }}
      cuenta={ventas.find((x) => x.id === v.id) ?? null}
      turnoId={turno?.id ?? null}
      {nombres}
      autorizan={null}
      {zona}
      alCerrar={() => (hoja = null)}
      alAviso={avisar}
      alListo={() => (hoja = null)}
    />
  {:else if hoja?.tipo === 'folio'}
    {@const h = hoja}
    {@const c = hoja.cobrada}
    <Hoja titulo={c.titulo} sub="Folio {c.folio} · cerrada a las {hora(c.cerrada_at)} · {dinero(c.total)}" alCerrar={() => (hoja = null)}>
      {#if h.pagos === null && !errorHoja}
        <span class="pista">Leyendo los pagos…</span>
      {:else if h.pagos}
        <div class="grupo-op">
          {#each h.pagos as p (p.id)}
            <PagoHecho
              pago={p}
              {nombres}
              {zona}
              alCancelar={!p.cancelado_at && p.cobrado_por !== null && p.turno_id === turno?.id
                ? () => (hoja = { tipo: 'cancelarPago', cobrada: c, pago: p })
                : undefined}
            />
          {/each}
        </div>
        <p class="pista">Si cancelas un pago, la cuenta se reabre con el folio {c.folio} y sale en Por cobrar para anotar el correcto.</p>
      {/if}
      {#if errorHoja}<CajaError mensaje={errorHoja} />{/if}
    </Hoja>
  {:else if hoja?.tipo === 'cancelarPago'}
    {@const c = hoja.cobrada}
    {@const p = hoja.pago}
    <HojaCancelarPago
      {cliente}
      pago={p}
      titulo={c.titulo}
      folio={c.folio}
      cerrada
      cobro={p.cobrado_por !== null ? quien(p.cobrado_por) : 'En línea'}
      abrio={c.abierta_por === null ? null : quien(c.abierta_por)}
      autorizan={null}
      {zona}
      alCerrar={() => (hoja = null)}
      alListo={(globo, reabierta) => {
        // El id se lee antes de cerrar la hoja: sin hoja, `c` ya no existe.
        const id = c.id;
        hoja = null;
        avisar(globo);
        if (ancho && reabierta) alReabrir(id);
        else {
          if (reabierta) vista = 'porcobrar';
          recargar();
        }
      }}
    />
  {:else if hoja?.tipo === 'mov'}
    {@const h = hoja}
    <Hoja titulo="Entrada o salida de efectivo" sub="No es venta: queda en el corte con su motivo" alCerrar={() => (hoja = null)}>
      <Selector
        etiqueta="Entra o sale"
        lleno
        alto={30}
        opciones={[
          { valor: 'sale', texto: 'Sale del cajón' },
          { valor: 'entra', texto: 'Entra al cajón' },
        ]}
        elegida={h.sale ? 'sale' : 'entra'}
        alElegir={(v) => ((h.sale = v === 'sale'), (h.clave = crypto.randomUUID()))}
      />
      <div class="campo">
        <label class="etq" for="mov-monto">Monto</label>
        <input id="mov-monto" inputmode="decimal" autocomplete="off" placeholder="$0.00" bind:value={h.monto} oninput={() => (h.clave = crypto.randomUUID())} />
      </div>
      <div class="campo">
        <label class="etq" for="mov-motivo">Motivo</label>
        <input
          id="mov-motivo"
          autocomplete="off"
          placeholder={h.sale ? 'Ej. «Pago al de las tortillas»' : 'Ej. «Monedas para cambio»'}
          bind:value={h.motivo}
          oninput={() => (h.clave = crypto.randomUUID())}
        />
      </div>
      {#if errorHoja}<CajaError mensaje={errorHoja} />{/if}
      <button type="button" class="cel-boton fijo" disabled={!h.monto.trim() || !h.motivo.trim() || ocupado} onclick={anotarMovimiento}>
        Anotar {h.sale ? 'salida' : 'entrada'}
      </button>
    </Hoja>
  {:else if hoja?.tipo === 'propinas' && hoja.elegida}
    {@const h = hoja}
    {@const p = hoja.elegida}
    <Hoja titulo="Propinas de {pila(p.nombre)}" sub="Le falta {dinero(p.falta)} de este turno" alCerrar={() => (hoja = null)}>
      <div class="campo">
        <label class="etq" for="prop-monto">Le pagas</label>
        <input id="prop-monto" inputmode="decimal" autocomplete="off" bind:value={h.monto} oninput={() => (h.clave = crypto.randomUUID())} />
        <p class="pista">Sale del cajón como «Propinas de {p.nombre}». No puede pasar de {dinero(p.falta)}.</p>
      </div>
      {#if errorHoja}<CajaError mensaje={errorHoja} />{/if}
      <div class="cel-pie sin-arriba">
        <button type="button" class="cel-boton contorno" onclick={() => ((h.elegida = null), (errorHoja = null))}>Atrás</button>
        <button type="button" class="cel-boton" disabled={!h.monto.trim() || ocupado} onclick={pagarPropina}>
          Pagar{leerMonto(h.monto) !== null ? ` ${dinero(leerMonto(h.monto)!)}` : ''}
        </button>
      </div>
    </Hoja>
  {:else if hoja?.tipo === 'propinas'}
    {@const h = hoja}
    <Hoja titulo="Propinas del turno" sub="Son de quien abrió cada cuenta" alCerrar={() => (hoja = null)}>
      {#if h.propinas === null && !errorHoja}
        <span class="pista">Leyendo las propinas…</span>
      {:else if h.propinas && h.propinas.length === 0}
        <p class="pista">Todavía no hay propinas en este turno.</p>
      {:else if h.propinas}
        <div class="grupo-op">
          {#each h.propinas as p (p.miembro_id)}
            <div class="persona-propina">
              <span class="inicial">{pila(p.nombre).charAt(0)}</span>
              <span class="t"><b>{pila(p.nombre)}</b><span>Le tocan {dinero(p.total)} · pagado {dinero(p.pagado)}</span></span>
              {#if p.falta > 0}
                <button
                  type="button"
                  class="boton-chico"
                  onclick={() => ((h.elegida = p), (h.monto = p.falta.toFixed(2)), (h.clave = crypto.randomUUID()), (errorHoja = null))}
                >
                  Pagar {dinero(p.falta)}
                </button>
              {:else}
                <span class="chip-estado">Al corriente</span>
              {/if}
            </div>
          {/each}
        </div>
      {/if}
      {#if errorHoja}<CajaError mensaje={errorHoja} />{/if}
    </Hoja>
  {/if}
{/snippet}

<style>
  .arriba-vista {
    flex: none;
    margin-top: 12px;
  }

  .desliza.lista {
    gap: 8px;
  }

  .cel-boton.fijo {
    flex: none;
  }

  .cel-pie.sin-arriba {
    padding-top: 0;
  }
</style>
