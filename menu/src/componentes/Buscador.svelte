<!--
  «Buscar en el menú» y el botón de ordenar (maqueta de la 6a, estados «Buscar» y «Ordenar»). Lo que
  se escribe busca en los nombres y las descripciones, en español y en inglés; la X lo borra.

  Desde «Tu menú en línea» (maqueta UDArhiEZceT7rmSKxqRA5r): la caja gris (la de siempre) o la blanca,
  más marcada (también la de la lupa con el logo al centro), y «Ordenar por» ya no abre una hoja: su
  botón saca debajo una listita como la del mundito, con el ícono de cada orden.
-->
<script lang="ts">
  import { ICONOS_ORDEN } from '../lib/iconos';
  import type { Textos } from '../lib/textos';
  import Icono from './Icono.svelte';
  import ListaBoton from './ListaBoton.svelte';

  let {
    busqueda = $bindable(),
    orden,
    blanca = false,
    t,
    campo = $bindable(),
    alOrdenar,
  }: {
    busqueda: string;
    orden: number;
    blanca?: boolean;
    t: Textos;
    campo?: HTMLInputElement;
    alOrdenar: (i: number) => void;
  } = $props();

  const ordenes = $derived(t.ordenes.map((texto, i) => ({ valor: String(i), texto, icono: ICONOS_ORDEN[i] })));
</script>

<div class="fila" class:f-blanca={blanca}>
  <label class="buscar">
    <Icono nombre="buscar" tamano={18} />
    <input bind:this={campo} bind:value={busqueda} type="search" placeholder={t.buscar} aria-label={t.buscar} autocomplete="off" enterkeyhint="search" />
    {#if busqueda}
      <button
        type="button"
        class="limpiar"
        aria-label={t.limpiar}
        onclick={() => {
          busqueda = '';
          campo?.focus();
        }}><Icono nombre="cerrar" tamano={16} /></button
      >
    {/if}
  </label>
  <ListaBoton clase="f-ordenar" opciones={ordenes} elegida={String(orden)} etiqueta={t.ordenar} alElegir={(v) => alOrdenar(Number(v))}>
    {#snippet boton({ abierta, alternar })}
      <button type="button" class="cuadro" aria-label={t.ordenar} aria-haspopup="listbox" aria-expanded={abierta} onclick={alternar}
        ><Icono nombre="ordenar" tamano={19} /></button
      >
    {/snippet}
  </ListaBoton>
</div>

<style>
  .fila {
    padding: 14px 16px 0;
    display: flex;
    gap: 8px;
  }

  .buscar {
    flex: 1;
    min-width: 0;
    height: 44px;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 14px;
    border-radius: 14px;
    background: var(--m-chip);
    color: var(--m-tenue);
    font-size: 14px;
    font-weight: 500;
    cursor: text;
  }

  input {
    flex: 1;
    min-width: 0;
    height: 100%;
    padding: 0;
    border: 0;
    outline: none;
    background: transparent;
    color: var(--m-texto);
    font-size: 14px;
    font-weight: 500;
    -webkit-appearance: none;
    appearance: none;
  }

  input::placeholder {
    color: var(--m-tenue);
    opacity: 1;
  }

  /* En el iPhone, un campo de menos de 16 hace que la página se acerque al tocarlo. */
  @supports (-webkit-touch-callout: none) {
    input {
      font-size: 16px;
    }
  }

  input::-webkit-search-cancel-button {
    display: none;
  }

  .limpiar {
    width: 28px;
    height: 28px;
    margin-right: -6px;
    flex: none;
    border: 0;
    padding: 0;
    background: transparent;
    color: var(--m-tenue);
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .cuadro {
    width: 44px;
    height: 44px;
    flex: none;
    border-radius: 14px;
    border: 0;
    background: var(--m-chip);
    color: var(--m-texto);
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0;
  }
</style>
