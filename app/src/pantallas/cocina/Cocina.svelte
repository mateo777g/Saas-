<!--
  La pantalla de cocina (parte 4a; maqueta Mesero y cocina TYq97pKacRCYBqcvRp1bZ2; libreta 5, «La
  cocina»). Una tarjeta por comanda de su área, de la más vieja a la más nueva, con los minutos
  que lleva esperando: a los 10 se pone amarilla y a los 20, roja. Un toque la marca «Lista» y se
  va. «Últimas listas» trae las 10 más recientes de hoy (el día de negocio, parte 4b) para
  regresarlas si se marcó por error. El área se elige una vez y este aparato la recuerda. Las comandas llegan solas con el tiempo real.

  La abre el aparato de cocina, que nunca vuelve a pedir el PIN, y el panel del gerente con su
  sesión. Los minutos y el reloj usan el reloj de este aparato, como la cuenta regresiva del
  código de Empleados: la hora de cada comanda es la de Postgres.
-->
<script lang="ts">
  import type { SupabaseClient } from '@supabase/supabase-js';
  import { onMount, type Snippet } from 'svelte';
  import CajaError from '../../diseno/CajaError.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import Integral from '../../diseno/Integral.svelte';
  import { ALGO_SALIO_PANEL, esDeRed, Fallo, SIN_CONEXION } from '../../lib/errores';
  import { enZona, plural } from '../../lib/formato';
  import {
    escuchar,
    leerCocina,
    leerNombres,
    leerZona,
    marcarComanda,
    type Area,
    type EnCocina,
    type Tarjeta,
  } from '../../lib/pos';

  let {
    cliente,
    restauranteId,
    aparato = null,
    enPanel = false,
    pestanas,
  }: {
    cliente: SupabaseClient;
    restauranteId: string;
    aparato?: string | null; // el nombre del aparato, arriba a la derecha
    enPanel?: boolean;
    pestanas?: Snippet;
  } = $props();

  // svelte-ignore state_referenced_locally
  const LLAVE_AREA = `fragmentless-cocina-${restauranteId}`;

  let areas = $state<Area[]>([]);
  let areaId = $state<number | null>(leerArea());
  let pantalla = $state<'area' | 'comandas' | 'listas'>('comandas');
  let datos = $state<EnCocina>({ pendientes: [], listas: [] });
  let nombres = $state(new Map<number, string>());
  let zona = $state('America/Mexico_City');
  let carga = $state<'leyendo' | 'listo' | 'error'>('leyendo');
  let error = $state<string | null>(null);
  let ahora = $state(Date.now());

  const area = $derived(areas.find((a) => a.id === areaId) ?? null);
  const pendientes = $derived(datos.pendientes.filter((c) => c.area_preparacion_id === areaId));

  function leerArea(): number | null {
    try {
      const guardada = localStorage.getItem(LLAVE_AREA);
      return guardada ? Number(guardada) : null;
    } catch (falla) {
      console.error('[cocina] no se pudo leer el área de este aparato:', falla);
      return null;
    }
  }

  function elegirArea(id: number) {
    areaId = id;
    pantalla = 'comandas';
    try {
      localStorage.setItem(LLAVE_AREA, String(id));
    } catch (falla) {
      console.error('[cocina] no se pudo guardar el área de este aparato:', falla);
    }
    recargar();
  }

  async function leerTodo() {
    try {
      const [a, z] = await Promise.all([
        cliente
          .from('areas_preparacion')
          .select('id, nombre')
          .eq('restaurante_id', restauranteId)
          .is('archivado_at', null)
          .order('id'),
        leerZona(cliente, restauranteId),
      ]);
      if (a.error) throw a.error;
      areas = a.data;
      zona = z;
      if (!areas.some((x) => x.id === areaId)) pantalla = 'area';
      await leer();
      carga = 'listo';
    } catch (falla) {
      console.error('[cocina] no se pudo abrir la cocina:', falla);
      if (carga !== 'listo') {
        carga = 'error';
        error = esDeRed(falla) ? SIN_CONEXION : ALGO_SALIO_PANEL;
      }
    }
  }

  // Como en el punto de venta: si llegan eventos mientras se lee, se lee otra vez al terminar.
  let leyendo: Promise<void> | null = null;
  let otraVez = false;
  function leer(): Promise<void> {
    if (leyendo) {
      otraVez = true;
      return leyendo;
    }
    leyendo = (async () => {
      do {
        otraVez = false;
        const [d, n] = await Promise.all([
          leerCocina(cliente, restauranteId, areaId),
          leerNombres(cliente, restauranteId),
        ]);
        datos = d;
        nombres = n;
      } while (otraVez);
    })().finally(() => (leyendo = null));
    return leyendo;
  }

  function recargar() {
    leer().catch((falla) => console.error('[cocina] no se pudieron volver a leer las comandas:', falla));
  }

  async function marcar(t: Tarjeta, lista: boolean) {
    error = null;
    // Se va de la pantalla al tocarla; si Postgres dice que no, regresa con la nueva lectura.
    if (lista) datos.pendientes = datos.pendientes.filter((c) => c.id !== t.id);
    else datos.listas = datos.listas.filter((c) => c.id !== t.id);
    try {
      await marcarComanda(cliente, t.id, lista);
    } catch (falla) {
      error = falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL;
    }
    recargar();
  }

  const minutos = (t: Tarjeta) => Math.max(0, Math.floor((ahora - Date.parse(t.created_at)) / 60000));
  const hora = (momento: string) => enZona(momento, zona).hora;
  const quien = (id: number | null) => (id === null ? '—' : (nombres.get(id) ?? '—'));
  const tipoTexto = (t: Tarjeta) => (t.tipo === 'domicilio' ? 'Domicilio · ' : t.tipo === 'para_llevar' ? 'Para llevar · ' : '');

  onMount(() => {
    leerTodo();
    const dejar = escuchar(cliente, restauranteId, ['comandas', 'venta_items', 'ventas'], () => {
      if (carga === 'listo') recargar();
    });
    const reloj = setInterval(() => (ahora = Date.now()), 15000);
    const alVolver = () => {
      if (document.visibilityState === 'visible') {
        ahora = Date.now();
        leerTodo();
      }
    };
    document.addEventListener('visibilitychange', alVolver);
    return () => {
      dejar();
      clearInterval(reloj);
      document.removeEventListener('visibilitychange', alVolver);
    };
  });
