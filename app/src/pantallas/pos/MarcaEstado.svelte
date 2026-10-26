<!--
  La marca de arriba de una mesa o de un pedido (maqueta Mesero y cocina): «En cocina» mientras
  alguna comanda espera, «Lista» cuando la cocina terminó y aquí no se ha abierto, y «Pidió la
  cuenta». Ocupada sin nada de eso, no lleva marca. «Reabierta» (parte 4c): se canceló un pago de
  una cuenta ya cerrada y volvió a Por cobrar con su folio. «WhatsApp» (parte 6b): la cuenta nació de
  un pedido del menú en línea; va antes de la otra marca.
-->
<script lang="ts">
  import Icono from '../../diseno/Icono.svelte';

  let {
    estado,
    whatsapp = false,
  }: { estado: 'reabierta' | 'cocina' | 'lista' | 'cuenta' | 'ocupada' | 'pendiente'; whatsapp?: boolean } = $props();
</script>

{#if whatsapp}
  <span class="marcas">
    <span class="marca-estado wa"><Icono nombre="mensaje" tamano={12} />WhatsApp</span>
    {@render marca()}
  </span>
{:else}
  {@render marca()}
{/if}

{#snippet marca()}

{#if estado === 'reabierta'}
  <span class="marca-estado reabierta"><Icono nombre="regresar" tamano={12} />Reabierta</span>
{:else if estado === 'cocina' || estado === 'pendiente'}
  <span class="marca-estado"><Icono nombre="reloj" tamano={12} />En cocina</span>
{:else if estado === 'lista'}
  <span class="marca-estado lista"><span class="punto"></span>Lista</span>
{:else if estado === 'cuenta'}
  <span class="marca-estado cuenta"><Icono nombre="cuenta" tamano={12} />Pidió la cuenta</span>
{/if}
{/snippet}
