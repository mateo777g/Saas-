<!--
  Lo que ve quien entró con su PIN, según sus roles (parte 4a; maqueta Mesero y cocina): el mesero y
  la caja, las mesas del punto de venta; la cocina, su pantalla a todo lo ancho. Quien tiene más de
  una cambia con pestañas arriba (Toño, mesero y caja: Mesas y Caja). La caja es la de la parte
  4b (maqueta La caja). El aparato recuerda la última pestaña.

  Usa la sesión del aparato (lib/aparato.ts), nunca la del panel.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import CajaError from '../../diseno/CajaError.svelte';
  import Selector from '../../diseno/Selector.svelte';
  import { supabaseAparato, type Lista, type PersonaAparato } from '../../lib/aparato';
  import { ALGO_SALIO_PANEL, esDeRed, SIN_CONEXION } from '../../lib/errores';
  import { NOMBRE_ROL } from '../../lib/roles';
  import Caja from '../caja/Caja.svelte';
  import Cocina from '../cocina/Cocina.svelte';
  import PuntoDeVenta from '../pos/PuntoDeVenta.svelte';
  import Arriba from './Arriba.svelte';

  type Pestana = 'mesas' | 'caja' | 'cocina';

  let {
    lista,
    persona,
    alPestana,
  }: { lista: Lista; persona: PersonaAparato; alPestana: (p: Pestana) => void } = $props();

  const LLAVE_PESTANA = 'fragmentless-aparato-pestana';

  const pestanas = $derived(
    [
      { valor: 'mesas' as const, texto: 'Mesas', si: persona.roles.includes('mesero') || persona.roles.includes('caja') },
      { valor: 'caja' as const, texto: 'Caja', si: persona.roles.includes('caja') },
      { valor: 'cocina' as const, texto: 'Cocina', si: persona.roles.includes('cocina') },
    ].filter((p) => p.si),
  );
  let elegida = $state<Pestana | null>(leerPestana());
  const pestana = $derived<Pestana>(pestanas.find((p) => p.valor === elegida)?.valor ?? pestanas[0]?.valor ?? 'mesas');
  const linea = $derived(`${persona.nombre} · ${persona.roles.map((r) => NOMBRE_ROL[r] ?? r).join(' · ')}`);

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

  // El restaurante de quien entró: lo dice su fila de miembros, que su sesión puede leer.
  async function leerRestaurante() {
    restaurante = { estado: 'leyendo' };
    const { data, error } = await supabaseAparato.from('miembros').select('restaurante_id').eq('id', persona.id).single();
    if (error) {
      console.error('[aparato] no se pudo leer el restaurante de quien entró:', error);
      restaurante = { estado: 'error', mensaje: esDeRed(error) ? SIN_CONEXION : ALGO_SALIO_PANEL };
      return;
    }
    restaurante = { estado: 'listo', id: data.restaurante_id };
  }

  onMount(leerRestaurante);
</script>

{#snippet selector()}
  {#if pestanas.length > 1}
    <div class="pestanas" class:en-cocina={pestana === 'cocina'}>
      <Selector etiqueta="Pantalla" lleno alto={30} opciones={pestanas} elegida={pestana} alElegir={elegir} />
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
  <div class="cocina-aparato">
    <Cocina cliente={supabaseAparato} restauranteId={restaurante.id} aparato={lista.aparato} pestanas={pestanas.length > 1 ? selector : undefined} />
  </div>
{:else if pestana === 'caja'}
  <div class="columna sin-margen">
    <Caja cliente={supabaseAparato} restauranteId={restaurante.id} restaurante={lista.restaurante} {linea} pestanas={selector} />
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

  .cocina-aparato {
    width: 100%;
    height: 100vh;
    height: 100dvh;
  }

  .pestanas {
    flex: none;
    margin-top: 12px;
  }

  .pestanas.en-cocina {
    margin-top: 0;
    width: 220px;
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
