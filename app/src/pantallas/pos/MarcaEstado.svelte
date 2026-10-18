<!--
  La marca de arriba de una mesa o de un pedido (maqueta Mesero y cocina): «En cocina» mientras
  alguna comanda espera, «Lista» cuando la cocina terminó y aquí no se ha abierto, y «Pidió la
  cuenta». Ocupada sin nada de eso, no lleva marca.
-->
<script lang="ts">
  import Icono from '../../diseno/Icono.svelte';

  let { estado }: { estado: 'cocina' | 'lista' | 'cuenta' | 'ocupada' | 'pendiente' } = $props();
</script>

{#if estado === 'cocina' || estado === 'pendiente'}
  <span class="marca-estado"><Icono nombre="reloj" tamano={12} />En cocina</span>
{:else if estado === 'lista'}
  <span class="marca-estado lista"><span class="punto"></span>Lista</span>
{:else if estado === 'cuenta'}
  <span class="marca-estado cuenta"><Icono nombre="cuenta" tamano={12} />Pidió la cuenta</span>
{/if}