</script>

<div class="cocina" class:en-panel={enPanel}>
  {#if carga === 'error'}
    <div class="k-vacio">
      <b>No pudimos abrir la cocina</b>
      <div class="caja-k"><CajaError mensaje={error ?? ALGO_SALIO_PANEL} /></div>
      <button type="button" class="boton" onclick={() => ((carga = 'leyendo'), (error = null), leerTodo())}>Intentar de nuevo</button>
    </div>
  {:else if carga === 'leyendo'}
    <div class="k-vacio"><span>Abriendo la cocina…</span></div>
  {:else if pantalla === 'area' || !area}
    <div class="k-elegir">
      <div class="k-elegir-caja vidrio sombra">
        <span class="etq">Esta pantalla</span>
        <h3>¿Qué área muestra?</h3>
        <p class="texto">Se queda guardada en este aparato. Para cambiarla, toca el nombre del área arriba.</p>
        {#each areas as a (a.id)}
          {@const n = datos.pendientes.filter((c) => c.area_preparacion_id === a.id).length}
          <button type="button" class="k-elegir-op" onclick={() => elegirArea(a.id)}>
            <Icono nombre={a.nombre === 'Cocina' ? 'cocina' : 'menu'} tamano={20} />{a.nombre}
            <span>{plural(n, 'comanda', 'comandas')}</span>
          </button>
        {/each}
        {#if pestanas}<div class="pestanas-elegir">{@render pestanas()}</div>{/if}
      </div>
    </div>
  {:else}
    <div class="k-arriba" class:vidrio={!enPanel} class:sombra={!enPanel}>
      {#if !enPanel}<div class="logo"><Integral ancho={20} alto={22} /></div>{/if}
      <button type="button" class="k-area" onclick={() => (pantalla = 'area')}>{area.nombre}<Icono nombre="abajo" tamano={16} /></button>
      <span class="chip-estado"><span class="punto"></span>{plural(pendientes.length, 'comanda', 'comandas')}</span>
      {@render pestanas?.()}
      <span class="crece"></span>
      {#if aparato}<span class="aparato">{aparato}</span>{/if}
      <button type="button" class="boton" onclick={() => (pantalla = 'listas')}><Icono nombre="regresar" tamano={16} />Últimas listas</button>
      <span class="k-reloj">{hora(new Date(ahora).toISOString())}</span>
    </div>

    {#if pendientes.length}
      <div class="k-rejilla">
        {#if error}<div class="caja-k ancho"><CajaError mensaje={error} /></div>{/if}
        {#each pendientes as t (t.id)}
          {@const m = minutos(t)}
          <button
            type="button"
            class="comanda"
            class:amarilla={m >= 10 && m < 20}
            class:roja={m >= 20}
            aria-label="Marcar lista la comanda de {t.titulo}"
            onclick={() => marcar(t, true)}
          >
            <span class="c-cabeza">
              <span class="t"><b>{t.titulo}</b><span>{tipoTexto(t)}{quien(t.enviada_por)} · {hora(t.created_at)}</span></span>
              <span class="c-min">{m} min</span>
            </span>
            <span class="c-items">
              {#each t.renglones as r (r.id)}
                <span class="c-item">
                  <span class="cant">{r.cantidad}</span>
                  <b>{r.nombre}</b>
                  {#if r.opciones.length}<span class="det">{r.opciones.map((o) => o.opcion).join(' · ')}</span>{/if}
                  {#if r.nota}<span class="nota-c">{r.nota}</span>{/if}
                </span>
              {/each}
            </span>
            <span class="c-pie">Toca cuando salga todo</span>
          </button>
        {/each}
      </div>
    {:else}
      <div class="k-vacio">
        {#if error}<div class="caja-k"><CajaError mensaje={error} /></div>{/if}
        <span class="cuadro-icono"><Icono nombre="check" tamano={18} /></span>
        <b>Sin comandas pendientes</b>
        <span>Las nuevas llegan solas, al momento.</span>
      </div>
    {/if}

    {#if pantalla === 'listas'}
      <div class="k-lado vidrio sombra">
        <div class="k-lado-cabeza">
          <div class="t">
            <b>Últimas listas</b>
            <span>Las 10 más recientes de hoy. Regresar la devuelve a la pantalla.</span>
          </div>
          <button type="button" class="cuadro" aria-label="Cerrar" title="Cerrar" onclick={() => (pantalla = 'comandas')}>
            <Icono nombre="cerrar" tamano={16} />
          </button>
        </div>
        <div class="k-lista">
          {#each datos.listas as t (t.id)}
            <div class="k-fila">
              <span class="t"><b>{t.titulo}</b><span>{quien(t.enviada_por)} · lista {hora(t.lista_at ?? t.created_at)}</span></span>
              <button type="button" class="boton-chico" onclick={() => marcar(t, false)}><Icono nombre="regresar" tamano={14} />Regresar</button>
            </div>
          {:else}
            <div class="vacio"><b>Nada marcado todavía</b></div>
          {/each}
        </div>
      </div>
    {/if}
  {/if}
</div>

<style>
  .cocina {
    position: relative;
    width: 100%;
    height: 100%;
    overflow: hidden;
    font-size: 14px;
    font-weight: 500;
  }

  .crece {
    flex-grow: 1;
  }

  .etq {
    font-family: var(--mono);
    font-size: 10.5px;
    letter-spacing: 0.14em;
    color: var(--tenue);
    text-transform: uppercase;
  }

  .texto {
    margin: 0;
    font-size: 13.5px;
    line-height: 1.5;
    color: var(--suave);
  }

  .vidrio {
    background: var(--vidrio);
    border: 1px solid var(--vidrio-linea);
    backdrop-filter: blur(18px) saturate(1.1);
    -webkit-backdrop-filter: blur(18px) saturate(1.1);
  }

  .sombra {
    box-shadow: 0 24px 60px var(--sombra);
  }

  .boton {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    height: 40px;
    padding: 0 14px;
    border-radius: 12px;
    border: 1px solid var(--linea);
    background: transparent;
    color: var(--texto);
    font-size: 13px;
    font-weight: 600;
    white-space: nowrap;
    transition: opacity 150ms;
  }

  .boton:hover {
    opacity: 0.86;
  }

  .boton-chico {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 30px;
    padding: 0 10px;
    border-radius: 10px;
    border: 1px solid var(--linea);
    background: transparent;
    color: var(--texto);
    font-size: 12px;
    font-weight: 600;
    white-space: nowrap;
  }

  .cuadro {
    width: 36px;
    height: 36px;
    flex: none;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    padding: 0;
    border: 1px solid var(--linea);
    border-radius: 10px;
    background: transparent;
    color: var(--texto);
  }

  .cuadro-icono {
    width: 36px;
    height: 36px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 11px;
    background: var(--chip);
  }

  .chip-estado {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    height: 28px;
    padding: 0 12px;
    border-radius: 14px;
    background: var(--chip);
    font-size: 12px;
    font-weight: 500;
    color: var(--suave);
    white-space: nowrap;
  }

  .punto {
    width: 7px;
    height: 7px;
    border-radius: 4px;
    background: var(--verde);
    flex: none;
  }

  .logo {
    width: 32px;
    height: 32px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 10px;
    background: var(--acento);
    color: var(--sobre-acento);
  }

  .aparato {
    font-family: var(--mono);
    font-size: 11px;
    color: var(--tenue);
    white-space: nowrap;
  }

  /* Arriba */
  .k-arriba {
    position: absolute;
    left: 16px;
    right: 16px;
    top: 16px;
    height: 64px;
    padding: 0 12px 0 14px;
    display: flex;
    align-items: center;
    gap: 14px;
    border-radius: 20px;
    z-index: 2;
  }

  .k-area {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    height: 40px;
    padding: 0 12px 0 14px;
    border-radius: 12px;
    border: 1px solid var(--linea);
    background: transparent;
    color: var(--texto);
    font-size: 17px;
    font-weight: 800;
    letter-spacing: -0.2px;
  }

  .k-reloj {
    font-family: var(--mono);
    font-size: 15px;
    font-weight: 500;
    font-variant-numeric: tabular-nums;
  }

  /* Las tarjetas */
  .k-rejilla {
    position: absolute;
    left: 16px;
    right: 16px;
    top: 96px;
    bottom: 16px;
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    grid-auto-rows: min-content;
    gap: 12px;
    align-content: start;
    overflow-y: auto;
    padding-bottom: 12px;
    scrollbar-width: none;
  }

  .k-rejilla::-webkit-scrollbar {
    display: none;
  }

  .comanda {
    display: flex;
    flex-direction: column;
    border-radius: 20px;
    border: 1px solid var(--linea);
    background: var(--solido);
    color: var(--texto);
    text-align: left;
    padding: 0;
    overflow: hidden;
    box-shadow: 0 8px 24px var(--sombra-segmento);
  }

  .comanda:active {
    transform: scale(0.99);
  }

  .c-cabeza {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 12px 14px;
    border-bottom: 1px solid var(--linea);
  }

  .c-cabeza .t {
    min-width: 0;
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .c-cabeza b {
    font-size: 18px;
    font-weight: 800;
    letter-spacing: -0.3px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .c-cabeza span {
    font-size: 12px;
    opacity: 0.75;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .c-min {
    flex: none;
    font-family: var(--mono);
    font-size: 15px;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
  }

  .comanda.amarilla .c-cabeza {
    background: var(--amarillo);
    color: var(--sobre-amarillo);
    border-bottom-color: transparent;
  }

  .comanda.roja .c-cabeza {
    background: var(--rojo);
    color: var(--sobre-rojo);
    border-bottom-color: transparent;
  }

  .c-items {
    display: flex;
    flex-direction: column;
    gap: 12px;
    padding: 14px;
  }

  .c-item {
    display: grid;
    grid-template-columns: 28px minmax(0, 1fr);
    gap: 2px 8px;
  }

  .c-item .cant {
    font-family: var(--mono);
    font-size: 17px;
    font-weight: 600;
    line-height: 1.25;
  }

  .c-item b {
    font-size: 16px;
    font-weight: 700;
    line-height: 1.25;
  }

  .c-item .det {
    grid-column: 2;
    font-size: 13px;
    color: var(--suave);
    line-height: 1.4;
  }

  .c-item .nota-c {
    grid-column: 2;
    font-size: 13px;
    font-weight: 700;
    line-height: 1.4;
  }

  .c-item .nota-c::before {
    content: 'Nota: ';
    font-weight: 500;
    color: var(--tenue);
  }

  .c-pie {
    padding: 10px 14px 12px;
    border-top: 1px dashed var(--linea-fuerte);
    font-size: 12px;
    color: var(--tenue);
  }

  .k-vacio {
    position: absolute;
    left: 16px;
    right: 16px;
    top: 96px;
    bottom: 16px;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 8px;
    text-align: center;
  }

  .k-vacio b {
    font-size: 18px;
    font-weight: 800;
  }

  .k-vacio span {
    font-size: 13.5px;
    color: var(--suave);
  }

  .caja-k {
    max-width: 520px;
    margin-bottom: 8px;
    text-align: left;
  }

  .caja-k.ancho {
    grid-column: 1 / -1;
    max-width: none;
    margin: 0;
  }

  /* Últimas listas */
  .k-lado {
    position: absolute;
    top: 96px;
    right: 16px;
    bottom: 16px;
    width: 380px;
    max-width: calc(100% - 32px);
    z-index: 3;
    border-radius: 24px;
    padding: 18px;
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .k-lado-cabeza {
    display: flex;
    align-items: flex-start;
    gap: 12px;
  }

  .k-lado-cabeza .t {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .k-lado-cabeza b {
    font-size: 17px;
    font-weight: 800;
  }

  .k-lado-cabeza span {
    font-size: 12px;
    color: var(--suave);
  }

  .k-lista {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .k-fila {
    display: flex;
    align-items: center;
    gap: 10px;
    min-height: 56px;
    padding: 8px 8px 8px 14px;
    border-radius: 14px;
    border: 1px solid var(--linea);
    background: var(--solido);
  }

  .k-fila .t {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .k-fila b {
    font-size: 14px;
    font-weight: 700;
  }

  .k-fila span {
    font-family: var(--mono);
    font-size: 11px;
    color: var(--tenue);
  }

  .vacio {
    padding: 36px 8px;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 6px;
    text-align: center;
  }

  .vacio b {
    font-size: 14.5px;
    font-weight: 700;
  }

  /* Elegir el área */
  .k-elegir {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 16px;
  }

  .k-elegir-caja {
    width: 460px;
    max-width: 100%;
    padding: 30px;
    border-radius: 28px;
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  .k-elegir-caja h3 {
    margin: 0;
    font-size: 24px;
    font-weight: 800;
    letter-spacing: -0.5px;
  }

  .k-elegir-op {
    display: flex;
    align-items: center;
    gap: 14px;
    min-height: 64px;
    padding: 0 18px;
    border: 1px solid var(--linea);
    border-radius: 16px;
    background: var(--solido);
    color: var(--texto);
    font-size: 17px;
    font-weight: 700;
    text-align: left;
  }

  .k-elegir-op span {
    margin-left: auto;
    font-size: 12.5px;
    font-weight: 500;
    color: var(--tenue);
  }

  /* Dentro del panel: sin vidrio arriba y en tres columnas. */
  .en-panel .k-arriba {
    top: 8px;
  }

  .en-panel .k-rejilla,
  .en-panel .k-vacio,
  .en-panel .k-lado {
    top: 84px;
  }

  .en-panel .k-rejilla {
    grid-template-columns: repeat(3, minmax(0, 1fr));
  }

  @media (max-width: 1000px) {
    .k-rejilla {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .boton {
      transition: none;
    }

    .comanda:active {
      transform: none;
    }
  }
</style>
