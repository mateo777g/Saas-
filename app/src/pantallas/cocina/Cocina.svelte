<!--
  La pantalla de cocina (parte 4a; libreta 5, «La cocina»). Una tarjeta por comanda de su área, de la más vieja a la más
  nueva, con los minutos que lleva esperando: a los 10 se pone amarilla y a los 20, roja. Un toque la marca «Lista» y se
  va. «Últimas listas» trae las 10 más recientes de hoy (el día de negocio, parte 4b) para regresarlas si se marcó por
  error. El área se elige una vez y este aparato la recuerda. Las comandas llegan solas con el tiempo real.

  Con la parte 4c: lo que se cancela sale aquí al momento, tachado en rojo con «Cancelado» y su motivo, para que no se
  prepare. La tarjeta se marca «Cambió» mientras siga pendiente, y suena un tono distinto al de «Lista», una vez por cada
  cancelación. Si se cancela todo, dice «Todo cancelado» y se quita con el mismo toque. Lo cancelado de algo ya «Lista» no
  regresa la tarjeta: sale tachado en «Últimas listas».

  Con el rediseño (14 nov 2026; planes/trabajo/rediseno/cocina.md) tiene la estructura de Pedidos a lo ancho: su barra de
  arriba (pos/ancho/Barra.svelte: en el aparato la estrella, el lugar y sus pestañas en el dock; en el panel «‹ Inicio» y la
  cajita de sucursales), con el chip, la cajita del área (CajaAreas) y el reloj; abajo, el Tablero: las comandas a la
  izquierda y «Últimas listas» en la tarjeta de la derecha. Cómo funciona no cambió: nunca pide nada, nunca se bloquea.

  La abre el aparato de cocina, que nunca vuelve a pedir el PIN, y el panel del gerente con su sesión. Los minutos y el
  reloj usan el reloj de este aparato, como la cuenta regresiva del código de Empleados: la hora de cada comanda es la de
  Postgres.
-->
<script lang="ts">
  import type { SupabaseClient } from '@supabase/supabase-js';
  import { onMount } from 'svelte';
  import Icono from '../../diseno/Icono.svelte';
  import { ALGO_SALIO_PANEL, esDeRed, Fallo, SIN_CONEXION } from '../../lib/errores';
  import { filasDeLaUltimaVez, recordarFilas } from '../../lib/esqueletos';
  import { enZona, plural } from '../../lib/formato';
  import { avisarCambio, prepararSonido } from '../../lib/sonido';
  import {
    escuchar,
    TIPO_EN_PALABRAS,
    leerCocina,
    leerNombres,
    leerZona,
    marcarComanda,
    type Area,
    type EnCocina,
    type Tarjeta,
  } from '../../lib/pos';
  import Barra from '../pos/ancho/Barra.svelte';
  import type { Anfitrion } from '../pos/ancho/barra';
  import '../pos/ancho/ancho.css';
  import CajaAreas from './CajaAreas.svelte';
  import Tablero from './Tablero.svelte';

  let {
    cliente,
    restauranteId,
    anfitrion,
  }: {
    cliente: SupabaseClient;
    restauranteId: string;
    anfitrion: Anfitrion; // quién la abre: el aparato (sus pestañas) o el panel («‹ Inicio» y la cajita de sucursales)
  } = $props();

  // svelte-ignore state_referenced_locally
  const LLAVE_AREA = `fragmentless-cocina-${restauranteId}`;

  let areas = $state<Area[]>([]);
  let areaId = $state<number | null>(leerArea());
  let datos = $state<EnCocina>({ pendientes: [], listas: [] });
  let nombres = $state(new Map<number, string>());
  let zona = $state('America/Mexico_City');
  let carga = $state<'leyendo' | 'listo' | 'error'>('leyendo');
  let error = $state<string | null>(null);
  let ahora = $state(Date.now());

  const area = $derived(areas.find((a) => a.id === areaId) ?? null);
  const pendientes = $derived(datos.pendientes.filter((c) => c.area_preparacion_id === areaId));

  // El esqueleto de la primera lectura: tantas comandas (hasta 6) y listas como había la última vez en este navegador.
  // svelte-ignore state_referenced_locally
  const llaveFilas = `cocina-${restauranteId}-${areaId ?? 'sin-area'}`;
  const esqueleto = {
    comandas: Math.min(6, filasDeLaUltimaVez(llaveFilas)),
    listas: filasDeLaUltimaVez(`${llaveFilas}-listas`),
  };
  $effect(() => {
    if (carga !== 'listo' || !area) return;
    recordarFilas(`cocina-${restauranteId}-${area.id}`, pendientes.length);
    recordarFilas(`cocina-${restauranteId}-${area.id}-listas`, datos.listas.length);
  });

  function leerArea(): number | null {
    try {
      const guardada = localStorage.getItem(LLAVE_AREA);
      return guardada ? Number(guardada) : null;
    } catch (falla) {
      console.error('[cocina] no se pudo leer el área de este aparato:', falla);
      return null;
    }
  }

  function guardarArea(id: number) {
    areaId = id;
    try {
      localStorage.setItem(LLAVE_AREA, String(id));
    } catch (falla) {
      console.error('[cocina] no se pudo guardar el área de este aparato:', falla);
    }
  }

  function elegirArea(id: number) {
    guardarArea(id);
    oidos = null;
    error = null;
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
      // Con una sola área no hay nada que elegir: se queda esa.
      if (areas.length === 1 && areaId !== areas[0].id) guardarArea(areas[0].id);
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
          leerCocina(cliente, restauranteId, area ? areaId : null),
          leerNombres(cliente, restauranteId),
        ]);
        datos = d;
        nombres = n;
        oirCambios(d);
      } while (otraVez);
    })().finally(() => (leyendo = null));
    return leyendo;
  }

  function recargar() {
    leer().catch((falla) => console.error('[cocina] no se pudieron volver a leer las comandas:', falla));
  }

  function reintentar() {
    carga = 'leyendo';
    error = null;
    leerTodo();
  }

  // Lo cancelado de las pendientes de esta área que ya sonó. La primera lectura solo lo anota.
  let oidos: Set<number> | null = null;
  function oirCambios(d: EnCocina) {
    const cancelados = d.pendientes
      .filter((c) => c.area_preparacion_id === areaId)
      .flatMap((c) => c.renglones.filter((r) => r.estado === 'cancelado').map((r) => r.id));
    if (oidos && cancelados.some((id) => !oidos!.has(id))) avisarCambio();
    oidos = new Set([...(oidos ?? []), ...cancelados]);
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
  // «Para llevar · WhatsApp · Lupita · 14:05»: la de un pedido del menú en línea lo dice (parte 6b).
  const lineaLista = (t: Tarjeta) =>
    (t.tipo === 'mesa' ? '' : `${TIPO_EN_PALABRAS[t.tipo]} · `) + (t.whatsapp ? 'WhatsApp · ' : '') + quien(t.enviada_por);
  const subDe = (t: Tarjeta) => `${lineaLista(t)} · ${hora(t.created_at)}`;

  // Lo de arriba: el chip dice cuántas hay (en vivo); la cajita, qué área muestra y cuántas tiene cada una.
  const chip = $derived.by(() => {
    if (carga === 'leyendo') return { texto: 'Cargando las comandas…', vivo: true };
    if (carga === 'error') return { texto: 'No se pudo leer', vivo: false };
    if (areas.length === 0) return { texto: 'Sin áreas', vivo: false, hueco: true };
    if (!area) return null;
    return { texto: plural(pendientes.length, 'comanda', 'comandas'), vivo: true };
  });
  const areasConCuenta = $derived(
    areas.map((a) => ({ ...a, comandas: datos.pendientes.filter((c) => c.area_preparacion_id === a.id).length })),
  );

  onMount(() => {
    leerTodo();
    const dejar = escuchar(cliente, restauranteId, ['comandas', 'venta_items', 'ventas'], () => {
      if (carga === 'listo') recargar();
    });
    const reloj = setInterval(() => (ahora = Date.now()), 15000);
    document.addEventListener('pointerdown', prepararSonido, true);
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
      document.removeEventListener('pointerdown', prepararSonido, true);
      document.removeEventListener('visibilitychange', alVolver);
    };
  });
