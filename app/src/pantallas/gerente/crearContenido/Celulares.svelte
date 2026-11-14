<!--
  El formato en tres celulares (Crear anuncios por pasos, 13 nov 2026, encuestas 3 a 5 de
  planes/trabajo/rediseno/crear-anuncios.md; acomodados como «Phone Mockups 1» de solaceui, con el iPhone de la maqueta
  del menú digital): el del centro es el formato elegido, grande y adelante; los otros dos detrás, asomándose. Al picar
  uno de un lado pasa al centro con el resorte del dock y el del centro se hace a un lado. Dentro de cada uno, la
  muestra del estilo elegido en su formato, con su etiqueta «Muestra»: el post y la historia en una pantalla parecida a
  la de Instagram (sin su logo; la cuenta es el restaurante), y el cartel en un menú en línea sencillo con el color del
  restaurante. Lo demás de cada pantalla va en gris: no es el anuncio. Abajo, el nombre y la medida del elegido.
-->
<script lang="ts">
  import { fade } from 'svelte/transition';
  import { esClaro } from '../../../lib/color';
  import { FORMATOS, formatoDe, type EstiloDeHoy, type Formato } from '../../../lib/crearContenido';
  import { urlFoto } from '../../../lib/fotos';
  import Celular from './Celular.svelte';

  let {
    formato,
    estilo,
    nombre,
    color,
    alElegir,
  }: {
    formato: Formato;
    estilo: EstiloDeHoy | null;
    // La cuenta del post y la historia, y la barra del cartel: el nombre y el color del restaurante.
    nombre: string;
    color: string | null;
    alElegir: (formato: Formato) => void;
  } = $props();

  // Dónde va cada uno: el elegido al centro; los otros dos, en su orden, a la izquierda y a la derecha.
  const lugares = $derived.by(() => {
    const otros = FORMATOS.filter((f) => f.valor !== formato).map((f) => f.valor);
    return { [formato]: 'centro', [otros[0]]: 'izquierda', [otros[1]]: 'derecha' } as Record<Formato, 'centro' | 'izquierda' | 'derecha'>;
  });
  const elegido = $derived(formatoDe(formato));
  const inicial = $derived(nombre.trim().charAt(0).toUpperCase() || '·');
  const fondo = $derived(color ?? '#121212');
  const letra = $derived(esClaro(fondo) ? '#111111' : '#ffffff');
  const muestra = (f: Formato) => (estilo ? urlFoto(estilo.muestras[f]) : null);
</script>

