<!--
  Las cuatro cifras de «Resumen de hoy», en 2 filas de 2 y con una sola gráfica de línea (maqueta
  V64Pv4gmANPRZuJW5hTe5D; libreta 4, «El rediseño del panel»): Vendido hoy por hora contra ayer (punteada),
  Esta semana por día, Lo más vendido con las piezas de ese producto cada día y Este mes acumulado con su
  proyección punteada. Todo sale de cifras_de_inicio, ya contado, con las mismas funciones que el agente:
  aquí solo se escribe y se dibuja. La primera vez que lee, cada tarjeta lleva su esqueleto (el valor, la
  gráfica y la nota; decidido el 8 nov 2026); si no pudo, cada valor dice «—»: nunca un $0 inventado.
-->
<script lang="ts">
  import Icono from '../../../diseno/Icono.svelte';
  import { pesos, plural } from '../../../lib/formato';
  import type { CifrasDeInicio } from '../../../lib/reportes';
  import GraficaLinea, { type Marca } from '../../../diseno/GraficaLinea.svelte';
  import SinDatos from '../../../diseno/SinDatos.svelte';
  import Esqueleto from '../../../diseno/Esqueleto.svelte';
  import { ejeEntero, escala, SIN_MARCAS } from '../../../lib/ejes';

  type Lectura = { estado: 'leyendo' } | { estado: 'listo'; datos: CifrasDeInicio } | { estado: 'error'; deRed: boolean };

  let { lectura }: { lectura: Lectura } = $props();

  const c = $derived(lectura.estado === 'listo' ? lectura.datos : null);
  const leyendo = $derived(lectura.estado === 'leyendo');
  const sinLeer = $derived(lectura.estado === 'error' ? 'No se pudo leer' : '');

  const SIN_VENTAS = 'Aún sin ventas';

  function milesDePesos(v: number): string {
    if (v >= 1_000_000) return `$${Number((v / 1_000_000).toFixed(2))} M`;
    if (v >= 1000) return `$${Number((v / 1000).toFixed(2))} mil`;
    return `$${Number(v.toFixed(2))}`;
  }

  function ejeDePesos(alto: number): { tope: number; marcas: Marca[] } {
    const { tope, paso } = escala(alto);
    if (alto <= 0) return { tope: 1000, marcas: [0, 500, 1000].map((valor) => ({ valor, texto: milesDePesos(valor) })) };
    return { tope, marcas: [0, paso, paso * 2].map((valor) => ({ valor, texto: milesDePesos(valor) })) };
  }

  const DIAS = ['L', 'M', 'M', 'J', 'V', 'S', 'D'].map((texto, x) => ({ x, texto }));

  // ─── Vendido hoy ───
  // Empieza en la última hora sin nada antes de la primera venta (de hoy o de ayer), y termina ahora.
  const hoy = $derived.by(() => {
    if (!c) return null;
    const horas = c.horas;
    const primera = horas.findIndex((h) => h.hoy > 0 || h.ayer > 0);
    const desde = primera === -1 ? Math.max(0, horas.length - 1) : Math.max(0, primera - 1);
    const filas = horas.slice(desde);
    const minutos = Number(c.hora.slice(3)) / 60;
    const ahora = Math.max(filas.length - 1 + minutos, 0.25);
    const hubo = c.vendido_hoy.hoy > 0 || c.vendido_hoy.ayer_a_esta_hora > 0;
    const { tope, marcas } = ejeDePesos(Math.max(c.vendido_hoy.hoy, c.vendido_hoy.ayer_a_esta_hora));
    return {
      tramo: ahora,
      equis: [...filas.map((_, i) => i), ahora],
      puntos: hubo ? [...filas.map((h) => h.hoy), c.vendido_hoy.hoy] : [],
      comparar: hubo ? [...filas.map((h) => h.ayer), c.vendido_hoy.ayer_a_esta_hora] : [],
      tope,
      marcas,
      ejeX: [
        { x: 0, texto: (filas[0]?.hora ?? c.hora).replace(/^0/, ''), ancla: 'start' as const },
        { x: ahora, texto: c.hora.replace(/^0/, ''), ancla: 'end' as const },
      ],
    };
  });

  // Hoy en $0 dice «Aún sin ventas cerradas» aunque ayer a esta hora ya llevara (decidido el 19 de octubre
  // de 2026). El % lo dio Postgres, redondeado.
  const notaHoy = $derived.by(() => {
    if (!c) return sinLeer;
    if (c.vendido_hoy.hoy === 0) return 'Aún sin ventas cerradas';
    if (c.vendido_hoy.porcentaje === null) return 'Ayer a esta hora no había ventas';
    return 'Contra ayer a esta hora (punteada)';
  });
  const cambio = $derived(c && c.vendido_hoy.hoy > 0 ? c.vendido_hoy.porcentaje : null);

  // ─── Esta semana ───
  const semana = $derived.by(() => {
    if (!c) return null;
    const puntos = c.semana.dias.map((d) => d.importe).filter((v): v is number => v !== null);
    return { puntos: c.semana.vendido > 0 ? puntos : [], ...ejeDePesos(Math.max(0, ...puntos)) };
  });

  // ─── Lo más vendido ───
  const primero = $derived(c?.lo_mas_vendido[0] ?? null);
  const producto = $derived.by(() => {
    if (!c) return null;
    const puntos = c.lo_mas_vendido_dias.map((d) => d.unidades).filter((v): v is number => v !== null);
    return { puntos, ...ejeEntero(Math.max(0, ...puntos)) };
  });

  // ─── Este mes ───
  const mes = $derived.by(() => {
    if (!c) return null;
    const [anio, numero] = c.hoy.split('-').map(Number);
    const dias = new Date(Date.UTC(anio, numero, 0)).getUTCDate();
    const acumulado = c.mes.dias.map((d) => d.acumulado);
    const alto = Math.max(c.mes.va_para ?? 0, ...acumulado);
    const tramo = dias - 1;
    return {
      tramo,
      puntos: alto > 0 ? acumulado : [],
      hacia: c.mes.va_para,
      ...ejeDePesos(alto),
      ejeX: [
        { x: 0, texto: '1', ancla: 'start' as const },
        { x: 14, texto: '15' },
        { x: tramo, texto: String(dias), ancla: 'end' as const },
      ],
    };
  });

  // Sin «Va para» (la primera semana de ventas), «Del 1 a hoy» (decidido el 19 de octubre de 2026).
  const notaMes = $derived(
    !c
      ? sinLeer
      : c.mes.va_para !== null
        ? `Va para ${pesos(c.mes.va_para)}`
        : c.mes.vendido === 0
          ? 'Sin ventas este mes'
          : 'Del 1 a hoy',
  );
