<!--
  La tarjeta de lealtad dibujada (la tarjeta de lealtad, maqueta v22 aprobada el 23 nov 2026): la misma en el menú, en Tu
  tarjeta del panel y en el cobro. Al frente, qué es, lo juntado (los sellos en círculos o los puntos con su barra) y lo que
  falta; atrás, el logo y el nombre del restaurante, su nombre, su número, el código corto y su QR (la llave del celular),
  en su cuadro blanco para que se lea. Un toque la voltea con el rebote de lo que se abre. Su fondo lo pinta
  lib/tarjetaFondo.ts una vez por color y estilo; Agua mueve su agua y Metal y Brillante cruzan su destello al tocarlos.
  Sin `atras` va quieta (la muestra, la de «Saca tu tarjeta»). Los textos llegan hechos (español o inglés): la tarjeta no
  traduce ni cuenta dinero.
-->
<script module lang="ts">
  export type EstiloTarjeta = 'liquido' | 'agua' | 'metal' | 'brillante' | 'liso' | 'olas';

  export type TextosTarjeta = {
    etq: string; // TARJETA DE LEALTAD
    premioListo: string; // Premio listo
    de: string; // de
    puntos: string; // puntos
    yaJuntaste: string; // ¡Ya lo juntaste!
    faltan: (n: number) => string; // Te faltan 2 para tu Gringa
    teEspera: string; // Tu Gringa te espera
    voltear: string; // Tu tarjeta: tócala para voltearla
    sub: string; // Tarjeta de lealtad
    sinCamara: string; // Sin cámara, diles este código
    qr: string; // Código QR de tu tarjeta
  };

  export type AtrasTarjeta = {
    restaurante: string;
    logo: string | null; // la URL del logo
    titular: string;
    telefono: string; // 10 dígitos
    codigo: string; // el código corto, 8 letras y números
    llave: string; // lo que lleva el QR
  };

  // Cuántas columnas llevan los sellos (de 2 a 20): uno o dos renglones hasta 14, tres después.
  export function columnasDeSellos(meta: number): number {
    if (meta <= 5) return meta;
    if (meta <= 14) return Math.ceil(meta / 2);
    return Math.ceil(meta / 3);
  }

  const escrito = (t: string) => t.replace(/(\d{3})(\d{3})(\d{4})/, '$1 $2 $3');
  const enDos = (c: string) => (c.length === 8 ? `${c.slice(0, 4)} ${c.slice(4)}` : c);
</script>

<script lang="ts">
  import { encode } from 'uqr';
  import { destelloTarjeta, pintarTarjeta, vigilarAguaViva } from '../lib/tarjetaFondo';
  import './tarjetaLealtad.css';

  let {
    estilo,
    color,
    forma,
    meta,
    saldo,
    premioListo,
    t,
    atras = null,
    llega = false,
    volteada = $bindable(false),
  }: {
    estilo: EstiloTarjeta;
    color: string;
    forma: 'sellos' | 'puntos';
    meta: number;
    saldo: number;
    premioListo: boolean;
    t: TextosTarjeta;
    atras?: AtrasTarjeta | null;
    // Recién sacada o pasada a este celular: entra volteada y gira al frente.
    llega?: boolean;
    volteada?: boolean;
  } = $props();

  let raiz = $state<HTMLElement>();
  let tarjeta = $state<HTMLElement>();

  // El fondo: una vez por color y estilo (se guarda en su caché).
  $effect(() => {
    if (raiz) pintarTarjeta(raiz, color, estilo, false);
  });
  $effect(() => {
    if (estilo !== 'agua') return;
    return vigilarAguaViva();
  });

  const llenos = $derived(Math.min(saldo, meta));
  const faltan = $derived(Math.max(0, meta - saldo));
  const qr = $derived(atras ? encode(atras.llave, { ecc: 'M', border: 0 }) : null);
  const trazo = $derived(
    qr ? qr.data.flatMap((fila, y) => fila.map((negro, x) => (negro ? `M${x} ${y}h1v1h-1z` : ''))).join('') : '',
  );

  function alTocar() {
    if (!atras) return;
    volteada = !volteada;
  }
</script>

