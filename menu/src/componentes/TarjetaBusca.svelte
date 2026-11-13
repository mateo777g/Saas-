<!--
  La búsqueda en tarjeta («Tu menú en línea», maqueta UDArhiEZceT7rmSKxqRA5r): cerrada dice «Buscar en
  el menú» y para qué sirve; al tocarla se despliega con el rebote de la caja del agente y trae la caja
  para escribir y los cuatro órdenes en botoncitos.
-->
<script lang="ts">
  import { ICONOS_ORDEN } from '../lib/iconos';
  import type { Textos } from '../lib/textos';
  import Icono from './Icono.svelte';

  let { busqueda = $bindable(), orden, t, alOrdenar }: { busqueda: string; orden: number; t: Textos; alOrdenar: (i: number) => void } = $props();

  let abierta = $state(false);
  let campo: HTMLInputElement;
</script>

<div class="f-tarjeta-busca" class:abierta>
  <button type="button" class="f-bt-cabeza" aria-expanded={abierta} onclick={() => (abierta = !abierta)}>
    <span class="f-bt-cuadro"><Icono nombre="buscar" tamano={21} /><span class="f-bt-orden"><Icono nombre="ordenar" tamano={12} grosor={2.2} /></span></span>
    <span class="f-bt-textos"><b>{t.tarjeta[0]}</b><span>{t.tarjeta[1]}</span></span>
    <span class="f-bt-flecha"><Icono nombre="chevron" tamano={20} grosor={2} /></span>
  </button>
  <div class="f-bt-cuerpo" inert={!abierta}>
    <div class="f-bt-dentro">
      <div>
        <label class="f-bt-caja">
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
        <b class="f-bt-titulo">{t.ordenar}</b>
        <div class="f-ordenes">
          {#each t.ordenes as texto, i (i)}
            <button type="button" class="f-orden" aria-pressed={orden === i} onclick={() => alOrdenar(i)}
              ><Icono nombre={ICONOS_ORDEN[i]} tamano={16} />{texto}</button
            >
          {/each}
        </div>
      </div>
    </div>
  </div>
</div>

<style>
  /* La caja de la maqueta era un dibujo; aquí se escribe en ella. */
  .f-bt-caja {
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
</style>
