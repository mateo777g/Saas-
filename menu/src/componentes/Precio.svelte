<!--
  El precio de un producto, en la lista y en su ventana: «Desde» cuando una opción obligatoria sube
  el precio, y en dólares «aprox.» abajo (libreta 6: la cuenta la hace Postgres). En las tarjetas
  del asistente (parte 6c), `enLinea` lo deja junto al precio.
-->
<script lang="ts">
  import type { Producto } from '../lib/datos';
  import { monto } from '../lib/precio';
  import type { Moneda } from '../lib/preferencias';
  import type { Textos } from '../lib/textos';

  let {
    producto,
    moneda,
    t,
    enLinea = false,
  }: { producto: Producto; moneda: Moneda; t: Textos; enLinea?: boolean } = $props();

  const enDolares = $derived(moneda === 'usd' && producto.precio_usd !== null);
</script>

{#if producto.desde}<small>{t.desde}</small>{/if}{monto(producto.precio, producto.precio_usd, moneda)}{#if enDolares}<span
    class="aprox"
    class:en-linea={enLinea}>{t.aprox}</span
  >{/if}

<style>
  small {
    font-size: 11.5px;
    font-weight: 600;
    color: var(--m-suave);
    margin-right: 3px;
  }

  .aprox {
    display: block;
    font-size: 10.5px;
    font-weight: 600;
    color: var(--m-tenue);
  }

  .aprox.en-linea {
    display: inline;
    margin-left: 5px;
  }
</style>
