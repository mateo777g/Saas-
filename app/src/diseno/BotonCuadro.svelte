<!--
  boton_cuadro() de diseno.py: el botón de solo icono (los de cada fila, la X de una ventana).
  Cuadro de 36 con borde fino, radio 10, icono 16; con el cursor encima se rellena de chip.
  `ayuda` es la etiqueta que sale al dejar el cursor encima; `etiqueta`, lo que lee un lector de
  pantalla cuando hace falta decir más ("Sumar meses a La fonda de Don Chuy").
-->
<script lang="ts">
  import Icono from './Icono.svelte';

  let {
    icono,
    ayuda,
    etiqueta,
    onclick,
  }: {
    icono: string;
    ayuda: string;
    etiqueta?: string;
    onclick?: (e: MouseEvent) => void;
  } = $props();
</script>

<button type="button" class="cuadro" title={ayuda} aria-label={etiqueta ?? ayuda} {onclick}>
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

  .cuadro:hover {
    background: var(--chip);
  }
</style>
