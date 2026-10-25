<!--
  El QR de las mesas en «Tu menú en línea» (maqueta de la 6a Qx4C5CbKJYpeAsJCfw4ghn, sección 3): lleva
  el link del menú, así la cámara del celular lo abre. Lo arma uqr (MIT), como el de Vincular aparato,
  en negro sobre blanco en los dos temas. «Descargar QR» da un PNG grande para imprimir.
-->
<script module lang="ts">
  import { encode } from 'uqr';

  // El PNG para imprimir: 32 px por cuadrito y 4 cuadritos de orilla blanca, como pide el estándar.
  export async function descargarQr(texto: string, archivo: string) {
    const qr = encode(texto, { ecc: 'M', border: 4 });
    const lado = 32;
    const lienzo = document.createElement('canvas');
    lienzo.width = lienzo.height = qr.size * lado;
    const pincel = lienzo.getContext('2d');
    if (!pincel) throw new Error('El navegador no pudo dibujar el QR');
    pincel.fillStyle = '#ffffff';
    pincel.fillRect(0, 0, lienzo.width, lienzo.height);
    pincel.fillStyle = '#000000';
    qr.data.forEach((fila, y) => fila.forEach((negro, x) => negro && pincel.fillRect(x * lado, y * lado, lado, lado)));
    const png = await new Promise<Blob | null>((listo) => lienzo.toBlob(listo, 'image/png'));
    if (!png) throw new Error('El navegador no pudo hacer el PNG del QR');
    const url = URL.createObjectURL(png);
    const enlace = document.createElement('a');
    enlace.href = url;
    enlace.download = archivo;
    enlace.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
</script>

<script lang="ts">
  let { texto }: { texto: string } = $props();

  const qr = $derived(encode(texto, { ecc: 'M', border: 0 }));
  // Un solo trazo con un cuadrito por cada módulo negro.
  const trazo = $derived(
    qr.data.flatMap((fila, y) => fila.map((negro, x) => (negro ? `M${x} ${y}h1v1h-1z` : ''))).join(''),
  );
</script>

<div class="qr">
  <svg viewBox="0 0 {qr.size} {qr.size}" shape-rendering="crispEdges" role="img" aria-label="QR de tu menú">
    <path d={trazo} />
  </svg>
</div>

<style>
  .qr {
    width: 112px;
    height: 112px;
    flex: none;
    padding: 8px;
    border-radius: 12px;
    background: var(--qr-fondo);
    border: 1px solid var(--linea);
  }

  svg {
    width: 100%;
    height: 100%;
    display: block;
    fill: var(--qr-tinta);
  }
</style>
