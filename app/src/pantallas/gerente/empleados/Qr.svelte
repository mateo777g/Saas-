<!--
  El QR de «Vincular aparato»: lleva la dirección del aparato con el código adentro
  (…/equipo?codigo=KMRPTX), así la cámara del celular abre la pantalla con el código ya escrito.
  Lo arma uqr (MIT) y se dibuja en negro sobre el cuadro blanco de la maqueta, en los dos temas,
  porque las cámaras leen mejor el QR oscuro sobre claro.
-->
<script lang="ts">
  import { encode } from 'uqr';

  let { texto }: { texto: string } = $props();

  const qr = $derived(encode(texto, { ecc: 'M', border: 0 }));
  // Un solo trazo con un cuadrito por cada módulo negro.
  const trazo = $derived(
    qr.data.flatMap((fila, y) => fila.map((negro, x) => (negro ? `M${x} ${y}h1v1h-1z` : ''))).join(''),
  );
</script>

<div class="qr">
  <svg viewBox="0 0 {qr.size} {qr.size}" shape-rendering="crispEdges" role="img" aria-label="QR del código">
    <path d={trazo} />
  </svg>
</div>

<style>
  .qr {
    width: 148px;
    height: 148px;
    flex: none;
    padding: 10px;
    border-radius: 12px;
    background: var(--qr-fondo);
  }

  svg {
    width: 128px;
    height: 128px;
    display: block;
    fill: var(--qr-tinta);
  }
</style>
