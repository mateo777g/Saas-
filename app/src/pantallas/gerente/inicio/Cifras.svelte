<!--
  Las cuatro cifras de Inicio, debajo del saludo (maqueta Agente IA KznKZdgQbLTZGs1EwVMvga; libreta
  1, «Las cuatro cifras de Inicio»): Vendido hoy contra lo que ayer ya estaba cerrado a esta misma
  hora, Esta semana, Lo más vendido y Este mes con «Va para». Todo sale de cifras_de_inicio, ya
  contado, con las mismas funciones que el agente: aquí solo se escribe y se dibuja (el largo de
  cada barra y la altura de cada punto van en proporción a lo que dio Postgres). Mientras lee, o
  si no pudo, cada valor dice «—»: nunca un $0 inventado.
-->
<script lang="ts">
  import Icono from '../../../diseno/Icono.svelte';
  import { dinero, plural } from '../../../lib/formato';
  import type { CifrasDeInicio } from '../../../lib/reportes';

  type Lectura = { estado: 'leyendo' } | { estado: 'listo'; datos: CifrasDeInicio } | { estado: 'error'; deRed: boolean };

  let { lectura }: { lectura: Lectura } = $props();

  const c = $derived(lectura.estado === 'listo' ? lectura.datos : null);
  const sinLeer = $derived(lectura.estado === 'error' ? 'No se pudo leer' : '');

  // Las dos gráficas miden 134 × 32, como en la maqueta.
  const W = 134;
  const H = 32;

  // ─── Vendido hoy ───
  const barras = $derived.by(() => {
    if (!c) return { hoy: 0, ayer: 0 };
    const { hoy, ayer_a_esta_hora: ayer } = c.vendido_hoy;
    const largo = Math.max(hoy, ayer, 1);
    return { hoy: (hoy / largo) * 100, ayer: (ayer / largo) * 100 };
  });

  // Hoy en $0 dice «Aún sin ventas cerradas» aunque ayer a esta hora ya llevara (decidido el 19 de
  // octubre de 2026): las barras ya enseñan la diferencia. El % lo dio Postgres, redondeado.
  const notaHoy = $derived.by((): { texto: string; flecha?: 'sube' | 'baja' } => {
    if (!c) return { texto: sinLeer };
    const { hoy, porcentaje } = c.vendido_hoy;
    if (hoy === 0) return { texto: 'Aún sin ventas cerradas' };
    if (porcentaje === null) return { texto: 'Ayer a esta hora no había ventas' };
    if (porcentaje > 0) return { texto: `${porcentaje} % más que ayer a esta hora`, flecha: 'sube' };
    if (porcentaje < 0) return { texto: `${Math.abs(porcentaje)} % menos que ayer a esta hora`, flecha: 'baja' };
    return { texto: 'Igual que ayer a esta hora' };
  });

  // ─── Esta semana: una barra por día, de lunes a domingo; los días que faltan, sin barra ───
  const LETRAS = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
  const banda = W / 7;
  const semana = $derived.by(() => {
    if (!c || c.semana.vendido === 0) return [];
    const mayor = Math.max(1, ...c.semana.dias.map((d) => d.importe ?? 0));
    return c.semana.dias.map((d) =>
      d.importe === null ? null : { alto: Math.max(2, (d.importe / mayor) * 19), importe: d.importe, hoy: d.dia === c.hoy },
    );
  });

  // ─── Lo más vendido: el primero arriba, los otros dos en su lista ───
  const top = $derived(c?.lo_mas_vendido ?? []);

  // ─── Este mes: lo que va (la línea) y hacia dónde va (la punteada, si hay «Va para») ───
  const mes = $derived.by(() => {
    if (!c) return null;
    const { vendido, dias, va_para } = c.mes;
    if (vendido === 0 && va_para === null) return null;
    const [anio, numero] = c.hoy.split('-').map(Number);
    const diasDelMes = new Date(Date.UTC(anio, numero, 0)).getUTCDate();
    const ultimo = dias[dias.length - 1];
    const escala = Math.max(1, va_para ?? 0, ultimo.acumulado);
    const x = (dia: number) => 2 + ((dia - 1) / (diasDelMes - 1)) * (W - 4);
    const y = (v: number) => 29 - (v / escala) * 26;
    const puntos = dias.map((d) => `${x(Number(d.dia.slice(8)))},${y(d.acumulado)}`);
    const punto = { x: x(Number(ultimo.dia.slice(8))), y: y(ultimo.acumulado) };
    return {
      area: `M${x(1)},29L${puntos.join('L')}L${punto.x},29Z`,
      linea: puntos.join(' '),
      punto,
      hacia: va_para === null ? null : { x: x(diasDelMes), y: y(va_para) },
    };
  });

  // Sin «Va para» (la primera semana de ventas), «Del 1 a hoy» (decidido el 19 de octubre de 2026).
  const notaMes = $derived(
    !c
      ? sinLeer
      : c.mes.va_para !== null
        ? `Va para ${dinero(c.mes.va_para)}`
        : c.mes.vendido === 0
          ? 'Sin ventas este mes'
          : 'Del 1 a hoy',
  );
