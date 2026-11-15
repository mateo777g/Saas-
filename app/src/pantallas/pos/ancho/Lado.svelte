<!--
  La tarjeta de la derecha a lo ancho (adaptabilidad; maqueta GBWEGCsQFcwKkWm7Qe9FPA v4): la de Crear anuncios, de 400 y
  del alto de la pantalla. Lo de adentro se desliza solo cuando no cabe, con su desvanecido abajo (como las ventanas,
  diseno/ventanaSeMueve.ts), y cuando cambia (`clave`: la cuenta, Abiertos, el cobro, la cobrada) entra con el rebote de
  la caja del agente.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';

  let { clave, children }: { clave: string; children: Snippet } = $props();

  let caja = $state<HTMLDivElement>();
  let conMas = $state(false);

  function medir() {
    if (caja) conMas = caja.scrollHeight - caja.scrollTop - caja.clientHeight > 2;
  }

  $effect(() => {
    if (!caja) return;
    const ojo = new ResizeObserver(medir);
    ojo.observe(caja);
    for (const hijo of caja.children) ojo.observe(hijo);
    const muta = new MutationObserver(medir);
    muta.observe(caja, { childList: true, subtree: true, characterData: true });
    medir();
    return () => {
      ojo.disconnect();
      muta.disconnect();
    };
  });
</script>

<aside class="der">
  <section class="tarjeta lado-tarjeta">
    {#key clave}
      <div class="tarjeta-scroll abre" class:con-mas={conMas} bind:this={caja} onscroll={medir}>
        {@render children()}
      </div>
    {/key}
  </section>
</aside>
