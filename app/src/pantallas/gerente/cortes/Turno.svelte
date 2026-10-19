<!--
  Un turno en Cortes y reportes (maqueta 7J6LvYWiktRnGxNugbuaoe). Cerrado: lo contado contra lo
  esperado de cada método, quién cobró, las propinas, las entradas y salidas y los pagos cancelados,
  como el corte de la caja. Abierto: desde cuándo, quién abrió, el fondo, las entradas y salidas y
  los pagos cancelados; lo esperado sale al cerrar, para nadie (libreta 5). Todos los montos y
  diferencias vienen de Postgres; aquí no se suma nada.
-->
<script lang="ts">
  import CajaError from '../../../diseno/CajaError.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import { NOMBRE_METODO, type Metodo } from '../../../lib/caja';
  import { enZona, pesos, plural } from '../../../lib/formato';
  import type { TurnoDelDia } from '../../../lib/reportes';
  import { quienLoHizo } from './quien';

  let { turno: t, zona }: { turno: TurnoDelDia; zona: string } = $props();

  const hora = (momento: string) => enZona(momento, zona).hora.replace(/^0(\d)/, '$1');

  const METODOS: Metodo[] = ['efectivo', 'tarjeta', 'transferencia'];

  function diferencia(d: number): { texto: string; clase: string } {
    if (d === 0) return { texto: 'Cuadra', clase: 'cuadra' };
    return d < 0 ? { texto: `Faltan ${pesos(-d)}`, clase: 'falta' } : { texto: `Sobran ${pesos(d)}`, clase: '' };
  }

  // El sello del turno: si todo cuadra, «Cuadra»; si solo un método no, lo que dice ese método;
  // si son varios, cuántos. No se suman efectivo y tarjeta entre sí.
  const sello = $derived.by(() => {
    const no = (t.cortes ?? []).filter((k) => k.diferencia !== 0);
    if (!no.length) return { texto: 'Cuadra', clase: 'cuadra' };
    if (no.length === 1) return diferencia(no[0].diferencia);
    return { texto: `No cuadran ${no.length} métodos`, clase: 'falta' };
  });
</script>

