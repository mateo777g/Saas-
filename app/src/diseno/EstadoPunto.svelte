<!--
  El estado de una fila con su punto: lleno y en negrita cuando está prendido ("Prendida",
  "Activo"), hueco y en gris tenue cuando no ("Pausada", "De baja").
-->
<script lang="ts">
  let { prendido, texto }: { prendido: boolean; texto: string } = $props();
</script>

<span class="estado" class:prendido>
  <span class="punto"></span>
  <span>{texto}</span>
</span>

<style>
  .estado {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 12.5px;
    font-weight: 500;
    color: var(--tenue);
  }

  .punto {
    width: 8px;
    height: 8px;
    flex: none;
    border-radius: 4px;
    border: 1.5px solid var(--tenue);
  }

  .prendido {
    font-weight: 600;
    color: var(--texto);
  }

  .prendido .punto {
    border: 0;
    background: var(--tinta);
  }
</style>
