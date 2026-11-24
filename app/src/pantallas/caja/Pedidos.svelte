<!--
  Pedidos (parte 6b; maqueta Pedidos por WhatsApp G2nxGb3xBgiPEYrDb6CgcW; libreta 6): los pedidos
  que llegan del menú en línea. Arriba, si se reciben pedidos ahora y el botón para pausarlos el
  resto del día de negocio. Luego los «Por confirmar», del más viejo al más nuevo y completos:
  «Confirmar» lo vuelve una cuenta a nombre de quien confirma y lo manda a cocina (a domicilio,
  antes se elige el envío); «Rechazar» pide el motivo. Abajo, más chicos, los «Atendidos hoy».

  Tiene el ancho del celular, como la caja. La abren la pestaña Pedidos del aparato de quien es de
  caja y la vista Pedidos del panel del gerente; por eso recibe la conexión y la vigía (lib/
  pedidos.svelte.ts), que ya leyó los pedidos y es la que suena.

  Con la adaptabilidad (encuesta 15 «A, Tablero»; planes/trabajo/adaptabilidad/pedidos-ancho.md): cuando le dan unos
  900 px o más, se acomoda sola a lo ancho (pedidos/Tablero.svelte): los pedidos en tarjetas, uno junto a otro, y los
  atendidos en una tarjeta a la derecha. Las hojas de confirmar y rechazar son las mismas, al centro y de 440. Con
  `franjaAfuera`, a lo ancho no pinta su cabeza (el lugar, las pestañas y la franja con «Pausar pedidos»): la pone quien la
  abre en su barra de arriba (el chip con pedidos/franja.ts y el botón con `vigia.pausar()`), y aquí queda la línea gris.
