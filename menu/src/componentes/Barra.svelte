<!--
  La barra de arriba, del color de Don Chuy (libreta 6, decidido el 20 de octubre de 2026): su logo,
  su nombre, la «i», si está abierto (con la hora del restaurante), el idioma y, si hay dólar del día,
  la moneda. La letra encima se pone sola oscura o blanca (estiloMenu). Sin logo, va solo el nombre;
  sin horario, no dice si está abierto. El logo va solo, sin marco (prueba de Banderitas, 31 de octubre
  de 2026), y desde «Tu menú en línea» no se achica a un cuadro: mide hasta 48 de alto y lo ancho que
  pida, hasta 190 (formas.css).

  Sus formas («Tu menú en línea», maqueta UDArhiEZceT7rmSKxqRA5r):
  - El logo a la izquierda (la de siempre), con o sin el nombre al lado; el idioma y la moneda como
    letras, el mundito o las monedas con su listita, o el cuadrito. Con carteles, la «i» y si está
    abierto se van al cartel; sin carteles se quedan aquí, como siempre.
  - El logo grande al centro, con la lupa a la izquierda (la búsqueda sale abajo de los carteles) y el
    engrane a la derecha, que abre Ajustes con el idioma y la moneda. Sin carteles, la «i» va junto a la
    lupa y si está abierto debajo del engrane.
-->
<script lang="ts">
  import { urlImagen } from '../lib/datos';
  import type { Formas } from '../lib/formas';
  import type { Moneda } from '../lib/preferencias';
  import type { Lengua, Textos } from '../lib/textos';
  import Cuadrito from './Cuadrito.svelte';
  import Icono from './Icono.svelte';
  import ListaBoton from './ListaBoton.svelte';

  let {
    nombre,
    logo,
    estado,
    abierto,
    lengua,
    moneda,
    conDolares,
    formas,
    conCarteles,
    t,
    arriba,
    lupaAbierta = false,
    ajustesAbierto = false,
    alLengua,
    alMoneda,
    alInfo,
    alLupa,
    alAjustes,
  }: {
    nombre: string;
    logo: string | null;
    estado: string | null;
    abierto: boolean;
    lengua: Lengua;
    moneda: Moneda;
    conDolares: boolean;
    formas: Formas;
    // Si salen carteles: entonces la «i» y si está abierto van en el cartel.
    conCarteles: boolean;
    t: Textos;
    // Lo que deja arriba: la barra de estado del celular, o 14 en la tira de la ventana del color.
    arriba: string;
    lupaAbierta?: boolean;
    ajustesAbierto?: boolean;
    alLengua: (l: Lengua) => void;
    alMoneda: (m: Moneda) => void;
    alInfo: () => void;
    alLupa?: () => void;
    alAjustes?: () => void;
  } = $props();

  const centro = $derived(formas.barra === 'centro');
  const sinNombre = $derived(!centro && !formas.con_nombre && !!logo);
  // «Abierto · cierra a las 23:00» en dos renglones, para la columna de la derecha con el logo al centro.
  const [estadoUno, estadoDos] = $derived((estado ?? '').split(' · '));

  const idiomas = $derived([
    { valor: 'es', texto: t.idiomas[0], bandera: 'mx' as const },
    { valor: 'en', texto: t.idiomas[1], bandera: 'us' as const },
  ]);
  const monedas = $derived([
    { valor: 'mxn', texto: t.monedas[0], bandera: 'mx' as const },
    { valor: 'usd', texto: t.monedas[1], bandera: 'us' as const },
  ]);
</script>

