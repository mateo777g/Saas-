<!--
  El punto de venta del mesero y de la caja (parte 4a; maqueta Mesero y cocina TYq97pKacRCYBqcvRp1bZ2;
  libreta 5). Lo abre el aparato del equipo con la sesión de quien puso su PIN, y el panel del
  gerente con la suya («Abrir» en Accesos para tu equipo): recibe la conexión y nunca importa la
  del panel.

  Lo anotado vive en este aparato hasta «Mandar a cocina», que llama a mandar_a_cocina con la
  clave del envío: con la misma clave Postgres no guarda nada dos veces. Si el internet se cae a
  medio envío, el borrador recuerda lo que se fue, y antes del siguiente envío pregunta si llegó.
  Las cuentas abiertas llegan solas con el tiempo real de Supabase; cuando una comanda que mandó
  esta persona pasa a «Lista», suena, vibra y sale el aviso.
-->
<script lang="ts">
  import type { SupabaseClient } from '@supabase/supabase-js';
  import { onMount, type Snippet } from 'svelte';
  import CajaError from '../../diseno/CajaError.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import { ALGO_SALIO_PANEL, esDeRed, Fallo, SIN_CONEXION } from '../../lib/errores';
  import { dinero, enZona } from '../../lib/formato';
  import {
    cambiarMesa,
    cuentaDelEnvio,
    escuchar,
    FalloPos,
    guardar,
    juntarMesas,
    leerAbiertas,
    leerGuardado,
    leerMenuPos,
    leerMesasPos,
    leerNombres,
    leerZona,
    mandarACocina,
    mismaLinea,
    pedirCuenta,
    restar,
    type Abiertas,
    type Borrador,
    type Comanda,
    type Guardado,
    type LineaBorrador,
    type MenuPos,
    type Mesa,
    type PedidoNuevo,
    type ProductoPos,
    type Venta,
  } from '../../lib/pos';
  import { avisarLista, prepararSonido } from '../../lib/sonido';
  import Agregar from './Agregar.svelte';
  import Cuenta, { type BloqueVista, type EnviadoVista, type LineaVista } from './Cuenta.svelte';
  import Hoja from './Hoja.svelte';
  import HojaLlevar from './HojaLlevar.svelte';
  import HojaOpciones from './HojaOpciones.svelte';
  import Lugar from './Lugar.svelte';
  import Mesas from './Mesas.svelte';
  import './pos.css';

  let {
    cliente,
    restauranteId,
    restaurante,
    miembroId,
    linea,
    donde,
    pestanas,
  }: {
    cliente: SupabaseClient;
    restauranteId: string;
    restaurante: string;
    miembroId: number;
    linea: string; // quién está: «Pepe Martínez · Mesero»
    donde: 'celular' | 'aparato' | 'navegador'; // dónde vive lo anotado, para los textos
    pestanas?: Snippet;
  } = $props();

  type Hojas =
    | { tipo: 'opciones'; producto: ProductoPos }
    | { tipo: 'menu' }
    | { tipo: 'juntar'; destino: Venta }
    | { tipo: 'llevar' };

  // ─── Lo que llega de Postgres ───
  let carga = $state<{ estado: 'leyendo' } | { estado: 'listo' } | { estado: 'error'; mensaje: string }>({
    estado: 'leyendo',
  });
  let menu = $state<MenuPos>({ categorias: [], areas: [] });
  let mesas = $state<Mesa[]>([]);
  let abiertas = $state<Abiertas>({ ventas: [], renglones: [], comandas: [] });
  let nombres = $state(new Map<number, string>());
  let zona = $state('America/Mexico_City');

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
  let aviso = $state<{ venta: number; titulo: string; area: string } | null>(null);
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
        const [nuevas, n] = await Promise.all([leerAbiertas(cliente, restauranteId), leerNombres(cliente, restauranteId)]);
        nombres = n;
        alLlegar(nuevas);
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
  function alLlegar(nuevas: Abiertas) {
    if (!primera) {
      const antes = new Map(abiertas.comandas.map((c) => [c.id, c.estado]));
      for (const c of nuevas.comandas) {
        if (c.estado === 'lista' && c.enviada_por === miembroId && antes.get(c.id) === 'pendiente') {
          avisoDeLista(c, nuevas);
        }
      }
    }
    primera = false;

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
      titulo: (v.tipo === 'mesa' ? v.mesa_nombre : v.cliente_nombre) ?? '',
      area: menu.areas.find((a) => a.id === c.area_preparacion_id)?.nombre ?? '',
    };
    const enPantalla = pantalla !== 'mesas' && actual !== null && ventaDe(actual, nuevas)?.id === v.id;
    if (!enPantalla && !guardado.sinVer.includes(v.id)) {
      guardado.sinVer.push(v.id);
      persistir();
    }
    avisarLista();
  }

  // ─── Qué cuenta es cada llave ───
  function ventaDe(llave: string, de: Abiertas = abiertas): Venta | null {
    const id = Number(llave.slice(1));
    if (llave[0] === 'm') return de.ventas.find((v) => v.tipo === 'mesa' && v.mesa_id === id) ?? null;
    if (llave[0] === 'v') return de.ventas.find((v) => v.id === id) ?? null;
    return null;
  }

  function llaveDe(v: Venta): string {
    return v.tipo === 'mesa' ? `m${v.mesa_id}` : `v${v.id}`;
  }

  function tituloDe(llave: string): string {
    const v = ventaDe(llave);
    if (llave[0] === 'm') return v?.mesa_nombre ?? mesas.find((m) => m.id === Number(llave.slice(1)))?.nombre ?? '';
    if (llave[0] === 'v') return v?.cliente_nombre ?? '';
    return guardado.borradores[llave]?.nuevo?.nombre ?? '';
  }

  function estadoDe(v: Venta): 'cocina' | 'lista' | 'cuenta' | 'ocupada' {
    if (v.cuenta_pedida_at) return 'cuenta';
    if (abiertas.comandas.some((c) => c.venta_id === v.id && c.estado === 'pendiente')) return 'cocina';
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

  function enviado(r: Abiertas['renglones'][number]): EnviadoVista {
    return {
      id: r.id,
      nombre: r.nombre,
      detalle: r.opciones.map((o) => o.opcion).join(' · '),
      nota: r.nota ?? '',
      cantidad: r.cantidad,
      importe: r.importe,
      por: quien(r.agregado_por),
    };
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
    const prefijo = tipo === 'domicilio' ? 'Domicilio' : tipo === 'para_llevar' ? 'Para llevar' : '';
    if (v) return `${prefijo ? `${prefijo} · ` : ''}Abrió ${quien(v.abierta_por)} · ${hora(v.created_at)}`;
    return `${prefijo || 'Libre'} · se abre al mandar a cocina`;
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

  async function mandar() {
    if (!actual || ocupado) return;
    let llave = actual;
    error = null;
    if (!navigator.onLine) {
      sinRed = true;
      return;
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
        return;
      }

      const v = ventaDe(llave);
      const destino = v ? { venta: v.id } : llave[0] === 'm' ? { mesa: Number(llave.slice(1)) } : (b.nuevo ?? null);
      if (!destino) {
        error = 'Esa cuenta ya no está abierta';
        return;
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
          return;
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
      avisar(areas.length ? `Mandado a ${areas.join(' y ')}` : 'Agregado a la cuenta');
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
    } catch (falla) {
      if (falla instanceof Fallo) error = falla.message;
      else {
        console.error('[pos] no se pudo mandar a cocina:', falla);
        if (esDeRed(falla)) sinRed = true;
        else error = ALGO_SALIO_PANEL;
      }
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

  // ─── Al abrir ───
  onMount(() => {
    leerTodo();
    const dejar = escuchar(cliente, restauranteId, ['ventas', 'venta_items', 'comandas'], () => {
      if (carga.estado === 'listo') recargarCuentas();
    });
    const alVolver = () => {
      if (document.visibilityState === 'visible') leerTodo();
    };
    const conRed = () => (sinRed = false);
    document.addEventListener('visibilitychange', alVolver);
    document.addEventListener('pointerdown', prepararSonido, true);
    window.addEventListener('online', conRed);
    return () => {
      dejar();
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
        <span>{a.area} · toca para abrirla</span>
      </button>
      <button type="button" class="cuadro" aria-label="Cerrar aviso" title="Cerrar" onclick={() => (aviso = null)}>
        <Icono nombre="cerrar" tamano={16} />
      </button>
    </div>
  {/if}
{/snippet}

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
      {pestanas}
      aviso={avisoLista}
      alVista={(v) => (vista = v)}
      alAbrir={abrir}
      alNuevoLlevar={() => (hoja = { tipo: 'llevar' })}
    />
  {:else if pantalla === 'cuenta' && (actual[0] !== 'v' || ventaActual)}
    <Cuenta
      titulo={tituloDe(actual)}
      sub={subCuenta}
      volver={actual[0] === 'm' ? 'Mesas' : 'Para llevar'}
      conCuenta={!!ventaActual}
      {domicilio}
      {lineas}
      {bloques}
      {sinArea}
      total={ventaActual ? ventaActual.total : null}
      {donde}
      {error}
      {sinRed}
      enviando={ocupado}
      aviso={avisoLista}
      alVolver={volver}
      alMenu={() => (hoja = { tipo: 'menu' })}
      alAgregar={() => ((pantalla = 'agregar'), (sinRed = false), (error = null))}
      alMandar={mandar}
      alCambiar={(i, n) =>
        cambiarBorrador((b) => {
          if (b.lineas[i] && b.lineas[i].cantidad + n >= 1) b.lineas[i].cantidad += n;
        })}
      alQuitar={(i) => cambiarBorrador((b) => b.lineas.splice(i, 1))}
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
    <Lugar {restaurante} linea="La cuenta · {tituloDe(actual)}" />
    <div class="ticket">
      {#each abiertas.renglones.filter((r) => r.venta_id === ventaActual.id) as r (r.id)}
        <div class="ticket-linea">
          <span class="cant">{r.cantidad}</span>
          <span class="que">
            {r.nombre}
            {#if r.opciones.length}<small>{r.opciones.map((o) => o.opcion).join(' · ')}</small>{/if}
          </span>
          <span class="imp">{dinero(r.importe)}</span>
        </div>
      {/each}
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
    <Lugar {restaurante} {linea} />
    <div class="desliza">
      <div class="vacio"><b>Esa cuenta ya no está abierta</b></div>
    </div>
    <div class="cel-pie"><button type="button" class="cel-boton" onclick={volver}>Volver a las mesas</button></div>
  {/if}

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
        {#if ventaActual.tipo === 'mesa'}
          <button type="button" onclick={() => elegir('cambiar')}>
            <Icono nombre="cambiar" tamano={18} />Cambiar de mesa<span class="sub">A una libre</span>
          </button>
          <button type="button" onclick={() => elegir('juntar')}>
            <Icono nombre="juntar" tamano={18} />Juntar con otra mesa<span class="sub">Esta queda libre</span>
          </button>
        {/if}
      </div>
    </Hoja>
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
  {/if}

  {#if globo}
    <div class="globo" role="status"><Icono nombre="check" tamano={14} />{globo}</div>
  {/if}
</div>

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
