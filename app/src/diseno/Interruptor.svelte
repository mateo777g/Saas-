<!--
  El interruptor del panel (maqueta de la 6a, el horario de Tu restaurante; con la 6b, «Hago envíos»
  y «Es un costo de envío»): un riel de 34 × 20 que se pinta de tinta al prenderse, con su texto al
  lado si lo lleva. Sin texto, `ayuda` es lo que lee el lector de pantalla.
-->
<script lang="ts">
  let {
    prendido,
    texto = '',
    ayuda = '',
    apagado = false,
    alCambiar,
  }: { prendido: boolean; texto?: string; ayuda?: string; apagado?: boolean; alCambiar: (prendido: boolean) => void } = $props();
</script>

<button
  type="button"
  class="interruptor"
  role="switch"
  aria-checked={prendido}
  aria-label={texto ? undefined : ayuda}
  disabled={apagado}
  onclick={() => alCambiar(!prendido)}
>
  <span class="riel"></span>{texto}
</button>

<style>
  .interruptor {
    display: inline-flex;
    align-items: center;
    gap: 9px;
    flex: none;
    border: 0;
    background: transparent;
    padding: 0;
    font-size: 12.5px;
    font-weight: 600;
    color: var(--texto);
  }

  .interruptor[aria-checked='false'] {
    color: var(--tenue);
  }

  .interruptor:disabled {
    cursor: default;
    opacity: 0.5;
  }

  .riel {
    width: 34px;
    height: 20px;
    border-radius: 10px;
    background: var(--linea-fuerte);
    position: relative;
    flex: none;
    transition: background-color 150ms;
  }

  .riel::after {
    content: '';
    position: absolute;
    top: 2px;
    left: 2px;
    width: 16px;
    height: 16px;
    border-radius: 8px;
    background: var(--solido);
    box-shadow: 0 1px 2px var(--sombra-segmento);
    transition: transform 150ms;
  }

  .interruptor[aria-checked='true'] .riel {
    background: var(--tinta);
  }

  .interruptor[aria-checked='true'] .riel::after {
    transform: translateX(14px);
  }

  @media (prefers-reduced-motion: reduce) {
    .riel,
    .riel::after {
      transition: none;
    }
  }
</style>
