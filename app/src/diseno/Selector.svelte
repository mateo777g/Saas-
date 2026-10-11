<!--
  selector() de diseno.py: el selector segmentado (Prendida / Pausada al pausar una licencia,
  Hoy / Semana / Mes en Inicio). Caja de chip, radio 12, relleno 3; el elegido en sólido con una
  sombra de 1 px. `alto` es el de cada segmento (30 en Flet, 34 en las ventanas) y `lleno` los
  reparte a lo ancho, todos iguales.
-->
<script lang="ts" generics="T extends string">
  let {
    opciones,
    elegida,
    alElegir,
    etiqueta,
    alto = 30,
    lleno = false,
  }: {
    opciones: { valor: T; texto: string }[];
    elegida: T;
    alElegir: (valor: T) => void;
    etiqueta: string;
    alto?: number;
    lleno?: boolean;
  } = $props();
</script>

<div
  class="selector"
  class:lleno
  role="group"
  aria-label={etiqueta}
  style:--alto="{alto}px"
  style:--cuantas={opciones.length}
>
  {#each opciones as opcion (opcion.valor)}
    <button
      type="button"
      aria-pressed={opcion.valor === elegida}
      onclick={() => alElegir(opcion.valor)}
    >
      {opcion.texto}
    </button>
  {/each}
</div>

<style>
  .selector {
    display: flex;
    gap: 2px;
    padding: 3px;
    border-radius: 12px;
    background: var(--chip);
  }

  .lleno {
    display: grid;
    grid-template-columns: repeat(var(--cuantas), minmax(0, 1fr));
  }

  button {
    height: var(--alto);
    padding: 0 12px;
    border: 0;
    border-radius: 9px;
    background: transparent;
    color: var(--suave);
    font-size: 12.5px;
    font-weight: 600;
    white-space: nowrap;
  }

  button[aria-pressed='true'] {
    background: var(--solido);
    color: var(--texto);
    box-shadow: 0 1px 3px var(--sombra-segmento);
  }
</style>