{#snippet frente()}
  <div class="tl-cara tl-frente">
    <div class="tl-arriba">
      <span class="tl-etq">{t.etq}</span>
      <span class="tl-crece-t"></span>
      {#if premioListo}
        <span class="tl-listo"
          ><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"
            ><rect x="3.5" y="8" width="17" height="4" rx="1"></rect><path d="M5 12v7.5h14V12"></path><path d="M12 8v11.5"></path><path
              d="M12 8c-1.5-3.5-5.5-3.5-5.5-1S10 8 12 8zM12 8c1.5-3.5 5.5-3.5 5.5-1S14 8 12 8z"
            ></path></svg
          >{t.premioListo}</span
        >
      {/if}
    </div>
    {#if forma === 'sellos'}
      <div class="tl-sellos" class:muchos={meta > 14} style:--tl-columnas={columnasDeSellos(meta)}>
        {#each { length: meta } as _, i (i)}
          <span class="tl-sello" class:lleno={i < llenos} class:premio={i === meta - 1}>
            {#if i < llenos}
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"
                ><path d="M5 12.5l4.5 4.5L19 7.5"></path></svg
              >
            {:else if i === meta - 1}
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"
                ><rect x="3.5" y="8" width="17" height="4" rx="1"></rect><path d="M5 12v7.5h14V12"></path><path d="M12 8v11.5"></path><path
                  d="M12 8c-1.5-3.5-5.5-3.5-5.5-1S10 8 12 8zM12 8c1.5-3.5 5.5-3.5 5.5-1S14 8 12 8z"
                ></path></svg
              >
            {/if}
          </span>
        {/each}
      </div>
      <div class="tl-abajo">
        <b>{llenos} {t.de} {meta}</b><span>{premioListo ? t.teEspera : t.faltan(faltan)}</span>
      </div>
    {:else}
      <div class="tl-puntos">
        <div class="tl-puntos-n"><b>{saldo.toLocaleString('en-US')}</b><span>{t.puntos}</span></div>
        <div class="tl-barra"><i style:width="{Math.min(100, (saldo / meta) * 100)}%"></i></div>
      </div>
      <div class="tl-abajo">
        <b>{premioListo ? t.yaJuntaste : `${saldo.toLocaleString('en-US')} ${t.de} ${meta.toLocaleString('en-US')}`}</b><span
          >{premioListo ? t.teEspera : t.faltan(faltan)}</span
        >
      </div>
    {/if}
    <span class="tl-destello" aria-hidden="true"></span>
  </div>
{/snippet}

<div class="tl-pinta" bind:this={raiz}>
  {#if atras}
    <button
      type="button"
      class="tl-tarjeta"
      class:llega
      data-volteada={volteada}
      aria-label={t.voltear}
      aria-pressed={volteada}
      bind:this={tarjeta}
      onclick={alTocar}
      onpointerdown={() => tarjeta && destelloTarjeta(tarjeta)}
      onpointerenter={(e) => e.pointerType !== 'touch' && tarjeta && destelloTarjeta(tarjeta)}
    >
      <span class="tl-gira">
        {@render frente()}
        <div class="tl-cara tl-atras">
          <div class="tl-at-arriba">
            <span class="tl-at-logo">{#if atras.logo}<img alt="" src={atras.logo} />{/if}</span>
            <span class="tl-at-nombres"><b>{atras.restaurante}</b><span>{t.sub}</span></span>
          </div>
          <div class="tl-at-abajo">
            <div class="tl-datos">
              <b class="tl-titular">{atras.titular}</b>
              <span class="tl-tel">{escrito(atras.telefono)}</span>
              <span class="tl-codigo-et">{t.sinCamara}</span>
              <span class="tl-codigo">{enDos(atras.codigo)}</span>
            </div>
            {#if qr}
              <div class="tl-qr">
                <svg viewBox="0 0 {qr.size} {qr.size}" shape-rendering="crispEdges" role="img" aria-label={t.qr}><path fill="#111" d={trazo} /></svg>
              </div>
            {/if}
          </div>
        </div>
      </span>
    </button>
  {:else}
    <div class="tl-tarjeta quieta" aria-hidden="true" bind:this={tarjeta}>
      <span class="tl-gira">{@render frente()}</span>
    </div>
  {/if}
</div>

<style>
  .tl-pinta {
    display: block;
  }
</style>
