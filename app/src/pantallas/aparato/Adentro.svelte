<!--
  Lo que ve quien entró con su PIN, según sus roles (parte 4a; maqueta Mesero y cocina): el mesero y
  la caja, las mesas del punto de venta; la cocina, su pantalla a todo lo ancho. Quien tiene más de
  una cambia con pestañas arriba (Toño, mesero y caja: Mesas y Caja). La caja es la de la parte
  4b (maqueta La caja). El aparato recuerda la última pestaña. Quien es de caja también tiene
  Pedidos (parte 6b; maqueta Pedidos por WhatsApp): su vigía vive aquí, encima de las pestañas, para
  que el tono suene en cualquiera. Con la adaptabilidad (encuesta 8), la pestaña del punto de venta
  dice «Mesas» donde hay mesas y «Vender» donde no. Desde ~900 px de ancho (tableta acostada o compu; «Lo que decidí yo» 7)
  el punto de venta va a lo ancho, a toda la pantalla, con sus pestañas en el dock de su barra de arriba. Pedidos también
  (pedidos-ancho.md, «Para la otra sesión»): su chip («Recibiendo pedidos hasta las 22:00») y «Pausar pedidos» van en esa
  barra, y Pedidos pinta el Tablero sin su cabeza (`franjaAfuera`). La Caja también (cobro-caja.md, 3e): pinta su propia
  barra con el mismo dock, su chip («Caja abierta desde las 08:00») y sus tres botones.

  Con el inventario (19 nov 2026; maqueta BBBNJST5w9qZfHWNdovGgb v3, encuestas 17 a 19): la cocina suma «Inventario»
  (lo que queda, con «Merma» y «Llegó»; su numerito, cuántos se acaban, viene de su vigía) y «Menú» (la vista chiquita de
  Mi menú con su ojito), y la caja suma «Menú». Las dos van siempre a lo ancho, como la Cocina. Con el recetario (19 nov
  2026; maqueta DFVTWEB3eZBEKctyxWjGjg v1, encuesta 6), la cocina y la caja suman «Recetario» (aparato/RecetarioAparato),
  también a lo ancho.

  Usa la sesión del aparato (lib/aparato.ts), nunca la del panel.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import Boton from '../../diseno/Boton.svelte';
  import CajaError from '../../diseno/CajaError.svelte';
  import Selector from '../../diseno/Selector.svelte';
  import { supabaseAparato, type Lista, type PersonaAparato } from '../../lib/aparato';
  import { ALGO_SALIO_PANEL, esDeRed, SIN_CONEXION } from '../../lib/errores';
  import { VigiaPedidos } from '../../lib/pedidos.svelte';
  import { leerZona } from '../../lib/pos';
  import { NOMBRE_ROL } from '../../lib/roles';
  import { VigiaInventario } from '../../lib/vigiaInventario.svelte';
  import Caja from '../caja/Caja.svelte';
  import Pedidos from '../caja/Pedidos.svelte';
  import { franjaDe } from '../caja/pedidos/franja';
  import Cocina from '../cocina/Cocina.svelte';
  import InventarioCocina from '../cocina/Inventario.svelte';
  import PuntoDeVenta from '../pos/PuntoDeVenta.svelte';
  import Barra from '../pos/ancho/Barra.svelte';
  import type { Anfitrion } from '../pos/ancho/barra';
  import '../pos/ancho/ancho.css';
  import Arriba from './Arriba.svelte';
  import MenuChico from './MenuChico.svelte';
  import RecetarioAparato from './RecetarioAparato.svelte';

  type Pestana = 'mesas' | 'caja' | 'pedidos' | 'cocina' | 'inventario' | 'menu' | 'recetario';

  let {
    lista,
    persona,
    alPestana,
  }: { lista: Lista; persona: PersonaAparato; alPestana: (p: Pestana) => void } = $props();

  const LLAVE_PESTANA = 'fragmentless-aparato-pestana';

  // Si el restaurante tiene mesas; si no se pudo saber, como si tuviera (la pestaña de siempre).
  let conMesas = $state(true);

  // La vigía de los pedidos, solo para quien es de caja; nace cuando se sabe el restaurante.
  let vigia = $state<VigiaPedidos | null>(null);
  // Los ingredientes en vivo, solo para la cocina (la caja no los lee).
  let vigiaInventario = $state<VigiaInventario | null>(null);

  const pestanas = $derived(
    [
      { valor: 'mesas' as const, texto: conMesas ? 'Mesas' : 'Vender', si: persona.roles.includes('mesero') || persona.roles.includes('caja') },
      { valor: 'caja' as const, texto: 'Caja', si: persona.roles.includes('caja') },
      // «Pedidos · 2», como «Por cobrar · 5»; en pausa, «Pedidos · Pausado».
      { valor: 'pedidos' as const, texto: vigia?.insignia ? `Pedidos · ${vigia.insignia}` : 'Pedidos', si: persona.roles.includes('caja') },
      { valor: 'cocina' as const, texto: 'Cocina', si: persona.roles.includes('cocina') },
      {
        valor: 'inventario' as const,
        texto: vigiaInventario?.insignia ? `Inventario · ${vigiaInventario.insignia}` : 'Inventario',
        si: persona.roles.includes('cocina'),
      },
      { valor: 'menu' as const, texto: 'Menú', si: persona.roles.includes('cocina') || persona.roles.includes('caja') },
      { valor: 'recetario' as const, texto: 'Recetario', si: persona.roles.includes('cocina') || persona.roles.includes('caja') },
    ].filter((p) => p.si),
  );
  let elegida = $state<Pestana | null>(leerPestana());
  const pestana = $derived<Pestana>(pestanas.find((p) => p.valor === elegida)?.valor ?? pestanas[0]?.valor ?? 'mesas');
  const linea = $derived(`${persona.nombre} · ${persona.roles.map((r) => NOMBRE_ROL[r] ?? r).join(' · ')}`);

  // A lo ancho: las pestañas en el dock, con su ícono; el número de Pedidos en su esquina.
  let anchoVentana = $state(0);
  const ancho = $derived(anchoVentana >= 900);
  const ICONO: Record<Pestana, string> = {
    mesas: 'cuenta',
    caja: 'r-billete',
    pedidos: 'r-bolsa',
    cocina: 'r-cocina',
    inventario: 'inventario',
    menu: 'cubiertos',
    recetario: 'libro',
  };
  const anfitrion = $derived<Anfitrion>({
    donde: 'aparato',
    restaurante: lista.restaurante,
    linea,
    pestanas: pestanas.map((p) => ({
      valor: p.valor,
      texto: p.valor === 'pedidos' ? 'Pedidos' : p.valor === 'inventario' ? 'Inventario' : p.texto,
      icono: p.valor === 'mesas' && conMesas ? 'r-mesas' : ICONO[p.valor],
      insignia:
        p.valor === 'pedidos' && /^\d+$/.test(String(vigia?.insignia ?? ''))
          ? String(vigia?.insignia)
          : p.valor === 'inventario'
            ? (vigiaInventario?.insignia ?? null)
            : null,
    })),
    pestana,
    alPestana: (v) => elegir(v as Pestana),
  });

  // El chip de Pedidos a lo ancho: lo de su franja (encuesta 4 de pedidos-ancho.md); mientras lee, «Cargando los pedidos…».
  let zona = $state('America/Mexico_City');
  const chipPedidos = $derived.by(() => {
    const d = vigia?.datos;
    if (!d) return vigia?.error ? { texto: 'No se pudo leer', vivo: false } : { texto: 'Cargando los pedidos…', vivo: true };
    const f = franjaDe(d, zona, false);
    return { texto: f.chip, vivo: f.tono === 'vivo', pausa: f.tono === 'pausa', hueco: f.tono === 'apagado' };
  });

  let restaurante = $state<{ estado: 'leyendo' } | { estado: 'listo'; id: string } | { estado: 'error'; mensaje: string }>({
    estado: 'leyendo',
  });

  function leerPestana(): Pestana | null {
    try {
      return localStorage.getItem(LLAVE_PESTANA) as Pestana | null;
    } catch (error) {
      console.error('[aparato] no se pudo leer la pestaña:', error);
      return null;
    }
  }

  function elegir(p: Pestana) {
    elegida = p;
    try {
      localStorage.setItem(LLAVE_PESTANA, p);
    } catch (error) {
      console.error('[aparato] no se pudo guardar la pestaña:', error);
    }
  }

  $effect(() => alPestana(pestana));

  // «Lista» le suena a quien confirmó un pedido; en Mesas ya lo hace el punto de venta.
  $effect(() => {
    if (vigia) vigia.oirListas = pestana !== 'mesas';
  });

  $effect(() => {
    if (restaurante.estado !== 'listo' || !persona.roles.includes('caja')) return;
    const v = new VigiaPedidos(supabaseAparato, restaurante.id, persona.id);
    vigia = v;
    const dejar = v.iniciar();
    return () => {
      dejar();
      vigia = null;
    };
  });

  $effect(() => {
    if (restaurante.estado !== 'listo' || !persona.roles.includes('cocina')) return;
    const v = new VigiaInventario(supabaseAparato, restaurante.id);
    vigiaInventario = v;
    const dejar = v.iniciar();
    return () => {
      dejar();
      vigiaInventario = null;
    };
  });

  // El restaurante de quien entró: lo dice su fila de miembros, que su sesión puede leer.
  async function leerRestaurante() {
    restaurante = { estado: 'leyendo' };
    const { data, error } = await supabaseAparato.from('miembros').select('restaurante_id').eq('id', persona.id).single();
    if (error) {
      console.error('[aparato] no se pudo leer el restaurante de quien entró:', error);
      restaurante = { estado: 'error', mensaje: esDeRed(error) ? SIN_CONEXION : ALGO_SALIO_PANEL };
      return;
    }
    const mesas = await supabaseAparato
      .from('mesas')
      .select('id', { count: 'exact', head: true })
      .eq('restaurante_id', data.restaurante_id)
      .is('archivado_at', null);
    if (mesas.error) console.error('[aparato] no se pudo saber si hay mesas:', mesas.error);
    else conMesas = (mesas.count ?? 0) > 0;
    restaurante = { estado: 'listo', id: data.restaurante_id };
    leerZona(supabaseAparato, data.restaurante_id)
      .then((z) => (zona = z))
      .catch((falla) => console.error('[aparato] no se pudo leer la zona de Pedidos; se usa la de México:', falla));
  }

  onMount(leerRestaurante);
