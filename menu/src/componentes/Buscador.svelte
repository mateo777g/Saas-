<!--
  «Buscar en el menú» y el botón de ordenar (maqueta de la 6a, estados «Buscar» y «Ordenar»). Lo que
  se escribe busca en los nombres y las descripciones, en español y en inglés; la X lo borra.
-->
<script lang="ts">
  import type { Textos } from '../lib/textos';
  import Icono from './Icono.svelte';

  let { busqueda = $bindable(), t, alOrdenar }: { busqueda: string; t: Textos; alOrdenar: () => void } = $props();

  let campo: HTMLInputElement;
</script>

<div class="fila">
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
          campo.focus();
        }}><Icono nombre="cerrar" tamano={16} /></button
      >
    {/if}
  </label>
  <button type="button" class="cuadro" aria-label={t.ordenar} onclick={alOrdenar}><Icono nombre="ordenar" tamano={19} /></button>
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
