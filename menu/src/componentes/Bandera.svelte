<!--
  La bandera de México o de Estados Unidos en las listitas del idioma y la moneda («Tu menú en línea»,
  maqueta UDArhiEZceT7rmSKxqRA5r), dibujadas: en Windows los emoji de banderas salen como letras.
-->
<script lang="ts">
  let { pais }: { pais: 'mx' | 'us' } = $props();
  const franjas = Array.from({ length: 7 }, (_, i) => (i * 2 * 20) / 13);
  const estrellas = Array.from({ length: 20 }, (_, i) => [1.5 + (i % 5) * 2.4, 1.5 + Math.floor(i / 5) * 2.6]);
</script>

<span class="f-bandera">
  {#if pais === 'mx'}
    <svg viewBox="0 0 30 20" aria-hidden="true">
      <rect width="10" height="20" fill="#006847"></rect>
      <rect x="10" width="10" height="20" fill="#ffffff"></rect>
      <rect x="20" width="10" height="20" fill="#CE1126"></rect>
      <circle cx="15" cy="9.6" r="2.4" fill="#8C5A2B"></circle>
      <path d="M12.7 11.4q2.3 2.1 4.6 0" stroke="#2E7D32" stroke-width="0.9" fill="none"></path>
    </svg>
  {:else}
    <svg viewBox="0 0 30 20" aria-hidden="true">
      <rect width="30" height="20" fill="#ffffff"></rect>
      {#each franjas as y (y)}<rect {y} width="30" height={20 / 13} fill="#B22234"></rect>{/each}
      <rect width="12.6" height={(7 * 20) / 13} fill="#3C3B6E"></rect>
      {#each estrellas as [cx, cy] (`${cx},${cy}`)}<circle {cx} {cy} r="0.55" fill="#ffffff"></circle>{/each}
    </svg>
  {/if}
</span>