</script>

<svelte:window bind:innerWidth={anchoVentana} />

{#snippet selector()}
  {#if pestanas.length > 1}
    <div class="pestanas">
      <Selector etiqueta="Pantalla" lleno vidrio alto={30} opciones={pestanas} elegida={pestana} alElegir={elegir} />
    </div>
  {/if}
{/snippet}

{#if restaurante.estado !== 'listo'}
  <div class="columna">
    <Arriba lugar={{ restaurante: lista.restaurante, aparato: lista.aparato }} />
    <div class="medio">
      {#if restaurante.estado === 'error'}
        <CajaError mensaje={restaurante.mensaje} />
        <button type="button" class="otra-vez" onclick={leerRestaurante}>Intentar de nuevo</button>
      {:else}
        <span class="tenue">Abriendo…</span>
      {/if}
    </div>
  </div>
{:else if pestana === 'cocina'}
  <!-- La Cocina siempre va a lo ancho, con la misma barra que Vender y Pedidos (planes/trabajo/rediseno/cocina.md). -->
  <div class="pantalla-ancha">
    <Cocina cliente={supabaseAparato} restauranteId={restaurante.id} {anfitrion} />
  </div>
{:else if pestana === 'inventario'}
  <!-- Inventario y Menú van siempre a lo ancho, como la Cocina. -->
  <div class="pantalla-ancha">
    {#if vigiaInventario}
      <InventarioCocina cliente={supabaseAparato} restauranteId={restaurante.id} vigia={vigiaInventario} {anfitrion} />
    {/if}
  </div>
{:else if pestana === 'menu'}
  <div class="pantalla-ancha">
    <MenuChico cliente={supabaseAparato} restauranteId={restaurante.id} {anfitrion} />
  </div>
{:else if pestana === 'recetario'}
  <div class="pantalla-ancha">
    <RecetarioAparato cliente={supabaseAparato} restauranteId={restaurante.id} {anfitrion} />
  </div>
{:else if pestana === 'pedidos' && ancho}
  <!-- Solo la barra va en .pos-ancho: sus clases (.rejilla, .tarjeta…) chocarían con las del Tablero de Pedidos. -->
  <div class="pantalla-ancha pedidos-ancho">
    <div class="pos-ancho solo-barra">
      <Barra {anfitrion} titulo="Pedidos" chip={chipPedidos}>
        <Boton
          etiqueta={vigia?.datos?.pausado ? 'Reanudar' : 'Pausar pedidos'}
          icono={vigia?.datos?.pausado ? 'reanudar' : 'detener'}
          cargando={vigia?.pausando ?? false}
          apagado={!vigia?.datos}
          onclick={() => vigia?.pausar()}
        />
      </Barra>
    </div>
    <div class="cuerpo-pedidos">
      {#if vigia}
        <Pedidos cliente={supabaseAparato} restauranteId={restaurante.id} restaurante={lista.restaurante} {vigia} {linea} franjaAfuera />
      {/if}
    </div>
  </div>
{:else if pestana === 'pedidos'}
  <div class="columna sin-margen">
    {#if vigia}
      <Pedidos cliente={supabaseAparato} restauranteId={restaurante.id} restaurante={lista.restaurante} {vigia} {linea} pestanas={selector} />
    {/if}
  </div>
{:else if pestana === 'caja' && ancho}
  <!-- La Caja pinta su propia barra, como el punto de venta: su chip y sus botones dependen de su turno. -->
  <div class="pantalla-ancha">
    <Caja cliente={supabaseAparato} restauranteId={restaurante.id} restaurante={lista.restaurante} {linea} ancho {anfitrion} />
  </div>
{:else if pestana === 'caja'}
  <div class="columna sin-margen">
    <Caja cliente={supabaseAparato} restauranteId={restaurante.id} restaurante={lista.restaurante} {linea} pestanas={selector} />
  </div>
{:else if ancho}
  <div class="pantalla-ancha">
    <PuntoDeVenta
      cliente={supabaseAparato}
      restauranteId={restaurante.id}
      restaurante={lista.restaurante}
      miembroId={persona.id}
      {linea}
      donde="aparato"
      conEfectivo={persona.roles.includes('mesero')}
      ancho
      {anfitrion}
    />
  </div>
{:else}
  <div class="columna sin-margen">
    <PuntoDeVenta
      cliente={supabaseAparato}
      restauranteId={restaurante.id}
      restaurante={lista.restaurante}
      miembroId={persona.id}
      {linea}
      donde={lista.compartido ? 'aparato' : 'celular'}
      conEfectivo={persona.roles.includes('mesero')}
      pestanas={selector}
    />
  </div>
{/if}

<style>
  /* El celular de la maqueta: 390 de ancho, al centro en una tableta, y lo de en medio se desliza
     entre lo de arriba y lo de abajo. */
  .columna {
    width: 100%;
    max-width: 390px;
    height: 100vh;
    height: 100dvh;
    margin: 0 auto;
    display: flex;
    flex-direction: column;
    padding: max(52px, env(safe-area-inset-top)) 16px max(30px, env(safe-area-inset-bottom));
  }

  /* El punto de venta lleva el margen adentro: así sus hojas y su velo tapan todo el celular,
     como en la maqueta. */
  .columna.sin-margen {
    padding: 0;
  }

  .columna > :global(.pos) {
    flex: 1;
    min-height: 0;
    padding: max(52px, env(safe-area-inset-top)) 16px max(30px, env(safe-area-inset-bottom));
  }

  /* A lo ancho, el punto de venta toma toda la pantalla (pos/ancho/ancho.css). */
  .pantalla-ancha {
    position: relative;
    width: 100%;
    height: 100vh;
    height: 100dvh;
  }

  /* Pedidos a lo ancho: la barra de 56 arriba y, debajo, el Tablero con los márgenes de Vender (pos/ancho/ancho.css). */
  .pedidos-ancho {
    background: var(--fondo);
    color: var(--texto);
  }

  .solo-barra {
    bottom: auto;
    height: 56px;
    z-index: 2;
    overflow: visible;
  }

  .cuerpo-pedidos {
    position: absolute;
    left: 0;
    right: 0;
    top: 56px;
    bottom: 0;
    padding: 20px 20px 20px 24px;
  }

  .pestanas {
    flex: none;
    margin-top: 12px;
  }

  .medio {
    flex: 1;
    display: flex;
    flex-direction: column;
    justify-content: center;
    gap: 14px;
  }

  .tenue {
    color: var(--tenue);
    font-size: 13px;
    text-align: center;
  }

  .otra-vez {
    height: 52px;
    border: 1px solid var(--linea);
    border-radius: 14px;
    background: transparent;
    color: var(--texto);
    font-size: 15px;
    font-weight: 700;
  }
</style>