{#snippet avatar(tam: number)}
  <span class="avatar" style:width="{tam}px" style:height="{tam}px" style:background={fondo} style:color={letra}>{inicial}</span>
{/snippet}

{#snippet imagen(f: Formato, clase: string)}
  {@const url = muestra(f)}
  <span class="imagen {clase}" style:background-image={url ? `url(${url})` : undefined}>
    <span class="etiqueta-muestra">Muestra</span>
  </span>
{/snippet}

<div class="celulares">
  <div class="escenario">
    {#each FORMATOS as f (f.valor)}
      {@const lugar = lugares[f.valor]}
      <button
        type="button"
        class="cel {lugar}"
        aria-pressed={lugar === 'centro'}
        aria-label="{f.texto} · {f.medida}"
        onclick={() => lugar !== 'centro' && alElegir(f.valor)}
      >
        {#if f.valor === 'post'}
          <Celular>
            <div class="pantalla-cel">
              <div class="ig-cabeza">{@render avatar(30)}<b class="cuenta">{nombre}</b><span class="puntos">···</span></div>
              {@render imagen('post', 'post')}
              <div class="ig-acciones">
                <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10z" /></svg>
                <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 12a8 8 0 0 1-11.6 7.1L4 20l1-4.2A8 8 0 1 1 20 12z" /></svg>
                <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M21 4 10 14" /><path d="M21 4l-7 17-4-7-7-4z" /></svg>
                <span class="crece"></span>
                <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 4h12v17l-6-4-6 4z" /></svg>
              </div>
              <div class="renglones"><span style:width="72%"></span><span style:width="46%"></span></div>
              <div class="ig-abajo" aria-hidden="true">
                <svg viewBox="0 0 24 24"><path d="M4 11l8-7 8 7v9h-5v-6H9v6H4z" /></svg>
                <svg viewBox="0 0 24 24"><circle cx="11" cy="11" r="6.5" /><path d="M16 16l4.5 4.5" /></svg>
                <svg viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="16" rx="4" /><path d="M12 8.5v7M8.5 12h7" /></svg>
                <svg viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="16" rx="4" /><path d="M10.5 9.5v5l4-2.5z" /></svg>
                {@render avatar(22)}
              </div>
            </div>
          </Celular>
        {:else if f.valor === 'historia'}
          <Celular oscura>
            <div class="pantalla-cel historia">
              {@render imagen('historia', 'historia')}
              <div class="hi-arriba">
                <div class="hi-barras"><span class="llena"></span><span></span></div>
                <div class="hi-cuenta">{@render avatar(26)}<b class="cuenta">{nombre}</b></div>
              </div>
              <div class="hi-abajo"><span class="hi-mensaje"></span>
                <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10z" /></svg>
                <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M21 4 10 14" /><path d="M21 4l-7 17-4-7-7-4z" /></svg>
              </div>
            </div>
          </Celular>
        {:else}
          <Celular colorReloj={letra}>
            <div class="pantalla-cel menu">
              <div class="me-barra" style:background={fondo} style:color={letra}>
                <span class="me-logo" style:color={fondo} style:background={letra}>{inicial}</span><b class="cuenta">{nombre}</b>
              </div>
              {@render imagen('cartel', 'cartel')}
              <span class="me-buscar"></span>
              <div class="me-categorias"><span class="activa" style:background={fondo}></span><span></span><span></span></div>
              {#each [64, 52, 70] as largo (largo)}
                <div class="me-producto"><span class="me-foto"></span><span class="me-textos"><span style:width="{largo}%"></span><span style:width="30%"></span></span></div>
              {/each}
            </div>
          </Celular>
        {/if}
      </button>
    {/each}
  </div>
  {#key formato}
    <p class="elegido" in:fade={{ duration: 250 }}><b>{elegido.texto}</b><span class="medida">{elegido.medida}</span></p>
  {/key}
  <p class="toca">Pica otro celular para cambiar el formato.</p>
</div>

<style>
  .celulares {
    display: flex;
    flex-direction: column;
    align-items: center;
  }

  /* El del centro a 0.8 (300 × 600); los de los lados a 0.64, centrados en su alto y a 175 del centro. */
  .escenario {
    position: relative;
    width: 590px;
    height: 600px;
  }

  .cel {
    --x: 0px;
    --y: 0px;
    --s: 0.8;
    --levanta: 0px;
    position: absolute;
    left: 50%;
    top: 0;
    width: 375px;
    height: 750px;
    margin: 0 0 0 -187.5px;
    padding: 0;
    border: 0;
    background: transparent;
    transform-origin: top center;
    transform: translate(var(--x), calc(var(--y) + var(--levanta))) scale(var(--s));
    transition: transform 0.65s var(--resorte-sube);
    cursor: pointer;
    text-align: left;
    -webkit-tap-highlight-color: transparent;
  }

  .cel.centro {
    z-index: 3;
    cursor: default;
  }

  .cel.izquierda,
  .cel.derecha {
    --s: 0.64;
    --y: 60px;
    z-index: 1;
  }

  .cel.izquierda {
    --x: -175px;
  }

  .cel.derecha {
    --x: 175px;
  }

  .cel.izquierda:hover,
  .cel.derecha:hover {
    --levanta: -8px;
  }

  .cel:focus-visible {
    outline: none;
  }

  .cel:focus-visible :global(.tel) {
    box-shadow: 0 0 0 3px var(--campo-aro);
  }

  /* ─── Lo de adentro (322 × 702) ─── */
  .pantalla-cel {
    position: absolute;
    inset: 0;
    display: flex;
    flex-direction: column;
    padding-top: 50px;
  }

  .cuenta {
    min-width: 0;
    font-size: 13px;
    font-weight: 700;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .avatar {
    flex: none;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 12px;
    font-weight: 800;
  }

  .imagen {
    position: relative;
    flex: none;
    display: block;
    background: #000000 center / cover no-repeat;
  }

  .etiqueta-muestra {
    position: absolute;
    left: 10px;
    top: 10px;
    padding: 3px 7px;
    border-radius: 6px;
    background: rgba(0, 0, 0, 0.55);
    color: #ffffff;
    font: 600 10px var(--jakarta);
    letter-spacing: 0.02em;
  }

  svg {
    width: 22px;
    height: 22px;
    flex: none;
    fill: none;
    stroke: currentColor;
    stroke-width: 1.7;
    stroke-linecap: round;
    stroke-linejoin: round;
  }

  .crece {
    flex-grow: 1;
  }

  /* El post */
  .ig-cabeza {
    height: 50px;
    display: flex;
    align-items: center;
    gap: 9px;
    padding: 0 12px;
  }

  .puntos {
    margin-left: auto;
    font-weight: 800;
    letter-spacing: 1px;
  }

  .imagen.post {
    width: 100%;
    aspect-ratio: 4 / 5;
  }

  .ig-acciones {
    height: 46px;
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 0 12px;
  }

  .renglones {
    display: flex;
    flex-direction: column;
    gap: 7px;
    padding: 2px 12px;
  }

  .renglones span,
  .me-textos span {
    height: 8px;
    border-radius: 4px;
    background: var(--chip);
  }

  .ig-abajo {
    margin-top: auto;
    height: 64px;
    padding: 0 22px 14px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    border-top: 1px solid var(--linea);
  }

  /* La historia */
  .imagen.historia {
    width: 100%;
    aspect-ratio: 9 / 16;
    border-radius: 10px;
    overflow: hidden;
  }

  .imagen.historia .etiqueta-muestra {
    top: auto;
    bottom: 12px;
  }

  .hi-arriba {
    position: absolute;
    left: 0;
    right: 0;
    top: 58px;
    padding: 0 10px;
    display: flex;
    flex-direction: column;
    gap: 10px;
    color: #ffffff;
  }

  .hi-barras {
    display: flex;
    gap: 4px;
  }

  .hi-barras span {
    flex: 1;
    height: 2.5px;
    border-radius: 2px;
    background: rgba(255, 255, 255, 0.4);
  }

  .hi-barras .llena {
    background: #ffffff;
  }

  .hi-cuenta {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .hi-abajo {
    margin-top: auto;
    height: 72px;
    padding: 0 14px 16px;
    display: flex;
    align-items: center;
    gap: 14px;
    color: #ffffff;
  }

  .hi-mensaje {
    flex: 1;
    height: 40px;
    border-radius: 20px;
    border: 1px solid rgba(255, 255, 255, 0.5);
  }

  /* El cartel, en un menú en línea sencillo */
  .pantalla-cel.menu {
    padding-top: 0;
  }

  .me-barra {
    flex: none;
    height: 104px;
    padding: 50px 14px 0;
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .me-logo {
    width: 34px;
    height: 34px;
    flex: none;
    border-radius: 10px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 14px;
    font-weight: 800;
  }

  .imagen.cartel {
    margin: 14px 12px 0;
    aspect-ratio: 16 / 9;
    border-radius: 14px;
    overflow: hidden;
  }

  .me-buscar {
    flex: none;
    height: 36px;
    margin: 14px 12px 0;
    border-radius: 18px;
    background: var(--chip);
  }

  .me-categorias {
    display: flex;
    gap: 8px;
    padding: 14px 12px 4px;
  }

  .me-categorias span {
    width: 64px;
    height: 26px;
    border-radius: 13px;
    background: var(--chip);
  }

  .me-categorias .activa {
    opacity: 0.85;
  }

  .me-producto {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 10px 12px;
  }

  .me-foto {
    width: 60px;
    height: 60px;
    flex: none;
    border-radius: 10px;
    background: var(--chip);
  }

  .me-textos {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  /* Abajo, el elegido */
  .elegido {
    margin: 18px 0 0;
    display: flex;
    align-items: baseline;
    gap: 10px;
    font-size: 14px;
  }

  .elegido b {
    font-weight: 700;
  }

  .medida {
    font-family: var(--mono);
    font-size: 12px;
    color: var(--tenue);
  }

  .toca {
    margin: 4px 0 0;
    font-size: 12px;
    font-weight: 500;
    color: var(--tenue);
  }

  @media (prefers-reduced-motion: reduce) {
    .cel {
      transition: none;
    }
  }
</style>
