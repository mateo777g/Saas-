<!--
  Una cuenta cobrada que se toca en la lista de la Caja a lo ancho (adaptabilidad 3c; lo que en la columna de hoy es la
  hoja de su folio): la palomita ya dibujada, «#21 cerrada», «Folio 1043 · Efectivo · 13:50» y su ticket (lo que llevaba
  y cómo pagó), y debajo cada pago con quién lo anotó; uno del turno abierto se cancela con «Cancelar» en rojo de
  contorno (parte 4c: la cuenta se reabre con su folio). Lee lo que llevaba y sus pagos al abrirse; mientras, el ticket en
  esqueleto. Si no se pudo leer, lo dice.
-->
<script lang="ts">
  import type { SupabaseClient } from '@supabase/supabase-js';
  import { onMount } from 'svelte';
  import Boton from '../../../diseno/Boton.svelte';
  import CajaError from '../../../diseno/CajaError.svelte';
  import { leerLineas, leerPagos, NOMBRE_METODO, type Cobrada as CobradaDato, type LineaTicket, type Pago } from '../../../lib/caja';
  import { ALGO_SALIO_PANEL, esDeRed, SIN_CONEXION } from '../../../lib/errores';
  import { enZona, pesos } from '../../../lib/formato';
  import Cobrada from '../../pos/cobro/Cobrada.svelte';

  let {
    cliente,
    restauranteId,
    cobrada,
    turnoId,
    nombres,
    zona,
    alCancelar,
  }: {
    cliente: SupabaseClient;
    restauranteId: string;
    cobrada: CobradaDato;
    turnoId: number | null;
    nombres: Map<number, string>;
    zona: string;
    alCancelar: (p: Pago) => void;
  } = $props();

  let datos = $state<{ lineas: LineaTicket[]; pagos: Pago[] } | null>(null);
  let error = $state<string | null>(null);

  const hora = (momento: string) => enZona(momento, zona).hora;
  const quien = (p: Pago) => (p.cobrado_por === null ? 'En línea' : (nombres.get(p.cobrado_por) ?? '—'));
  const seCancela = (p: Pago) => !p.cancelado_at && p.cobrado_por !== null && p.turno_id !== null && p.turno_id === turnoId;
  const vivos = $derived((datos?.pagos ?? []).filter((p) => !p.cancelado_at));

  async function leer() {
    error = null;
    try {
      const [lineas, pagos] = await Promise.all([
        leerLineas(cliente, restauranteId, cobrada.id),
        leerPagos(cliente, restauranteId, [cobrada.id]),
      ]);
      datos = { lineas, pagos };
    } catch (falla) {
      console.error('[caja] no se pudo leer la cuenta cobrada:', falla);
      error = esDeRed(falla) ? SIN_CONEXION : ALGO_SALIO_PANEL;
    }
  }

  onMount(leer);
</script>

<Cobrada
  titulo="{cobrada.titulo.split(' · ')[0]} cerrada"
  folio={cobrada.folio}
  cuando={hora(cobrada.cerrada_at)}
  lineas={datos?.lineas ?? []}
  subtotal={cobrada.subtotal}
  descuento={cobrada.descuento > 0 ? { texto: '', monto: cobrada.descuento } : null}
  total={cobrada.total}
  pagos={datos ? vivos.map((p) => ({ metodo: p.metodo, monto: p.monto, propina: p.propina, recibido: p.recibido, cambio: p.cambio ?? 0 })) : null}
  metodos={cobrada.metodos}
  animar={false}
  cargando={!datos && !error}
>
  {#if error}
    <CajaError mensaje={error} />
    <div class="otra-vez"><Boton etiqueta="Intentar de nuevo" icono="actualizar" onclick={leer} /></div>
  {:else if datos?.pagos.length}
    <div class="bloque-c">
      <span class="etiqueta-c">Pagos</span>
      <div class="pagos">
        {#each datos.pagos as p (p.id)}
          <div class="f" class:con-boton={seCancela(p)} class:cancelado={!!p.cancelado_at}>
            <span>
              {NOMBRE_METODO[p.metodo]} · {p.cancelado_at ? `cancelado · «${p.cancelado_motivo}»` : `${quien(p)} · ${hora(p.created_at)}`}{p.propina && !p.cancelado_at ? ` · propina ${pesos(p.propina)}` : ''}
            </span>
            <b>{pesos(p.monto)}</b>
            {#if seCancela(p)}<Boton etiqueta="Cancelar" tono="peligro" tamano="chico" onclick={() => alCancelar(p)} />{/if}
          </div>
        {/each}
      </div>
      {#if datos.pagos.some(seCancela)}
        <p class="pista">Si cancelas un pago, la cuenta se reabre con el folio {cobrada.folio} y sale en Por cobrar para anotar el correcto.</p>
      {/if}
    </div>
  {/if}
</Cobrada>

<style>
  .otra-vez {
    display: flex;
    justify-content: center;
  }

  .pagos {
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 14px 16px;
    border-radius: 12px;
    background: var(--fondo);
  }

  .f {
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    align-items: center;
    gap: 12px;
    min-height: 20px;
    font-size: 13px;
  }

  .f.con-boton {
    grid-template-columns: minmax(0, 1fr) auto auto;
  }

  .f span {
    color: var(--suave);
    font-weight: 600;
    line-height: 1.4;
  }

  .f b {
    font-family: var(--mono);
    font-weight: 500;
    white-space: nowrap;
  }

  .f.cancelado span,
  .f.cancelado b {
    color: var(--tenue);
    text-decoration: line-through;
  }

  .pista {
    margin: 0;
    font-size: 12px;
    line-height: 1.45;
    color: var(--tenue);
  }
</style>
