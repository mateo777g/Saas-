<!--
  La gráfica de Inicio, una sola para los paneles, como Cloudflare (maqueta V64Pv4gmANPRZuJW5hTe5D): rejilla
  tenue, el eje a la derecha en mono, el área clara, un punto en lo último y, si hay, la comparación punteada
  o la proyección. Azul en claro y verde en oscuro (--grafica; quien la usa puede cambiarlo, como la tarjeta
  de Sin funcionar). Aquí no se cuenta nada: cada punto va en proporción a lo que dio Postgres.
-->
<script lang="ts">
  export type Marca = { valor: number; texto: string };
  export type EjeX = { x: number; texto: string; ancla?: 'start' | 'middle' | 'end' };

  let {
    etiqueta,
    tramo,
    equis,
    puntos,
    comparar,
    hacia,
    tope,
    marcas,
    ejeX,
    ancho = 448,
    alto = 150,
    sinPunto = false,
  }: {
    etiqueta: string;
    // Cuánto mide el eje de las equis.
    tramo: number;
    // Dónde va cada punto; sin esto, 0, 1, 2…
    equis?: number[];
    puntos: number[];
    comparar?: number[];
    hacia?: number | null;
    tope: number;
    marcas: Marca[];
    ejeX: EjeX[];
    ancho?: number;
    alto?: number;
    // Lo que mira hacia adelante (Vencen en 7 días) no tiene un «ahora» al final.
    sinPunto?: boolean;
  } = $props();

  const ARRIBA = 6;
  const derecha = $derived(ancho - 46);
  const abajo = $derived(alto - 22);
  const letras = $derived(alto - 4);

  const x = (v: number) => (v / tramo) * derecha;
  const y = (v: number) => abajo - (v / tope) * (abajo - ARRIBA);
  const trazo = (lista: number[]) => lista.map((v, i) => `${x(equis ? equis[i] : i).toFixed(1)},${y(v).toFixed(1)}`);

  const linea = $derived(trazo(puntos));
  const ultimo = $derived.by(() => {
    if (!puntos.length) return null;
    const i = puntos.length - 1;
    return { x: x(equis ? equis[i] : i), y: y(puntos[i]) };
  });
  // El área va del primer punto al último, aunque la línea no empiece en el borde.
  const primero = $derived(puntos.length ? x(equis ? equis[0] : 0) : 0);
</script>

<svg viewBox="0 0 {ancho} {alto}" role="img" aria-label={etiqueta}>
  {#each marcas as m (m.valor)}
    <line class="rejilla" x1="0" x2={derecha} y1={y(m.valor).toFixed(1)} y2={y(m.valor).toFixed(1)} />
    <text class="eje" x={derecha + 6} y={y(m.valor).toFixed(1)} dominant-baseline="middle">{m.texto}</text>
  {/each}
  {#each ejeX as e (e.x + e.texto)}
    <text class="eje" x={x(e.x).toFixed(1)} y={letras} text-anchor={e.ancla ?? 'middle'}>{e.texto}</text>
  {/each}
  {#if comparar?.length}
    <polyline class="punteada" points={trazo(comparar).join(' ')} />
  {/if}
  {#if ultimo}
    <path class="area" d="M{Number(primero.toFixed(1))},{abajo} L{linea.join(' L')} L{ultimo.x.toFixed(1)},{abajo} Z" />
    {#if hacia !== undefined && hacia !== null}
      <line class="proyeccion" x1={ultimo.x.toFixed(1)} y1={ultimo.y.toFixed(1)} x2={x(tramo).toFixed(1)} y2={y(hacia).toFixed(1)} />
    {/if}
    <polyline class="linea" points={linea.join(' ')} />
    {#if !sinPunto}
      <circle class="punto" cx={ultimo.x.toFixed(1)} cy={ultimo.y.toFixed(1)} r="3" />
    {/if}
  {/if}
</svg>

<style>
  svg {
    display: block;
    width: 100%;
    height: auto;
    overflow: visible;
  }

  .rejilla {
    stroke: var(--linea);
    stroke-width: 1;
  }

  .eje {
    fill: var(--tenue);
    font-family: var(--mono);
    font-size: 10px;
    font-weight: 400;
  }

  .area {
    fill: var(--grafica);
    opacity: 0.12;
  }

  .linea {
    fill: none;
    stroke: var(--grafica);
    stroke-width: 2;
    stroke-linejoin: round;
    stroke-linecap: round;
  }

  .punteada {
    fill: none;
    stroke: var(--linea-fuerte);
    stroke-width: 1.5;
    stroke-dasharray: 3 3;
  }

  .proyeccion {
    fill: none;
    stroke: var(--grafica);
    stroke-width: 1.5;
    stroke-dasharray: 3 3;
    opacity: 0.7;
  }

  .punto {
    fill: var(--grafica);
  }
</style>
