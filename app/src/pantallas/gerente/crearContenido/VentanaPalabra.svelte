<!--
  «Cambiar palabra» (maqueta JQBw2yGFSiky1x9twUyYbe): una palabra del paso de texto la escribe Don
  Chuy. Va tal cual al anuncio y no gasta nada más; con el tope de letras de su lugar y, si su lugar
  va en mayúsculas, en mayúsculas mientras escribe. Lo demás (su forma) lo revisa el Worker.
-->
<script lang="ts">
  import Boton from '../../../diseno/Boton.svelte';
  import GrupoCampos from '../../../diseno/GrupoCampos.svelte';
  import Ventana from '../../../diseno/Ventana.svelte';

  let {
    titulo,
    inicial,
    tope,
    mayusculas,
    alUsar,
    alCerrar,
  }: {
    titulo: string;
    inicial: string;
    tope: number;
    mayusculas: boolean;
    alUsar: (texto: string) => void;
    alCerrar: () => void;
  } = $props();

  // svelte-ignore state_referenced_locally
  let texto = $state(inicial);
  const lista = $derived(texto.trim() !== '');

  function alEscribir(e: Event & { currentTarget: HTMLInputElement }) {
    if (!mayusculas) return;
    const campo = e.currentTarget;
    const donde = campo.selectionStart;
    texto = campo.value.toUpperCase();
    campo.value = texto;
    if (donde !== null) campo.setSelectionRange(donde, donde);
  }

  function usar() {
    if (lista) alUsar(texto.trim());
  }
</script>

<Ventana centrado etiqueta="Cambiar palabra" {titulo} ancho={420} relleno="24px 28px" {alCerrar}>
  <div class="grupo-arriba">
  <GrupoCampos>
  <div class="campo">
    <div class="etq-fila">
      <label class="etq" for="palabra">Va en tu anuncio</label>
      <span class="letras">{[...texto].length} / {tope}</span>
    </div>
    <!-- svelte-ignore a11y_autofocus -->
    <input
      id="palabra"
      bind:value={texto}
      oninput={alEscribir}
      onkeydown={(e) => {
        if (e.key === 'Enter') usar();
      }}
      maxlength={tope}
      autocomplete="off"
      spellcheck="false"
      autofocus
    />
    <p class="pista">Va tal cual al anuncio. No gasta nada más.</p>
  </div>
  </GrupoCampos>
  </div>
  <div class="pie">
    <Boton etiqueta="Cancelar" icono="cerrar" tono="alarga" onclick={alCerrar} />
    <span class="crece"></span>
    <Boton etiqueta="Usar esta palabra" icono="check-fino" tono="tinta" apagado={!lista} onclick={usar} />
  </div>
</Ventana>

<style>
  /* El campo va en su gris (GrupoCampos, 9 nov 2026); el espacio de arriba pasa al grupo. */
  .grupo-arriba {
    margin-top: 18px;
  }

  .campo {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .etq-fila {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 12px;
  }

  .etq {
    font-family: var(--mono);
    font-size: 10.5px;
    letter-spacing: 0.14em;
    color: var(--tenue);
    text-transform: uppercase;
  }

  .letras {
    font-family: var(--mono);
    font-size: 11px;
    color: var(--tenue);
    font-variant-numeric: tabular-nums;
  }

  input {
    width: 100%;
    height: 44px;
    padding: 0 14px;
    border: 0;
    border-radius: 12px;
    background: var(--campo-fondo);
    box-shadow: var(--campo-sombra);
    color: var(--texto);
    font-size: 14px;
    font-weight: 700;
    letter-spacing: 0.02em;
    outline: none;
    transition:
      background-color 0.15s ease,
      box-shadow 0.15s ease-out;
  }

  /* Como las cajas de texto (diseno/Campo.svelte, el Input de HeroUI), desde el 9 nov 2026. */
  input:hover:not(:focus) {
    background: var(--campo-encima);
  }

  input:focus {
    box-shadow: 0 0 0 2px var(--campo-aro);
  }

  @media (prefers-reduced-motion: reduce) {
    input {
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

  .pie {
    margin-top: 20px;
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .crece {
    flex-grow: 1;
  }
</style>
