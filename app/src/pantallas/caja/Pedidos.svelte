<!--
  Pedidos (parte 6b; maqueta Pedidos por WhatsApp G2nxGb3xBgiPEYrDb6CgcW; libreta 6): los pedidos
  que llegan del menú en línea. Arriba, si se reciben pedidos ahora y el botón para pausarlos el
  resto del día de negocio. Luego los «Por confirmar», del más viejo al más nuevo y completos:
  «Confirmar» lo vuelve una cuenta a nombre de quien confirma y lo manda a cocina (a domicilio,
  antes se elige el envío); «Rechazar» pide el motivo. Abajo, más chicos, los «Atendidos hoy».

  Tiene el ancho del celular, como la caja. La abren la pestaña Pedidos del aparato de quien es de
  caja y la vista Pedidos del panel del gerente; por eso recibe la conexión y la vigía (lib/
  pedidos.svelte.ts), que ya leyó los pedidos y es la que suena.
-->
<script lang="ts">
  import type { SupabaseClient } from '@supabase/supabase-js';
  import { onMount, type Snippet } from 'svelte';
  import CajaError from '../../diseno/CajaError.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import { ALGO_SALIO_PANEL, esDeRed, SIN_CONEXION } from '../../lib/errores';
  import { dinero, enZona } from '../../lib/formato';
  import {
    confirmarPedido,
    leerEnvios,
    pausarPedidos,
    rechazarPedido,
    type Envio,
    type Horario,
    type PorConfirmar,
    type VigiaPedidos,
  } from '../../lib/pedidos.svelte';
  import { FalloPos, leerZona } from '../../lib/pos';
  import Hoja from '../pos/Hoja.svelte';
  import Lugar from '../pos/Lugar.svelte';
  import '../pos/pos.css';

  let {
    cliente,
    restauranteId,
    restaurante,
    vigia,
    linea = '',
    enPanel = false,
    pestanas,
  }: {
    cliente: SupabaseClient;
    restauranteId: string;
    restaurante: string;
    vigia: VigiaPedidos;
    linea?: string; // quién está: «Lupita Hernández · Caja»; en el panel no se pinta
    enPanel?: boolean;
    pestanas?: Snippet;
  } = $props();

  const MOTIVOS = ['Pedido falso', 'Ya cerramos', 'No tenemos lo que pidió', 'Lo canceló el cliente', 'Otro motivo'];

  type Hojas =
    | { tipo: 'confirmar'; pedido: PorConfirmar; envios: Envio[] | null; envio: number | null | undefined }
    | { tipo: 'rechazar'; pedido: PorConfirmar; motivo: string | null; texto: string };

  let zona = $state('America/Mexico_City');
  let hoja = $state<Hojas | null>(null);
  let errorHoja = $state<string | null>(null);
  let error = $state<string | null>(null);
  let ocupado = $state(false);
  let globo = $state<string | null>(null);
  // Para «llegó hace 3 min»: la hora de Postgres al leer, y el reloj que solo avanza desde entonces.
  let reloj = $state(performance.now());

  const datos = $derived(vigia.datos);
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

  // «a la 1:00», como el menú en línea.
  const alas = (h: string) => (/^1:/.test(h) ? `a la ${h}` : `a las ${h}`);
  const DIAS = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
  function abre(e: Exclude<Horario, null | { abierto: true }>): string {
    const { dia, hora: h, en_dias } = e.abre;
    return `Abres ${en_dias === 0 ? 'hoy' : en_dias === 1 ? 'mañana' : `el ${DIAS[dia - 1]}`} ${alas(h)}`;
  }

  // La franja de arriba: recibiendo, en pausa, fuera de horario o sin lo que hace falta.
  const franja = $derived.by(() => {
    if (!datos) return null;
    const ven = 'tus clientes ven «Por ahora no recibimos pedidos»';
    if (datos.pausado) {
      return { tono: 'pausa', titulo: 'Pedidos en pausa', sub: `Desde las ${hora(datos.pausado_at ?? datos.ahora)} · ${ven}` };
    }
    if (datos.recibe && datos.estado?.abierto) {
      return { tono: 'vivo', titulo: 'Recibiendo pedidos', sub: `Por WhatsApp, desde tu menú · hasta ${alas(datos.estado.cierra).slice(2)}` };
    }
    if (datos.estado && !datos.estado.abierto) return { tono: 'apagado', titulo: 'Fuera de horario', sub: `${abre(datos.estado)} · ${ven}` };
    const falta = datos.estado === null ? 'tu horario' : 'tu teléfono';
    return {
      tono: 'apagado',
      titulo: 'No recibes pedidos',
      sub: enPanel ? `Falta ${falta} en Tu restaurante` : `Falta ${falta}: tu gerente lo pone en Tu restaurante`,
    };
  });

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
    hoja = { tipo: 'confirmar', pedido: p, envios: p.tipo === 'domicilio' ? null : [], envio: p.tipo === 'domicilio' ? undefined : null };
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
      else avisar(`#${pedido.numero} confirmado · ya va a cocina`);
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

  // ─── Pausar ───
  async function pausar() {
    if (!datos) return;
    ocupado = true;
    error = null;
    try {
      await pausarPedidos(cliente, restauranteId, !datos.pausado);
      await vigia.leer();
    } catch (falla) {
      error = mensaje(falla, 'no se pudieron pausar los pedidos');
    } finally {
      ocupado = false;
    }
  }

  onMount(() => {
    leerZona(cliente, restauranteId)
      .then((z) => (zona = z))
      .catch((falla) => console.error('[pedidos] no se pudo leer la zona; se usa la de México:', falla));
    const tic = setInterval(() => (reloj = performance.now()), 20000);
    return () => clearInterval(tic);
  });