{#snippet info()}
  <button type="button" class="redondo" aria-label={t.info} onclick={alInfo}><Icono nombre="info" tamano={19} /></button>
{/snippet}

<header class="barra" class:f-centro={centro} class:f-sin-nombre={sinNombre} style:padding-top={arriba}>
  {#if centro}
    <div class="f-izq">
      <div class="f-izq-botones">
        <button type="button" class="f-lupa" aria-label={t.buscar} aria-expanded={lupaAbierta} onclick={alLupa}
          ><Icono nombre="buscar" tamano={21} grosor={1.9} /></button
        >
        {#if !conCarteles}{@render info()}{/if}
      </div>
    </div>
    <div class="f-medio" class:sin-logo={!logo}>
      {#if logo}<span class="logo"><img src={urlImagen(logo)} alt="" /></span>{/if}
    </div>
    <div class="f-der">
      <button type="button" class="f-engrane" aria-label={t.ajustes} aria-haspopup="dialog" aria-expanded={ajustesAbierto} onclick={alAjustes}
        ><Icono nombre="ajustes" tamano={21} /></button
      >
      {#if !conCarteles && estado}
        <span class="abierto" class:cerrado={!abierto}><i></i>{estadoUno}{#if estadoDos}<span class="f-segundo">{estadoDos}</span>{/if}</span>
      {/if}
    </div>
    {#if !logo || formas.con_nombre}<h1 class="nombre f-nombre-centro">{nombre}</h1>{/if}
  {:else}
    <div class="marca">
      {#if logo}
        <span class="logo"><img src={urlImagen(logo)} alt="" /></span>
      {/if}
      <h1 class="nombre">{nombre}</h1>
      {#if !conCarteles}{@render info()}{/if}
    </div>
    <div class="fila2" class:f-sin-abierto={conCarteles}>
      {#if !conCarteles}
        <span class="abierto" class:cerrado={!abierto}>
          {#if estado}<i></i>{estado}{/if}
        </span>
      {/if}
      {#if formas.idioma === 'planeta'}
        <ListaBoton opciones={idiomas} elegida={lengua} etiqueta={t.idioma} alElegir={(v) => alLengua(v as Lengua)}>
          {#snippet boton({ abierta, alternar })}
            <button type="button" class="f-idioma" aria-haspopup="listbox" aria-expanded={abierta} aria-label={t.idioma} onclick={alternar}>
              <Icono nombre="mundo" tamano={18} grosor={1.6} /><span>{lengua.toUpperCase()}</span>
            </button>
          {/snippet}
        </ListaBoton>
      {:else if formas.idioma === 'cuadro'}
        <Cuadrito
          letras={lengua === 'es' ? 'EN' : 'ES'}
          etiqueta={lengua === 'es' ? t.idiomas[1] : t.idiomas[0]}
          alTocar={() => alLengua(lengua === 'es' ? 'en' : 'es')}
        />
      {:else}
        <span class="par" role="group" aria-label={t.idioma}>
          <button type="button" aria-pressed={lengua === 'es'} onclick={() => alLengua('es')}>ES</button>
          <button type="button" aria-pressed={lengua === 'en'} onclick={() => alLengua('en')}>EN</button>
        </span>
      {/if}
      {#if conDolares}
        {#if formas.moneda === 'monedas'}
          <ListaBoton opciones={monedas} elegida={moneda} etiqueta={t.moneda} alElegir={(v) => alMoneda(v as Moneda)}>
            {#snippet boton({ abierta, alternar })}
              <button type="button" class="f-moneda" aria-haspopup="listbox" aria-expanded={abierta} aria-label={t.moneda} onclick={alternar}>
                <Icono nombre="monedas" tamano={20} grosor={1.3} /><span>{moneda.toUpperCase()}</span>
              </button>
            {/snippet}
          </ListaBoton>
        {:else if formas.moneda === 'cuadro'}
          <Cuadrito
            letras={moneda === 'mxn' ? 'USD' : 'MXN'}
            etiqueta={moneda === 'mxn' ? t.monedas[1] : t.monedas[0]}
            alTocar={() => alMoneda(moneda === 'mxn' ? 'usd' : 'mxn')}
          />
        {:else}
          <span class="par" role="group" aria-label={t.moneda}>
            <button type="button" aria-pressed={moneda === 'mxn'} onclick={() => alMoneda('mxn')}>MXN</button>
            <button type="button" aria-pressed={moneda === 'usd'} onclick={() => alMoneda('usd')}>USD</button>
          </span>
        {/if}
      {/if}
    </div>
  {/if}
</header>

<style>
  .barra {
    background: var(--m-barra);
    color: var(--m-sobre-barra);
    padding: 50px 16px 14px;
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .marca {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .logo {
    height: 48px;
    width: 48px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  /* Cabe en los 48 px con su forma, y sus esquinas se redondean. */
  .logo img {
    max-width: 100%;
    max-height: 100%;
    border-radius: 14px;
  }

  .nombre {
    flex: 1;
    min-width: 0;
    margin: 0;
    font-size: 19px;
    font-weight: 800;
    letter-spacing: -0.4px;
    line-height: 1.2;
  }

  .redondo {
    width: 40px;
    height: 40px;
    flex: none;
    border-radius: 20px;
    border: 0;
    background: var(--m-barra-chip);
    color: var(--m-sobre-barra);
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0;
  }

  .fila2 {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .abierto {
    flex: 1;
    min-width: 0;
    display: flex;
    align-items: center;
    gap: 7px;
    font-size: 12.5px;
    font-weight: 600;
    color: var(--m-barra-suave);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .abierto i {
    width: 7px;
    height: 7px;
    border-radius: 4px;
    background: #4cc26f;
    flex: none;
  }

  .abierto.cerrado i {
    background: var(--m-barra-suave);
  }

  .par {
    display: flex;
    padding: 2px;
    border-radius: 9px;
    background: var(--m-barra-chip);
    flex: none;
  }

  .par button {
    height: 26px;
    min-width: 34px;
    padding: 0 8px;
    border: 0;
    border-radius: 7px;
    background: transparent;
    color: var(--m-barra-suave);
    font-family: var(--mono);
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.04em;
  }

  .par button[aria-pressed='true'] {
    background: var(--m-sobre-barra);
    color: var(--m-barra);
  }
</style>