</script>

<div class="cifras">
  <div class="cifra">
    <span class="etiqueta">VENDIDO HOY</span>
    <span class="valor">{c ? dinero(c.vendido_hoy.hoy) : '—'}</span>
    <div class="mini comparar">
      <div class="barra-fila">
        <span class="etq-mini">HOY</span>
        <span class="riel"><span class="lleno" style:width="{barras.hoy}%"></span></span>
      </div>
      <div class="barra-fila">
        <span class="etq-mini">AYER</span>
        <span class="riel"><span class="lleno ayer" style:width="{barras.ayer}%"></span></span>
      </div>
    </div>
    <span class="nota">
      {#if notaHoy.flecha}
        <span class="flecha" class:baja={notaHoy.flecha === 'baja'}><Icono nombre="flecha-{notaHoy.flecha}" tamano={13} /></span>
      {/if}
      <span>{notaHoy.texto}</span>
    </span>
  </div>

  <div class="cifra">
    <span class="etiqueta">ESTA SEMANA</span>
    <span class="valor">{c ? dinero(c.semana.vendido) : '—'}</span>
    <div class="mini">
      <svg viewBox="0 0 {W} {H}" role="img" aria-label="Ventas de cada día de la semana">
        <line class="g-base" x1="0" x2={W} y1="20.5" y2="20.5" />
        {#each LETRAS as letra, i (i)}
          {@const dia = semana[i]}
          {#if dia}
            <rect class="g-col" class:hoy={dia.hoy} x={banda * (i + 0.5) - 5.5} y={20 - dia.alto} width="11" height={dia.alto} rx="2">
              <title>{dinero(dia.importe)}</title>
            </rect>
          {/if}
          <text class="g-dia" x={banda * (i + 0.5)} y={H - 1} text-anchor="middle">{letra}</text>
        {/each}
      </svg>
    </div>
    <span class="nota">{!c ? sinLeer : c.semana.vendido === 0 ? 'Sin ventas esta semana' : 'De lunes a hoy'}</span>
  </div>

  <div class="cifra">
    <span class="etiqueta">LO MÁS VENDIDO</span>
    <span class="valor texto-largo">{top.length ? top[0].nombre : '—'}</span>
    <div class="mini ranking">
      {#if c && !top.length}
        <div class="mini-vacio">Sin ventas todavía</div>
      {:else}
        {#each top.slice(1) as p, i (i)}
          <div class="rank">
            <span class="mono lugar">0{i + 2}</span>
            <span class="rank-nombre">{p.nombre}</span>
            <span class="rank-n">{p.unidades}</span>
          </div>
        {/each}
      {/if}
    </div>
    <span class="nota">{!c ? sinLeer : !top.length ? 'Sin ventas esta semana' : `${plural(top[0].unidades, 'pieza', 'piezas')} · semana`}</span>
  </div>

  <div class="cifra">
    <span class="etiqueta">ESTE MES</span>
    <span class="valor">{c ? dinero(c.mes.vendido) : '—'}</span>
    <div class="mini">
      <svg viewBox="0 0 {W} {H}" role="img" aria-label="Ventas acumuladas del mes y hacia dónde van">
        <line class="g-base" x1="0" x2={W} y1="29.5" y2="29.5" />
        {#if mes}
          <path class="g-area" d={mes.area} />
          {#if mes.hacia}
            <line class="g-proyeccion" x1={mes.punto.x} y1={mes.punto.y} x2={mes.hacia.x} y2={mes.hacia.y} />
          {/if}
          <polyline class="g-linea" points={mes.linea} />
          <circle class="g-punto" cx={mes.punto.x} cy={mes.punto.y} r="2.75" />
        {/if}
      </svg>
    </div>
    <span class="nota">{notaMes}</span>
  </div>
</div>

<style>
  .cifras {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 12px;
  }

  .cifra {
    min-width: 0;
    padding: 16px;
    border-radius: 18px;
    background: var(--solido);
    border: 1px solid var(--linea);
    display: flex;
    flex-direction: column;
    gap: 7px;
  }

  .valor {
    height: 32px;
    font-size: 26px;
    font-weight: 800;
    letter-spacing: -0.5px;
    line-height: 32px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    font-variant-numeric: tabular-nums;
  }

  .valor.texto-largo {
    font-size: 19px;
    letter-spacing: -0.3px;
  }

  .mini {
    height: 32px;
    position: relative;
  }

  .mini svg {
    display: block;
    width: 100%;
    height: 100%;
    overflow: visible;
  }

  .nota {
    display: flex;
    align-items: flex-start;
    gap: 4px;
    font-size: 12.5px;
    font-weight: 500;
    color: var(--suave);
    line-height: 1.35;
  }

  .flecha {
    flex: none;
    margin-top: 2px;
    color: var(--verde);
  }

  .flecha.baja {
    color: var(--tenue);
  }

  .comparar {
    display: flex;
    flex-direction: column;
    justify-content: center;
    gap: 8px;
  }

  .barra-fila {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .etq-mini {
    width: 30px;
    flex: none;
    font-family: var(--mono);
    font-size: 9.5px;
    letter-spacing: 0.1em;
    color: var(--tenue);
  }

  .riel {
    flex: 1;
    height: 6px;
    display: block;
    border-radius: 3px;
    background: var(--chip);
    overflow: hidden;
  }

  .lleno {
    display: block;
    height: 100%;
    border-radius: 3px;
    background: var(--tinta);
  }

  .lleno.ayer {
    background: var(--tenue);
  }

  .g-col {
    fill: var(--tenue);
  }

  .g-col.hoy {
    fill: var(--tinta);
  }

  .g-base {
    stroke: var(--linea);
    stroke-width: 1;
  }

  .g-dia {
    font-family: var(--mono);
    font-size: 8.5px;
    fill: var(--tenue);
  }

  .g-linea {
    fill: none;
    stroke: var(--tinta);
    stroke-width: 1.75;
    stroke-linejoin: round;
    stroke-linecap: round;
  }

  .g-area {
    fill: var(--chip);
  }

  .g-proyeccion {
    fill: none;
    stroke: var(--tenue);
    stroke-width: 1.25;
    stroke-dasharray: 3 3;
  }

  .g-punto {
    fill: var(--tinta);
  }

  .ranking {
    display: flex;
    flex-direction: column;
    justify-content: center;
    gap: 4px;
  }

  .rank {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 12px;
    font-weight: 600;
  }

  .lugar {
    font-size: 10.5px;
    font-weight: 400;
    color: var(--tenue);
  }

  .rank-nombre {
    flex: 1;
    min-width: 0;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .rank-n {
    font-family: var(--mono);
    font-size: 11px;
    font-weight: 400;
    color: var(--suave);
  }

  .mini-vacio {
    height: 100%;
    display: flex;
    align-items: center;
    font-size: 12px;
    font-weight: 500;
    color: var(--tenue);
  }
</style>