-->
<script lang="ts">
  import type { SupabaseClient } from '@supabase/supabase-js';
  import { onMount, type Snippet } from 'svelte';
  import CajaError from '../../diseno/CajaError.svelte';
  import Esqueleto from '../../diseno/Esqueleto.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import { ALGO_SALIO_PANEL, esDeRed, SIN_CONEXION } from '../../lib/errores';
  import { filasDeLaUltimaVez, recordarFilas } from '../../lib/esqueletos';
  import { dinero, enZona } from '../../lib/formato';
  import { confirmarPedido, leerEnvios, rechazarPedido, type Envio, type PorConfirmar, type VigiaPedidos } from '../../lib/pedidos.svelte';
  import { areasDeLaCuenta, areasDelPedido, FalloPos, leerZona, textoMandar } from '../../lib/pos';
  import Hoja from '../pos/Hoja.svelte';
  import Lugar from '../pos/Lugar.svelte';
  import '../pos/pos.css';
  import { franjaDe } from './pedidos/franja';
  import Tablero from './pedidos/Tablero.svelte';
  import UsaPremio from './pedidos/UsaPremio.svelte';

  let {
    cliente,
    restauranteId,
    restaurante,
    vigia,
    linea = '',
    enPanel = false,
    franjaAfuera = false,
    errorArriba = null,
    pestanas,
  }: {
    cliente: SupabaseClient;
    restauranteId: string;
    restaurante: string;
    vigia: VigiaPedidos;
    linea?: string; // quién está: «Lupita Hernández · Caja»; en el panel no se pinta
    enPanel?: boolean;
    // A lo ancho, la cabeza va en la barra de arriba de quien la abre.
    franjaAfuera?: boolean;
    // El error de lo que quien la abre tiene en su barra de arriba («Hago envíos» del panel): sale con los de aquí.
    errorArriba?: string | null;
    pestanas?: Snippet;
  } = $props();

  // A lo ancho desde unos 900 px («Lo que decidí yo» 7 de la adaptabilidad): lo que mide por dentro.
  let medida = $state<DOMRectReadOnly>();
  const ancho = $derived((medida?.width ?? 0) >= 900);
  const conFranja = $derived(!(ancho && franjaAfuera));

  const MOTIVOS = ['Pedido falso', 'Ya cerramos', 'No tenemos lo que pidió', 'Lo canceló el cliente', 'Otro motivo'];

  type Hojas =
    // areas: a dónde irá (areasDelPedido); null mientras se lee o si no se pudo leer.
    | { tipo: 'confirmar'; pedido: PorConfirmar; envios: Envio[] | null; envio: number | null | undefined; areas: string[] | null }
    | { tipo: 'rechazar'; pedido: PorConfirmar; motivo: string | null; texto: string };

  let zona = $state('America/Mexico_City');
  let hoja = $state<Hojas | null>(null);
  let errorHoja = $state<string | null>(null);
  let error = $state<string | null>(null);
  let ocupado = $state(false);
  let globo = $state<string | null>(null);
  // Los errores de arriba, sin repetir el mismo texto dos veces (sin red, todos dicen lo mismo).
  const errores = $derived([...new Set([error, vigia.errorPausa, errorArriba].filter((e): e is string => !!e))]);
  // Para «llegó hace 3 min»: la hora de Postgres al leer, y el reloj que solo avanza desde entonces.
  let reloj = $state(performance.now());

  const datos = $derived(vigia.datos);

  // En el panel, el esqueleto de la primera lectura (regla «Los esqueletos» del panel; el aparato sigue con su texto):
  // tantos pedidos por confirmar como había la última vez, hasta 3.
  const esqueletoPedidos = $derived(enPanel ? Math.min(3, filasDeLaUltimaVez(`pedidos-${restauranteId}`)) : 0);
  // A lo ancho caben más: hasta 6 tarjetas y los atendidos de la última vez.
  const esqueletoAncho = $derived(
    enPanel
      ? {
          pedidos: Math.min(6, filasDeLaUltimaVez(`pedidos-${restauranteId}`)),
          atendidos: filasDeLaUltimaVez(`atendidos-${restauranteId}`),
        }
      : null,
  );
  $effect(() => {
    if (!enPanel || !datos) return;
    recordarFilas(`pedidos-${restauranteId}`, datos.por_confirmar.length);
    recordarFilas(`atendidos-${restauranteId}`, datos.atendidos.length);
  });
  const hora = (momento: string) => enZona(momento, zona).hora;
  const pila = (nombre: string | null) => (nombre ?? '—').trim().split(/\s+/)[0];
  const telefono = (t: string) => `${t.slice(0, 3)} ${t.slice(3, 6)} ${t.slice(6)}`;

  // Cuánto lleva esperando, con la hora de Postgres y no la del aparato.
  let leidoEn = performance.now();
  let leidoAhora = '';
  $effect(() => {
    if (datos && datos.ahora !== leidoAhora) {
      leidoAhora = datos.ahora;
      leidoEn = performance.now();
      reloj = leidoEn;
    }
  });
  function llego(p: PorConfirmar): string {
    if (!datos) return '';
    const ahora = Date.parse(datos.ahora) + (reloj - leidoEn);
    const minutos = Math.floor((ahora - Date.parse(p.created_at)) / 60000);
    if (minutos < 1) return 'llegó hace un momento';
    if (minutos < 60) return `llegó hace ${minutos} min`;
    return `llegó a las ${hora(p.created_at)}`;
  }

  // La franja de arriba: recibiendo, en pausa, fuera de horario o sin lo que hace falta (pedidos/franja.ts).
  const franja = $derived(datos ? franjaDe(datos, zona, enPanel) : null);

  function avisar(texto: string) {
    globo = texto;
    setTimeout(() => {
      if (globo === texto) globo = null;
    }, 1600);
  }

  function mensaje(falla: unknown, contexto: string): string {
    if (falla instanceof FalloPos) return falla.message;
    console.error(`[pedidos] ${contexto}:`, falla);
    return esDeRed(falla) ? SIN_CONEXION : ALGO_SALIO_PANEL;
  }

  function releer() {
    vigia.leer().catch(() => {});
  }

  // ─── Confirmar ───
  async function abrirConfirmar(p: PorConfirmar) {
    error = null;
    errorHoja = null;
    hoja = { tipo: 'confirmar', pedido: p, envios: p.tipo === 'domicilio' ? null : [], envio: p.tipo === 'domicilio' ? undefined : null, areas: null };
    // A dónde va, para la hoja; si no se puede leer, la hoja dice solo lo que siempre es cierto.
    areasDelPedido(cliente, restauranteId, p.id)
      .then((areas) => {
        if (hoja?.tipo === 'confirmar' && hoja.pedido.id === p.id) hoja.areas = areas;
      })
      .catch((falla) => console.error('[pedidos] no se pudo leer a qué áreas va el pedido:', falla));
    if (p.tipo !== 'domicilio') return;
    try {
      const envios = await leerEnvios(cliente, restauranteId);
      if (hoja?.tipo === 'confirmar' && hoja.pedido.id === p.id) hoja.envios = envios;
    } catch (falla) {
      errorHoja = mensaje(falla, 'no se pudieron leer los envíos');
    }
  }

  async function confirmar() {
    if (hoja?.tipo !== 'confirmar' || hoja.envio === undefined) return;
    const { pedido, envio } = hoja;
    ocupado = true;
    errorHoja = null;
    try {
      const venta = await confirmarPedido(cliente, pedido.id, envio);
      hoja = null;
      if (venta === null) error = `El #${pedido.numero} era de ayer: se rechazó solo, «No se confirmó».`;
      else {
        // El aviso dice a dónde fue; si no se pudo leer, solo «confirmado» (el pedido ya está).
        const areas = await areasDeLaCuenta(cliente, restauranteId, venta).catch((f) => {
          console.error('[pedidos] no se pudieron leer las áreas del pedido confirmado:', f);
          return [];
        });
        avisar(`#${pedido.numero} confirmado${areas.length ? ` · va a ${areas.join(' y ')}` : ''}`);
      }
      releer();
    } catch (falla) {
      errorHoja = mensaje(falla, 'no se pudo confirmar el pedido');
      releer();
    } finally {
      ocupado = false;
    }
  }

  // ─── Rechazar ───
  const motivoListo = (h: Extract<Hojas, { tipo: 'rechazar' }>) =>
    h.motivo !== null && (h.motivo !== 'Otro motivo' || h.texto.trim() !== '');

  async function rechazar() {
    if (hoja?.tipo !== 'rechazar' || !motivoListo(hoja)) return;
    const { pedido } = hoja;
    const motivo = hoja.motivo === 'Otro motivo' ? hoja.texto.trim() : hoja.motivo!;
    ocupado = true;
    errorHoja = null;
    try {
      await rechazarPedido(cliente, pedido.id, motivo);
      hoja = null;
      avisar(`#${pedido.numero} rechazado`);
      releer();
    } catch (falla) {
      errorHoja = mensaje(falla, 'no se pudo rechazar el pedido');
      releer();
    } finally {
      ocupado = false;
    }
  }

  // ─── Pausar: lo hace la vigía, para que el botón también pueda ir en la barra de arriba ───
  function pausar() {
    error = null;
    vigia.pausar();
  }

  onMount(() => {
    leerZona(cliente, restauranteId)
      .then((z) => (zona = z))
      .catch((falla) => console.error('[pedidos] no se pudo leer la zona; se usa la de México:', falla));
    const tic = setInterval(() => (reloj = performance.now()), 20000);
    return () => clearInterval(tic);
  });
