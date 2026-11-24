<!--
  La cámara para leer el QR de la tarjeta de lealtad en el cobro (maqueta v22, «Escanear»): la cámara de atrás en su cuadro
  oscuro con las cuatro esquinas, la línea que baja y «Apunta a su QR». Lee con el lector del navegador (BarcodeDetector)
  donde existe y, donde no (iPad, Chrome en Windows), con jsQR, que se descarga solo al abrirla (encuesta del 23 nov
  2026). Al leer un QR lo entrega una vez y se apaga. Si no hay cámara o no dan permiso, lo dice y pide escribir el código.
-->
<script lang="ts">
  import { onMount } from 'svelte';

  let { alLeer, alFallar }: { alLeer: (texto: string) => void; alFallar: (mensaje: string) => void } = $props();

  let video = $state<HTMLVideoElement>();

  type Lector = (fuente: HTMLVideoElement) => Promise<string | null>;

  async function hacerLector(): Promise<Lector> {
    const Detector = (globalThis as { BarcodeDetector?: new (o: { formats: string[] }) => { detect: (f: unknown) => Promise<{ rawValue: string }[]> } })
      .BarcodeDetector;
    if (Detector) {
      try {
        const d = new Detector({ formats: ['qr_code'] });
        return async (v) => (await d.detect(v))[0]?.rawValue ?? null;
      } catch {
        // Sin el formato qr_code en este navegador: jsQR.
      }
    }
    const { default: jsQR } = await import('jsqr');
    const lienzo = document.createElement('canvas');
    const ctx = lienzo.getContext('2d', { willReadFrequently: true })!;
    return async (v) => {
      const w = v.videoWidth;
      const h = v.videoHeight;
      if (!w || !h) return null;
      // Más chico se lee igual y más rápido.
      const escala = Math.min(1, 640 / Math.max(w, h));
      lienzo.width = Math.round(w * escala);
      lienzo.height = Math.round(h * escala);
      ctx.drawImage(v, 0, 0, lienzo.width, lienzo.height);
      const img = ctx.getImageData(0, 0, lienzo.width, lienzo.height);
      return jsQR(img.data, img.width, img.height, { inversionAttempts: 'dontInvert' })?.data ?? null;
    };
  }

  onMount(() => {
    let vivo = true;
    let flujo: MediaStream | null = null;
    let reloj = 0;
    void (async () => {
      try {
        flujo = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' }, audio: false });
      } catch (falla) {
        console.error('[lealtad] no se pudo abrir la cámara:', falla);
        if (vivo) alFallar('No se pudo abrir la cámara. Escribe su código, el de abajo de su QR.');
        return;
      }
      if (!vivo || !video) return flujo.getTracks().forEach((t) => t.stop());
      video.srcObject = flujo;
      await video.play().catch(() => {});
      let leer: Lector;
      try {
        leer = await hacerLector();
      } catch (falla) {
        console.error('[lealtad] no se pudo cargar el lector de QR:', falla);
        if (vivo) alFallar('No se pudo leer con la cámara. Escribe su código, el de abajo de su QR.');
        return;
      }
      const vuelta = async () => {
        if (!vivo || !video) return;
        let texto: string | null = null;
        try {
          texto = await leer(video);
        } catch (falla) {
          console.error('[lealtad] el lector de QR falló:', falla);
        }
        if (!vivo) return;
        if (texto) {
          vivo = false;
          alLeer(texto.trim());
          return;
        }
        reloj = window.setTimeout(vuelta, 160);
      };
      void vuelta();
    })();
    return () => {
      vivo = false;
      clearTimeout(reloj);
      flujo?.getTracks().forEach((t) => t.stop());
    };
  });
</script>

<div class="camara">
  <!-- svelte-ignore a11y_media_has_caption -->
  <video bind:this={video} playsinline muted></video>
  <span class="esq a"></span><span class="esq b"></span><span class="esq c"></span><span class="esq d"></span>
  <span class="linea-scan"></span>
  <span class="camara-t">Apunta a su QR</span>
</div>

<style>
  .camara {
    position: relative;
    height: 188px;
    border-radius: 14px;
    overflow: hidden;
    display: grid;
    place-items: center;
    background:
      radial-gradient(60% 70% at 50% 45%, #4a4f57, #1b1d21 70%),
      #1b1d21;
  }

  video {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .esq {
    position: absolute;
    width: 26px;
    height: 26px;
    border: 3px solid #fff;
  }

  .esq.a {
    top: 28px;
    left: calc(50% - 70px);
    border-right: 0;
    border-bottom: 0;
    border-top-left-radius: 10px;
  }

  .esq.b {
    top: 28px;
    right: calc(50% - 70px);
    border-left: 0;
    border-bottom: 0;
    border-top-right-radius: 10px;
  }

  .esq.c {
    bottom: 32px;
    left: calc(50% - 70px);
    border-right: 0;
    border-top: 0;
    border-bottom-left-radius: 10px;
  }

  .esq.d {
    bottom: 32px;
    right: calc(50% - 70px);
    border-left: 0;
    border-top: 0;
    border-bottom-right-radius: 10px;
  }

  .linea-scan {
    position: absolute;
    left: calc(50% - 62px);
    width: 124px;
    height: 2px;
    top: 34px;
    border-radius: 1px;
    background: #4fa3ff;
    box-shadow: 0 0 12px 2px rgba(79, 163, 255, 0.7);
    animation: baja 1.6s ease-in-out infinite alternate;
  }

  @keyframes baja {
    to {
      transform: translateY(118px);
    }
  }

  .camara-t {
    position: absolute;
    bottom: 8px;
    left: 0;
    right: 0;
    text-align: center;
    color: rgba(255, 255, 255, 0.86);
    font: 600 12px var(--jakarta);
  }

  @media (prefers-reduced-motion: reduce) {
    .linea-scan {
      animation: none;
    }
  }
</style>