{#snippet movimientos()}
  <div class="bloque">
    <span class="etiqueta">ENTRADAS Y SALIDAS</span>
    <div class="lista">
      {#each t.movimientos as m, i (i)}
        <div class="f">
          <span><b>{m.motivo}</b><small>{m.tipo === 'retiro' ? 'Salida' : 'Entrada'} · {m.registrado_por} · {hora(m.created_at)}</small></span>
          <span class="n">{m.tipo === 'retiro' ? '−' : '+'}{pesos(m.monto)}</span>
        </div>
      {:else}
        <p class="vacia">{t.estado === 'abierto' ? 'Ninguna todavía.' : 'Ninguna.'}</p>
      {/each}
    </div>
  </div>
{/snippet}

{#snippet cancelados()}
  <div class="bloque">
    <span class="etiqueta">PAGOS CANCELADOS</span>
    <div class="lista">
      {#each t.pagos_cancelados as p (p.pago_id)}
        <div class="f">
          <span>
            <b>{p.folio ? `Folio ${p.folio} · ` : ''}{p.cuenta}</b>
            <small>
              {NOMBRE_METODO[p.metodo]}{p.propina > 0 ? ` con ${pesos(p.propina)} de propina` : ''} · «{p.motivo}» ·
              {quienLoHizo(p.pidio_id, p.pidio, p.autorizo_id, p.autorizo)} · {hora(p.cancelado_at)}
            </small>
          </span>
          <span class="n tachado">{pesos(p.monto)}</span>
        </div>
      {:else}
        <p class="vacia">Ninguno.</p>
      {/each}
    </div>
  </div>
{/snippet}

<div class="turno">
  {#if t.estado === 'abierto'}
    <div class="cabeza">
      <span class="cuadro-icono"><Icono nombre="billete" tamano={18} /></span>
      <div class="t">
        <b>Caja abierta desde las {hora(t.abierto_at)}</b>
        <span>Abrió {t.abierto_por} · Fondo {pesos(t.fondo_inicial)}</span>
      </div>
      <span class="sello"><span class="punto"></span>Abierta</span>
    </div>
    <CajaError
      tipo="info"
      mensaje="Lo esperado, lo contado, quién cobró y las propinas salen cuando se cierre la caja. Mientras está abierta nadie los ve, tampoco tú."
    />
    <div class="dos">
      {@render movimientos()}
      {@render cancelados()}
    </div>
    <p class="pista">Hay {plural(t.cuentas_abiertas, 'cuenta abierta', 'cuentas abiertas')} ahora.</p>
  {:else}
    <div class="cabeza">
      <span class="cuadro-icono"><Icono nombre="corte" tamano={18} /></span>
      <div class="t">
        <b>Turno de {hora(t.abierto_at)} a {t.cerrado_at ? hora(t.cerrado_at) : '—'}</b>
        <span>
          {t.abierto_por === t.cerrado_por ? `Abrió y cerró ${t.abierto_por}` : `Abrió ${t.abierto_por} · cerró ${t.cerrado_por}`}
          · Fondo {pesos(t.fondo_inicial)}
        </span>
      </div>
      <span class="sello {sello.clase}">
        {#if sello.clase === 'cuadra'}<Icono nombre="check" tamano={14} />{/if}{sello.texto}
      </span>
    </div>

    <div class="bloque">
      <span class="etiqueta">LO CONTADO CONTRA LO ESPERADO</span>
      <div class="tabla-corte">
        <div class="f cab"><span>Método</span><span class="n">Esperado</span><span class="n">Contado</span><span class="n">Diferencia</span></div>
        {#each t.cortes ?? [] as k (k.metodo)}
          {@const d = diferencia(k.diferencia)}
          <div class="f">
            <span>{NOMBRE_METODO[k.metodo]}</span>
            <span class="n">{pesos(k.esperado)}</span>
            <span class="n">{pesos(k.contado)}</span>
            <span class="n {d.clase}">{d.texto}</span>
          </div>
        {/each}
      </div>
    </div>

    <div class="dos">
      <div class="bloque">
        <span class="etiqueta">QUIÉN COBRÓ</span>
        <div class="lista">
          {#each t.por_persona ?? [] as q (q.miembro_id)}
            <div class="f">
              <span>
                <b>{q.nombre}</b>
                <small>{METODOS.filter((m) => q[m] > 0).map((m) => `${NOMBRE_METODO[m]} ${pesos(q[m])}`).join(' · ')}</small>
              </span>
              <span class="n">{pesos(q.total)}</span>
            </div>
          {:else}
            <p class="vacia">Nadie cobró en este turno.</p>
          {/each}
        </div>
      </div>
      <div class="bloque">
        <span class="etiqueta">PROPINAS</span>
        <div class="lista">
          {#each t.propinas as p (p.miembro_id)}
            <div class="f">
              <span><b>{p.nombre}</b><small>Pagado {pesos(p.pagado)}{p.falta > 0 ? ` · faltó ${pesos(p.falta)}` : ' · al corriente'}</small></span>
              <span class="n">{pesos(p.total)}</span>
            </div>
          {:else}
            <p class="vacia">Sin propinas.</p>
          {/each}
        </div>
      </div>
    </div>

    <div class="dos">
      {@render movimientos()}
      {@render cancelados()}
    </div>
  {/if}
</div>

<style>
  .turno {
    flex: none;
    padding: 16px;
    border-radius: 18px;
    border: 1px solid var(--linea);
    background: var(--solido);
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  .cabeza {
    display: flex;
    align-items: center;
    gap: 12px;
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

  .cabeza .t {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .cabeza b {
    font-size: 15px;
    font-weight: 800;
    letter-spacing: -0.2px;
  }

  .cabeza .t span {
    font-size: 12px;
    color: var(--tenue);
  }

  .sello {
    height: 28px;
    flex: none;
    display: inline-flex;
    align-items: center;
    gap: 7px;
    padding: 0 12px;
    border-radius: 14px;
    background: var(--chip);
    font-size: 12px;
    font-weight: 700;
    white-space: nowrap;
  }

  .sello.cuadra,
  .n.cuadra {
    color: var(--verde);
  }

  .sello.falta,
  .n.falta {
    color: var(--rojo);
  }

  .punto {
    width: 7px;
    height: 7px;
    border-radius: 4px;
    background: var(--verde);
  }

  .bloque {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .bloque > .etiqueta {
    display: block;
    min-height: 18px;
    padding: 0 2px;
  }

  .dos {
    display: grid;
    grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
    gap: 12px;
    align-items: start;
  }

  .tabla-corte {
    display: flex;
    flex-direction: column;
    border: 1px solid var(--linea);
    border-radius: 14px;
    overflow: hidden;
  }

  .tabla-corte .f {
    display: grid;
    grid-template-columns: minmax(0, 1.2fr) repeat(3, minmax(0, 1fr));
    gap: 8px;
    padding: 10px 12px;
    border-top: 1px solid var(--linea);
    font-size: 12.5px;
    align-items: baseline;
  }

  .tabla-corte .f:first-child {
    border-top: 0;
  }

  .tabla-corte .f.cab {
    font-family: var(--mono);
    font-size: 10px;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    color: var(--tenue);
  }

  .n {
    font-family: var(--mono);
    font-variant-numeric: tabular-nums;
    text-align: right;
    white-space: nowrap;
  }

  .tabla-corte .n.cuadra,
  .tabla-corte .n.falta {
    font-weight: 600;
  }

  .lista {
    display: flex;
    flex-direction: column;
    border: 1px solid var(--linea);
    border-radius: 14px;
  }

  .lista .f {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 12px;
    padding: 10px 12px;
    border-top: 1px solid var(--linea);
    font-size: 12.5px;
  }

  .lista .f:first-child {
    border-top: 0;
  }

  .lista .f > span:first-child {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .lista b {
    font-weight: 700;
  }

  .lista small {
    font-size: 11px;
    line-height: 1.45;
    color: var(--tenue);
  }

  .tachado {
    text-decoration: line-through;
    text-decoration-color: var(--tenue);
  }

  .vacia {
    margin: 0;
    padding: 12px;
    font-size: 12px;
    color: var(--tenue);
  }

  .pista {
    margin: 0;
    font-size: 12px;
    line-height: 1.45;
    color: var(--tenue);
  }
</style>
