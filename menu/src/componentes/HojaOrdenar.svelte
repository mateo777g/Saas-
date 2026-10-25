<!--
  «Ordenar por» (maqueta de la 6a, estado «Ordenar»): Recomendado es el orden de Mi menú; los otros
  ordenan los productos dentro de cada categoría. Al elegir uno se cierra.
-->
<script lang="ts">
  import type { Textos } from '../lib/textos';
  import Hoja from './Hoja.svelte';
  import Icono from './Icono.svelte';

  let { orden, t, alElegir, alCerrar }: { orden: number; t: Textos; alElegir: (i: number) => void; alCerrar: () => void } = $props();
</script>

<Hoja etiqueta={t.ordenar} {alCerrar}>
  <div class="cabeza">
    <h3 class="titulo">{t.ordenar}</h3>
    <button type="button" class="cerrar" aria-label={t.cerrar} onclick={alCerrar}><Icono nombre="cerrar" tamano={18} /></button>
  </div>
  <div class="orden" role="radiogroup" aria-label={t.ordenar}>
    {#each t.ordenes as texto, i (i)}
      <button type="button" role="radio" aria-checked={i === orden} onclick={() => alElegir(i)}>
        {texto}
        {#if i === orden}<Icono nombre="check-delgado" tamano={18} />{/if}
      </button>
    {/each}
  </div>
</Hoja>

<style>
  .cabeza {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
  }

  .titulo {
    margin: 0;
    font-size: 20px;
    font-weight: 800;
    letter-spacing: -0.3px;
  }

  .cerrar {
    width: 40px;
    height: 40px;
    flex: none;
    border-radius: 20px;
    border: 1px solid var(--m-linea);
    background: transparent;
    color: var(--m-texto);
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0;
  }

  .orden {
    display: flex;
    flex-direction: column;
    margin-top: 10px;
  }

  .orden button {
    display: flex;
    align-items: center;
    justify-content: space-between;
    height: 52px;
    padding: 0 2px;
    border: 0;
    border-bottom: 1px solid var(--m-linea);
    background: transparent;
    color: var(--m-texto);
    font-size: 15px;
    font-weight: 500;
    text-align: left;
  }

  .orden button:last-child {
    border-bottom: 0;
  }

  .orden button[aria-checked='true'] {
    font-weight: 700;
  }
</style>
