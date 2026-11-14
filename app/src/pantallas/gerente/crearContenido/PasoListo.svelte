<!--
  El anuncio de Crear anuncios (fue el paso 3, «Listo», 13 nov 2026; sale de Resultado.svelte, la tarjeta de la derecha
  de la 7b-1). Desde el 14 nov 2026 (detalle 4 de planes/trabajo/rediseno/crear-anuncios.md) va en el paso 2, en el
  lugar de los celulares: con la forma de su formato, la rejilla de puntitos con su pastilla de segundos mientras se hace
  (Cargador, tal cual); cuando sale, tu anuncio de borroso a nítido ahí mismo; si no salió, por qué y que no contó.
  Debajo, su medida y el pie que era de «Lo que pediste» («Puedes salir…» / «Guardado en Mi biblioteca»). «Lo que
  pediste» se fue: la izquierda del paso 2 ya lo dice. Los botones (Otra vez, Descargar, Ponerlo en mi menú) van en la
  barra de abajo de la vista.
-->
<script module lang="ts">
  import type { Formato } from '../../../lib/crearContenido';

  export type LoQueSeVe =
    | { fase: 'vacio' }
    | { fase: 'haciendo'; formato: Formato; nombres: string; desde: number }
    | { fase: 'listo'; formato: Formato; id: number; ruta: string }
    | { fase: 'fallo'; formato: Formato; motivo: 'rechazado' | 'no_salio' | 'cerrada' };
</script>

<script lang="ts">
  import CajaError from '../../../diseno/CajaError.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import { formatoDe } from '../../../lib/crearContenido';
  import { urlFoto } from '../../../lib/fotos';
  import Cargador from './Cargador.svelte';

  let {
    se,
    lugar,
  }: {
    se: LoQueSeVe;
    // El ancho y el alto que tiene, en el lugar de los celulares, entre el título y la barra de abajo.
    lugar: [number, number];
  } = $props();

  // Grande: 600 de alto (el cartel, 720 de ancho). Si no alcanza (los 590 de los celulares, una laptop de 768 de alto),
  // se achica lo justo para caber con su medida y su pie abajo, sin deslizar.
  const GRANDE: Record<Formato, [number, number]> = { post: [480, 600], historia: [338, 600], cartel: [720, 405] };
  const ABAJO = 80;

  const formato = $derived(se.fase === 'vacio' ? 'post' : se.formato);
  const f = $derived(formatoDe(formato));
  const escala = $derived.by(() => {
    const [w, h] = lugar;
    if (!w || !h) return 1;
    const [a, b] = GRANDE[formato];
    return Math.max(0.5, Math.min(1, w / a, (h - ABAJO) / b));
  });
  const ancho = $derived(Math.round(GRANDE[formato][0] * escala));
  const alto = $derived(Math.round(GRANDE[formato][1] * escala));

  function textoDelFallo(motivo: 'rechazado' | 'no_salio' | 'cerrada'): string {
    if (motivo === 'rechazado') return 'OpenAI no aceptó este anuncio. Cambia el mensaje e inténtalo otra vez.';
    if (motivo === 'cerrada') return 'Tu último anuncio no se pudo hacer. No contó.';
    return 'No se pudo hacer tu anuncio. Inténtalo otra vez.';
  }
</script>

<div class="paso-listo">
  <div class="zona">
    {#if se.fase === 'haciendo'}
      <div class="marco haciendo" style:width="{ancho}px" style:height="{alto}px">
        <Cargador desde={se.desde} />
      </div>
    {:else if se.fase === 'listo'}
      {#key se.id}
        <div class="marco listo" style:width="{ancho}px" style:height="{alto}px">
          <img src={urlFoto(se.ruta)} alt="Tu anuncio" />
        </div>
      {/key}
    {:else if se.fase === 'fallo'}
      <div class="marco vacio" style:width="{ancho}px" style:height="{alto}px">
        <div class="centro">
          <CajaError mensaje={textoDelFallo(se.motivo)} compacta />
          {#if se.motivo !== 'cerrada'}<span class="chico">No contó.</span>{/if}
        </div>
      </div>
    {/if}
    <p class="medida">{f.texto} · <span class="mono">{f.medida}</span></p>
    {#if se.fase === 'haciendo' || se.fase === 'listo'}
      <p class="pie">
        {#if se.fase === 'haciendo'}
          <Icono nombre="info" tamano={16} /><span>Puedes salir: se sigue haciendo y te queda en Mi biblioteca.</span>
        {:else}
          <span class="verde"><Icono nombre="check-fino" tamano={16} /></span><span class="fuerte">Guardado en Mi biblioteca</span>
        {/if}
      </p>
    {/if}
  </div>
</div>

<style>
  .paso-listo {
    display: flex;
    justify-content: center;
  }

  .zona {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 14px;
  }

  .marco {
    position: relative;
    flex: none;
    border-radius: 18px;
    overflow: hidden;
  }

  .marco.vacio {
    border: 1.5px dashed var(--linea-fuerte);
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 24px;
  }

  .marco.haciendo {
    background: var(--solido);
    border: 1px solid var(--borde-tarjeta);
    color: var(--texto);
  }

  /* Cuando sale: de borroso a nítido y de un poco grande a su tamaño (el de la 7b). */
  .marco.listo {
    background: #111111;
    box-shadow: 0 12px 32px var(--sombra-anuncio);
    animation: aparecer 700ms cubic-bezier(0.23, 1, 0.32, 1) both;
  }

  @keyframes aparecer {
    from {
      opacity: 0;
      transform: scale(1.06);
      filter: blur(24px);
    }
  }

  .marco.listo img {
    display: block;
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .centro {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 10px;
    text-align: center;
  }

  .centro .chico {
    font-size: 12px;
    color: var(--tenue);
  }

  .centro :global(.caja) {
    text-align: left;
  }

  .medida {
    margin: 0;
    font-size: 13px;
    font-weight: 600;
  }

  .mono {
    font-family: var(--mono);
    font-weight: 400;
    font-size: 12px;
    color: var(--tenue);
  }

  /* El pie que era de «Lo que pediste», debajo de la medida y de su ancho. */
  .pie {
    align-self: stretch;
    margin: 0;
    display: flex;
    align-items: flex-start;
    justify-content: center;
    gap: 9px;
    padding-top: 12px;
    border-top: 1px solid var(--linea);
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .pie :global(svg) {
    flex: none;
    margin-top: 1px;
  }

  .verde {
    display: flex;
    color: var(--verde);
  }

  .fuerte {
    font-size: 12.5px;
    font-weight: 600;
    color: var(--texto);
  }

  @media (prefers-reduced-motion: reduce) {
    .marco.listo {
      animation: none;
    }
  }
</style>