</script>

<div class="cifras" aria-busy={leyendo}>
  {#if leyendo}<span class="solo-lector">Leyendo las cifras de hoy…</span>{/if}

  <div class="tarjeta">
    <span class="etiqueta cabeza">Vendido hoy</span>
    <div class="valor-fila">
      <span class="valor">{#if leyendo}<Esqueleto ancho="128px" alto="26px" />{:else}{c ? pesos(c.vendido_hoy.hoy) : '—'}{/if}</span>
      {#if cambio !== null && cambio !== 0}
        <span class="cambio" class:sube={cambio > 0}>
          <Icono nombre={cambio > 0 ? 'r-sube' : 'r-baja'} tamano={14} />{Math.abs(cambio)} %
        </span>
      {/if}
    </div>
    {#if leyendo}
      <Esqueleto proporcion="448 / 150" redondo="8px" />
    {:else if c && !hoy?.puntos.length}
      <SinDatos texto={SIN_VENTAS} />
    {:else}
    <GraficaLinea
      etiqueta="Lo vendido hoy hora por hora, contra ayer"
      tramo={hoy?.tramo ?? 1}
      equis={hoy?.equis}
      puntos={hoy?.puntos ?? []}
      comparar={hoy?.comparar}
      tope={hoy?.tope ?? 1}
      marcas={hoy?.marcas ?? SIN_MARCAS}
      ejeX={hoy?.ejeX ?? []}
    />
    {/if}
    <span class="nota">{#if leyendo}<Esqueleto ancho="38%" alto="10px" />{:else}{notaHoy}{/if}</span>
  </div>

  <div class="tarjeta">
    <span class="etiqueta cabeza">Esta semana</span>
    <div class="valor-fila"><span class="valor">{#if leyendo}<Esqueleto ancho="112px" alto="26px" />{:else}{c ? pesos(c.semana.vendido) : '—'}{/if}</span></div>
    {#if leyendo}
      <Esqueleto proporcion="448 / 150" redondo="8px" />
    {:else if c && !semana?.puntos.length}
      <SinDatos texto={SIN_VENTAS} />
    {:else}
    <GraficaLinea
      etiqueta="Lo vendido cada día de la semana"
      tramo={6}
      puntos={semana?.puntos ?? []}
      tope={semana?.tope ?? 1}
      marcas={semana?.marcas ?? SIN_MARCAS}
      ejeX={DIAS}
    />
    {/if}
    <span class="nota">{#if leyendo}<Esqueleto ancho="30%" alto="10px" />{:else}{!c ? sinLeer : c.semana.vendido === 0 ? 'Sin ventas esta semana' : 'De lunes a hoy'}{/if}</span>
  </div>

  <div class="tarjeta">
    <span class="etiqueta cabeza">Lo más vendido</span>
    <div class="valor-fila"><span class="valor largo">{#if leyendo}<Esqueleto ancho="176px" alto="26px" />{:else}{primero?.nombre ?? '—'}{/if}</span></div>
    {#if leyendo}
      <Esqueleto proporcion="448 / 150" redondo="8px" />
    {:else if c && !primero}
      <SinDatos texto={SIN_VENTAS} />
    {:else}
    <GraficaLinea
      etiqueta={primero ? `Piezas de ${primero.nombre} cada día de la semana` : 'Piezas del producto más vendido cada día de la semana'}
      tramo={6}
      puntos={producto?.puntos ?? []}
      tope={producto?.tope ?? 1}
      marcas={producto?.marcas ?? SIN_MARCAS}
      ejeX={DIAS}
    />
    {/if}
    <span class="nota">
      {#if leyendo}<Esqueleto ancho="44%" alto="10px" />{:else}{!c ? sinLeer : !primero ? 'Sin ventas esta semana' : `${plural(primero.unidades, 'pieza', 'piezas')} en la semana · por día`}{/if}
    </span>
  </div>

  <div class="tarjeta">
    <span class="etiqueta cabeza">Este mes</span>
    <div class="valor-fila"><span class="valor">{#if leyendo}<Esqueleto ancho="120px" alto="26px" />{:else}{c ? pesos(c.mes.vendido) : '—'}{/if}</span></div>
    {#if leyendo}
      <Esqueleto proporcion="448 / 150" redondo="8px" />
    {:else if c && !mes?.puntos.length}
      <SinDatos texto={SIN_VENTAS} />
    {:else}
    <GraficaLinea
      etiqueta="Lo vendido en el mes, acumulado, y hacia dónde va"
      tramo={mes?.tramo ?? 29}
      puntos={mes?.puntos ?? []}
      hacia={mes?.hacia}
      tope={mes?.tope ?? 1}
      marcas={mes?.marcas ?? SIN_MARCAS}
      ejeX={mes?.ejeX ?? []}
    />
    {/if}
    <span class="nota">{#if leyendo}<Esqueleto ancho="26%" alto="10px" />{:else}{notaMes}{/if}</span>
  </div>
</div>

<style>
  .cifras {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 12px;
  }

  .tarjeta {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 10px;
    padding: 20px 22px 18px;
    background: var(--solido);
    border: 1px solid var(--borde-tarjeta);
    border-radius: 14px;
  }

  .cabeza {
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  .valor-fila {
    min-width: 0;
    display: flex;
    align-items: baseline;
    gap: 8px;
  }

  .valor {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 28px;
    font-weight: 800;
    letter-spacing: -0.5px;
    font-variant-numeric: tabular-nums;
  }

  .valor.largo {
    line-height: 34px;
  }

  .cambio {
    display: inline-flex;
    align-items: center;
    gap: 2px;
    font-size: 12.5px;
    font-weight: 600;
    color: var(--suave);
    white-space: nowrap;
  }

  .cambio.sube {
    color: var(--verde);
  }

  .nota {
    min-height: 15px;
    font-size: 12px;
    font-weight: 400;
    color: var(--suave);
  }
</style>
