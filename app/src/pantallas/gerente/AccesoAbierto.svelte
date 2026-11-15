<!--
  El punto de venta, la caja o la cocina abiertos dentro del panel (maquetas Mesero y cocina y La
  caja; libreta 4, decidido el 17 de octubre de 2026): con la sesión del gerente, sin PIN ni
  aparato, y lo que agrega o cobra queda a su nombre. El punto de venta y la caja conservan el
  ancho del celular, al centro; la cocina usa todo el ancho. Con la adaptabilidad (maqueta GBWEGCsQFcwKkWm7Qe9FPA v4), si
  la vista mide ~880 o más, el punto de venta va a lo ancho: su barra con «‹ Inicio», el dock Mesas · Para llevar y la
  cajita de sucursales. La caja también (3c): su barra con «‹ Inicio», su chip, sus tres botones y la cajita. La cocina
  (rediseño, 14 nov 2026) pinta siempre su propia barra, con el chip, el área y el reloj, y su Tablero, a cualquier ancho.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import BarraArriba from '../../diseno/BarraArriba.svelte';
  import CajaError from '../../diseno/CajaError.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import Tarjeta from '../../diseno/Tarjeta.svelte';
  import { ALGO_SALIO_PANEL, esDeRed, SIN_CONEXION } from '../../lib/errores';
  import type { Sucursal } from '../../lib/gerente';
  import CajaSucursales from './CajaSucursales.svelte';
  import { supabase } from '../../lib/supabase';
  import Caja from '../caja/Caja.svelte';
  import Cocina from '../cocina/Cocina.svelte';
  import PuntoDeVenta from '../pos/PuntoDeVenta.svelte';

  let {
    que,
    sucursal,
    usuarioId,
    alVolver,
    sucursales = [],
    alElegir,
  }: {
    que: 'pos' | 'caja' | 'cocina';
    sucursal: Sucursal;
    usuarioId: string;
    alVolver: () => void;
    sucursales?: Sucursal[]; // para la cajita de sucursales de la barra a lo ancho
    alElegir?: (s: Sucursal) => void;
  } = $props();

  let anchoVista = $state(0);
  const ancho = $derived(anchoVista >= 880);

  // Su fila de miembros en esta sucursal: a su nombre queda lo que agrega. Arriba sale su nombre
  // de pila de Empleados, el mismo que ve su equipo en lo que agrega (no su apodo de Perfil, que
  // el equipo no puede leer; decidido el 17 de octubre de 2026).
  let yo = $state<
    { estado: 'leyendo' } | { estado: 'listo'; id: number; nombre: string } | { estado: 'error'; mensaje: string }
  >({
    estado: 'leyendo',
  });

  async function leer() {
    yo = { estado: 'leyendo' };
    const { data, error } = await supabase
      .from('miembros')
      .select('id, nombre')
      .eq('restaurante_id', sucursal.id)
      .eq('usuario_id', usuarioId)
      .single();
    if (error) {
      console.error('[gerente] no se pudo leer su fila de miembros:', error);
      yo = { estado: 'error', mensaje: esDeRed(error) ? SIN_CONEXION : ALGO_SALIO_PANEL };
      return;
    }
    yo = { estado: 'listo', id: data.id, nombre: data.nombre.trim().split(/\s+/)[0] };
  }

  onMount(leer);
</script>

{#snippet cajita()}
  {#if alElegir && sucursales.length}<CajaSucursales {sucursales} actual={sucursal} {alElegir} />{/if}
{/snippet}

<div class="medida" bind:clientWidth={anchoVista}></div>

{#if que === 'cocina'}
  <!-- La Cocina, siempre con la estructura de Pedidos a lo ancho y su propia barra (planes/trabajo/rediseno/cocina.md).
       No necesita la fila de miembros: marcar «Lista» no deja nombre. -->
  <Cocina cliente={supabase} restauranteId={sucursal.id} anfitrion={{ donde: 'panel', alInicio: alVolver, sucursal: cajita }} />
{:else if ancho && que === 'pos' && yo.estado === 'listo'}
  <PuntoDeVenta
    cliente={supabase}
    restauranteId={sucursal.id}
    restaurante={sucursal.nombre}
    miembroId={yo.id}
    linea="{yo.nombre} · Gerente"
    donde="navegador"
    ancho
    anfitrion={{ donde: 'panel', alInicio: alVolver, sucursal: cajita }}
  />
{:else if ancho && que === 'caja' && yo.estado === 'listo'}
  <Caja
    cliente={supabase}
    restauranteId={sucursal.id}
    restaurante={sucursal.nombre}
    enPanel
    ancho
    anfitrion={{ donde: 'panel', alInicio: alVolver, sucursal: cajita }}
  />
{:else}
<BarraArriba
  titulo={que === 'pos' ? 'Punto de venta' : 'Caja'}
  estado={{ texto: 'Con tu sesión de gerente', vivo: true }}
>
  {#snippet antes()}
    <button type="button" class="volver" onclick={alVolver}><Icono nombre="anterior" tamano={16} />Inicio</button>
  {/snippet}
</BarraArriba>

<Tarjeta como="section" class="tarjeta-acceso">
  {#if yo.estado === 'error'}
    <div class="medio">
      <CajaError mensaje={yo.mensaje} />
      <button type="button" class="volver" onclick={leer}>Intentar de nuevo</button>
    </div>
  {:else if yo.estado === 'listo' && que === 'pos'}
    <div class="panel-cel">
      <PuntoDeVenta
        cliente={supabase}
        restauranteId={sucursal.id}
        restaurante={sucursal.nombre}
        miembroId={yo.id}
        linea="{yo.nombre} · Gerente"
        donde="navegador"
      />
    </div>
  {:else if yo.estado === 'listo' && que === 'caja'}
    <div class="panel-cel">
      <Caja cliente={supabase} restauranteId={sucursal.id} restaurante={sucursal.nombre} enPanel />
    </div>
  {/if}
</Tarjeta>
{/if}

<style>
  /* Mide el ancho de la vista, sin tapar nada. */
  .medida {
    position: absolute;
    left: 0;
    right: 0;
    top: 0;
    height: 0;
    pointer-events: none;
  }

  .volver {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 34px;
    padding: 0 12px 0 8px;
    border-radius: 9px;
    border: 1px solid var(--linea);
    background: transparent;
    color: var(--texto);
    font-size: 12.5px;
    font-weight: 600;
    flex: none;
  }

  :global(.tarjeta-acceso) {
    position: absolute;
    left: var(--vista-izquierda);
    right: var(--vista-derecha);
    top: var(--vista-arriba);
    bottom: var(--vista-abajo);
    overflow: hidden;
  }

  .panel-cel {
    position: absolute;
    top: 16px;
    bottom: 16px;
    left: 50%;
    width: 390px;
    max-width: calc(100% - 32px);
    transform: translateX(-50%);
    border-radius: 30px;
    border: 1px solid var(--linea);
    background: var(--suelo);
    overflow: hidden;
    display: flex;
    flex-direction: column;
  }

  .panel-cel > :global(.pos) {
    flex: 1;
    min-height: 0;
    padding: 18px 16px 30px;
  }

  .medio {
    position: absolute;
    inset: 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 14px;
    padding: 24px;
  }
</style>
