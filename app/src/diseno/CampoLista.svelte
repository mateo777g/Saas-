<!--
  Un campo para elegir de una lista, con la etiqueta encima y la pista debajo como campo():
  la lista del navegador, 44 de alto, radio 12, en sólido. Las opciones van en grupos
  («Directos», «De otro distribuidor»); un grupo vacío no sale, y uno sin etiqueta pone sus
  opciones sueltas (las categorías de un producto). Mientras no se elige nada,
  muestra `placeholder` («Elige un cliente»), que no se puede volver a elegir. Sin `placeholder`
  siempre hay uno elegido (el grupo de un estilo).
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
    placeholder?: string;
    pista?: string;
  } = $props();
</script>

<div class="campo">
  <label class="etiqueta" for={id}>{etiqueta}</label>
  <select {id} value={valor} onchange={(e) => (valor = e.currentTarget.value)}>
    {#if placeholder !== undefined}
      <option value="" disabled selected={valor === ''}>{placeholder}</option>
    {/if}
    {#each grupos.filter((g) => g.opciones.length > 0) as g (g.etiqueta)}
      {#if g.etiqueta}
        <optgroup label={g.etiqueta}>
          {#each g.opciones as o (o.valor)}
            <option value={o.valor} selected={o.valor === valor}>{o.texto}</option>
          {/each}
        </optgroup>
      {:else}
        {#each g.opciones as o (o.valor)}
          <option value={o.valor} selected={o.valor === valor}>{o.texto}</option>
        {/each}
      {/if}
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

  /* Desde el 9 nov 2026, como las cajas de texto (diseno/Campo.svelte, el Input de HeroUI): sin borde, en
     --campo-fondo con su sombra, más gris con el mouse encima y el aro azul al elegir. La lista sigue siendo la
     del navegador. */
  select {
    width: 100%;
    height: 44px;
    padding: 0 11px;
    border: 0;
    border-radius: 12px;
    background: var(--campo-fondo);
    box-shadow: var(--campo-sombra);
    color: var(--texto);
    font-size: 13.5px;
    font-weight: 500;
    outline: none;
    transition:
      background-color 0.15s ease,
      box-shadow 0.15s ease-out;
  }

  select:hover:not(:focus) {
    background: var(--campo-encima);
  }

  select:focus {
    box-shadow: 0 0 0 2px var(--campo-aro);
  }

  @media (prefers-reduced-motion: reduce) {
    select {
      transition: none;
    }
  }

  .pista {
    margin: 0;
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--tenue);
  }
</style>
