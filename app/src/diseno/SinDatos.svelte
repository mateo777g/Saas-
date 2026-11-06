<!--
  El lugar de una gráfica que todavía no tiene qué dibujar, como el «No data» de Cloudflare (maqueta
  4Ryyf9E7u4vsDs57PdkAnz): una onda tenue con su pastilla. Mide lo mismo que la gráfica de ese tamaño.
-->
<script lang="ts">
  let { texto, ancho = 448, alto = 150 }: { texto: string; ancho?: number; alto?: number } = $props();
</script>

<div class="vacio">
  <svg viewBox="0 0 {ancho} {alto}" aria-hidden="true">
    <g transform="scale({ancho / 280} {alto / 110})">
      <path
        vector-effect="non-scaling-stroke"
        d="M0,62 C20,58 34,66 52,60 S84,40 104,52 S140,72 166,58 S210,46 236,64 S266,70 280,58 L280,110 L0,110 Z"
      />
    </g>
  </svg>
  <span>{texto}</span>
</div>

<style>
  .vacio {
    position: relative;
  }

  svg {
    display: block;
    width: 100%;
    height: auto;
  }

  path {
    fill: var(--chip);
    stroke: var(--linea-fuerte);
    stroke-width: 1;
    opacity: 0.7;
  }

  span {
    position: absolute;
    left: 50%;
    top: 50%;
    transform: translate(-50%, -50%);
    padding: 4px 10px;
    border: 1px solid var(--borde-tarjeta);
    border-radius: 999px;
    background: var(--solido);
    color: var(--suave);
    font-size: 11.5px;
    font-weight: 400;
    white-space: nowrap;
  }
</style>
