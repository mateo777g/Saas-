<!--
  El historial de un ingrediente, a la derecha de su ventana (maqueta BBBNJST5w9qZfHWNdovGgb v3, «Pastor»): cuánto queda
  y, del más nuevo al más viejo, cada cosa que lo subió o lo bajó, con cuándo y quién («Chente · cocina»). Lo que llegó,
  las mermas y los conteos traen «Deshacer»: nace un movimiento contrario y los dos se ven tachados. Se vuelve a leer
  cuando cambia lo que queda (una cuenta que se cierra, una merma desde la cocina).
-->
<script lang="ts">
  import './tabla.css';
  import CajaError from '../../../diseno/CajaError.svelte';
  import Esqueleto from '../../../diseno/Esqueleto.svelte';
  import { esDeRed, SIN_CONEXION } from '../../../lib/errores';
  import { cantidad, comoVa, deshacerMovimiento, leerHistorial, type Ingrediente, type Movimiento } from '../../../lib/inventario';
  import { supabase } from '../../../lib/supabase';

  let {
    restauranteId,
    ingrediente,
    zona,
    hoy,
    alCambiar,
  }: {
    restauranteId: string;
    ingrediente: Ingrediente;
    zona: string;
    hoy: string;
    alCambiar: () => void;
  } = $props();

  let movimientos = $state<Movimiento[] | null>(null);
  let error = $state<string | null>(null);
  let deshaciendo = $state<number | null>(null);

  async function leer() {
    try {
      movimientos = await leerHistorial(supabase, restauranteId, ingrediente, zona, hoy);
      error = null;
    } catch (falla) {
      console.error('[inventario] no se pudo leer el historial:', falla);
      error = esDeRed(falla) ? SIN_CONEXION : 'No se pudo leer su historial. Intenta de nuevo.';
    }
  }

  // Al abrir y cada vez que cambia lo que queda.
  $effect(() => {
    void ingrediente.existencia;
    void leer();
  });

  async function deshacer(m: Movimiento) {
    if (deshaciendo !== null) return;
    deshaciendo = m.id;
    try {
      await deshacerMovimiento(supabase, restauranteId, m.id, crypto.randomUUID());
      alCambiar();
      await leer();
    } catch (falla) {
      error = (falla as Error).message;
    } finally {
      deshaciendo = null;
    }
  }

  const va = $derived(comoVa(ingrediente));
</script>

<div class="historial">
  <div class="cabeza">
    <span class="etiqueta">HISTORIAL</span>
    <span class="queda">Queda <b class={va}>{cantidad(ingrediente.existencia, ingrediente.unidad)}</b></span>
  </div>
  {#if error}
    <div class="error"><CajaError mensaje={error} compacta /></div>
  {/if}
  <div class="lista inv-desliza">
    {#if movimientos === null}
      <span class="solo-lector">Cargando su historial…</span>
      {#each [150, 120, 170, 130] as ancho, i (i)}
        <div class="mov" aria-hidden="true">
          <span class="que"><Esqueleto ancho="{ancho}px" alto="11px" /><Esqueleto ancho="110px" alto="10px" /></span>
          <Esqueleto ancho="50px" alto="11px" />
          <span></span>
        </div>
      {/each}
    {:else if !movimientos.length}
      <p class="vacio">Todavía no tiene movimientos.</p>
    {:else}
      {#each movimientos as m (m.id)}
        <div class="mov" class:tachado={m.tachado}>
          <span class="que"><b>{m.titulo}</b><span>{m.cuando} · {m.quien}</span></span>
          <span class="cuanto" class:sube={m.cantidad > 0 && !m.tachado}>{cantidad(m.cantidad, ingrediente.unidad, true)}</span>
          {#if m.sePuedeDeshacer}
            <button type="button" class="deshacer" disabled={deshaciendo !== null} onclick={() => deshacer(m)}>
              {deshaciendo === m.id ? 'Deshaciendo…' : 'Deshacer'}
            </button>
          {:else}
            <span></span>
          {/if}
        </div>
      {/each}
    {/if}
  </div>
</div>

<style>
  .historial {
    min-width: 0;
    display: flex;
    flex-direction: column;
    border: 1px solid var(--borde-tarjeta);
    border-radius: 14px;
    background: var(--solido);
    overflow: hidden;
  }

  .cabeza {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 14px 16px 10px;
    border-bottom: 1px solid var(--linea);
  }

  .queda {
    font-size: 13px;
    font-weight: 500;
    color: var(--tenue);
  }

  .queda b {
    margin-left: 4px;
    font-family: var(--mono);
    font-size: 13px;
    font-weight: 600;
    color: var(--texto);
  }

  .queda b.amarillo {
    color: var(--amarillo-texto);
  }

  .queda b.rojo {
    color: var(--rojo);
  }

  .error {
    padding: 10px 16px 0;
  }

  .lista {
    max-height: 390px;
    overflow: auto;
  }

  .mov {
    display: grid;
    grid-template-columns: 1fr auto 86px;
    gap: 12px;
    align-items: center;
    min-height: 56px;
    padding: 0 16px;
    border-bottom: 1px solid var(--linea);
  }

  .mov:last-child {
    border-bottom: 0;
  }

  .que {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .que b {
    font-size: 13.5px;
    font-weight: 600;
    color: var(--texto);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .que span {
    font-size: 12px;
    font-weight: 500;
    color: var(--tenue);
  }

  .cuanto {
    font-family: var(--mono);
    font-size: 13px;
    font-weight: 600;
    text-align: right;
    white-space: nowrap;
    color: var(--texto);
  }

  .cuanto.sube {
    color: var(--verde);
  }

  .tachado b,
  .tachado .cuanto {
    text-decoration: line-through;
    color: var(--tenue);
  }

  .deshacer {
    justify-self: end;
    height: 30px;
    padding: 0 10px;
    border: 1px solid var(--borde-tarjeta);
    border-radius: 10px;
    background: transparent;
    color: var(--texto);
    font-size: 12px;
    font-weight: 600;
    white-space: nowrap;
    transition: background 0.15s;
  }

  .deshacer:hover:not(:disabled) {
    background: var(--chip);
  }

  .deshacer:disabled {
    opacity: 0.5;
  }

  .vacio {
    margin: 0;
    padding: 24px 16px;
    font-size: 12.5px;
    color: var(--tenue);
    text-align: center;
  }

  @media (prefers-reduced-motion: reduce) {
    .deshacer {
      transition: none;
    }
  }
</style>
