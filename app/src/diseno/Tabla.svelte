<!--
  Una tabla en sólido (la regla "VIDRIO vs SÓLIDO": lo que se lee de cerca va en sólido, dentro
  del vidrio): radio 18, borde fino, la fila de encabezados en mono y el cuerpo que se desplaza
  solo. `columnas` es el reparto de las columnas (grid-template-columns), el mismo para los
  encabezados y para cada fila.

  Cada fila la pinta quien usa la tabla, con class="fila"; adentro puede usar class="celda" (y
  "fuerte", "tenue" o "numero") para el texto de cada columna. Si no hay filas, va una NotaTabla.
  `relleno` y `altoFila` cambian las filas: las de Mi menú miden 64 con su foto de 44 adentro.

  `marco` es la tabla del rediseño (Mi menú, 8 nov 2026; maqueta Ltm74p3fb7tiAqYcj5nqbX), como la Table
  de HeroUI: un marco gris de 20 de esquina con 4 de orilla, los encabezados en ese gris (12 px, con
  mayúscula inicial, y una rayita entre uno escrito y el siguiente), las filas en blanco con 16 de
  esquina y una línea tenue entre ellas, y 32 entre columna y columna. La tabla mide lo que sus filas y,
  si no caben, el cuerpo se desliza con los encabezados fijos. Con el mouse encima, o elegida
  (aria-pressed), la fila deja ver un poco el marco; una fila con class="quieta" (un esqueleto) no.
  Las demás tablas siguen como antes hasta su turno.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';

  let {
    columnas,
    encabezados,
    relleno = '12px 16px',
    altoFila = 0,
    marco = false,
    children,
  }: {
    columnas: string;
    encabezados: { texto: string; derecha?: boolean }[];
    relleno?: string;
    altoFila?: number;
    marco?: boolean;
    children: Snippet;
  } = $props();

  const conRaya = (i: number) => marco && !!encabezados[i].texto && !!encabezados[i + 1]?.texto;
</script>

<div class="tabla" class:marco style:--columnas={columnas} style:--relleno={relleno} style:--alto-fila="{altoFila}px">
  <div class="fila cabecera">
    {#each encabezados as e, i (i)}
      <span class="etiqueta" class:derecha={e.derecha} class:con-raya={conRaya(i)}>{e.texto}</span>
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

  /* ─── En su marco ─── */
  .tabla.marco {
    flex: 0 1 auto;
    padding: 0 4px 4px;
    border: 0;
    border-radius: 20px;
    background: var(--tabla-marco);
  }

  .tabla.marco :global(.fila) {
    gap: 32px;
  }

  .tabla.marco .cabecera {
    height: 36px;
    min-height: 36px;
    border-bottom: 1px solid var(--tabla-linea-cabecera);
  }

  .tabla.marco .etiqueta {
    position: relative;
    font-family: var(--jakarta);
    font-size: 12px;
    font-weight: 500;
    line-height: 16px;
    letter-spacing: 0;
    color: var(--tabla-encabezado);
  }

  .tabla.marco .con-raya::after {
    content: '';
    position: absolute;
    top: 50%;
    right: -16px;
    width: 1px;
    height: 16px;
    translate: 0 -50%;
    border-radius: 4px;
    background: var(--tabla-raya);
  }

  .tabla.marco .cuerpo {
    flex: 0 1 auto;
    min-height: 0;
    border-radius: 16px;
  }

  .tabla.marco .cuerpo > :global(.fila) {
    background: var(--solido);
    border-bottom: 1px solid var(--tabla-linea);
    transition: background-color 0.15s cubic-bezier(0.4, 0, 0.2, 1);
  }

  .tabla.marco .cuerpo > :global(.fila:last-child) {
    border-bottom: 0;
  }

  .tabla.marco .cuerpo > :global(.fila:not(.quieta):hover),
  .tabla.marco .cuerpo > :global(.fila[aria-pressed='true']) {
    background: color-mix(in oklab, var(--solido) 40%, transparent);
  }

  .tabla.marco .cuerpo > :global(.nota) {
    background: var(--solido);
  }

  /* Cristal: la tabla es contenido y va de material, como las tarjetas (libreta 4, «El estilo Cristal»): vidrio
     tranquilo, sin canto ni luz, y sus renglones dejan de ser sólidos (un relleno claro transparente detrás de todos). */
  :global(:root[data-estilo='cristal'][data-tema='oscuro']) .tabla.marco {
    background: var(--cristal-tinte);
    -webkit-backdrop-filter: blur(26px) saturate(150%);
    backdrop-filter: blur(26px) saturate(150%);
    border: 1px solid var(--cristal-linea);
    box-shadow: 0 18px 40px -14px var(--cristal-sombra);
  }

  :global(:root[data-estilo='cristal'][data-tema='claro']) .tabla.marco {
    background: var(--cl-tinte);
    -webkit-backdrop-filter: blur(26px) saturate(160%);
    backdrop-filter: blur(26px) saturate(160%);
    border: 1px solid var(--cl-linea);
    box-shadow: 0 18px 40px -14px var(--cl-sombra);
  }

  :global(:root[data-estilo='cristal'][data-tema='oscuro']) .tabla.marco .cuerpo {
    background: var(--cristal-relleno);
  }

  :global(:root[data-estilo='cristal'][data-tema='claro']) .tabla.marco .cuerpo {
    background: rgba(255, 255, 255, 0.32);
  }

  :global(:root[data-estilo='cristal']) .tabla.marco .cuerpo > :global(:is(.fila, .nota)) {
    background: transparent;
  }

  :global(:root[data-estilo='cristal'][data-tema='oscuro']) .tabla.marco .cuerpo > :global(:is(.fila:not(.quieta):hover, .fila[aria-pressed='true'])) {
    background: rgba(255, 255, 255, 0.05);
  }

  :global(:root[data-estilo='cristal'][data-tema='claro']) .tabla.marco .cuerpo > :global(:is(.fila:not(.quieta):hover, .fila[aria-pressed='true'])) {
    background: rgba(255, 255, 255, 0.4);
  }

  @media (prefers-reduced-motion: reduce) {
    .tabla.marco .cuerpo > :global(.fila) {
      transition: none;
    }
  }
</style>