</script>

{#snippet laFranja()}
  {#if franja && datos}
    <div class="ped-arriba {franja.tono}">
      <span class="punto"></span>
      <span class="t"><b>{franja.titulo}</b><span>{franja.sub}</span></span>
      <button type="button" class="boton-chico" disabled={ocupado || vigia.pausando} onclick={pausar}>
        {datos.pausado ? 'Reanudar' : 'Pausar pedidos'}
      </button>
    </div>
  {/if}
{/snippet}

<div class="pos" class:ancho bind:contentRect={medida}>
  {#if conFranja}
    {#if !enPanel}<Lugar {restaurante} {linea} />{/if}
    {@render pestanas?.()}
  {/if}

  {#if ancho}
    {#if conFranja}{@render laFranja()}{/if}
    <Tablero
      {datos}
      falloLectura={vigia.error && !datos}
      esqueleto={esqueletoAncho}
      {errores}
      nota={conFranja ? null : (franja?.nota ?? null)}
      {llego}
      {hora}
      alConfirmar={abrirConfirmar}
      alRechazar={(p) => ((error = null), (errorHoja = null), (hoja = { tipo: 'rechazar', pedido: p, motivo: null, texto: '' }))}
      alReintentar={releer}
    />
  {:else if !datos}
    <div class="desliza">
      {#if vigia.error}
        <CajaError mensaje={SIN_CONEXION} />
      {:else if enPanel}
        <span class="solo-lector">Abriendo los pedidos…</span>
        <div class="bloque-cabeza" aria-hidden="true"><Esqueleto ancho="120px" alto="10px" /></div>
        {#each Array.from({ length: esqueletoPedidos }, (_, i) => i) as i (i)}
          <div class="pedido" aria-hidden="true">
            <div class="ped-cabeza">
              <Esqueleto ancho="34px" alto="14px" />
              <span class="t"><Esqueleto ancho="{i % 2 ? 96 : 120}px" alto="12px" /><Esqueleto ancho="140px" alto="10px" /></span>
              <Esqueleto ancho="56px" alto="12px" />
            </div>
            <Esqueleto ancho="80%" alto="10px" />
            <Esqueleto ancho="60%" alto="10px" />
          </div>
        {/each}
      {:else}
        <div class="vacio"><span>Abriendo los pedidos…</span></div>
      {/if}
    </div>
    {#if vigia.error}
      <div class="cel-pie">
        <button type="button" class="cel-boton contorno crece" onclick={releer}>Intentar de nuevo</button>
      </div>
    {/if}
  {:else}
    {@render laFranja()}

    <div class="desliza lista">
      {#each errores as e (e)}<CajaError mensaje={e} />{/each}
      <div class="bloque-cabeza"><span class="etq">Por confirmar · {datos.por_confirmar.length}</span></div>
      {#each datos.por_confirmar as p (p.id)}
        <div class="pedido">
          <div class="ped-cabeza">
            <span class="ped-num">#{p.numero}</span>
            <span class="t">
              <b>{p.cliente_nombre}</b>
              <span class="tipo">{p.tipo === 'domicilio' ? 'A domicilio' : 'Para llevar'} · {llego(p)}</span>
            </span>
            <span class="tot">{dinero(p.total)}</span>
          </div>
          <!-- El teléfono también para llevar (desde la migración tu_menu_en_linea el menú lo pide en los dos), como a lo
               ancho; la dirección y «Paga con», solo a domicilio. -->
          {#if p.cliente_telefono || p.tipo === 'domicilio'}
            <div class="ped-entrega">
              {#if p.cliente_telefono}
                <span><Icono nombre="celular" tamano={14} /><span class="mono">{telefono(p.cliente_telefono)}</span></span>
              {/if}
              {#if p.tipo === 'domicilio'}
                <span>
                  <Icono nombre="ubicacion" tamano={14} />
                  <span>{p.cliente_direccion}{p.cliente_referencias ? ` · ${p.cliente_referencias}` : ''}</span>
                </span>
                {#if p.paga_con !== null}
                  <span><Icono nombre="billete" tamano={14} /><span>Paga con {dinero(p.paga_con)}</span></span>
                {/if}
              {/if}
            </div>
          {/if}
          <div class="ped-items">
            {#each p.renglones as r, i (i)}
              <div class="ped-item">
                <span class="cant">{r.cantidad}</span>
                <b>{r.nombre}</b>
                <span class="imp">{dinero(r.importe)}</span>
                {#if r.opciones.length}<span class="det">{r.opciones.map((o) => o.opcion).join(' · ')}</span>{/if}
                {#if r.nota}<span class="nota-r">{r.nota}</span>{/if}
              </div>
            {/each}
          </div>
          {#if p.premio}<UsaPremio premio={p.premio} />{/if}
          <p class="ped-pista"><Icono nombre="mensaje" tamano={13} />Confírmalo cuando te llegue su WhatsApp.</p>
          <div class="ped-botones">
            <button
              type="button"
              class="cel-boton contorno"
              onclick={() => ((error = null), (errorHoja = null), (hoja = { tipo: 'rechazar', pedido: p, motivo: null, texto: '' }))}
            >
              Rechazar
            </button>
            <button type="button" class="cel-boton" onclick={() => abrirConfirmar(p)}>Confirmar</button>
          </div>
        </div>
      {:else}
        <div class="vacio">
          <b>Sin pedidos por confirmar</b>
          <span>Los pedidos de tu menú en línea llegan aquí, con un tono.</span>
        </div>
      {/each}

      {#if datos.atendidos.length}
        <div class="bloque-cabeza"><span class="etq">Atendidos hoy · {datos.atendidos.length}</span></div>
        {#each datos.atendidos as a (a.id)}
          {@const rechazado = a.estado === 'rechazado'}
          <div class="atendido" class:rechazado>
            <span class="ped-num">#{a.numero}</span>
            <span class="t">
              <b>{a.cliente_nombre}</b>
              {#if rechazado}
                <span class="rechazo">
                  {a.atendido_por ? `Rechazó ${pila(a.atendido_por)} · ` : ''}{hora(a.atendido_at)} · «{a.rechazo_motivo}»
                </span>
              {:else}
                <span>Confirmó {pila(a.atendido_por)} · {hora(a.atendido_at)} · ya es cuenta</span>
              {/if}
            </span>
            <span class="m">{dinero(a.total)}</span>
          </div>
        {/each}
      {/if}
    </div>
  {/if}

  {#if hoja?.tipo === 'confirmar'}
    {@const h = hoja}
    {@const p = hoja.pedido}
    {@const dom = p.tipo === 'domicilio'}
    {@const elegido = h.envios?.find((e) => e.id === h.envio) ?? null}
    {@const envio = elegido?.precio ?? 0}
    {@const listo = h.envio !== undefined}
    <!-- El premio de la tarjeta que entra al confirmar (la prueba de verdad del 23 nov: el total no lo restaba). Solo si
         todavía alcanza; si no, se confirma sin él y su aviso ámbar ya lo dice. En pesos se resta de toda la cuenta, como
         lo deja Postgres; un producto entra en $0. -->
    {@const premio = p.premio?.alcanza ? p.premio : null}
    {@const menos = premio?.tipo === 'pesos' ? (premio.pesos ?? 0) : 0}
    <Hoja titulo="Confirmar #{p.numero}" sub="{p.cliente_nombre} · {dom ? 'A domicilio' : 'Para llevar'}" alCerrar={() => (hoja = null)}>
      <p class="confirmar-texto">
        {h.areas?.length ? `Se manda a ${h.areas.join(' y ')} y queda` : 'Queda'} como cuenta {dom ? 'a domicilio' : 'para llevar'} a tu nombre:
        <b>«#{p.numero} · {p.cliente_nombre}»</b>. {dom ? 'La cobras cuando regrese el repartidor.' : 'La cobras cuando pase por ella.'}
      </p>
      {#if dom}
        <div class="campo">
          <span class="etq">¿Cuánto es el envío?</span>
          {#if h.envios === null && !errorHoja}
            <span class="pista">Leyendo tus envíos…</span>
          {:else if h.envios}
            <div class="chips-cobro" role="group" aria-label="Envío">
              {#each h.envios as e (e.id)}
                <button type="button" class="chip-cat" aria-pressed={h.envio === e.id} onclick={() => (h.envio = e.id)}>
                  {e.nombre}<span class="mono">{dinero(e.precio)}</span>
                </button>
              {/each}
              <button type="button" class="chip-cat" aria-pressed={h.envio === null} onclick={() => (h.envio = null)}>
                Sin envío
              </button>
            </div>
            <p class="pista">
              {#if h.envios.length}
                Son los productos de Mi menú con «Es un costo de envío».
              {:else}
                {enPanel ? 'Crea tu envío en Mi menú.' : 'Tu gerente crea tus envíos en Mi menú.'}
              {/if}
            </p>
          {/if}
        </div>
      {/if}
      <div class="resumen">
        {#if dom || premio}
          <div class="resumen-fila"><span>Pedido</span><span>{dinero(p.total)}</span></div>
        {/if}
        {#if dom}
          <div class="resumen-fila"><span>Envío</span><span>{listo ? dinero(envio) : '—'}</span></div>
        {/if}
        {#if premio}
          <div class="resumen-fila desc">
            <span>{premio.tipo === 'producto' ? `${premio.nombre ?? 'Su producto'} · premio de la tarjeta` : 'Premio de la tarjeta'}</span>
            <span>{premio.tipo === 'producto' ? dinero(0) : `-${dinero(menos)}`}</span>
          </div>
        {/if}
        <div class="resumen-fila fuerte"><span>Total</span><span>{listo ? dinero(p.total + envio - menos) : '—'}</span></div>
      </div>
      {#if errorHoja}<CajaError mensaje={errorHoja} />{/if}
      <button type="button" class="cel-boton fijo" disabled={!listo || ocupado} onclick={confirmar}
        >{h.areas?.length ? `Confirmar y m${textoMandar(h.areas).slice(1)}` : 'Confirmar'}</button
      >
    </Hoja>
  {:else if hoja?.tipo === 'rechazar'}
    {@const h = hoja}
    {@const p = hoja.pedido}
    <Hoja titulo="Rechazar #{p.numero}" sub="{p.cliente_nombre} · {dinero(p.total)}" alCerrar={() => (hoja = null)}>
      <div class="campo">
        <span class="etq">¿Por qué?</span>
        <div class="chips-cobro" role="group" aria-label="Motivo">
          {#each MOTIVOS as m (m)}
            <button type="button" class="chip-cat" aria-pressed={h.motivo === m} onclick={() => (h.motivo = m)}>
              {m}
            </button>
          {/each}
        </div>
        {#if h.motivo === 'Otro motivo'}
          <input class="motivo-otro" maxlength="140" placeholder="Escribe el motivo" aria-label="Motivo" autocomplete="off" bind:value={h.texto} />
        {/if}
      </div>
      <p class="pista">El pedido se queda guardado como rechazado, con tu nombre y el motivo. La página no le avisa: contéstale por WhatsApp.</p>
      {#if errorHoja}<CajaError mensaje={errorHoja} />{/if}
      <button type="button" class="cel-boton fijo" disabled={!motivoListo(h) || ocupado} onclick={rechazar}>Rechazar #{p.numero}</button>
    </Hoja>
  {/if}

  {#if globo}
    <div class="globo" role="status"><Icono nombre="check" tamano={14} />{globo}</div>
  {/if}
</div>

<style>
  /* ─── A lo ancho (pedidos/Tablero.svelte) ─── */
  .pos.ancho > :global(.tablero:not(:first-child)) {
    margin-top: 16px;
  }

  /* Las hojas de confirmar y rechazar, las de siempre: al centro y de 440, sobre un velo que tapa toda la pantalla, como
     las ventanas del panel (encuesta 3 de pedidos-ancho.md; Vender y la Caja hacen lo mismo con las suyas). */
  .pos.ancho :global(.hoja-velo) {
    position: fixed;
    z-index: 30;
    justify-content: center;
  }

  .pos.ancho :global(.hoja) {
    max-width: 440px;
  }

  /* El globo, sin barra de abajo: a 24 del borde, con el rebote de la caja del agente, como el de la maqueta. */
  .pos.ancho .globo {
    bottom: 24px;
    z-index: 31;
    border-radius: 12px;
    animation: globo-sale 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275);
  }

  @keyframes globo-sale {
    from {
      opacity: 0;
      transform: translate(-50%, 14px) scale(0.97);
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .pos.ancho .globo {
      animation: none;
    }
  }

  .desliza.lista {
    gap: 8px;
  }

  .cel-boton.fijo {
    flex: none;
  }

  .ped-arriba {
    flex: none;
    margin-top: 12px;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 10px 10px 10px 14px;
    border-radius: 16px;
    border: 1px solid var(--linea);
    background: var(--solido);
  }

  .ped-arriba .t {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .ped-arriba b {
    font-size: 14px;
    font-weight: 700;
  }

  .ped-arriba .t span {
    font-size: 11.5px;
    color: var(--tenue);
  }

  .ped-arriba.pausa .punto {
    background: var(--amarillo);
  }

  .ped-arriba.apagado .punto {
    background: var(--tenue);
  }

  .bloque-cabeza {
    margin-top: 4px;
  }

  .pedido {
    flex: none;
    display: flex;
    flex-direction: column;
    gap: 10px;
    padding: 12px 14px 14px;
    border-radius: 18px;
    border: 1px solid var(--linea);
    background: var(--solido);
  }

  .ped-cabeza {
    display: flex;
    align-items: flex-start;
    gap: 10px;
  }

  .ped-num {
    min-width: 46px;
    height: 30px;
    padding: 0 8px;
    border-radius: 9px;
    background: var(--tinta);
    color: var(--sobre-tinta);
    font-family: var(--mono);
    font-size: 13.5px;
    font-weight: 600;
    display: flex;
    align-items: center;
    justify-content: center;
    flex: none;
  }

  .ped-cabeza .t {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .ped-cabeza b {
    font-size: 15px;
    font-weight: 700;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .ped-cabeza .tipo {
    font-size: 11.5px;
    color: var(--tenue);
  }

  .ped-cabeza .tot {
    font-family: var(--mono);
    font-size: 14px;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
    white-space: nowrap;
  }

  .ped-entrega {
    display: flex;
    flex-direction: column;
    gap: 4px;
    padding: 9px 12px;
    border-radius: 12px;
    background: var(--chip);
    font-size: 12.5px;
    line-height: 1.4;
  }

  .ped-entrega > span {
    display: flex;
    gap: 8px;
    align-items: flex-start;
  }

  .ped-entrega :global(svg) {
    margin-top: 1px;
    flex: none;
    color: var(--suave);
  }

  .ped-entrega .mono {
    font-family: var(--mono);
    font-variant-numeric: tabular-nums;
  }

  .ped-items {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .ped-item {
    display: grid;
    grid-template-columns: 22px minmax(0, 1fr) auto;
    gap: 2px 8px;
    font-size: 13px;
  }

  .ped-item .cant {
    font-family: var(--mono);
    font-weight: 600;
    font-variant-numeric: tabular-nums;
  }

  .ped-item b {
    font-weight: 700;
  }

  .ped-item .det,
  .ped-item .nota-r {
    grid-column: 2;
    font-size: 12px;
    color: var(--suave);
    line-height: 1.4;
  }

  .ped-item .nota-r::before {
    content: 'Nota: ';
    color: var(--tenue);
  }

  .ped-item .imp {
    grid-row: 1;
    grid-column: 3;
    font-family: var(--mono);
    font-variant-numeric: tabular-nums;
    text-align: right;
  }

  .ped-pista {
    margin: 0;
    display: flex;
    align-items: center;
    gap: 7px;
    font-size: 11.5px;
    color: var(--tenue);
  }

  .ped-botones {
    display: grid;
    grid-template-columns: minmax(0, 1fr) minmax(0, 1.5fr);
    gap: 8px;
  }

  .ped-botones .cel-boton {
    flex: none;
    height: 44px;
    font-size: 14px;
  }

  .atendido {
    display: flex;
    align-items: center;
    gap: 12px;
    min-height: 58px;
    flex: none;
    padding: 9px 14px;
    border-radius: 14px;
    border: 1px solid var(--linea);
  }

  .atendido .ped-num {
    min-width: 40px;
    height: 26px;
    font-size: 12px;
    background: var(--chip);
    color: var(--suave);
  }

  .atendido .t {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .atendido b {
    font-size: 13.5px;
    font-weight: 700;
  }

  .atendido .t span {
    font-size: 11.5px;
    color: var(--tenue);
  }

  .atendido .t .rechazo {
    color: var(--suave);
  }

  .atendido .m {
    font-family: var(--mono);
    font-size: 12.5px;
    font-variant-numeric: tabular-nums;
    color: var(--suave);
  }

  .atendido.rechazado .m {
    text-decoration: line-through;
    color: var(--tenue);
  }

  .confirmar-texto b {
    color: var(--texto);
    font-weight: 600;
  }

  .motivo-otro {
    margin-top: 8px;
  }
</style>
