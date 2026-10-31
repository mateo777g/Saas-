<!--
  La barra de arriba, del color de Don Chuy (libreta 6, decidido el 20 de octubre de 2026): su logo,
  su nombre, la «i», si está abierto (con la hora del restaurante), ES / EN y, si puso su tipo de
  cambio, MXN / USD. La letra encima se pone sola oscura o blanca (estiloColor). Sin logo, va solo
  el nombre; sin horario, no dice si está abierto. El logo va solo, con sus esquinas suaves y sin
  marco (decidido en la prueba de Banderitas, el 31 de octubre de 2026).
-->
<script lang="ts">
  import { urlImagen } from '../lib/datos';
  import type { Moneda } from '../lib/preferencias';
  import type { Lengua, Textos } from '../lib/textos';
  import Icono from './Icono.svelte';

  let {
    nombre,
    logo,
    estado,
    abierto,
    lengua,
    moneda,
    conDolares,
    t,
    arriba,
    alLengua,
    alMoneda,
    alInfo,
  }: {
    nombre: string;
    logo: string | null;
    estado: string | null;
    abierto: boolean;
    lengua: Lengua;
    moneda: Moneda;
    conDolares: boolean;
    t: Textos;
    // Lo que deja arriba: la barra de estado del celular, o 14 en la tira de la ventana del color.
    arriba: string;
    alLengua: (l: Lengua) => void;
    alMoneda: (m: Moneda) => void;
    alInfo: () => void;
  } = $props();
</script>

<header class="barra" style:padding-top={arriba}>
  <div class="marca">
    {#if logo}
      <span class="logo"><img src={urlImagen(logo)} alt="" /></span>
    {/if}
    <h1 class="nombre">{nombre}</h1>
    <button type="button" class="redondo" aria-label={t.info} onclick={alInfo}><Icono nombre="info" tamano={19} /></button>
  </div>
  <div class="fila2">
    <span class="abierto" class:cerrado={!abierto}>
      {#if estado}<i></i>{estado}{/if}
    </span>
    <span class="par" role="group" aria-label={t.idioma}>
      <button type="button" aria-pressed={lengua === 'es'} onclick={() => alLengua('es')}>ES</button>
      <button type="button" aria-pressed={lengua === 'en'} onclick={() => alLengua('en')}>EN</button>
    </span>
    {#if conDolares}
      <span class="par" role="group" aria-label={t.moneda}>
        <button type="button" aria-pressed={moneda === 'mxn'} onclick={() => alMoneda('mxn')}>MXN</button>
        <button type="button" aria-pressed={moneda === 'usd'} onclick={() => alMoneda('usd')}>USD</button>
      </span>
    {/if}
  </div>
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
