<!--
  El paso 3 de Crear anuncios, «Listo» (13 nov 2026, encuestas 6 a 8 de planes/trabajo/rediseno/crear-anuncios.md; sale
  de Resultado.svelte, la tarjeta de la derecha de la 7b-1): grande al centro, con la forma de su formato, la rejilla de
  puntitos con su pastilla de segundos mientras se hace (Cargador, tal cual); cuando sale, tu anuncio de borroso a
  nítido ahí mismo; si no salió, por qué y que no contó. A un lado, «Lo que pediste»: lo que dice Postgres del anuncio
  (sus productos con su fotito, el formato, el estilo con su muestra, el color, tu mensaje y lo que irá en él), así se
  ve igual al volver a la vista o si lo hizo otro gerente. Los botones (Otra vez, Descargar, Ponerlo en mi menú) van en
  la barra de abajo de la vista.
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
  import {
    datosQueVan,
    formatoDe,
    type EstiloDeHoy,
    type ProductoDelMenu,
    type RestauranteDelAnuncio,
    type Resultado,
  } from '../../../lib/crearContenido';
  import { urlFoto } from '../../../lib/fotos';
  import Cargador from './Cargador.svelte';

  let {
    se,
    pedido,
    productos,
    estilo,
    restaurante,
    lugar,
  }: {
    se: LoQueSeVe;
    // El anuncio que se enseña, como lo guardó Postgres.
    pedido: Resultado | null;
    // Los del menú: de aquí salen las fotitos y los precios.
    productos: ProductoDelMenu[];
    // Su estilo, si hoy todavía sale.
    estilo: EstiloDeHoy | null;
    restaurante: RestauranteDelAnuncio | null;
    // El ancho y el alto que tiene el paso 3 entre las dos barras.
    lugar: [number, number];
  } = $props();

  // Grande al centro: 600 de alto (el cartel, 720 de ancho). Si la pantalla no alcanza (una laptop de 768 de alto), se
  // achica lo justo para caber con su medida abajo y «Lo que pediste» a un lado, sin deslizar.
  const GRANDE: Record<Formato, [number, number]> = { post: [480, 600], historia: [338, 600], cartel: [720, 405] };
  const LADO = 300 + 40;
  const ABAJO = 32;

  const formato = $derived(se.fase === 'vacio' ? (pedido?.formato ?? 'post') : se.formato);
  const f = $derived(formatoDe(formato));
  const escala = $derived.by(() => {
    const [w, h] = lugar;
    if (!w || !h) return 1;
    const [a, b] = GRANDE[formato];
    return Math.max(0.5, Math.min(1, (w - (pedido ? LADO : 0)) / a, (h - ABAJO) / b));
  });
  const ancho = $derived(Math.round(GRANDE[formato][0] * escala));
  const alto = $derived(Math.round(GRANDE[formato][1] * escala));

  const suyos = $derived(
    (pedido?.productos ?? []).map((p) => productos.find((m) => m.id === p.id) ?? { id: p.id, nombre: p.nombre, imagen_ruta: null }),
  );
  const color = $derived(pedido?.color ?? restaurante?.color ?? null);
  const palabras = $derived(Object.values(pedido?.palabras ?? {}).filter((p) => p.trim() !== ''));
  const datos = $derived.by(() => {
    if (!estilo || !restaurante || !pedido) return [];
    const van = pedido.productos.map((p) => productos.find((m) => m.id === p.id)).filter((p) => p !== undefined);
    return datosQueVan(estilo, pedido.formato, restaurante, van);
  });

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
  </div>

  {#if pedido}
    <aside class="pedido" aria-label="Lo que pediste">
      <span class="etq">Lo que pediste</span>

      <div class="grupo">
        <span class="nombre-grupo">{suyos.length === 1 ? 'Producto' : 'Productos'}</span>
        {#each suyos as p, i (p.id)}
          <div class="producto">
            <span class="numero">{i + 1}</span>
            <span class="foto" style:background-image={p.imagen_ruta ? `url(${urlFoto(p.imagen_ruta)})` : undefined}></span>
            <span class="texto-largo">{p.nombre}</span>
          </div>
        {/each}
      </div>

      <div class="renglon"><span class="nombre-grupo">Formato</span><span class="valor">{f.texto}</span></div>
      <div class="renglon">
        <span class="nombre-grupo">Estilo</span>
        <span class="valor">
          {#if estilo}<span class="mini" style:background-image="url({urlFoto(estilo.muestras.post)})"></span>{estilo.nombre}{:else}Ya no sale hoy{/if}
        </span>
      </div>
      {#if estilo?.color}
        <div class="renglon">
          <span class="nombre-grupo">Color</span>
          <span class="valor">
            {#if color}<span class="gota" style:background={color}></span><span class="mono">{color}</span>{:else}Los de tu estilo{/if}
          </span>
        </div>
      {/if}
      {#if pedido.mensaje || (estilo && estilo.mensaje > 0)}
        <div class="grupo">
          <span class="nombre-grupo">Tu mensaje</span>
          <span class="mensaje" class:vacio={!pedido.mensaje}>{pedido.mensaje || 'Sin mensaje: lo escoge tu estilo.'}</span>
        </div>
      {/if}
      {#if palabras.length || datos.length}
        <div class="grupo">
          <span class="nombre-grupo">Irá en el anuncio</span>
          {#if palabras.length}
            <div class="palabras">{#each palabras as p, i (i)}<span class="palabra">{p}</span>{/each}</div>
          {/if}
          {#if datos.length}<span class="datos">{datos.join(' · ')}</span>{/if}
        </div>
      {/if}

      <div class="pie-pedido">
        {#if se.fase === 'haciendo'}
          <Icono nombre="info" tamano={16} /><span>Puedes salir: se sigue haciendo y te queda en Mi biblioteca.</span>
        {:else if se.fase === 'listo'}
          <span class="verde"><Icono nombre="check-fino" tamano={16} /></span><span class="fuerte">Guardado en Mi biblioteca</span>
        {/if}
      </div>
    </aside>
  {/if}
</div>

<style>
  .paso-listo {
    min-height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 40px;
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

  /* «Lo que pediste»: una tarjeta del panel (blanca, su borde, 14), que sale de un lado con el rebote. */
  .pedido {
    width: 300px;
    flex: none;
    align-self: center;
    padding: 18px 20px;
    background: var(--solido);
    border: 1px solid var(--borde-tarjeta);
    border-radius: 14px;
    display: flex;
    flex-direction: column;
    animation: entra 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275) both;
  }

  @keyframes entra {
    from {
      opacity: 0;
      transform: translateX(16px);
    }
  }

  .etq {
    font-family: var(--mono);
    font-size: 10.5px;
    letter-spacing: 0.14em;
    color: var(--tenue);
    text-transform: uppercase;
    padding-bottom: 6px;
  }

  .grupo,
  .renglon {
    padding: 11px 0;
    border-top: 1px solid var(--linea);
  }

  .grupo {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .renglon {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .nombre-grupo {
    font-size: 12px;
    font-weight: 500;
    color: var(--tenue);
  }

  .valor {
    margin-left: auto;
    min-width: 0;
    display: inline-flex;
    align-items: center;
    gap: 8px;
    font-size: 13px;
    font-weight: 600;
  }

  .producto {
    display: flex;
    align-items: center;
    gap: 10px;
    min-width: 0;
  }

  .numero {
    width: 20px;
    height: 20px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 6px;
    background: var(--chip);
    font: 500 10.5px var(--mono);
    color: var(--suave);
  }

  /* Sin foto, el cuadro negro (como sin-foto.png de Flet). */
  .foto {
    width: 32px;
    height: 32px;
    flex: none;
    border-radius: 8px;
    background: #000000 center / cover no-repeat;
  }

  .texto-largo {
    min-width: 0;
    font-size: 13px;
    font-weight: 600;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .mini {
    width: 20px;
    height: 25px;
    flex: none;
    border-radius: 5px;
    background: #000000 center / cover no-repeat;
  }

  .gota {
    width: 16px;
    height: 16px;
    flex: none;
    border-radius: 5px;
    box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.12);
  }

  .mensaje {
    font-size: 13px;
    font-weight: 600;
    line-height: 1.4;
    overflow-wrap: anywhere;
  }

  .mensaje.vacio {
    color: var(--tenue);
    font-weight: 500;
  }

  .palabras {
    display: flex;
    flex-wrap: wrap;
    gap: 5px;
  }

  .palabra {
    height: 24px;
    display: inline-flex;
    align-items: center;
    padding: 0 8px;
    border-radius: 7px;
    background: var(--chip);
    font-size: 11px;
    font-weight: 700;
    letter-spacing: 0.02em;
  }

  .datos {
    font-size: 12.5px;
    font-weight: 600;
    line-height: 1.45;
    color: var(--suave);
  }

  .pie-pedido {
    display: flex;
    align-items: flex-start;
    gap: 9px;
    padding-top: 12px;
    border-top: 1px solid var(--linea);
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .pie-pedido:empty {
    display: none;
  }

  .pie-pedido :global(svg) {
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
    .marco.listo,
    .pedido {
      animation: none;
    }
  }
</style>
