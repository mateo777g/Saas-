<!--
  El punto de venta del mesero y de la caja (parte 4a; maqueta Mesero y cocina TYq97pKacRCYBqcvRp1bZ2;
  libreta 5). Lo abre el aparato del equipo con la sesión de quien puso su PIN, y el panel del
  gerente con la suya («Abrir» en Accesos para tu equipo): recibe la conexión y nunca importa la
  del panel.

  Lo anotado vive en este aparato hasta «Mandar a cocina», que llama a mandar_a_cocina con la
  clave del envío: con la misma clave Postgres no guarda nada dos veces. Si el internet se cae a
  medio envío, el borrador recuerda lo que se fue, y antes del siguiente envío pregunta si llegó.
  Las cuentas abiertas llegan solas con el tiempo real de Supabase; cuando una comanda que mandó
  esta persona pasa a «Lista», suena, vibra y sale el aviso. Con la parte 4b, una cuenta sin nada
  por mandar se cobra desde aquí con la hoja de cobro (la misma de la caja), y quien es mesero ve
  el efectivo que trae para la caja.

  Con la parte 4c (maqueta Cancelaciones y descuentos R5psXDQp1ovBFxBvmWbq46), lo mandado se cancela
  o se descuenta desde la cuenta, y en «⋯» están el descuento a toda la cuenta y «Cancelar cuenta».
  Si quien está es de la caja o gerente, queda a su nombre; si no, autoriza la caja o un gerente con
  su PIN en este aparato. Una cuenta reabierta (se canceló un pago de una cuenta cerrada) ya no es
  la de su mesa: sale en Para llevar con su folio, sin «Cambiar de mesa» ni «Juntar».

  A lo ancho (adaptabilidad; maqueta GBWEGCsQFcwKkWm7Qe9FPA v4), quien lo abre (el aparato o el panel, `anfitrion`) lo
  dice con `ancho`, y aquí se pinta otra cara con lo mismo de abajo: la barra de arriba con su dock (pos/ancho/Barra), con
  mesas primero sus cuadros, y si no el menú en cuadros a la izquierda y la cuenta en la tarjeta de la derecha, con la
  barra de abajo de Crear anuncios («Anotar · 3» o «Mandar a Cocina · 4» y «Cobrar», que primero manda). Sin mesas (o en
  Para llevar) siempre hay un pedido nuevo listo; «Abiertos · 3» cambia la tarjeta a lo abierto. «Cobrar» abre el cobro
  en la misma tarjeta, con el menú a la vista (pos/cobro/, el mismo de la Caja), y abajo «Atrás» y «Anotar pago»; ya
  cobrada, «Nuevo pedido». Las hojas del celular siguen siendo hojas, al centro.
