<!--
  Abrir la caja a lo ancho, en la tarjeta de la derecha (adaptabilidad 3c; encuesta 6 de cobro-caja.md): «La caja está
  cerrada», el fondo en su gris (ya trae el del turno pasado) y «Abrir caja» en verde. La lista de Por cobrar se queda a
  la izquierda. Lo de adentro es lo de la columna de hoy (caja/Caja.svelte).
-->
<script lang="ts">
  import Boton from '../../../diseno/Boton.svelte';
  import CajaError from '../../../diseno/CajaError.svelte';
  import Campo from '../../../diseno/Campo.svelte';
  import GrupoCampos from '../../../diseno/GrupoCampos.svelte';
  import Icono from '../../../diseno/Icono.svelte';

  let {
    fondo,
    ultimoFondo,
    error,
    ocupado,
    alFondo,
    alAbrir,
  }: {
    fondo: string;
    ultimoFondo: number | null;
    error: string | null;
    ocupado: boolean;
    alFondo: (texto: string) => void;
    alAbrir: () => void;
  } = $props();
</script>

<div class="encabezado">
  <span class="cuadro-c"><Icono nombre="candado" tamano={18} /></span>
  <div class="titulos">
    <span class="titulo">La caja está cerrada</span>
    <span class="sub">Ábrela con el efectivo que hay en el cajón. Sin caja abierta no se anotan pagos.</span>
  </div>
</div>
<GrupoCampos>
  <Campo
    id="caja-fondo"
    etiqueta="FONDO"
    placeholder="$0.00"
    modoTeclado="decimal"
    pista={ultimoFondo === null ? '¿Con cuánto efectivo arranca la caja?' : 'Es el fondo del turno pasado. Cámbialo si hoy dejas otro.'}
    bind:valor={() => fondo, (v) => alFondo(v)}
  />
</GrupoCampos>
{#if error}<CajaError mensaje={error} />{/if}
<div class="abrir">
  <Boton etiqueta="Abrir caja" tono="verde" apagado={!fondo.trim()} cargando={ocupado} onclick={alAbrir} />
</div>

<style>
  .abrir {
    display: flex;
    justify-content: flex-end;
  }
</style>
