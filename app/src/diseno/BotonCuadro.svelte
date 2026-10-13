<!--
  boton_cuadro() de diseno.py: el botón de solo icono (los de cada fila, la X de una ventana).
  Cuadro de 36 con borde fino, radio 10, icono 16; con el cursor encima se rellena de chip.
  `ayuda` es la etiqueta que sale al dejar el cursor encima; `etiqueta`, lo que lee un lector de
  pantalla cuando hace falta decir más ("Sumar meses a La fonda de Don Chuy"). `apagado` lo deja
  al 35 % y sin clic (la flecha de subir de la primera categoría).
-->
<script lang="ts">
  import Icono from './Icono.svelte';

  let {
    icono,
    ayuda,
    etiqueta,
    apagado = false,
    onclick,
    ...resto
  }: {
    icono: string;
    ayuda: string;
    etiqueta?: string;
    apagado?: boolean;
    onclick?: (e: MouseEvent) => void;
    [dato: `data-${string}`]: string | number;
  } = $props();
</script>

<button
  type="button"
  class="cuadro"
  title={ayuda}
  aria-label={etiqueta ?? ayuda}
  disabled={apagado}
  {onclick}
  {...resto}
>
  <Icono nombre={icono} tamano={16} />
</button>

<style>
  .cuadro {
    width: 36px;
    height: 36px;
    flex: none;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    padding: 0;
    border: 1px solid var(--linea);
    border-radius: 10px;
    background: transparent;
    color: var(--texto);
    transition: background-color 150ms;
  }

  .cuadro:hover:not(:disabled) {
    background: var(--chip);
  }

  .cuadro:disabled {
    opacity: 0.35;
    cursor: default;
  }
</style>
