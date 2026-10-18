<!--
  El punto de venta, la caja o la cocina abiertos dentro del panel (maquetas Mesero y cocina y La
  caja; libreta 4, decidido el 17 de octubre de 2026): con la sesión del gerente, sin PIN ni
  aparato, y lo que agrega o cobra queda a su nombre. El punto de venta y la caja conservan el
  ancho del celular, al centro; la cocina usa todo el ancho.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import CajaError from '../../diseno/CajaError.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import Vidrio from '../../diseno/Vidrio.svelte';
  import { ALGO_SALIO_PANEL, esDeRed, SIN_CONEXION } from '../../lib/errores';
  import type { Sucursal } from '../../lib/gerente';
  import { supabase } from '../../lib/supabase';
  import Caja from '../caja/Caja.svelte';
  import Cocina from '../cocina/Cocina.svelte';
  import PuntoDeVenta from '../pos/PuntoDeVenta.svelte';

  let {
    que,
    sucursal,
    usuarioId,
    alVolver,
  }: { que: 'pos' | 'caja' | 'cocina'; sucursal: Sucursal; usuarioId: string; alVolver: () => void } = $props();

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

<Vidrio como="header" class="arriba-acceso" radio={18} sombra={false}>
  <button type="button" class="volver" onclick={alVolver}><Icono nombre="anterior" tamano={16} />Inicio</button>
  <h1 class="titulo">{que === 'pos' ? 'Punto de venta' : que === 'caja' ? 'Caja' : 'Cocina'}</h1>
  <span class="chip"><span class="punto"></span>Con tu sesión de gerente</span>
</Vidrio>

<Vidrio como="section" class="tarjeta-acceso" radio={26}>
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
  {:else if yo.estado === 'listo'}
    <Cocina cliente={supabase} restauranteId={sucursal.id} enPanel />
  {/if}
</Vidrio>

<style>
  :global(.arriba-acceso) {
    position: absolute;
    left: 276px;
    right: 16px;
    top: 16px;
    height: 60px;
    z-index: 3;
    padding: 0 12px 0 14px;
    display: flex;
    align-items: center;
    gap: 14px;
  }

  .titulo {
    margin: 0;
    font-size: 15px;
    font-weight: 700;
  }

  .volver {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 36px;
    padding: 0 12px 0 8px;
    border-radius: 12px;
    border: 1px solid var(--linea);
    background: transparent;
    color: var(--texto);
    font-size: 12.5px;
    font-weight: 600;
    flex: none;
  }

  .chip {
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
    flex: none;
    border-radius: 4px;
    background: var(--verde);
  }

  :global(.tarjeta-acceso) {
    position: absolute;
    left: 276px;
    right: 16px;
    top: 92px;
    bottom: 16px;
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
