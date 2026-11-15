<!--
  Lo de la barra de abajo mientras se cobra a lo ancho (adaptabilidad 3b; maqueta GBWEGCsQFcwKkWm7Qe9FPA v4, «Cobrar»,
  «Cobrada» y «Caja»): a la izquierda qué se cobra («#24 · Comer aquí» y su línea), y a la derecha «Atrás» si quien lo
  pinta lo pide, y «Anotar pago · $98.00» en verde (entra dinero); se prende solo cuando ya se puede anotar, y con una
  cuenta de $0 dice «Cerrar la cuenta». Ya cobrada: «#24 cerrada» con su línea y, si se pide, el botón que sigue
  («Nuevo pedido» en verde). Va dentro de la `.barra-contenido` de quien lo pinta.
-->
<script lang="ts">
  import Boton from '../../../diseno/Boton.svelte';
  import { pesos } from '../../../lib/formato';
  import type { Cobro } from './cobro.svelte';

  let {
    cobro,
    fuerte,
    chico = '',
    alAtras,
    siguiente,
  }: {
    cobro: Cobro;
    fuerte: string; // «#24 · Comer aquí» o, ya cobrada, «#24 cerrada»
    chico?: string; // «3 productos · Latte, Concha y Cuernito» o «Ya no sale en Abiertos»
    alAtras?: () => void;
    siguiente?: { texto: string; alPulsar: () => void } | null; // ya cobrada: «Nuevo pedido»
  } = $props();

  const c = $derived(cobro);
</script>

<div class="estado" role="status">
  <b>{fuerte}</b>
  {#if chico}<small>{chico}</small>{/if}
</div>
{#if c.cerrada}
  {#if siguiente}<Boton etiqueta={siguiente.texto} tono="verde" onclick={siguiente.alPulsar} />{/if}
{:else}
  {#if alAtras}<Boton etiqueta="Atrás" icono="anterior" apagado={c.ocupado} onclick={alAtras} />{/if}
  <Boton
    etiqueta={c.enCero ? 'Cerrar la cuenta' : `Anotar pago${c.cobrarEnBoton !== null ? ` · ${pesos(c.cobrarEnBoton)}` : ''}`}
    tono="verde"
    apagado={!c.listo}
    cargando={c.ocupado}
    onclick={() => c.anotar()}
  />
{/if}
