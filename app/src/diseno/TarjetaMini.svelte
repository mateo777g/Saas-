<!--
  La tarjeta de lealtad chiquita (maqueta v22, `mini` de armar.py): en Tu pedido del menú, junto a lo que suma, y donde
  haga falta recordarla sin la grande. Lleva el estilo y el color de la grande (lib/tarjetaFondo.ts la pinta), y lo
  juntado: con sellos, sus puntitos (hasta 10, como la maqueta, a escala de la meta); con puntos, su barrita.
-->
<script lang="ts">
  import type { EstiloTarjeta } from './TarjetaLealtad.svelte';
  import { pintarTarjeta } from '../lib/tarjetaFondo';
  import './tarjetaLealtad.css';

  let {
    estilo,
    color,
    forma,
    meta,
    saldo,
  }: { estilo: EstiloTarjeta; color: string; forma: 'sellos' | 'puntos'; meta: number; saldo: number } = $props();

  let raiz = $state<HTMLElement>();
  $effect(() => {
    if (raiz) pintarTarjeta(raiz, color, estilo, false);
  });

  // Con más de 10 sellos la chiquita no cabe: va a escala (8 de 20 son 4 de 10).
  const huecos = $derived(Math.min(meta, 10));
  const llenos = $derived(meta <= 10 ? Math.min(saldo, meta) : Math.floor((Math.min(saldo, meta) / meta) * 10));
  const avance = $derived(`${Math.min(100, Math.round((saldo / meta) * 100))}%`);
</script>

{#if forma === 'sellos'}
  <span class="tl-mini" bind:this={raiz} style:--tl-columnas={huecos <= 5 ? huecos : Math.ceil(huecos / 2)} aria-hidden="true">
    {#each { length: huecos } as _, i (i)}<i class:lleno={i < llenos}></i>{/each}
  </span>
{:else}
  <span class="tl-mini puntos" bind:this={raiz} style:--p={avance} aria-hidden="true"></span>
{/if}
