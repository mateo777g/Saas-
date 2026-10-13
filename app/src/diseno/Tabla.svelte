<!--
  Una tabla en sólido (la regla "VIDRIO vs SÓLIDO": lo que se lee de cerca va en sólido, dentro
  del vidrio): radio 18, borde fino, la fila de encabezados en mono y el cuerpo que se desplaza
  solo. `columnas` es el reparto de las columnas (grid-template-columns), el mismo para los
  encabezados y para cada fila.

  Cada fila la pinta quien usa la tabla, con class="fila"; adentro puede usar class="celda" (y
  "fuerte", "tenue" o "numero") para el texto de cada columna. Si no hay filas, va una NotaTabla.
  `relleno` y `altoFila` cambian las filas: las de Mi menú miden 64 con su foto de 44 adentro.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';

  let {
    columnas,
    encabezados,
    relleno = '12px 16px',
    altoFila = 0,
    children,
  }: {
    columnas: string;
    encabezados: { texto: string; derecha?: boolean }[];
    relleno?: string;
    altoFila?: number;
    children: Snippet;
  } = $props();
</script>

<div class="tabla" style:--columnas={columnas} style:--relleno={relleno} style:--alto-fila="{altoFila}px">
  <div class="fila cabecera">
    {#each encabezados as e, i (i)}
      <span class="etiqueta" class:derecha={e.derecha}>{e.texto}</span>
    {/each}
  </div>
  <div class="cuerpo">
    {@render children()}
  </div>
</div>

<style>
  .tabla {
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;
    background: var(--solido);
    border: 1px solid var(--linea);
    border-radius: 18px;
    overflow: hidden;
  }

  .tabla :global(.fila) {
    display: grid;
    grid-template-columns: var(--columnas);
    gap: 16px;
    align-items: center;
    min-height: var(--alto-fila);
    padding: var(--relleno);
    border-bottom: 1px solid var(--linea);
  }

  .tabla .cabecera {
    height: 40px;
    min-height: 40px;
    flex: none;
    padding-block: 0;
  }

  .derecha {
    text-align: right;
  }

  .cuerpo {
    flex: 1;
    overflow: auto;
  }

  .tabla :global(.celda) {
    font-size: 12.5px;
    font-weight: 500;
    color: var(--suave);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    font-variant-numeric: tabular-nums;
  }

  .tabla :global(.celda.fuerte) {
    color: var(--texto);
    font-weight: 600;
  }

  .tabla :global(.celda.tenue) {
    color: var(--tenue);
  }

  .tabla :global(.celda.numero) {
    font-family: var(--mono);
    font-size: 13px;
    color: var(--texto);
    text-align: right;
  }
</style>