-->
<script lang="ts">
  import type { SupabaseClient } from '@supabase/supabase-js';
  import { onDestroy, onMount, untrack, type Snippet } from 'svelte';
  import Boton from '../../diseno/Boton.svelte';
  import BotonCuadro from '../../diseno/BotonCuadro.svelte';
  import CajaError from '../../diseno/CajaError.svelte';
  import Esqueleto from '../../diseno/Esqueleto.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import { ALGO_SALIO_PANEL, esDeRed, Fallo, SIN_CONEXION } from '../../lib/errores';
  import { dinero, enZona, pesos, plural } from '../../lib/formato';
  import {
    cambiarMesa,
    cuentaDelEnvio,
    escuchar,
    FalloPos,
    guardar,
    guardarTipoPedido,
    ICONO_DE_TIPO,
    leerTipoPedido,
    juntarMesas,
    leerAbiertas,
    leerComandasFuera,
    leerGuardado,
    leerMenuPos,
    leerEquipo,
    leerMesasPos,
    leerZona,
    mandarACocina,
    mesasDeLaUltimaVez,
    mismaLinea,
    nombreDeCuenta,
    pedirCuenta,
    quitarDescuento,
    recordarMesas,
    restar,
    textoDescuento,
    textoMandar,
    TIPO_EN_PALABRAS,
    type Abiertas,
    type Borrador,
    type Comanda,
    type ComandaFuera,
    type Equipo,
    type Guardado,
    type LineaBorrador,
    type MenuPos,
    type Mesa,
    type PedidoNuevo,
    type ProductoPos,
    type Renglon,
    type Venta,
  } from '../../lib/pos';
  import { VigiaTerminal } from '../../lib/terminal.svelte';
  import { faltaDe, leerTurno, miEfectivo } from '../../lib/caja';
  import { avisarLista, prepararSonido } from '../../lib/sonido';
  import Agregar from './Agregar.svelte';
  import Cuenta, { type BloqueVista, type DescuentoVista, type EnviadoVista, type LineaVista } from './Cuenta.svelte';
  import Hoja from './Hoja.svelte';
  import HojaCancelar from './HojaCancelar.svelte';
  import HojaCancelarCuenta from './HojaCancelarCuenta.svelte';
  import HojaCobrar from './HojaCobrar.svelte';
  import HojaDescuento from './HojaDescuento.svelte';
  import HojaLlevar from './HojaLlevar.svelte';
  import HojaOpciones from './HojaOpciones.svelte';
  import Lugar from './Lugar.svelte';
  import Mesas from './Mesas.svelte';
  import AbiertosLado from './ancho/AbiertosLado.svelte';
  import Barra from './ancho/Barra.svelte';
  import type { Anfitrion } from './ancho/barra';
  import CuentaLado from './ancho/CuentaLado.svelte';
  import EsqueletoLado from './ancho/EsqueletoLado.svelte';
  import Lado from './ancho/Lado.svelte';
  import MenuCuadros from './ancho/MenuCuadros.svelte';
  import MenuCuenta, { type OpcionMenu } from './ancho/MenuCuenta.svelte';
  import MesasCuadros from './ancho/MesasCuadros.svelte';
  import './ancho/ancho.css';
  import AbajoCobro from './cobro/Abajo.svelte';
  import CobradaVista from './cobro/Cobrada.svelte';
  import { Cobro } from './cobro/cobro.svelte';
  import Encima from './cobro/Encima.svelte';
  import TarjetaCobro from './cobro/Tarjeta.svelte';
  import './pos.css';

  let {
    cliente,
    restauranteId,
    restaurante,
    miembroId,
    linea,
    donde,
    conEfectivo = false,
    pestanas,
    ancho = false,
    anfitrion = null,
  }: {
    cliente: SupabaseClient;
    restauranteId: string;
    restaurante: string;
    miembroId: number;
    linea: string; // quién está: «Pepe Martínez · Mesero»
    donde: 'celular' | 'aparato' | 'navegador'; // dónde vive lo anotado, para los textos
    conEfectivo?: boolean; // quien es mesero ve el efectivo que trae para la caja
    pestanas?: Snippet;
    ancho?: boolean; // a lo ancho (≥ ~900 px): lo decide quien lo abre
    anfitrion?: Anfitrion | null; // quién lo abre, para la barra de arriba a lo ancho
  } = $props();

  // La terminal de la sucursal y sus cobros (lib/terminal.svelte.ts): «Mandar a la terminal» y «En la terminal» en Mesas.
  const terminal = untrack(() => new VigiaTerminal(cliente, restauranteId)); // la sucursal no cambia mientras se ve

  type Hojas =
    | { tipo: 'opciones'; producto: ProductoPos }
    | { tipo: 'menu' }
    | { tipo: 'juntar'; destino: Venta }
    | { tipo: 'llevar' }
    | { tipo: 'cobrar'; venta: Venta }
    | { tipo: 'renglon'; renglon: number }
    | { tipo: 'cancelar'; renglon: number }
    | { tipo: 'descuento'; renglon: number | null } // sin renglón: a toda la cuenta
    | { tipo: 'cancelarCuenta' };

  // ─── Lo que llega de Postgres ───
  let carga = $state<{ estado: 'leyendo' } | { estado: 'listo' } | { estado: 'error'; mensaje: string }>({
    estado: 'leyendo',
  });
  let menu = $state<MenuPos>({ categorias: [], areas: [] });
  let mesas = $state<Mesa[]>([]);
  let abiertas = $state<Abiertas>({ ventas: [], renglones: [], comandas: [] });
  let equipo = $state<Equipo>({ nombres: new Map(), yoAutorizo: false, autorizan: [] });
  const nombres = $derived(equipo.nombres);
  // Quién autoriza lo que pide PIN; null si quien está es de la caja o gerente.
  const autorizan = $derived(equipo.yoAutorizo ? null : equipo.autorizan);
  let zona = $state('America/Mexico_City');
  let turnoId = $state<number | null>(null);
  let turnoDesde = $state<string | null>(null); // cuándo se abrió la caja, para el chip a lo ancho
  let efectivo = $state<number | null>(null);
  // Cuántas mesas había la última vez en este navegador: a lo ancho, el esqueleto de la primera lectura (mesas o menú).
  // svelte-ignore state_referenced_locally
  let mesasAntes = $state<number | null>(mesasDeLaUltimaVez(restauranteId));

  // ─── Lo que vive en este aparato ───
  // svelte-ignore state_referenced_locally
  let guardado = $state<Guardado>(leerGuardado(restauranteId, miembroId));

  // ─── Lo que se ve ───
  let pantalla = $state<'mesas' | 'cuenta' | 'agregar' | 'pedida' | 'elegir'>('mesas');
  let vista = $state<'mesas' | 'llevar'>('mesas');
  let actual = $state<string | null>(null); // la llave de la cuenta abierta en pantalla
  let cat = $state(0);
  let modo = $state<'cambiar' | 'juntar'>('cambiar');
  let hoja = $state<Hojas | null>(null);
  let globo = $state<string | null>(null);
  // cerrada: la cuenta ya se cobró (mostrador: se cobra antes de mandar); no hay qué abrir.
  let aviso = $state<{ venta: number; titulo: string; area: string; cerrada?: boolean } | null>(null);
  let error = $state<string | null>(null);
  let sinRed = $state(false);
  let ocupado = $state(false);

  function persistir() {
    guardar(restauranteId, miembroId, $state.snapshot(guardado));
  }

  function avisar(texto: string) {
    globo = texto;
    setTimeout(() => {
      if (globo === texto) globo = null;
    }, 1600);
  }

  // ─── Leer ───
  async function leerTodo() {
    try {
      const [m, ms, z] = await Promise.all([
        leerMenuPos(cliente, restauranteId),
        leerMesasPos(cliente, restauranteId),
        leerZona(cliente, restauranteId),
      ]);
      menu = m;
      mesas = ms;
      zona = z;
      await leerCuentas();
      // Si ahora hay mesas y se adelantó un pedido nuevo vacío (la última vez no había), se regresa a las mesas.
      if (ms.length && mesasAntes === 0 && actual?.[0] === 'n' && !guardado.borradores[actual]?.lineas.length) actual = null;
      mesasAntes = ms.length;
      recordarMesas(restauranteId, ms.length);
      carga = { estado: 'listo' };
    } catch (falla) {
      console.error('[pos] no se pudo leer el punto de venta:', falla);
      if (carga.estado !== 'listo') {
        carga = { estado: 'error', mensaje: esDeRed(falla) ? SIN_CONEXION : ALGO_SALIO_PANEL };
      }
    }
  }

  // Las cuentas se vuelven a leer con cada evento del tiempo real. Si llegan varios mientras se
  // lee, se lee una vez más al terminar.
  let leyendo: Promise<void> | null = null;
  let otraVez = false;
  async function leerCuentas(): Promise<void> {
    if (leyendo) {
      otraVez = true;
      return leyendo;
    }
    leyendo = (async () => {
      do {
        otraVez = false;
        const [nuevas, q, t, e] = await Promise.all([
          leerAbiertas(cliente, restauranteId),
          leerEquipo(cliente, restauranteId, miembroId),
          leerTurno(cliente, restauranteId),
          conEfectivo ? miEfectivo(cliente, restauranteId) : Promise.resolve(null),
        ]);
        equipo = q;
        turnoId = t.abierto?.id ?? null;
        turnoDesde = t.abierto?.created_at ?? null;
        efectivo = e;
        // Si esto falla, el punto de venta sigue: solo se pierde el aviso de una cuenta ya cobrada.
        const f = await leerComandasFuera(
          cliente,
          restauranteId,
          miembroId,
          nuevas.ventas.map((v) => v.id),
          fuera.map((c) => c.id),
        ).catch((falla) => {
          console.error('[pos] no se pudieron leer las comandas de cuentas ya cobradas:', falla);
          return null;
        });
        alLlegar(nuevas, f);
      } while (otraVez);
    })().finally(() => (leyendo = null));
    return leyendo;
  }

  function recargarCuentas() {
    leerCuentas().catch((falla) => console.error('[pos] no se pudieron volver a leer las cuentas:', falla));
  }

  // Lo que cambia al llegar las cuentas nuevas: el aviso de «Lista» (solo comparando con la
  // lectura anterior) y los borradores cuyo envío en duda sí llegó.
  let primera = true;
  // Las comandas que mandó esta persona y siguen en la cocina, de cuentas ya cerradas (leerComandasFuera).
  let fuera: ComandaFuera[] = [];
  function alLlegar(nuevas: Abiertas, nuevasFuera: ComandaFuera[] | null) {
    if (!primera) {
      const antes = new Map([...abiertas.comandas, ...fuera].map((c) => [c.id, c.estado]));
      for (const c of nuevas.comandas) {
        // Una comanda con todo cancelado se quita en la cocina, pero no es «Lista».
        const algo = nuevas.renglones.some((r) => r.comanda_id === c.id && r.estado === 'activo');
        if (c.estado === 'lista' && c.enviada_por === miembroId && antes.get(c.id) === 'pendiente' && algo) {
          avisoDeLista(c, nuevas);
        }
      }
      for (const c of nuevasFuera ?? []) {
        if (c.estado === 'lista' && antes.get(c.id) === 'pendiente' && c.algo) avisoDeListaCobrada(c);
      }
    }
    primera = false;
    // Sin respuesta (falló la lectura), se siguen vigilando las de antes.
    if (nuevasFuera) fuera = nuevasFuera.filter((c) => c.estado === 'pendiente');

    let cambio = false;
    for (const [llave, b] of Object.entries(guardado.borradores)) {
      const llego = b.enDuda && nuevas.renglones.find((r) => r.clave_envio === b.enDuda!.clave);
      if (llego) {
        llegoEnDuda(llave, llego.venta_id);
        cambio = true;
        sinRed = false; // esta lectura llegó: hay conexión
      }
    }
    const abiertasIds = new Set(nuevas.ventas.map((v) => v.id));
    const sinVer = guardado.sinVer.filter((id) => abiertasIds.has(id));
    if (sinVer.length !== guardado.sinVer.length) {
      guardado.sinVer = sinVer;
      cambio = true;
    }
    if (cambio) persistir();
    abiertas = nuevas;
  }

  function avisoDeLista(c: Comanda, nuevas: Abiertas) {
    const v = nuevas.ventas.find((x) => x.id === c.venta_id);
    if (!v) return;
    aviso = {
      venta: v.id,
      titulo: nombreDe(v),
      area: menu.areas.find((a) => a.id === c.area_preparacion_id)?.nombre ?? '',
    };
    const enPantalla = pantalla !== 'mesas' && actual !== null && ventaDe(actual, nuevas)?.id === v.id;
    if (!enPantalla && !guardado.sinVer.includes(v.id)) {
      guardado.sinVer.push(v.id);
      persistir();
    }
    avisarLista();
  }

  // La de una cuenta ya cobrada: suena y avisa igual, pero no hay cuenta que abrir ni que marcar.
  function avisoDeListaCobrada(c: ComandaFuera) {
    aviso = {
      venta: c.venta_id,
      titulo: c.titulo,
      area: menu.areas.find((a) => a.id === c.area_preparacion_id)?.nombre ?? '',
      cerrada: true,
    };
    avisarLista();
  }

  // ─── Qué cuenta es cada llave ───
  // La de una mesa es la abierta sin folio: una reabierta ya no ocupa su mesa y va por su id.
  const deMesa = (v: Venta) => v.tipo === 'mesa' && v.folio === null;

  function ventaDe(llave: string, de: Abiertas = abiertas): Venta | null {
    const id = Number(llave.slice(1));
    if (llave[0] === 'm') return de.ventas.find((v) => deMesa(v) && v.mesa_id === id) ?? null;
    if (llave[0] === 'v') return de.ventas.find((v) => v.id === id) ?? null;
    return null;
  }

  function llaveDe(v: Venta): string {
    return deMesa(v) ? `m${v.mesa_id}` : `v${v.id}`;
  }

  const nombreDe = (v: Venta) => nombreDeCuenta(v);

  function tituloDe(llave: string): string {
    const v = ventaDe(llave);
    if (llave[0] === 'm') return v?.mesa_nombre ?? mesas.find((m) => m.id === Number(llave.slice(1)))?.nombre ?? '';
    if (llave[0] === 'v') return v ? nombreDe(v) : '';
    return guardado.borradores[llave]?.nuevo?.nombre || 'Pedido nuevo';
  }

  // «En cocina» mientras alguna comanda espera con algo que no se canceló.
  function enCocina(v: Venta): boolean {
    return abiertas.comandas.some(
      (c) =>
        c.venta_id === v.id &&
        c.estado === 'pendiente' &&
        abiertas.renglones.some((r) => r.comanda_id === c.id && r.estado === 'activo'),
    );
  }

  function estadoDe(v: Venta): 'reabierta' | 'cocina' | 'lista' | 'cuenta' | 'ocupada' {
    if (v.folio !== null) return 'reabierta';
    if (v.cuenta_pedida_at) return 'cuenta';
    if (enCocina(v)) return 'cocina';
    if (guardado.sinVer.includes(v.id)) return 'lista';
    return 'ocupada';
  }

  const quien = (id: number | null) => (id === null ? '—' : (nombres.get(id) ?? '—'));
  const hora = (momento: string) => enZona(momento, zona).hora;

  // ─── La cuenta en pantalla, ya en palabras ───
  const ventaActual = $derived(actual ? ventaDe(actual) : null);
  const borradorActual = $derived<Borrador | null>(actual ? (guardado.borradores[actual] ?? null) : null);
  const productos = $derived(new Map(menu.categorias.flatMap((c) => c.productos.map((p) => [p.id, p] as const))));
  const nombreArea = $derived(new Map(menu.areas.map((a) => [a.id, a.nombre])));

  function detalleDe(producto: ProductoPos | undefined, opciones: number[]): string {
    if (!producto) return '';
    return producto.grupos
      .flatMap((g) => g.opciones.filter((o) => opciones.includes(o.id)).map((o) => o.nombre))
      .join(' · ');
  }

  // El importe de una línea anotada es solo para verla: el que cuenta lo pone Postgres al mandar.
  const lineas = $derived<LineaVista[]>(
    (borradorActual?.lineas ?? []).map((l) => {
      const p = productos.get(l.producto_id);
      const extra = p ? p.grupos.flatMap((g) => g.opciones).filter((o) => l.opciones.includes(o.id)).reduce((s, o) => s + o.precio_extra, 0) : 0;
      return {
        nombre: p?.nombre ?? l.nombre,
        detalle: detalleDe(p, l.opciones),
        nota: l.nota,
        cantidad: l.cantidad,
        importe: p ? (p.precio + extra) * l.cantidad : null,
      };
    }),
  );

  function enviado(r: Renglon): EnviadoVista {
    const cancelado = r.estado === 'cancelado';
    const conDescuento = !cancelado && r.descuento_tipo !== null && r.descuento_valor !== null;
    return {
      id: r.id,
      nombre: r.nombre,
      detalle: r.opciones.map((o) => o.opcion).join(' · '),
      nota: r.nota ?? '',
      cantidad: r.cantidad,
      importe: cancelado ? r.importe + r.descuento : r.importe,
      antes: conDescuento ? r.importe + r.descuento : null,
      descuento: conDescuento
        ? `${textoDescuento(r.descuento_tipo!, r.descuento_valor!)} · «${r.descuento_motivo}» · −${dinero(r.descuento)}`
        : null,
      cancelado: cancelado ? `Cancelado · «${r.cancelado_motivo}» · autorizó ${quien(r.autorizado_por)}` : null,
      por: quien(r.agregado_por),
    };
  }

  const descuentoCuenta = $derived<DescuentoVista | null>(
    ventaActual?.descuento_tipo && ventaActual.descuento_valor !== null
      ? {
          texto: textoDescuento(ventaActual.descuento_tipo, ventaActual.descuento_valor),
          motivo: ventaActual.descuento_motivo ?? '',
          monto: ventaActual.descuento,
        }
      : null,
  );

  // El renglón de una hoja, como está ahora (el tiempo real lo cambia).
  const renglonDe = (id: number | null) => (id === null ? null : (abiertas.renglones.find((r) => r.id === id) ?? null));

  function areaDe(r: Renglon): string | null {
    const c = abiertas.comandas.find((k) => k.id === r.comanda_id);
    return c ? (nombreArea.get(c.area_preparacion_id) ?? null) : null;
  }

  const bloques = $derived<BloqueVista[]>(
    ventaActual
      ? abiertas.comandas
          .filter((c) => c.venta_id === ventaActual.id)
          .slice()
          .reverse()
          .map((c) => ({
            id: c.id,
            etiqueta: `${hora(c.created_at)} · ${nombreArea.get(c.area_preparacion_id) ?? ''}`,
            etiquetaAncha: `${nombreArea.get(c.area_preparacion_id) ?? ''} · ${hora(c.created_at)}`,
            estado: c.estado,
            renglones: abiertas.renglones.filter((r) => r.comanda_id === c.id).map(enviado),
          }))
      : [],
  );
  const sinArea = $derived<EnviadoVista[]>(
    ventaActual ? abiertas.renglones.filter((r) => r.venta_id === ventaActual.id && r.comanda_id === null).map(enviado) : [],
  );

  const subCuenta = $derived.by(() => {
    if (!actual) return '';
    const v = ventaActual;
    const tipo = v?.tipo ?? borradorActual?.nuevo?.tipo ?? 'mesa';
    const prefijo = v && v.folio !== null ? `Folio ${v.folio} · reabierta` : tipo === 'mesa' ? '' : TIPO_EN_PALABRAS[tipo];
    if (v) return `${prefijo ? `${prefijo} · ` : ''}Abrió ${quien(v.abierta_por)} · ${hora(v.created_at)}`;
    return `${prefijo || 'Libre'} · se abre al ${mandarTexto === 'Anotar' ? 'anotar' : 'mandar'}`;
  });

  const domicilio = $derived.by(() => {
    const v = ventaActual;
    if (v?.tipo === 'domicilio') return { telefono: v.cliente_telefono ?? '', direccion: v.cliente_direccion ?? '' };
    const n = borradorActual?.nuevo;
    if (!v && n?.tipo === 'domicilio') return { telefono: n.telefono, direccion: n.direccion };
    return null;
  });

  // ─── Moverse ───
  function abrir(llave: string) {
    actual = llave;
    pantalla = 'cuenta';
    hoja = null;
    error = null;
    sinRed = false;
    const v = ventaDe(llave);
    if (v && guardado.sinVer.includes(v.id)) {
      guardado.sinVer = guardado.sinVer.filter((id) => id !== v.id);
      persistir();
    }
    if (v && aviso?.venta === v.id) aviso = null;
  }

  function volver() {
    if (actual && actual[0] === 'n' && !guardado.borradores[actual]?.lineas.length) {
      delete guardado.borradores[actual];
      persistir();
    }
    vista = actual && actual[0] !== 'm' ? 'llevar' : 'mesas';
    pantalla = 'mesas';
    actual = null;
    error = null;
    sinRed = false;
  }

  // ─── El borrador ───
  // Cada cambio le da una clave nueva: el envío que se intente después ya es otro.
  function cambiarBorrador(cambio: (b: Borrador) => void) {
    if (!actual) return;
    const b = guardado.borradores[actual] ?? { clave: crypto.randomUUID(), lineas: [] };
    cambio(b);
    b.clave = crypto.randomUUID();
    if (b.lineas.length || b.nuevo || b.enDuda) guardado.borradores[actual] = b;
    else delete guardado.borradores[actual];
    persistir();
  }

  function anotar(p: ProductoPos, opciones: number[], nota: string, cantidad: number) {
    cambiarBorrador((b) => {
      const igual = b.lineas.find((l) => mismaLinea(l, { producto_id: p.id, opciones, nota }));
      if (igual) igual.cantidad += cantidad;
      else b.lineas.push({ producto_id: p.id, nombre: p.nombre, cantidad, opciones, nota });
    });
  }

  function alProducto(p: ProductoPos) {
    if (p.grupos.length) hoja = { tipo: 'opciones', producto: p };
    else anotar(p, [], '', 1);
  }

  const cuantos = $derived(
    (borradorActual?.lineas ?? []).reduce((m, l) => m.set(l.producto_id, (m.get(l.producto_id) ?? 0) + l.cantidad), new Map<number, number>()),
  );
  const porMandar = $derived((borradorActual?.lineas ?? []).reduce((s, l) => s + l.cantidad, 0));

  // A qué áreas va lo anotado, en el orden de las áreas: lo dice el botón (adaptabilidad, encuesta 7).
  const areaDeProducto = $derived(
    new Map(menu.categorias.flatMap((c) => c.productos.map((p) => [p.id, c.area] as const))),
  );
  const mandarTexto = $derived.by(() => {
    const van = new Set((borradorActual?.lineas ?? []).map((l) => areaDeProducto.get(l.producto_id)).filter((a) => !!a));
    return textoMandar(menu.areas.map((a) => a.nombre).filter((n) => van.has(n)));
  });

  // ─── Mandar a cocina ───
  // El envío en duda sí llegó a esa cuenta: se le resta al borrador lo que llevaba, y un para
  // llevar nuevo pasa a ser esa cuenta. Regresa la llave con la que sigue el borrador.
  function llegoEnDuda(llave: string, ventaId: number): string {
    const b = guardado.borradores[llave];
    if (!b?.enDuda) return llave;
    b.lineas = restar(b.lineas, b.enDuda.lineas);
    b.clave = crypto.randomUUID();
    delete b.enDuda;
    const nueva = llave[0] === 'n' ? `v${ventaId}` : llave;
    if (nueva !== llave) {
      delete guardado.borradores[llave];
      delete b.nuevo;
      if (b.lineas.length) guardado.borradores[nueva] = b;
    } else if (!b.lineas.length) delete guardado.borradores[llave];
    if (actual === llave) actual = nueva;
    persistir();
    return nueva;
  }

  // Regresa la cuenta a la que llegó lo mandado, o null si no se mandó.
  async function mandar(): Promise<number | null> {
    if (!actual || ocupado) return null;
    let llave = actual;
    error = null;
    if (!navigator.onLine) {
      sinRed = true;
      return null;
    }
    ocupado = true;
    try {
      // Un envío anterior se fue sin saber si llegó y después se cambió lo anotado: antes de
      // mandar, se pregunta si llegó, para no mandar dos veces lo que llevaba.
      const antes = guardado.borradores[llave];
      if (antes?.enDuda && antes.enDuda.clave !== antes.clave) {
        const ventaId = await cuentaDelEnvio(cliente, restauranteId, antes.enDuda.clave);
        if (ventaId !== null) llave = llegoEnDuda(llave, ventaId);
        else {
          delete antes.enDuda;
          persistir();
        }
      }
      const b = guardado.borradores[llave];
      if (!b?.lineas.length) {
        recargarCuentas();
        return null;
      }

      const v = ventaDe(llave);
      const destino = v ? { venta: v.id } : llave[0] === 'm' ? { mesa: Number(llave.slice(1)) } : (b.nuevo ?? null);
      if (!destino) {
        error = 'Esa cuenta ya no está abierta';
        return null;
      }
      const enviadas: LineaBorrador[] = $state.snapshot(b.lineas);
      const clave = b.clave;
      let ventaId: number;
      try {
        ventaId = await mandarACocina(
          cliente,
          restauranteId,
          clave,
          enviadas.map((l) => ({ producto_id: l.producto_id, cantidad: l.cantidad, opciones: l.opciones, nota: l.nota })),
          destino,
        );
      } catch (falla) {
        // Sin internet de regreso: no se sabe si llegó. Lo anotado se queda, y se recuerda qué
        // se fue y con qué clave.
        if (falla instanceof FalloPos && falla.sinRed) {
          const sigue = guardado.borradores[llave];
          if (sigue) {
            sigue.enDuda = { clave, lineas: enviadas };
            persistir();
          }
          sinRed = true;
          return null;
        }
        throw falla;
      }

      // Llegó: lo mandado sale del borrador (si mientras tanto se anotó más, eso se queda).
      const sigue = guardado.borradores[llave];
      if (sigue) {
        sigue.lineas = sigue.clave === clave ? [] : restar(sigue.lineas, enviadas);
        sigue.clave = crypto.randomUUID();
        delete sigue.enDuda;
        persistir();
      }
      sinRed = false;
      const areas = [
        ...new Set(
          enviadas
            .map((l) => menu.categorias.find((c) => c.productos.some((p) => p.id === l.producto_id))?.area)
            .filter((a): a is string => !!a),
        ),
      ];
      avisar(areas.length ? `Mandado a ${areas.join(' y ')}` : 'Anotado');
      await leerCuentas().catch((f) => console.error('[pos] no se pudieron volver a leer las cuentas:', f));

      // Un para llevar nuevo ya es su cuenta.
      const queda = guardado.borradores[llave];
      if (llave[0] === 'n') {
        delete guardado.borradores[llave];
        if (queda?.lineas.length) {
          delete queda.nuevo;
          guardado.borradores[`v${ventaId}`] = queda;
        }
        if (actual === llave) actual = `v${ventaId}`;
      } else if (queda && !queda.lineas.length) delete guardado.borradores[llave];
      persistir();
      return ventaId;
    } catch (falla) {
      if (falla instanceof Fallo) error = falla.message;
      else {
        console.error('[pos] no se pudo mandar a cocina:', falla);
        if (esDeRed(falla)) sinRed = true;
        else error = ALGO_SALIO_PANEL;
      }
      return null;
    } finally {
      ocupado = false;
    }
  }

  // ─── Lo del botón ⋯ ───
  async function pedir() {
    const v = ventaActual;
    hoja = null;
    if (!v) return;
    try {
      await pedirCuenta(cliente, v.id);
      pantalla = 'pedida';
      recargarCuentas();
    } catch (falla) {
      error = falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL;
    }
  }

  function elegir(m: 'cambiar' | 'juntar') {
    hoja = null;
    error = null;
    modo = m;
    pantalla = 'elegir';
  }

  // Lo anotado aquí para una mesa se va con su cuenta.
  function moverBorrador(de: string, a: string) {
    const b = guardado.borradores[de];
    if (!b) return;
    const ya = guardado.borradores[a];
    if (ya) {
      for (const l of b.lineas) {
        const igual = ya.lineas.find((x) => mismaLinea(x, l));
        if (igual) igual.cantidad += l.cantidad;
        else ya.lineas.push(l);
      }
      ya.clave = crypto.randomUUID();
    } else guardado.borradores[a] = b;
    delete guardado.borradores[de];
    persistir();
  }

  async function alElegirMesa(m: Mesa) {
    const v = ventaActual;
    if (!v || !actual || ocupado) return;
    error = null;
    if (modo === 'juntar') {
      const destino = ventaDe(`m${m.id}`);
      if (destino) hoja = { tipo: 'juntar', destino };
      return;
    }
    ocupado = true;
    try {
      await cambiarMesa(cliente, v.id, m.id);
      moverBorrador(actual, `m${m.id}`);
      actual = `m${m.id}`;
      pantalla = 'cuenta';
      avisar(`Pasó a «${m.nombre}»`);
      await leerCuentas().catch((f) => console.error('[pos] no se pudieron volver a leer las cuentas:', f));
    } catch (falla) {
      error = falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL;
    } finally {
      ocupado = false;
    }
  }

  async function confirmarJuntar(destino: Venta) {
    const v = ventaActual;
    if (!v || !actual || ocupado) return;
    ocupado = true;
    try {
      await juntarMesas(cliente, v.id, destino.id);
      hoja = null;
      moverBorrador(actual, llaveDe(destino));
      actual = llaveDe(destino);
      pantalla = 'cuenta';
      avisar(`Se juntó con «${destino.mesa_nombre}»`);
      await leerCuentas().catch((f) => console.error('[pos] no se pudieron volver a leer las cuentas:', f));
    } catch (falla) {
      hoja = null;
      error = falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL;
    } finally {
      ocupado = false;
    }
  }

  // ─── Lo que pide PIN (parte 4c) ───
  function hecho(texto: string) {
    hoja = null;
    avisar(texto);
    recargarCuentas();
  }

  // Quitar un descuento no pide PIN.
  async function quitar(renglon: number | null) {
    const v = ventaActual;
    if (!v || ocupado) return;
    ocupado = true;
    try {
      await quitarDescuento(cliente, v.id, renglon);
      hecho('Descuento quitado');
    } catch (falla) {
      hoja = null;
      error = falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL;
    } finally {
      ocupado = false;
    }
  }

  // ─── Para llevar ───
  function empezarLlevar(pedido: PedidoNuevo) {
    const llave = `n${crypto.randomUUID()}`;
    guardado.borradores[llave] = { clave: crypto.randomUUID(), lineas: [], nuevo: pedido };
    persistir();
    hoja = null;
    actual = llave;
    error = null;
    sinRed = false;
    cat = 0;
    pantalla = 'agregar';
  }

  const nuevos = $derived(
    Object.entries(guardado.borradores)
      .filter(([llave, b]) => llave[0] === 'n' && b.nuevo && b.lineas.length)
      .map(([llave, b]) => ({ llave, pedido: b.nuevo! })),
  );
  const anotadas = $derived(
    new Set(
      Object.entries(guardado.borradores)
        .filter(([llave, b]) => llave[0] === 'm' && b.lineas.length)
        .map(([llave]) => Number(llave.slice(1))),
    ),
  );

  // ─── A lo ancho (adaptabilidad; maqueta GBWEGCsQFcwKkWm7Qe9FPA v4) ───
  // La tarjeta de la derecha enseña la cuenta, lo abierto sin mesa o el cobro (3e: el de pos/cobro/, en la tarjeta).
  let lado = $state<'cuenta' | 'abiertos' | 'cobro'>('cuenta');
  const cuentasDeMesa = $derived(new Map(abiertas.ventas.filter(deMesa).map((v) => [v.mesa_id!, v] as const)));
  const sinMesa = $derived(abiertas.ventas.filter((v) => !deMesa(v)));
  const nuevoActual = $derived(!ventaActual && actual?.[0] === 'n' ? (borradorActual?.nuevo ?? null) : null);
  const sumaPorMandar = $derived(lineas.reduce((s, l) => s + (l.importe ?? 0), 0));
  // A domicilio, sin teléfono o dirección no se manda (Postgres lo pide; aquí solo se apaga el botón).
  const faltanDatos = $derived(
    nuevoActual?.tipo === 'domicilio' && (!nuevoActual.telefono.trim() || !nuevoActual.direccion.trim()),
  );
  // Con mesas, la de la cuenta abierta; sin cuenta, la que se eligió en el dock.
  const vistaAncho = $derived(actual ? (actual[0] === 'm' ? 'mesas' : 'llevar') : vista);
  const enLasMesas = $derived(mesas.length > 0 && !actual && vista === 'mesas');

  // Sin mesas (o en Para llevar) siempre hay un pedido nuevo listo para anotar: el vacío que ya había, o uno nuevo con
  // el último tipo que se usó en este aparato.
  function pedidoNuevo() {
    const vacio = Object.entries(guardado.borradores).find(([k, b]) => k[0] === 'n' && b.nuevo && !b.lineas.length && !b.enDuda)?.[0];
    const llave = vacio ?? `n${crypto.randomUUID()}`;
    if (!vacio) {
      guardado.borradores[llave] = {
        clave: crypto.randomUUID(),
        lineas: [],
        nuevo: { tipo: leerTipoPedido(), nombre: '', telefono: '', direccion: '' },
      };
      persistir();
    }
    actual = llave;
    pantalla = 'cuenta';
    lado = 'cuenta';
    hoja = null;
    error = null;
    sinRed = false;
  }

  // Mientras lee la primera vez, si la última vez no había mesas, el pedido nuevo ya sale (vive en el aparato).
  $effect(() => {
    if (!ancho || actual) return;
    if (carga.estado === 'listo' ? mesas.length === 0 || vista === 'llevar' : carga.estado === 'leyendo' && mesasAntes === 0)
      untrack(pedidoNuevo);
  });

  function cambiarNuevo(cambio: Partial<PedidoNuevo>) {
    cambiarBorrador((b) => {
      if (b.nuevo) Object.assign(b.nuevo, cambio);
    });
    if (cambio.tipo) guardarTipoPedido(cambio.tipo);
  }

  function abrirAncho(llave: string) {
    abrir(llave);
    lado = 'cuenta';
  }

  function alProductoAncho(p: ProductoPos) {
    // Ya cobrada una cuenta sin mesa, lo que se toque es de un pedido nuevo.
    if (lado === 'cobro' && cobroAncho?.cerrada && !cobroDe?.mesa) pedidoNuevo();
    lado = 'cuenta';
    alProducto(p);
  }

  // Las vistas del dock con mesas: Mesas (sus cuadros) o Para llevar (un pedido nuevo).
  function irVista(v: string) {
    volver();
    hoja = null;
    lado = 'cuenta';
    vista = v === 'mesas' ? 'mesas' : 'llevar';
  }

  // «Anotar» o «Mandar a…»: un pedido nuevo ya mandado deja su lugar a otro, como en el mostrador.
  async function anotarAncho() {
    const eraNuevo = actual?.[0] === 'n';
    const hecho = mandarTexto === 'Anotar' ? 'anotado' : mandarTexto.replace('Mandar', 'mandado');
    const id = await mandar();
    if (id === null || !eraNuevo) return;
    const v = abiertas.ventas.find((x) => x.id === id);
    actual = null;
    if (v) avisar(`${nombreDe(v)} ${hecho}: ya está en Abiertos`);
  }

  // El «⋯» de la cuenta a lo ancho: lo mismo que la hoja del celular, en la lista de Mi menú (maqueta v4).
  function opcionesMenu(v: Venta): OpcionMenu[] {
    return [
      { clave: 'pedir', texto: 'Pedir la cuenta', icono: 'cuenta' },
      ...(deMesa(v)
        ? [
            { clave: 'cambiar', texto: 'Cambiar de mesa', icono: 'cambiar' },
            { clave: 'juntar', texto: 'Juntar con otra mesa', icono: 'juntar' },
          ]
        : []),
      { clave: 'descuento', texto: descuentoCuenta ? 'Cambiar descuento' : 'Descuento a la cuenta', icono: 'porcentaje' },
      ...(descuentoCuenta ? [{ clave: 'quitar', texto: 'Quitar descuento', icono: 'regresar', apagado: ocupado }] : []),
      { clave: 'cancelar', texto: 'Cancelar cuenta', icono: 'eliminar', peligro: true },
    ];
  }

  function alMenuAncho(clave: string) {
    error = null;
    if (clave === 'pedir') pedir();
    else if (clave === 'cambiar' || clave === 'juntar') elegir(clave);
    else if (clave === 'descuento') hoja = { tipo: 'descuento', renglon: null };
    else if (clave === 'quitar') quitar(null);
    else if (clave === 'cancelar') hoja = { tipo: 'cancelarCuenta' };
  }

  // «Cobrar» desde antes (encuesta 4): primero manda lo anotado y luego abre el cobro en la tarjeta de la derecha (3e),
  // con el menú a la vista. El cobro es el de la Caja (pos/cobro/): vive mientras la tarjeta lo enseña.
  let cobroAncho = $state.raw<Cobro | null>(null);
  // La cuenta como estaba al cobrarla: al cerrarse ya no sale en abiertas, y Cobrada la sigue nombrando.
  let cobroDe = $state.raw<{ id: number; titulo: string; tarjeta: string; mesa: boolean; reabierta: boolean } | null>(null);

  function soltarCobro() {
    cobroAncho?.destruir();
    cobroAncho = null;
    cobroDe = null;
  }

  async function cobrarAncho() {
    let v = ventaActual;
    if (porMandar) {
      const id = await mandar();
      if (id === null) return;
      v = abiertas.ventas.find((x) => x.id === id) ?? null;
    }
    if (!v) return;
    soltarCobro();
    const venta = { id: v.id, titulo: nombreDe(v) || '—', tipo: v.tipo, abrio: v.abierta_por === null ? null : quien(v.abierta_por) };
    cobroDe = {
      id: v.id,
      titulo: venta.titulo,
      tarjeta: v.tipo === 'mesa' ? venta.titulo : `${venta.titulo} · ${TIPO_EN_PALABRAS[v.tipo]}`,
      mesa: deMesa(v),
      reabierta: v.folio !== null,
    };
    cobroAncho = new Cobro(() => ({
      cliente,
      restauranteId,
      venta,
      cuenta: abiertas.ventas.find((x) => x.id === venta.id) ?? null,
      turnoId,
      nombres,
      autorizan,
      zona,
      renglones: abiertas.renglones,
      terminal,
      alAviso: avisar,
    }));
    lado = 'cobro';
    hoja = null;
    error = null;
  }

  // El cobro se suelta al dejar de verse (otra cuenta, Abiertos, un producto, más angosto que el ancho).
  $effect(() => {
    if ((lado !== 'cobro' || !ancho) && cobroAncho) untrack(soltarCobro);
  });
  onDestroy(soltarCobro);

  // Lo que dice la barra de abajo mientras se cobra: «#24 · Comer aquí · 3 productos · Latte, Concha y Cuernito».
  const lineaCobro = $derived.by(() => {
    if (!cobroDe) return '';
    const rs = abiertas.renglones.filter((r) => r.venta_id === cobroDe!.id && r.estado === 'activo');
    if (!rs.length) return '';
    const n = rs.reduce((s, r) => s + r.cantidad, 0);
    const nom = [...new Set(rs.map((r) => r.nombre))];
    return `${plural(n, 'producto', 'productos')} · ${nom.length > 1 ? `${nom.slice(0, -1).join(', ')} y ${nom.at(-1)}` : nom[0]}`;
  });

  const chipAncho = $derived(
    carga.estado !== 'listo'
      ? carga.estado === 'leyendo'
        ? { texto: !actual && mesasAntes ? 'Cargando tus mesas…' : 'Cargando el menú…', vivo: true }
        : { texto: 'No se pudo leer', vivo: false }
      : mesas.length
        ? { texto: `${cuentasDeMesa.size} de ${mesas.length} mesas ocupadas`, vivo: true }
        : turnoDesde
          ? { texto: `Caja abierta desde las ${hora(turnoDesde)}`, vivo: true }
          : { texto: 'Caja sin abrir', vivo: false, pausa: true },
  );

  // ─── Al abrir ───
  onMount(() => {
    leerTodo();
    const dejar = escuchar(cliente, restauranteId, ['ventas', 'venta_items', 'comandas', 'pagos', 'turnos'], () => {
      if (carga.estado === 'listo') recargarCuentas();
    });
    const dejarTerminal = terminal.iniciar();
    const alVolver = () => {
      if (document.visibilityState === 'visible') leerTodo();
    };
    const conRed = () => (sinRed = false);
    document.addEventListener('visibilitychange', alVolver);
    document.addEventListener('pointerdown', prepararSonido, true);
    window.addEventListener('online', conRed);
    return () => {
      dejar();
      dejarTerminal();
      document.removeEventListener('visibilitychange', alVolver);
      document.removeEventListener('pointerdown', prepararSonido, true);
      window.removeEventListener('online', conRed);
    };
  });
