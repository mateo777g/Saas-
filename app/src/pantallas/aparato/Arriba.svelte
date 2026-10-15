<!--
  Lo de arriba de cada pantalla del aparato (maqueta de Empleados 36iXMMqXCfVv4NuVR7vNSc): el ∫∫
  en su cuadro de acento con el restaurante y el nombre del aparato, o, en el PIN de la tableta
  compartida, «Cambiar de persona» para regresar a la lista. Sin ligar, solo el logo.
-->
<script lang="ts">
  import Icono from '../../diseno/Icono.svelte';
  import Integral from '../../diseno/Integral.svelte';

  let {
    lugar = null,
    alVolver,
  }: { lugar?: { restaurante: string; aparato: string } | null; alVolver?: () => void } = $props();
</script>

<div class="arriba">
  {#if alVolver}
    <button type="button" class="volver" onclick={alVolver}>
      <Icono nombre="anterior" tamano={16} />Cambiar de persona
    </button>
  {:else}
    <span class="logo"><Integral ancho={20} alto={22} /></span>
    {#if lugar}
      <span class="lugar">
        <b>{lugar.restaurante}</b>
        <span>{lugar.aparato}</span>
      </span>
    {/if}
  {/if}
</div>

<style>
  .arriba {
    min-height: 40px;
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .logo {
    width: 32px;
    height: 32px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 10px;
    background: var(--acento);
    color: var(--sobre-acento);
  }

  .lugar {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .lugar b {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 13.5px;
    font-weight: 700;
  }

  .lugar span {
    font-family: var(--mono);
    font-size: 10.5px;
    color: var(--tenue);
  }

  .volver {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 36px;
    padding: 0 12px 0 8px;
    border: 1px solid var(--linea);
    border-radius: 12px;
    background: transparent;
    color: var(--texto);
    font-size: 12.5px;
    font-weight: 600;
  }
</style>
