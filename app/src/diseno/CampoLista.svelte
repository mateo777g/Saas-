<!--
  Un campo para elegir de una lista, con la etiqueta encima y la pista debajo como campo():
  la lista del navegador, 44 de alto, radio 12, en sólido. Las opciones van en grupos
  («Directos», «De otro distribuidor»); un grupo vacío no sale. Mientras no se elige nada,
  muestra `placeholder` («Elige un cliente»), que no se puede volver a elegir.
-->
<script lang="ts">
  let {
    id,
    etiqueta,
    valor = $bindable(''),
    grupos,
    placeholder,
    pista,
  }: {
    id: string;
    etiqueta: string;
    valor?: string;
    grupos: { etiqueta: string; opciones: { valor: string; texto: string }[] }[];
    placeholder: string;
    pista?: string;
  } = $props();
</script>

<div class="campo">
  <label class="etiqueta" for={id}>{etiqueta}</label>
  <select {id} value={valor} onchange={(e) => (valor = e.currentTarget.value)}>
    <option value="" disabled selected={valor === ''}>{placeholder}</option>
    {#each grupos.filter((g) => g.opciones.length > 0) as g (g.etiqueta)}
      <optgroup label={g.etiqueta}>
        {#each g.opciones as o (o.valor)}
          <option value={o.valor} selected={o.valor === valor}>{o.texto}</option>
        {/each}
      </optgroup>
    {/each}
  </select>
  {#if pista}
    <p class="pista">{pista}</p>
  {/if}
</div>

<style>
  .campo {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  select {
    width: 100%;
    height: 44px;
    padding: 0 10px;
    border: 1px solid var(--linea);
    border-radius: 12px;
    background: var(--solido);
    color: var(--texto);
    font-size: 13.5px;
    font-weight: 500;
    outline: none;
  }

  select:focus {
    border-color: var(--suave);
  }

  .pista {
    margin: 0;
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--tenue);
  }
</style>
