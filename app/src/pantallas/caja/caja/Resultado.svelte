<!--
  El corte ya cerrado, a lo ancho, en la tarjeta de la derecha (adaptabilidad 3c; encuesta 7 de cobro-caja.md): lo mismo
  que la columna de hoy (caja/Caja.svelte, «Corte de caja»): por método, lo esperado, lo contado y la diferencia
  («Cuadra» en verde, «Faltan» en rojo); quién cobró, las propinas y las entradas y salidas. Todos los números vienen de
  resumen_turno. «Listo» va en la barra de abajo.
-->
<script lang="ts">
  import Icono from '../../../diseno/Icono.svelte';
  import { NOMBRE_METODO, type ResumenTurno } from '../../../lib/caja';
  import { pesos } from '../../../lib/formato';

  let { r, hora }: { r: ResumenTurno; hora: (momento: string) => string } = $props();

  const pila = (nombre: string | null) => (nombre ?? '—').trim().split(/\s+/)[0];

  function diferencia(d: number): { texto: string; clase: string } {
    if (d === 0) return { texto: 'Cuadra', clase: 'cuadra' };
    if (d < 0) return { texto: `Faltan ${pesos(-d)}`, clase: 'falta' };
    return { texto: `Sobran ${pesos(d)}`, clase: '' };
  }
</script>

<div class="encabezado">
  <span class="cuadro-c"><Icono nombre="corte" tamano={18} /></span>
  <div class="titulos">
    <span class="titulo">Corte de caja</span>
    <span class="sub">Turno de {pila(r.abierto_por)} · {hora(r.abierto_at)} a {r.cerrado_at ? hora(r.cerrado_at) : '—'} · cerró {pila(r.cerrado_por)}</span>
  </div>
</div>

<div class="bloque-c">
  <span class="etiqueta-c">Lo contado contra lo esperado</span>
  <div class="gris">
    <div class="m cab"><span>Método</span><span>Esperado</span><span>Contado</span></div>
    {#each r.cortes ?? [] as k (k.metodo)}
      {@const d = diferencia(k.diferencia)}
      <div class="m">
        <span class="nom">{NOMBRE_METODO[k.metodo]}<small class="dif {d.clase}">{d.texto}</small></span>
        <b>{pesos(k.esperado)}</b>
        <b>{pesos(k.contado)}</b>
      </div>
    {/each}
  </div>
  <p class="pista">En efectivo, lo esperado es el fondo más lo cobrado y las entradas, menos las salidas. Las propinas cuentan.</p>
</div>

{#if r.por_persona?.length}
  <div class="bloque-c">
    <span class="etiqueta-c">Quién cobró</span>
    <div class="gris">
      {#each r.por_persona as q (q.miembro_id)}
        <div class="f">
          <span>
            {pila(q.nombre)}
            <small>{(['efectivo', 'tarjeta', 'transferencia'] as const).filter((m) => q[m] > 0).map((m) => `${NOMBRE_METODO[m]} ${pesos(q[m])}`).join(' · ')}</small>
          </span>
          <b>{pesos(q.total)}</b>
        </div>
      {/each}
    </div>
  </div>
{/if}

{#if r.propinas.length}
  <div class="bloque-c">
    <span class="etiqueta-c">Propinas</span>
    <div class="gris">
      {#each r.propinas as p (p.miembro_id)}
        <div class="f">
          <span>{pila(p.nombre)}<small>Pagado {pesos(p.pagado)}{p.falta > 0 ? ` · falta ${pesos(p.falta)}` : ' · al corriente'}</small></span>
          <b>{pesos(p.total)}</b>
        </div>
      {/each}
    </div>
  </div>
{/if}

{#if r.movimientos?.length}
  <div class="bloque-c">
    <span class="etiqueta-c">Entradas y salidas</span>
    <div class="gris">
      {#each r.movimientos as m, i (i)}
        <div class="f">
          <span>{m.motivo}<small>{m.tipo === 'retiro' ? 'Salida' : 'Entrada'} · {pila(m.registrado_por)} · {hora(m.created_at)}</small></span>
          <b>{m.tipo === 'retiro' ? '−' : '+'}{pesos(m.monto)}</b>
        </div>
      {/each}
    </div>
  </div>
{/if}

{#if r.cuentas_abiertas}
  <p class="pista">
    {r.cuentas_abiertas === 1 ? 'Quedó una cuenta abierta para el siguiente turno.' : `Quedaron ${r.cuentas_abiertas} cuentas abiertas para el siguiente turno.`}
  </p>
{/if}

<style>
  .gris {
    display: flex;
    flex-direction: column;
    gap: 10px;
    padding: 14px 16px;
    border-radius: 12px;
    background: var(--fondo);
  }

  .m {
    display: grid;
    grid-template-columns: minmax(0, 1fr) 92px 92px;
    gap: 10px;
    align-items: start;
    font-size: 13px;
  }

  .m.cab span {
    font-family: var(--mono);
    font-size: 10.5px;
    letter-spacing: 0.1em;
    text-transform: uppercase;
    color: var(--tenue);
  }

  .m.cab span:not(:first-child),
  .m b {
    text-align: right;
  }

  .m b,
  .f b {
    font-family: var(--mono);
    font-weight: 500;
    white-space: nowrap;
  }

  .nom,
  .f span {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
    font-weight: 600;
  }

  small {
    font-size: 11.5px;
    font-weight: 500;
    color: var(--suave);
  }

  .dif.cuadra {
    color: var(--verde);
  }

  .dif.falta {
    color: var(--rojo);
  }

  .f {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    gap: 12px;
    font-size: 13px;
  }

  .pista {
    margin: 0;
    font-size: 12px;
    line-height: 1.45;
    color: var(--tenue);
  }
</style>