</script>

<div class="cocina">
  <!-- Solo la barra va en .pos-ancho (sus clases chocarían con las del Tablero), como Pedidos en el aparato. -->
  <div class="pos-ancho barra-c">
    <Barra {anfitrion} titulo="Cocina" {chip}>
      {#if carga === 'listo' && area}
        <CajaAreas areas={areasConCuenta} actual={area.id} alElegir={elegirArea} />
      {/if}
      <span class="reloj">{hora(new Date(ahora).toISOString())}</span>
    </Barra>
  </div>

  <main class="cuerpo">
    {#if carga === 'listo' && areas.length === 0}
      <!-- Un restaurante nace sin áreas (adaptabilidad, «Lo que decidí yo» 4). -->
      <div class="aviso">
        <span class="cuadrito"><Icono nombre="r-cocina" tamano={18} /></span>
        <b>Todavía no hay áreas</b>
        <span>Tu gerente las agrega en Mi menú, en su panel.</span>
      </div>
    {:else if carga === 'listo' && !area}
      <!-- La primera vez en este aparato, con más de un área. -->
      <div class="elegir">
        <section class="tarjeta elegir-caja">
          <div class="encabezado">
            <span class="cuadrito"><Icono nombre="r-cocina" tamano={18} /></span>
            <div class="titulos">
              <span class="titulo">¿Qué área muestra?</span>
              <span class="sub">Se queda guardada en este aparato. Para cambiarla, toca el nombre del área arriba.</span>
            </div>
          </div>
          <div class="opciones">
            {#each areasConCuenta as a (a.id)}
              <button type="button" class="opcion" onclick={() => elegirArea(a.id)}>
                <span class="cuadro-icono"><Icono nombre="cocina" tamano={16} /></span>
                <span class="nombre">{a.nombre}</span>
                <span class="cuenta">{plural(a.comandas, 'comanda', 'comandas')}</span>
                <Icono nombre="siguiente" tamano={16} />
              </button>
            {/each}
          </div>
        </section>
      </div>
    {:else}
      <Tablero
        clave={areaId ?? 'sin-area'}
        comandas={carga === 'listo' ? pendientes : null}
        listas={carga === 'listo' ? datos.listas : null}
        falloLectura={carga === 'error'}
        esqueleto={carga === 'leyendo' ? esqueleto : null}
        {error}
        {subDe}
        {minutos}
        {hora}
        {lineaLista}
        alMarcar={(t) => marcar(t, true)}
        alRegresar={(t) => marcar(t, false)}
        alReintentar={reintentar}
      />
    {/if}
  </main>
</div>

<style>
  .cocina {
    position: absolute;
    inset: 0;
    background: var(--fondo);
    color: var(--texto);
    font-size: 13.5px;
    text-align: left;
    overflow: hidden;
  }

  /* Cristal, en el panel: lo de atrás es el fondo del marco, con sus manchas, y sin recortar el desvanecido de la barra
     de arriba, que corre por detrás de la barra lateral (como .pos-ancho en pos/ancho/ancho.css). */
  :global(:root[data-estilo='cristal'] .lugar-vista) .cocina {
    background: transparent;
    overflow: visible;
  }

  /* La barra de arriba de 56; lo que cuelga de ella (la lista del área) sale por debajo. */
  .pos-ancho.barra-c {
    bottom: auto;
    height: 56px;
    z-index: 2;
    overflow: visible;
    background: transparent;
  }

  /* El reloj, en mono como siempre. */
  .reloj {
    font-family: var(--mono);
    font-size: 14px;
    font-weight: 500;
    font-variant-numeric: tabular-nums;
    white-space: nowrap;
  }

  /* En una tableta parada, el aparato no cabe con el lugar escrito: queda la estrella. */
  @media (max-width: 860px) {
    .barra-c :global(.ap-lugar) {
      display: none;
    }
  }

  /* En un celular el dock (al centro) no deja lugar: se van el chip y el reloj, y la cajita del área queda en su ícono
     (CajaAreas). Lo que dice el chip ya lo dice «POR PREPARAR · N». */
  @media (max-width: 600px) {
    .barra-c :global(.chip),
    .reloj {
      display: none;
    }
  }

  /* Debajo de la barra, en el lugar de una vista (los mismos márgenes que Pedidos y Vender). */
  .cuerpo {
    position: absolute;
    left: var(--vista-izquierda);
    right: var(--vista-derecha);
    top: var(--vista-arriba);
    bottom: var(--vista-abajo);
    display: flex;
    flex-direction: column;
    container: cocina / inline-size;
  }

  .cuadrito,
  .cuadro-icono {
    width: 36px;
    height: 36px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 11px;
    background: var(--chip);
    color: var(--texto);
  }

  /* Sin áreas: al centro, como «Sin pedidos por confirmar». */
  .aviso {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 6px;
    padding: 40px 16px 60px;
    text-align: center;
  }

  .aviso .cuadrito {
    margin-bottom: 6px;
  }

  .aviso b {
    font-size: 14.5px;
    font-weight: 700;
  }

  .aviso > span:not(.cuadrito) {
    font-size: 12.5px;
    color: var(--suave);
    line-height: 1.45;
  }

  /* Elegir el área: una tarjeta de Crear anuncios al centro, con las áreas como renglones. */
  .elegir {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    padding-bottom: 40px;
  }

  .elegir-caja {
    width: 440px;
    max-width: 100%;
    padding: 20px;
    background: var(--solido);
    border: 1px solid var(--borde-tarjeta);
    border-radius: 14px;
    display: flex;
    flex-direction: column;
    gap: 16px;
    animation: abre 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275);
  }

  @keyframes abre {
    from {
      opacity: 0;
      transform: translateY(14px) scale(0.98);
    }
  }

  .encabezado {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .titulos {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .titulo {
    font-size: 14.5px;
    font-weight: 700;
  }

  .sub {
    font-size: 12.5px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .opciones {
    display: flex;
    flex-direction: column;
    margin: 0 -8px;
  }

  .opcion {
    width: 100%;
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 10px 10px;
    border: 0;
    border-radius: 12px;
    background: transparent;
    color: var(--texto);
    text-align: left;
    font: inherit;
    cursor: pointer;
    transition:
      background-color 150ms,
      transform 0.15s ease;
  }

  .opcion + .opcion {
    box-shadow: 0 -1px 0 var(--tabla-linea, var(--linea));
  }

  .opcion:hover {
    background: var(--chip);
  }

  .opcion:active {
    transform: scale(0.98);
  }

  .opcion .nombre {
    flex: 1;
    min-width: 0;
    font-size: 15px;
    font-weight: 700;
  }

  .opcion .cuenta {
    font-family: var(--mono);
    font-size: 11.5px;
    color: var(--tenue);
    white-space: nowrap;
  }

  .opcion :global(svg:last-child) {
    color: var(--suave);
  }

  @media (prefers-reduced-motion: reduce) {
    .elegir-caja {
      animation: none;
    }

    .opcion {
      transition: none;
    }

    .opcion:active {
      transform: none;
    }
  }
</style>
