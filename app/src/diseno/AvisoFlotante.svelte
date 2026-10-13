<!--
  aviso() de piezas.py: la píldora oscura que sale abajo unos segundos, centrada sobre el
  contenido (a la derecha de la barra lateral), con la letra del panel. La usan las acciones que
  no abren ventana y no tienen dónde poner su caja de error: el ojito, Ocultar varios y las
  flechas de Categorías («No hay conexión con el servidor. Revisa tu internet.»).
-->
<script lang="ts">
  import { onDestroy } from 'svelte';

  const DURACION = 4000;

  let { mensaje, alTerminar }: { mensaje: string; alTerminar: () => void } = $props();

  const temporizador = setTimeout(() => alTerminar(), DURACION);
  onDestroy(() => clearTimeout(temporizador));
</script>

<div class="lugar" role="status" aria-live="polite">
  <div class="aviso">{mensaje}</div>
</div>

<style>
  .lugar {
    position: fixed;
    left: 276px;
    right: 0;
    bottom: 40px;
    z-index: 20;
    display: flex;
    justify-content: center;
    padding: 0 16px;
    pointer-events: none;
  }

  .aviso {
    width: 320px;
    max-width: 100%;
    padding: 15px 20px;
    border-radius: 24px;
    background: var(--globo);
    color: var(--globo-texto);
    font-size: 13px;
    font-weight: 500;
    line-height: 1.45;
    text-align: center;
    box-shadow: 0 8px 24px var(--sombra);
  }
</style>
