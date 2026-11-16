<!--
  Lo de la barra de abajo mientras se cobra a lo ancho (adaptabilidad 3b; maqueta GBWEGCsQFcwKkWm7Qe9FPA v4, «Cobrar»,
  «Cobrada» y «Caja»): a la izquierda qué se cobra («#24 · Comer aquí» y su línea), y a la derecha «Atrás» si quien lo
  pinta lo pide, y «Anotar pago · $98.00» en verde (entra dinero); se prende solo cuando ya se puede anotar, y con una
  cuenta de $0 dice «Cerrar la cuenta». Ya cobrada: «#24 cerrada» con su línea y, si se pide, el botón que sigue
  («Nuevo pedido» en verde). Va dentro de la `.barra-contenido` de quien lo pinta.

  Con la terminal conectada (maqueta 8aJ1RUKVd2xA5kgawVpDkQ v2): con Tarjeta, «La cobré a mano» y «Mandar a la terminal ·
  $489.50» en verde (con menos de $5.00, gris y la razón a la izquierda); mientras espera, «Revisar» y «Cancelar cobro»
  en rojo de contorno, y a la izquierda quién lo mandó y a qué hora; si hay que revisar, «No se pagó» y «Sí se pagó».
-->
<script lang="ts">
  import Boton from '../../../diseno/Boton.svelte';
  import { enZona, pesos } from '../../../lib/formato';
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
  // Mientras espera o se revisa: quién lo mandó y a qué hora.
  const mando = $derived(
    c.cobroT && c.fase !== 'elegir'
      ? `${c.e.nombres.get(c.cobroT.mandado_por) ?? 'Alguien'} lo mandó a las ${enZona(c.cobroT.created_at, c.e.zona).hora}`
      : null,
  );
</script>

<div class="estado" role="status">
  <b>{fuerte}{c.fase === 'esperando' ? ' · En la terminal' : c.fase === 'revisa' ? ' · Revisa la terminal' : ''}</b>
  {#if mando}
    <small>{mando}</small>
  {:else if c.conTerminal && c.poco && !c.cerrada}
    <small>Menos de $5.00 no se puede mandar a la terminal</small>
  {:else if chico}<small>{chico}</small>{/if}
</div>
{#if c.fase === 'esperando' && !c.cerrada}
  <Boton etiqueta="Revisar" icono="actualizar" apagado={c.revisando} cargando={c.revisando} onclick={() => c.revisar()} />
  <Boton etiqueta="Cancelar cobro" tono="peligro" icono="cerrar" apagado={c.ocupado} onclick={() => c.cancelarTerminal()} />
{:else if c.fase === 'revisa' && !c.cerrada}
  <Boton etiqueta="No se pagó" tono="peligro" icono="cerrar" apagado={c.ocupado} onclick={() => c.confirmar(false)} />
  <Boton etiqueta="Sí se pagó" tono="verde" apagado={c.ocupado} cargando={c.ocupado} onclick={() => c.confirmar(true)} />
{:else if c.cerrada}
  {#if siguiente}<Boton etiqueta={siguiente.texto} tono="verde" onclick={siguiente.alPulsar} />{/if}
{:else}
  {#if alAtras}<Boton etiqueta="Atrás" icono="anterior" apagado={c.ocupado} onclick={alAtras} />{/if}
  {#if c.conTerminal && !c.enCero}
    <Boton etiqueta="La cobré a mano" apagado={!c.listo} onclick={() => c.anotar()} />
    <Boton
      etiqueta={`${c.notaTerminal ? 'Reintentar' : 'Mandar a la terminal'}${c.cobrarEnBoton !== null ? ` · ${pesos(c.cobrarEnBoton)}` : ''}`}
      tono="verde"
      apagado={!c.listoTerminal}
      cargando={c.ocupado}
      onclick={() => c.mandar()}
    />
  {:else}
    <Boton
      etiqueta={c.enCero ? 'Cerrar la cuenta' : `Anotar pago${c.cobrarEnBoton !== null ? ` · ${pesos(c.cobrarEnBoton)}` : ''}`}
      tono="verde"
      apagado={!c.listo}
      cargando={c.ocupado}
      onclick={() => c.anotar()}
    />
  {/if}
{/if}
