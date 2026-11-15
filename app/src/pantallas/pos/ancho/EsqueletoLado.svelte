<!--
  La tarjeta de la derecha mientras se lee la primera vez (regla «Los esqueletos»; maqueta GBWEGCsQFcwKkWm7Qe9FPA v4,
  «Mesa 4» cargando): la cabeza de la cuenta (cuadrito, título y su texto) y tres renglones (nombre, detalle e importe)
  en bloques grises que laten, con las medidas de CuentaLado para que nada brinque al llegar. Solo cuando todavía no se
  sabe qué va a salir: si el pedido nuevo ya está listo en este aparato, sale él y no esto.
-->
<script lang="ts">
  import Esqueleto from '../../../diseno/Esqueleto.svelte';

  let { texto = 'Abriendo el punto de venta…' }: { texto?: string } = $props();

  const RENGLONES = [
    { nombre: '62%', detalle: '38%', importe: '52px' },
    { nombre: '48%', detalle: '30%', importe: '46px' },
    { nombre: '56%', detalle: '42%', importe: '52px' },
  ];
</script>

<span class="solo-lector" role="status">{texto}</span>
<div class="encabezado" aria-hidden="true">
  <Esqueleto ancho="36px" alto="36px" redondo="11px" />
  <div class="titulos">
    <Esqueleto ancho="120px" alto="15px" />
    <Esqueleto ancho="170px" alto="12px" />
  </div>
</div>
<div class="bloque-c" aria-hidden="true">
  <Esqueleto ancho="140px" alto="10px" />
  <div class="renglones">
    {#each RENGLONES as r, i (i)}
      <div class="renglon">
        <span class="que"><Esqueleto ancho={r.nombre} alto="14px" /><Esqueleto ancho={r.detalle} alto="11px" /></span>
        <span class="imp"><Esqueleto ancho={r.importe} alto="13px" /></span>
      </div>
    {/each}
  </div>
</div>
