<!--
  Lo que sale en lugar de las filas cuando una tabla no tiene qué mostrar ("Todavía no hay
  ningún restaurante.") o no se pudo leer: una línea fuerte y otra suave, al centro.
-->
<script lang="ts">
  let { titulo, texto }: { titulo: string; texto: string } = $props();
</script>

<div class="nota" role="status">
  <b>{titulo}</b>
  <span>{texto}</span>
</div>

<style>
  .nota {
    padding: 40px 16px;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 6px;
    text-align: center;
  }

  b {
    font-size: 14.5px;
    font-weight: 700;
  }

  span {
    font-size: 12.5px;
    font-weight: 500;
    color: var(--suave);
  }
</style>
