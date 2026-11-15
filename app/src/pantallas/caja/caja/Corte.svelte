<!--
  Cerrar la caja a lo ancho, el corte a ciegas, en la tarjeta de la derecha (adaptabilidad 3c; encuesta 7 de
  cobro-caja.md): los tres campos de la columna de hoy en su gris; «Atrás» y «Cerrar caja» van en la barra de abajo. Lo
  esperado sale hasta que se cierra (caja/caja/Resultado.svelte). La lista se queda a la izquierda.
-->
<script lang="ts">
  import CajaError from '../../../diseno/CajaError.svelte';
  import Campo from '../../../diseno/Campo.svelte';
  import GrupoCampos from '../../../diseno/GrupoCampos.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import type { Metodo } from '../../../lib/caja';

  let {
    turno,
    contado = $bindable(),
    abiertas,
    error,
  }: {
    turno: string; // «Turno de Lupita · desde las 08:00»
    contado: Record<Metodo, string>;
    abiertas: number; // cuentas que siguen abiertas: las cobra el siguiente turno
    error: string | null;
  } = $props();

  const CAMPOS = [
    { m: 'efectivo', etq: 'EFECTIVO EN EL CAJÓN', pista: 'Billetes y monedas, con el fondo.' },
    { m: 'tarjeta', etq: 'CIERRE DE LA TERMINAL', pista: 'Lo que dice el corte de la terminal de tarjeta.' },
    { m: 'transferencia', etq: 'TRANSFERENCIAS', pista: 'Lo que llegó a la cuenta del restaurante.' },
  ] as const;
</script>

<div class="encabezado">
  <span class="cuadro-c"><Icono nombre="corte" tamano={18} /></span>
  <div class="titulos">
    <span class="titulo">Cerrar caja</span>
    <span class="sub">{turno}</span>
  </div>
</div>
<p class="texto">Cuenta lo que hay y escríbelo. Lo esperado sale cuando cierres.</p>
<GrupoCampos>
  {#each CAMPOS as c (c.m)}
    <Campo id="corte-{c.m}" etiqueta={c.etq} placeholder="$0.00" modoTeclado="decimal" pista={c.pista} bind:valor={contado[c.m]} />
  {/each}
</GrupoCampos>
{#if abiertas}
  <CajaError
    tipo="info"
    mensaje={abiertas === 1 ? 'Queda una cuenta abierta. La cobra el siguiente turno.' : `Quedan ${abiertas} cuentas abiertas. Las cobra el siguiente turno.`}
  />
{/if}
{#if error}<CajaError mensaje={error} />{/if}

<style>
  .texto {
    margin: 0;
    font-size: 13px;
    line-height: 1.5;
    color: var(--suave);
  }
</style>
