<!--
  Lo de arriba de cada pantalla del aparato (maqueta de Empleados 36iXMMqXCfVv4NuVR7vNSc): el
  logo del restaurante con su nombre y el del aparato, o, en el PIN de la tableta compartida,
  «Cambiar de persona» para regresar a la lista. El logo es el de «Tu restaurante» (lib/marcaAparato.ts);
  sin logo, solo el nombre. Sin ligar, o mientras carga, nada: todavía no se sabe de qué restaurante es.
-->
<script lang="ts">
  import Icono from '../../diseno/Icono.svelte';
  import LogoRestaurante from '../../diseno/LogoRestaurante.svelte';
  import { leerMarca } from '../../lib/marcaAparato';

  let {
    lugar = null,
    alVolver,
  }: { lugar?: { restaurante: string; aparato: string } | null; alVolver?: () => void } = $props();

  const marca = leerMarca();
</script>

<div class="arriba">
  {#if alVolver}
    <button type="button" class="volver" onclick={alVolver}>
      <Icono nombre="anterior" tamano={16} />Cambiar de persona
    </button>
  {:else if lugar}
    {#if marca?.logo}<LogoRestaurante ruta={marca.logo} />{/if}
    <span class="lugar">
      <b>{lugar.restaurante}</b>
      <span>{lugar.aparato}</span>
    </span>
  {/if}
</div>

<style>
  .arriba {
    min-height: 40px;
    display: flex;
    align-items: center;
    gap: 10px;
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