</script>

{#snippet avisoLista()}
  {#if aviso}
    {@const a = aviso}
    <div class="aviso-lista vidrio sombra-pos" role="status">
      <span class="punto"></span>
      <button
        type="button"
        class="abrir"
        onclick={() => {
          const v = abiertas.ventas.find((x) => x.id === a.venta);
          aviso = null;
          if (v) abrir(llaveDe(v));
        }}
      >
        <b>{a.titulo} · Lista</b>
        <span>{a.area} · {a.cerrada ? 'ya está pagada' : 'toca para abrirla'}</span>
      </button>
      <button type="button" class="cuadro" aria-label="Cerrar aviso" title="Cerrar" onclick={() => (aviso = null)}>
        <Icono nombre="cerrar" tamano={16} />
      </button>
    </div>
  {/if}
{/snippet}

{#snippet hojas()}
{#if hoja?.tipo === 'opciones'}
  {@const producto = hoja.producto}
  <HojaOpciones
    {producto}
    alCerrar={() => (hoja = null)}
    alAgregar={(opciones, nota, cantidad) => {
      anotar(producto, opciones, nota, cantidad);
      hoja = null;
    }}
  />
{:else if hoja?.tipo === 'menu' && ventaActual && actual}
  <Hoja titulo={tituloDe(actual)} sub={dinero(ventaActual.total)} alCerrar={() => (hoja = null)}>
    <div class="menu-hoja">
      <button type="button" onclick={pedir}>
        <Icono nombre="cuenta" tamano={18} />Pedir la cuenta<span class="sub">La enseñas en grande</span>
      </button>
      {#if deMesa(ventaActual)}
        <button type="button" onclick={() => elegir('cambiar')}>
          <Icono nombre="cambiar" tamano={18} />Cambiar de mesa<span class="sub">A una libre</span>
        </button>
        <button type="button" onclick={() => elegir('juntar')}>
          <Icono nombre="juntar" tamano={18} />Juntar con otra mesa<span class="sub">Esta queda libre</span>
        </button>
      {/if}
      <button type="button" onclick={() => (hoja = { tipo: 'descuento', renglon: null })}>
        <Icono nombre="porcentaje" tamano={18} />{descuentoCuenta ? 'Cambiar descuento' : 'Descuento a la cuenta'}
        <span class="sub">{descuentoCuenta ? `${descuentoCuenta.texto} ahora` : 'Con motivo y PIN'}</span>
      </button>
      {#if descuentoCuenta}
        <button type="button" disabled={ocupado} onclick={() => quitar(null)}>
          <Icono nombre="regresar" tamano={18} />Quitar descuento<span class="sub">No pide PIN</span>
        </button>
      {/if}
      <button type="button" onclick={() => (hoja = { tipo: 'cancelarCuenta' })}>
        <Icono nombre="cerrar" tamano={18} />Cancelar cuenta<span class="sub">Con motivo y PIN</span>
      </button>
    </div>
  </Hoja>
{:else if hoja?.tipo === 'renglon' && ventaActual}
  {@const r = renglonDe(hoja.renglon)}
  {#if r && r.estado === 'activo'}
    {@const k = abiertas.comandas.find((c) => c.id === r.comanda_id)}
    {@const det = r.opciones.map((o) => o.opcion).join(' · ')}
    <Hoja
      titulo="{r.cantidad} {r.nombre}"
      sub="{det ? `${det} · ` : ''}{dinero(r.importe)}{k ? ` · mandado ${hora(k.created_at)}` : ' · se entrega directo'}"
      alCerrar={() => (hoja = null)}
    >
      <div class="menu-hoja">
        <button type="button" onclick={() => (hoja = { tipo: 'cancelar', renglon: r.id })}>
          <Icono nombre="cerrar" tamano={18} />Cancelar<span class="sub">Con motivo y PIN</span>
        </button>
        <button type="button" onclick={() => (hoja = { tipo: 'descuento', renglon: r.id })}>
          <Icono nombre="porcentaje" tamano={18} />{r.descuento_tipo ? 'Cambiar descuento' : 'Descuento'}<span class="sub">En % o en pesos</span>
        </button>
        {#if r.descuento_tipo}
          <button type="button" disabled={ocupado} onclick={() => quitar(r.id)}>
            <Icono nombre="regresar" tamano={18} />Quitar descuento<span class="sub">No pide PIN</span>
          </button>
        {/if}
      </div>
    </Hoja>
  {/if}
{:else if hoja?.tipo === 'cancelar' && ventaActual}
  {@const r = renglonDe(hoja.renglon)}
  {#if r}
    <HojaCancelar
      {cliente}
      venta={ventaActual}
      renglon={r}
      area={areaDe(r)}
      {autorizan}
      {zona}
      alCerrar={() => (hoja = null)}
      alListo={hecho}
    />
  {/if}
{:else if hoja?.tipo === 'descuento' && ventaActual && actual}
  {@const id = hoja.renglon}
  {@const r = renglonDe(id)}
  {#if id === null || r}
    <HojaDescuento
      {cliente}
      venta={ventaActual}
      titulo={tituloDe(actual)}
      renglon={r}
      {autorizan}
      {zona}
      alCerrar={() => (hoja = null)}
      alListo={hecho}
    />
  {/if}
{:else if hoja?.tipo === 'cancelarCuenta' && ventaActual && actual}
  {@const v = ventaActual}
  <HojaCancelarCuenta
    {cliente}
    venta={v}
    titulo={tituloDe(actual)}
    sub={subCuenta}
    renglones={abiertas.renglones.filter((r) => r.venta_id === v.id)}
    {autorizan}
    {zona}
    alCerrar={() => (hoja = null)}
    alListo={(globo) => {
      hecho(globo);
      volver();
    }}
  />
{:else if hoja?.tipo === 'juntar' && ventaActual && actual}
  {@const de = tituloDe(actual)}
  {@const a = hoja.destino}
  <Hoja titulo="¿Juntar «{de}» con «{a.mesa_nombre}»?" alCerrar={() => (hoja = null)}>
    <p class="confirmar-texto">
      Todo lo de «{de}» ({dinero(ventaActual.total)}) pasa a la cuenta de «{a.mesa_nombre}», y «{de}» queda libre. Lo
      que esté en cocina sigue ahí, con el nombre de «{a.mesa_nombre}».
    </p>
    <div class="cel-pie sin-arriba">
      <button type="button" class="cel-boton contorno" onclick={() => (hoja = null)}>No</button>
      <button type="button" class="cel-boton" disabled={ocupado} onclick={() => confirmarJuntar(a)}>Juntar</button>
    </div>
  </Hoja>
{:else if hoja?.tipo === 'llevar'}
  <HojaLlevar alCerrar={() => (hoja = null)} alEmpezar={empezarLlevar} />
{:else if hoja?.tipo === 'cobrar'}
  {@const v = hoja.venta}
  <HojaCobrar
    {cliente}
    {restauranteId}
    venta={{
      id: v.id,
      titulo: nombreDe(v) || '—',
      tipo: v.tipo,
      abrio: v.abierta_por === null ? null : quien(v.abierta_por),
    }}
    cuenta={abiertas.ventas.find((x) => x.id === v.id) ?? null}
    {turnoId}
    {nombres}
    {autorizan}
    {zona}
    {terminal}
    alCerrar={() => (hoja = null)}
    alAviso={avisar}
    alListo={() => {
      // El id se lee antes de cerrar la hoja: sin hoja, `v` ya no existe.
      const id = v.id;
      hoja = null;
      if (!abiertas.ventas.some((x) => x.id === id)) volver();
    }}
  />
{/if}
{/snippet}

{#snippet caraAncha(a: Anfitrion)}
  {@const conMesas = mesas.length > 0}
  <div class="pos-ancho">
    <Barra
      anfitrion={a}
      titulo="Punto de venta"
      chip={chipAncho}
      vistas={conMesas
        ? {
            opciones: [
              { valor: 'mesas', texto: 'Mesas', icono: 'r-mesas' },
              { valor: 'llevar', texto: 'Para llevar', icono: a.donde === 'aparato' ? 'cuenta' : 'r-bolsa' },
            ],
            elegida: vistaAncho,
            alElegir: irVista,
          }
        : null}
      volver={pantalla === 'elegir' && actual
        ? { texto: tituloDe(actual), alVolver: () => ((pantalla = 'cuenta'), (error = null)) }
        : conMesas && actual?.[0] === 'm'
          ? { texto: 'Mesas', alVolver: () => irVista('mesas') }
          : null}
    />

    {#if carga.estado === 'leyendo' && !actual}
      <div class="cuerpo-ancho sin-abajo">
        {#if mesasAntes}
          <MesasCuadros mesas={[]} deMesa={new Map()} anotadas={new Set()} {estadoDe} quien={() => ''} hora={() => ''} cargando={mesasAntes} alAbrir={() => {}} />
        {:else}
          <div class="dos">
            <MenuCuadros categorias={[]} cuantos={new Map()} cargando alProducto={() => {}} />
            <Lado clave="leyendo"><EsqueletoLado /></Lado>
          </div>
        {/if}
      </div>
    {:else if carga.estado === 'error'}
      <div class="cuerpo-ancho sin-abajo">
        <div class="medio-ancho">
          <CajaError mensaje={carga.mensaje} />
          <Boton etiqueta="Intentar de nuevo" onclick={() => ((carga = { estado: 'leyendo' }), leerTodo())} />
        </div>
      </div>
    {:else if enLasMesas}
      <div class="cuerpo-ancho sin-abajo">
        <MesasCuadros
          {mesas}
          deMesa={cuentasDeMesa}
          {anotadas}
          {estadoDe}
          quien={(v) => quien(v.abierta_por)}
          hora={(v) => hora(v.created_at)}
          {terminal}
          alAbrir={(m) => abrirAncho(`m${m.id}`)}
        />
      </div>
    {:else if actual}
      {@const llave = actual}
      {@const v = ventaActual}
      {@const sigue = llave[0] !== 'v' || !!v}
      <div class="cuerpo-ancho">
        <div class="dos">
          {#if pantalla === 'elegir' && v}
            {@const juntar = modo === 'juntar'}
            <MesasCuadros
              mesas={mesas.filter((m) => m.id !== v.mesa_id && cuentasDeMesa.has(m.id) === juntar)}
              deMesa={cuentasDeMesa}
              {anotadas}
              {estadoDe}
              quien={(x) => quien(x.abierta_por)}
              hora={(x) => hora(x.created_at)}
              apagadas={ocupado}
              alAbrir={alElegirMesa}
            >
              {#snippet encima()}
                {#if error}<CajaError mensaje={error} />{/if}
              {/snippet}
            </MesasCuadros>
          {:else}
            <MenuCuadros categorias={menu.categorias} {cuantos} cargando={carga.estado === 'leyendo'} alProducto={alProductoAncho} />
          {/if}

          {#if lado === 'cobro' && cobroAncho && cobroDe}
            {@const de = cobroDe}
            {#if cobroAncho.cerrada}
              {@const x = cobroAncho.cerrada}
              <Lado clave="cobrada-{de.id}">
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
              <Lado clave="cobro-{de.id}"><TarjetaCobro cobro={cobroAncho} titulo={de.tarjeta} /></Lado>
            {/if}
          {:else if !sigue}
            <Lado clave="cerrada-{llave}">
              <div class="vacio-c"><b>Esa cuenta ya no está abierta</b><span>Se cobró, se canceló o se juntó con otra.</span></div>
            </Lado>
          {:else if lado === 'abiertos'}
            <Lado clave="abiertos">
              <AbiertosLado
                nuevos={nuevos.filter((n) => n.llave !== llave)}
                ventas={sinMesa}
                {estadoDe}
                quien={(x) => quien(x.abierta_por)}
                hora={(x) => hora(x.created_at)}
                alAbrir={abrirAncho}
              />
            </Lado>
          {:else if pantalla === 'pedida' && v}
            <Lado clave="pedida-{llave}">
              <div class="encabezado">
                <span class="cuadro-c"><Icono nombre="cuenta" tamano={18} /></span>
                <div class="titulos"><span class="titulo">La cuenta · {tituloDe(llave)}</span><span class="sub">Enséñasela al cliente.</span></div>
              </div>
              <div class="renglones">
                {#each abiertas.renglones.filter((r) => r.venta_id === v.id && r.estado === 'activo') as r (r.id)}
                  <div class="renglon">
                    <span class="que">
                      <b><span class="cant-e">{r.cantidad}</span>{r.nombre}</b>
                      {#if r.opciones.length}<span class="det">{r.opciones.map((o) => o.opcion).join(' · ')}</span>{/if}
                    </span>
                    <span class="imp">{pesos(r.importe)}</span>
                  </div>
                {/each}
              </div>
              <div class="resumen-c">
                {#if descuentoCuenta}
                  <div class="desc"><span>Descuento {descuentoCuenta.texto}</span><span>−{pesos(descuentoCuenta.monto)}</span></div>
                {/if}
                <div class="fuerte"><span>Total</span><span>{pesos(v.total)}</span></div>
                <div><span>Precios con IVA incluido</span><span></span></div>
              </div>
            </Lado>
          {:else}
            {@const deMesaEsta = llave[0] === 'm'}
            {@const tipo = v?.tipo ?? nuevoActual?.tipo ?? 'mesa'}
            <Lado clave="cuenta-{llave}">
              <CuentaLado
                titulo={nuevoActual ? nuevoActual.nombre.trim() || 'Pedido nuevo' : tituloDe(llave)}
                sub={nuevoActual
                  ? nuevoActual.nombre.trim()
                    ? TIPO_EN_PALABRAS[nuevoActual.tipo]
                    : 'Sin nombre, sale con su número del día.'
                  : subCuenta}
                icono={deMesaEsta ? 'mesas' : nuevoActual ? 'cuenta' : ICONO_DE_TIPO[tipo]}
                nuevo={nuevoActual}
                idCampos="pos-{llave}"
                alNuevo={cambiarNuevo}
                etiquetaLineas="{mandarTexto === 'Anotar' ? 'Por anotar' : 'Por mandar'} · solo en este {donde}"
                {lineas}
                {bloques}
                {sinArea}
                conCuenta={!!v}
                domicilio={v ? domicilio : null}
                subtotal={v?.subtotal ?? 0}
                descuento={descuentoCuenta}
                pagado={v?.pagado ?? 0}
                falta={v ? faltaDe(v) : null}
                {error}
                {sinRed}
                {mandarTexto}
                {donde}
                alCambiar={(i, n) =>
                  cambiarBorrador((b) => {
                    if (b.lineas[i] && b.lineas[i].cantidad + n >= 1) b.lineas[i].cantidad += n;
                  })}
                alQuitar={(i) => cambiarBorrador((b) => b.lineas.splice(i, 1))}
                alRenglon={(id) => ((hoja = { tipo: 'renglon', renglon: id }), (error = null))}
              >
                {#snippet accion()}
                  {#if v}
                    <MenuCuenta opciones={opcionesMenu(v)} alElegir={alMenuAncho} />
                  {/if}
                  {#if !deMesaEsta && carga.estado === 'leyendo'}
                    <Esqueleto ancho="118px" alto="40px" redondo="12px" />
                  {:else if !deMesaEsta}
                    <Boton etiqueta="Abiertos · {nuevos.filter((n) => n.llave !== llave).length + sinMesa.length}" icono="reloj" onclick={() => (lado = 'abiertos')} />
                  {/if}
                {/snippet}
              </CuentaLado>
            </Lado>
          {/if}
        </div>
      </div>

      <!-- La barra de abajo de Crear anuncios: cambia con lo que hay en la tarjeta. -->
      <footer class="barra-abajo">
        {#key `${lado}-${pantalla}-${sigue}-${!!cobroAncho?.cerrada}`}
          <div class="barra-contenido">
            {#if lado === 'cobro' && cobroAncho && cobroDe}
              {@const de = cobroDe}
              <AbajoCobro
                cobro={cobroAncho}
                fuerte={cobroAncho.cerrada ? `${de.titulo.split(' · ')[0]} cerrada` : de.tarjeta}
                chico={cobroAncho.cerrada
                  ? de.reabierta
                    ? 'Ya no sale en Por cobrar'
                    : de.mesa
                      ? 'La mesa quedó libre'
                      : 'Ya no sale en Abiertos'
                  : lineaCobro}
                alAtras={() => (lado = 'cuenta')}
                siguiente={de.mesa
                  ? { texto: 'Volver a las mesas', alPulsar: () => irVista('mesas') }
                  : { texto: 'Nuevo pedido', alPulsar: pedidoNuevo }}
              />
            {:else if !sigue}
              <div class="estado"><b>Esa cuenta ya no está abierta</b></div>
              <Boton etiqueta="Volver" icono="anterior" onclick={volver} />
            {:else if lado === 'abiertos'}
              <div class="estado" role="status">
                <b>{plural(nuevos.filter((n) => n.llave !== llave).length + sinMesa.length, 'abierto', 'abiertos')}</b>
                <small>Por cobrar: {pesos(sinMesa.reduce((t, x) => t + faltaDe(x), 0))}</small>
              </div>
              <!-- El pedido nuevo es el que se estaba anotando, si lo había. -->
              <Boton etiqueta="Pedido nuevo" icono="mas" onclick={() => (llave[0] === 'n' ? (lado = 'cuenta') : pedidoNuevo())} />
            {:else if pantalla === 'elegir'}
              <div class="estado"><b>{modo === 'juntar' ? '¿Con qué mesa se junta?' : '¿A qué mesa pasa?'}</b>
                <small>{modo === 'juntar' ? `Todo lo de «${tituloDe(llave)}» pasa a la cuenta que elijas.` : `«${tituloDe(llave)}» pasa con todo lo que lleva a una mesa libre.`}</small>
              </div>
              <Boton etiqueta="Cancelar" onclick={() => ((pantalla = 'cuenta'), (error = null))} />
            {:else if pantalla === 'pedida'}
              <div class="estado"><b>La cuenta · {tituloDe(llave)}</b><small>Pidió la cuenta</small></div>
              <Boton etiqueta="Listo" tono="tinta" onclick={() => (pantalla = 'cuenta')} />
            {:else}
              {@const nombresPorMandar = lineas.map((l) => l.nombre)}
              <div class="estado" role="status">
                {#if lineas.length}
                  <b>{v ? `${mandarTexto === 'Anotar' ? 'Por anotar' : 'Por mandar'} · ${porMandar}` : plural(porMandar, 'producto', 'productos')}</b>
                  <small>{nombresPorMandar.length > 1 ? `${nombresPorMandar.slice(0, -1).join(', ')} y ${nombresPorMandar.at(-1)}` : nombresPorMandar[0]}</small>
                {:else if v}
                  <b>Todo {mandarTexto === 'Anotar' ? 'anotado' : 'mandado'}</b><small>Toca un producto para agregar</small>
                {:else if faltanDatos}
                  <small>A domicilio, primero el teléfono y la dirección</small>
                {:else}
                  <small>Nada anotado todavía</small>
                {/if}
              </div>
              <span class="total-abajo">
                <span>{v && v.pagado > 0 ? 'Falta' : 'Total'}</span><b>{pesos((v ? (v.pagado > 0 ? faltaDe(v) : v.total) : 0) + sumaPorMandar)}</b>
              </span>
              {#if sinRed}
                <Boton etiqueta="Sin conexión" icono="sinred" tono="tinta" apagado={ocupado} onclick={anotarAncho} />
              {:else}
                <Boton
                  etiqueta="{mandarTexto}{porMandar ? ` · ${porMandar}` : ''}"
                  tono="tinta"
                  apagado={!porMandar || ocupado || faltanDatos}
                  cargando={ocupado}
                  onclick={anotarAncho}
                />
              {/if}
              <Boton etiqueta="Cobrar" tono="verde" apagado={(!porMandar && !v) || ocupado || faltanDatos || sinRed} onclick={cobrarAncho} />
            {/if}
          </div>
        {/key}
      </footer>
    {/if}

    {#if aviso}
      {@const av = aviso}
      <div class="aviso-ancho" role="status">
        <span class="punto-v"></span>
        <button
          type="button"
          class="abrir"
          onclick={() => {
            const x = abiertas.ventas.find((y) => y.id === av.venta);
            aviso = null;
            if (x) abrirAncho(llaveDe(x));
          }}
        >
          <b>{av.titulo} · Lista</b>
          <span>{av.area} · {av.cerrada ? 'ya está pagada' : 'toca para abrirla'}</span>
        </button>
        <BotonCuadro icono="cerrar" ayuda="Cerrar aviso" onclick={() => (aviso = null)} />
      </div>
    {/if}

    <div class="pos capa-hojas">
      {@render hojas()}
      {#if cobroAncho}<Encima cobro={cobroAncho} />{/if}
    </div>

    {#if globo}
      <div class="globo-a" class:sin-abajo={enLasMesas} role="status"><Icono nombre="check" tamano={14} />{globo}</div>
    {/if}
  </div>
{/snippet}

{#if ancho && anfitrion}
  {@render caraAncha(anfitrion)}
{:else}
<div class="pos">
  {#if carga.estado === 'leyendo'}
    <Lugar {restaurante} {linea} />
    {@render pestanas?.()}
    <div class="desliza"><div class="vacio"><span>Abriendo las mesas…</span></div></div>
  {:else if carga.estado === 'error'}
    <Lugar {restaurante} {linea} />
    {@render pestanas?.()}
    <div class="desliza">
      <CajaError mensaje={carga.mensaje} />
    </div>
    <div class="cel-pie">
      <button type="button" class="cel-boton contorno crece" onclick={() => ((carga = { estado: 'leyendo' }), leerTodo())}>
        Intentar de nuevo
      </button>
    </div>
  {:else if pantalla === 'mesas' || !actual}
    <Mesas
      {restaurante}
      {linea}
      {mesas}
      ventas={abiertas.ventas}
      {nuevos}
      {anotadas}
      {vista}
      {estadoDe}
      quien={(v) => quien(v.abierta_por)}
      hora={(v) => hora(v.created_at)}
      {efectivo}
      {pestanas}
      aviso={avisoLista}
      alVista={(v) => (vista = v)}
      alAbrir={abrir}
      alNuevoLlevar={() => (hoja = { tipo: 'llevar' })}
      {terminal}
    />
  {:else if pantalla === 'cuenta' && (actual[0] !== 'v' || ventaActual)}
    <Cuenta
      titulo={tituloDe(actual)}
      sub={subCuenta}
      volver={actual[0] === 'm' ? 'Mesas' : mesas.length ? 'Para llevar' : 'Volver'}
      {mandarTexto}
      conCuenta={!!ventaActual}
      {domicilio}
      {lineas}
      {bloques}
      {sinArea}
      subtotal={ventaActual?.subtotal ?? 0}
      descuento={descuentoCuenta}
      total={ventaActual ? ventaActual.total : null}
      pagado={ventaActual?.pagado ?? 0}
      falta={ventaActual ? faltaDe(ventaActual) : null}
      {donde}
      {error}
      {sinRed}
      enviando={ocupado}
      aviso={avisoLista}
      alVolver={volver}
      alMenu={() => (hoja = { tipo: 'menu' })}
      alAgregar={() => ((pantalla = 'agregar'), (sinRed = false), (error = null))}
      alMandar={mandar}
      alCobrar={() => ventaActual && ((hoja = { tipo: 'cobrar', venta: ventaActual }), (error = null))}
      alCambiar={(i, n) =>
        cambiarBorrador((b) => {
          if (b.lineas[i] && b.lineas[i].cantidad + n >= 1) b.lineas[i].cantidad += n;
        })}
      alQuitar={(i) => cambiarBorrador((b) => b.lineas.splice(i, 1))}
      alRenglon={(id) => ((hoja = { tipo: 'renglon', renglon: id }), (error = null))}
    />
  {:else if pantalla === 'agregar' && (actual[0] !== 'v' || ventaActual)}
    <Agregar
      titulo={tituloDe(actual)}
      categorias={menu.categorias}
      {cat}
      {cuantos}
      {porMandar}
      aviso={avisoLista}
      alCategoria={(i) => (cat = i)}
      {alProducto}
      alVer={() => (pantalla = 'cuenta')}
    />
  {:else if pantalla === 'pedida' && ventaActual}
    <Lugar {restaurante} linea="La cuenta · {tituloDe(actual)}" comoSeVe={false} />
    <div class="ticket">
      {#each abiertas.renglones.filter((r) => r.venta_id === ventaActual.id && r.estado === 'activo') as r (r.id)}
        <div class="ticket-linea">
          <span class="cant">{r.cantidad}</span>
          <span class="que">
            {r.nombre}
            {#if r.opciones.length}<small>{r.opciones.map((o) => o.opcion).join(' · ')}</small>{/if}
          </span>
          <span class="imp">{dinero(r.importe)}</span>
        </div>
      {/each}
      {#if descuentoCuenta}
        <div class="ticket-linea">
          <span class="cant"></span>
          <span class="que">Descuento {descuentoCuenta.texto}</span>
          <span class="imp">−{dinero(descuentoCuenta.monto)}</span>
        </div>
      {/if}
      <div class="ticket-total"><b>Total</b><span>{dinero(ventaActual.total)}</span></div>
      <div class="ticket-pie">Precios con IVA incluido</div>
    </div>
    <div class="cel-pie"><button type="button" class="cel-boton" onclick={() => (pantalla = 'cuenta')}>Listo</button></div>
  {:else if pantalla === 'elegir' && ventaActual}
    {@const de = tituloDe(actual)}
    {@const juntar = modo === 'juntar'}
    {@const lista = mesas.filter((m) => m.id !== ventaActual.mesa_id && !!ventaDe(`m${m.id}`) === juntar)}
    <div class="cel-arriba">
      <button type="button" class="cel-volver" onclick={() => ((pantalla = 'cuenta'), (error = null))}>
        <Icono nombre="anterior" tamano={16} />{de}
      </button>
    </div>
    <div class="elegir-cabeza">
      <h1 class="cel-titulo">{juntar ? '¿Con qué mesa se junta?' : '¿A qué mesa pasa?'}</h1>
      <p class="cel-texto">
        {juntar
          ? `Todo lo de «${de}» pasa a la cuenta que elijas, y «${de}» queda libre.`
          : `«${de}» pasa con todo lo que lleva a una mesa libre.`}
      </p>
    </div>
    {#if error}<div class="caja-pos" role="alert"><CajaError mensaje={error} /></div>{/if}
    <div class="desliza">
      {#if lista.length === 0}
        <div class="vacio">
          <b>{juntar ? 'No hay otra mesa con cuenta' : 'No hay mesas libres'}</b>
        </div>
      {:else}
        <div class="rejilla-mesas">
          {#each lista as m (m.id)}
            {@const v = ventaDe(`m${m.id}`)}
            <button type="button" class="mesa" class:libre={!v} disabled={ocupado} onclick={() => alElegirMesa(m)}>
              <span class="mesa-nombre">{m.nombre}</span>
              {#if v}
                <span class="mesa-abajo">
                  <span class="mesa-total">{dinero(v.total)}</span>
                  <span class="mesa-quien">Abrió {quien(v.abierta_por)}</span>
                </span>
              {:else}
                <span class="mesa-libre">Libre</span>
              {/if}
            </button>
          {/each}
        </div>
      {/if}
    </div>
  {:else}
    <!-- La cuenta se cerró o se juntó mientras se veía. -->
    <Lugar {restaurante} {linea} comoSeVe={false} />
    <div class="desliza">
      <div class="vacio"><b>Esa cuenta ya no está abierta</b></div>
    </div>
    <div class="cel-pie"><button type="button" class="cel-boton" onclick={volver}>{mesas.length ? 'Volver a las mesas' : 'Volver'}</button></div>
  {/if}

  {@render hojas()}

  {#if globo}
    <div class="globo" role="status"><Icono nombre="check" tamano={14} />{globo}</div>
  {/if}
</div>

{/if}

<style>
  .elegir-cabeza {
    flex: none;
    display: flex;
    flex-direction: column;
    gap: 6px;
    margin-top: 16px;
  }

  .cel-pie.sin-arriba {
    padding-top: 0;
  }

  /* El vidrio del aviso, con la sombra de con-sombra de la maqueta. */
  :global(.pos .aviso-lista.vidrio) {
    background: var(--vidrio);
    border: 1px solid var(--vidrio-linea);
    backdrop-filter: blur(18px) saturate(1.1);
    -webkit-backdrop-filter: blur(18px) saturate(1.1);
  }

  :global(.pos .sombra-pos) {
    box-shadow: 0 24px 60px var(--sombra);
  }
</style>
