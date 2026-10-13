<!--
  Lo que sale en lugar de las filas cuando una tabla no tiene qué mostrar ("Todavía no hay
  ningún restaurante.") o no se pudo leer: una línea fuerte y otra suave, al centro. Debajo
  puede llevar un botón («Ir a Categorías»). `relleno` es el de arriba y abajo: 40 en el panel
  de Fragmentless, 48 en Mi menú (como en Flet). `angosta` corta el texto a 52 caracteres por
  línea, como en la maqueta del Menú.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';

  let {
    titulo,
    texto = '',
    relleno = 40,
    angosta = false,
    children,
  }: { titulo: string; texto?: string; relleno?: number; angosta?: boolean; children?: Snippet } = $props();
</script>

<div class="nota" role="status" style:padding-block="{relleno}px">
  <b>{titulo}</b>
  {#if texto}<span class:angosta>{texto}</span>{/if}
  {#if children}<div class="debajo">{@render children()}</div>{/if}
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

  .angosta {
    max-width: 52ch;
    line-height: 1.45;
  }

  .debajo {
    margin-top: 10px;
  }
</style>
