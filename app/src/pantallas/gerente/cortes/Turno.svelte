<!--
  Un turno en la tarjeta de la derecha de Cortes y reportes (14 nov 2026), con la forma del corte ya cerrado de la Caja a
  lo ancho (caja/caja/Resultado.svelte): la cabeza con su cuadrito, el sello en su caja de color (verde si cuadra, rojo si
  falta, como la caja del cambio del cobro) y cada bloque en su gris. Cerrado: lo contado contra lo esperado de cada
  método, quién cobró, las propinas, las entradas y salidas y los pagos cancelados. Abierto: desde cuándo, quién abrió, el
  fondo, las entradas y salidas y los pagos cancelados; lo esperado sale al cerrar, para nadie (libreta 5). Todos los
  montos y diferencias vienen de Postgres; aquí no se suma nada.
-->
<script lang="ts">
  import CajaError from '../../../diseno/CajaError.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import { NOMBRE_METODO, type Metodo } from '../../../lib/caja';
  import { enZona, pesos, plural } from '../../../lib/formato';
  import type { TurnoDelDia } from '../../../lib/reportes';
  import { diferencia, type Sello } from './filas';
  import { quienLoHizo } from './quien';

  let { turno: t, zona, sello }: { turno: TurnoDelDia; zona: string; sello: Sello } = $props();

  const hora = (momento: string) => enZona(momento, zona).hora;
  const METODOS: Metodo[] = ['efectivo', 'tarjeta', 'transferencia'];
</script>

{#snippet bloque(titulo: string)}
  <span class="etiqueta-c">{titulo}</span>
{/snippet}

{#snippet movimientos()}
  <div class="bloque-c">
    {@render bloque('Entradas y salidas')}
    <div class="gris">
      {#each t.movimientos as m, i (i)}
        <div class="f">
          <span>{m.motivo}<small>{m.tipo === 'retiro' ? 'Salida' : 'Entrada'} · {m.registrado_por} · {hora(m.created_at)}</small></span>
          <b>{m.tipo === 'retiro' ? '−' : '+'}{pesos(m.monto)}</b>
        </div>
      {:else}
        <p class="vacia">{t.estado === 'abierto' ? 'Ninguna todavía.' : 'Ninguna.'}</p>
      {/each}
    </div>
  </div>
{/snippet}

{#snippet cancelados()}
  <div class="bloque-c">
    {@render bloque('Pagos cancelados')}
    <div class="gris">
      {#each t.pagos_cancelados as p (p.pago_id)}
        <div class="f">
          <span>
            {p.folio ? `Folio ${p.folio} · ` : ''}{p.cuenta}
            <small>
              {NOMBRE_METODO[p.metodo]}{p.propina > 0 ? ` con ${pesos(p.propina)} de propina` : ''} · «{p.motivo}» ·
              {quienLoHizo(p.pidio_id, p.pidio, p.autorizo_id, p.autorizo)} · {hora(p.cancelado_at)}
            </small>
          </span>
          <b class="tachado">{pesos(p.monto)}</b>
        </div>
      {:else}
        <p class="vacia">Ninguno.</p>
      {/each}
    </div>
  </div>
{/snippet}

{#if t.estado === 'abierto'}
  <div class="encabezado">
    <span class="cuadro-c"><Icono nombre="billete" tamano={18} /></span>
    <div class="titulos">
      <span class="titulo">Caja abierta desde las {hora(t.abierto_at)}</span>
      <span class="sub">Abrió {t.abierto_por} · Fondo {pesos(t.fondo_inicial)}</span>
    </div>
  </div>
  <CajaError
    tipo="info"
    mensaje="Lo esperado, lo contado, quién cobró y las propinas salen cuando se cierre la caja. Mientras está abierta nadie los ve, tampoco tú."
  />
  {@render movimientos()}
  {@render cancelados()}
  <p class="pista">Hay {plural(t.cuentas_abiertas, 'cuenta abierta', 'cuentas abiertas')} ahora.</p>
{:else}
  <div class="encabezado">
    <span class="cuadro-c"><Icono nombre="corte" tamano={18} /></span>
    <div class="titulos">
      <span class="titulo">Turno de {hora(t.abierto_at)} a {t.cerrado_at ? hora(t.cerrado_at) : '—'}</span>
      <span class="sub">
        {t.abierto_por === t.cerrado_por ? `Abrió y cerró ${t.abierto_por}` : `Abrió ${t.abierto_por} · cerró ${t.cerrado_por}`}
        · Fondo {pesos(t.fondo_inicial)}
      </span>
    </div>
  </div>

  <div class="veredicto {sello.clase}" role="status">
    {#if sello.clase === 'cuadra'}<Icono nombre="check" tamano={16} />{:else}<Icono nombre="alerta" tamano={16} />{/if}
    <span>{sello.texto}</span>
  </div>

  <div class="bloque-c">
    {@render bloque('Lo contado contra lo esperado')}
    <div class="gris">
      <div class="m cab"><span>Método</span><span>Esperado</span><span>Contado</span></div>
      {#each t.cortes ?? [] as k (k.metodo)}
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

  <div class="bloque-c">
    {@render bloque('Quién cobró')}
    <div class="gris">
      {#each t.por_persona ?? [] as q (q.miembro_id)}
        <div class="f">
          <span>{q.nombre}<small>{METODOS.filter((m) => q[m] > 0).map((m) => `${NOMBRE_METODO[m]} ${pesos(q[m])}`).join(' · ')}</small></span>
          <b>{pesos(q.total)}</b>
        </div>
      {:else}
        <p class="vacia">Nadie cobró en este turno.</p>
      {/each}
    </div>
  </div>

  <div class="bloque-c">
    {@render bloque('Propinas')}
    <div class="gris">
      {#each t.propinas as p (p.miembro_id)}
        <div class="f">
          <span>{p.nombre}<small>Pagado {pesos(p.pagado)}{p.falta > 0 ? ` · faltó ${pesos(p.falta)}` : ' · al corriente'}</small></span>
          <b>{pesos(p.total)}</b>
        </div>
      {:else}
        <p class="vacia">Sin propinas.</p>
      {/each}
    </div>
  </div>

  {@render movimientos()}
  {@render cancelados()}
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

  /* El sello del turno en su caja de color, como la caja del cambio del cobro. */
  .veredicto {
    display: flex;
    align-items: center;
    gap: 10px;
    min-height: 52px;
    padding: 0 16px;
    border-radius: 12px;
    background: var(--fondo);
    font-size: 15px;
    font-weight: 700;
  }

  .veredicto.cuadra {
    background: color-mix(in srgb, var(--verde) 14%, transparent);
    color: var(--verde);
  }

  .veredicto.falta {
    background: color-mix(in srgb, var(--rojo) 12%, transparent);
    color: var(--rojo);
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
  .f > span {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
    font-weight: 600;
  }

  small {
    font-size: 11.5px;
    font-weight: 500;
    line-height: 1.4;
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

  .tachado {
    color: var(--tenue);
    text-decoration: line-through;
  }

  .vacia {
    margin: 0;
    font-size: 12.5px;
    color: var(--tenue);
  }

  .pista {
    margin: 0;
    font-size: 12px;
    line-height: 1.45;
    color: var(--tenue);
  }
</style>
