<!--
  El PIN de 4 números (maqueta de Empleados 36iXMMqXCfVv4NuVR7vNSc): la caja de campo() de 132 de
  ancho, en mono de 18 y con los números separados. Desde el 9 nov 2026, como las demás cajas de texto
  (diseno/Campo.svelte, el Input de HeroUI). Solo deja escribir números, hasta 4. Se ve
  mientras Don Chuy lo escribe, para que se lo diga a Pepe; después nadie lo puede ver.
-->
<script lang="ts">
  let {
    id,
    etiqueta,
    valor = $bindable(''),
    pista,
  }: { id: string; etiqueta: string; valor?: string; pista: string } = $props();

  function escribir(e: Event & { currentTarget: HTMLInputElement }) {
    const limpio = e.currentTarget.value.replace(/\D/g, '').slice(0, 4);
    e.currentTarget.value = limpio;
    valor = limpio;
  }
</script>

<div class="campo">
  <label class="etiqueta" for={id}>{etiqueta}</label>
  <input
    {id}
    value={valor}
    oninput={escribir}
    inputmode="numeric"
    maxlength="4"
    placeholder="····"
    autocomplete="off"
    spellcheck="false"
  />
  <p class="pista">{pista}</p>
</div>

<style>
  .campo {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  input {
    width: 132px;
    height: 44px;
    padding: 0 0 0 18px;
    border: 0;
    border-radius: 12px;
    background: var(--campo-fondo);
    box-shadow: var(--campo-sombra);
    color: var(--texto);
    font-family: var(--mono);
    font-size: 18px;
    font-weight: 500;
    letter-spacing: 0.5em;
    outline: none;
    transition:
      background-color 0.15s ease,
      box-shadow 0.15s ease-out;
  }

  /* Como las cajas de texto (diseno/Campo.svelte, el Input de HeroUI): más gris con el mouse encima y el aro azul al escribir. */
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

  input::placeholder {
    color: var(--tenue);
  }

  .pista {
    margin: 0;
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--tenue);
  }
</style>
