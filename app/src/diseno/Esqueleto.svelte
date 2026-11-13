<!--
  Un bloque gris que late mientras algo se lee, en el lugar de lo que va a salir (el Skeleton de shadcn/ui
  portado sin React ni Tailwind: su animate-pulse de 2 s y su bg-muted, que aquí es --chip; esquinas de 6 px).
  Solo es forma: quien lo usa dice con texto para el lector de pantalla qué se está leyendo. En línea se
  centra en el renglón, así que dentro de un texto grande ocupa su mismo alto y nada brinca al llegar.
  Con «reducir movimiento», quieto. Decidido por el developer el 8 nov 2026, para las tarjetas de Inicio.
-->
<script lang="ts">
  let {
    ancho = '100%',
    alto = '12px',
    redondo = '6px',
    proporcion,
  }: {
    ancho?: string;
    alto?: string;
    redondo?: string;
    // En lugar del alto: el de una gráfica que mide «448 / 150».
    proporcion?: string;
  } = $props();
</script>

<span
  class="esqueleto"
  aria-hidden="true"
  style:width={ancho}
  style:height={proporcion ? 'auto' : alto}
  style:aspect-ratio={proporcion}
  style:border-radius={redondo}
></span>

<style>
  .esqueleto {
    display: inline-block;
    flex: none;
    vertical-align: middle;
    max-width: 100%;
    background: var(--chip);
    animation: late 2s cubic-bezier(0.4, 0, 0.6, 1) infinite;
  }

  @keyframes late {
    50% {
      opacity: 0.5;
    }
  }

  /* Cristal: los esqueletos son contenido y van de material (libreta 4): el mismo latido, con un relleno blanco
     transparente sobre el material (en claro, oscuro transparente), un poco más que --chip para que se vea. */
  :global(:root[data-estilo='cristal'][data-tema='oscuro']) .esqueleto {
    background: var(--cristal-esqueleto);
  }

  :global(:root[data-estilo='cristal'][data-tema='claro']) .esqueleto {
    background: var(--cl-esqueleto);
  }

  @media (prefers-reduced-motion: reduce) {
    .esqueleto {
      animation: none;
    }
  }
</style>