</script>

<div class="pos">
  {#if !enPanel}<Lugar {restaurante} {linea} />{/if}
  {@render pestanas?.()}

  {#if !datos}
    <div class="desliza">
      {#if vigia.error}
        <CajaError mensaje={SIN_CONEXION} />
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
    {#if franja}
      <div class="ped-arriba {franja.tono}">
        <span class="punto"></span>
        <span class="t"><b>{franja.titulo}</b><span>{franja.sub}</span></span>
        <button type="button" class="boton-chico" disabled={ocupado} onclick={pausar}>
          {datos.pausado ? 'Reanudar' : 'Pausar pedidos'}
        </button>
      </div>
    {/if}

    <div class="desliza lista">
      {#if error}<CajaError mensaje={error} />{/if}
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
          {#if p.tipo === 'domicilio'}
            <div class="ped-entrega">
              {#if p.cliente_telefono}
                <span><Icono nombre="celular" tamano={14} /><span class="mono">{telefono(p.cliente_telefono)}</span></span>
              {/if}
              <span>
                <Icono nombre="ubicacion" tamano={14} />
                <span>{p.cliente_direccion}{p.cliente_referencias ? ` · ${p.cliente_referencias}` : ''}</span>
              </span>
              {#if p.paga_con !== null}
                <span><Icono nombre="billete" tamano={14} /><span>Paga con {dinero(p.paga_con)}</span></span>
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
    <Hoja titulo="Confirmar #{p.numero}" sub="{p.cliente_nombre} · {dom ? 'A domicilio' : 'Para llevar'}" alCerrar={() => (hoja = null)}>
      <p class="confirmar-texto">
        Se manda a cocina y queda como cuenta {dom ? 'a domicilio' : 'para llevar'} a tu nombre:
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
        {#if dom}
          <div class="resumen-fila"><span>Pedido</span><span>{dinero(p.total)}</span></div>
          <div class="resumen-fila"><span>Envío</span><span>{listo ? dinero(envio) : '—'}</span></div>
        {/if}
        <div class="resumen-fila fuerte"><span>Total</span><span>{listo ? dinero(p.total + envio) : '—'}</span></div>
      </div>
      {#if errorHoja}<CajaError mensaje={errorHoja} />{/if}
      <button type="button" class="cel-boton fijo" disabled={!listo || ocupado} onclick={confirmar}>Confirmar y mandar a cocina</button>
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
