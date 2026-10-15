<!--
  El aparato sin ligar (maqueta de Empleados): pide el código de 6 letras que el gerente sacó en
  Vincular aparato. Si llegó por el QR, el código ya viene escrito. Solo deja letras, hasta 6, y
  Vincular se prende con las 6. El error sale en la caja, como en el panel.
-->
<script lang="ts">
  import CajaError from '../../diseno/CajaError.svelte';
  import { FalloAparato, vincular, type Ligado } from '../../lib/aparato';
  import { ALGO_SALIO_PANEL } from '../../lib/errores';
  import Arriba from './Arriba.svelte';

  let {
    codigoInicial = '',
    aviso = null,
    alLigar,
  }: { codigoInicial?: string; aviso?: string | null; alLigar: (ligado: Ligado) => void } = $props();

  // svelte-ignore state_referenced_locally
  let codigo = $state(codigoInicial);
  // svelte-ignore state_referenced_locally
  let error = $state<string | null>(aviso);
  let ligando = $state(false);

  function escribir(e: Event & { currentTarget: HTMLInputElement }) {
    const limpio = e.currentTarget.value.toUpperCase().replace(/[^A-Z]/g, '').slice(0, 6);
    e.currentTarget.value = limpio;
    codigo = limpio;
    error = null;
  }

  async function ligar(e: SubmitEvent) {
    e.preventDefault();
    if (codigo.length !== 6 || ligando) return;
    ligando = true;
    try {
      alLigar(await vincular(codigo));
    } catch (falla) {
      if (!(falla instanceof FalloAparato)) console.error('[aparato] no se pudo vincular:', falla);
      error = falla instanceof FalloAparato ? falla.message : ALGO_SALIO_PANEL;
      ligando = false;
    }
  }
</script>

<Arriba />
<form class="cuerpo" onsubmit={ligar} novalidate>
  <div class="centro">
    <h1 class="titulo">Vincula este aparato</h1>
    <p class="texto">Pídele a tu gerente el código de 6 letras. Lo saca en Empleados, en Vincular aparato.</p>
    <input
      class="codigo"
      value={codigo}
      oninput={escribir}
      maxlength="6"
      autocomplete="off"
      autocapitalize="characters"
      spellcheck="false"
      placeholder="ABCDEF"
      aria-label="Código de 6 letras"
    />
    {#if error}<CajaError mensaje={error} />{/if}
  </div>
  <button type="submit" class="boton" disabled={codigo.length !== 6 || ligando}>
    {ligando ? 'Vinculando…' : 'Vincular'}
  </button>
</form>

<style>
  .codigo {
    width: 100%;
    height: 60px;
    padding: 0;
    border: 1px solid var(--linea);
    border-radius: 14px;
    background: var(--solido);
    color: var(--texto);
    text-align: center;
    font-family: var(--mono);
    font-size: 28px;
    letter-spacing: 0.35em;
    text-transform: uppercase;
    outline: none;
  }

  .codigo:focus {
    border-color: var(--suave);
  }

  .codigo::placeholder {
    color: var(--linea-fuerte);
  }
</style>
