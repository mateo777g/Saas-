<!--
  campo() de diseno.py: una caja de texto en sólido con su etiqueta encima ("NOMBRE", mono) y,
  si hace falta, una pista debajo. Borde fino (más marcado mientras se escribe), radio 12, 44 de
  alto, letra 13.5. Sin relleno propio: toma el sólido de la ventana en la que va.
  `valor` siempre es texto, también en las fechas ('aaaa-mm-dd') y los números: quien guarda lo
  convierte.
-->
<script lang="ts">
  let {
    id,
    etiqueta,
    valor = $bindable(''),
    tipo = 'text',
    pista,
    placeholder,
    autocomplete = 'off',
    corrector = true,
    min,
    step,
  }: {
    id: string;
    etiqueta: string;
    valor?: string;
    tipo?: 'text' | 'email' | 'tel' | 'date' | 'number';
    pista?: string;
    placeholder?: string;
    autocomplete?: HTMLInputElement['autocomplete'];
    corrector?: boolean;
    min?: number;
    step?: number;
  } = $props();
</script>

<div class="campo">
  <label class="etiqueta" for={id}>{etiqueta}</label>
  <input
    {id}
    type={tipo}
    value={valor}
    oninput={(e) => (valor = e.currentTarget.value)}
    {placeholder}
    {autocomplete}
    spellcheck={corrector}
    {min}
    {step}
  />
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

  input {
    width: 100%;
    height: 44px;
    padding: 0 14px;
    border: 1px solid var(--linea);
    border-radius: 12px;
    background: transparent;
    color: var(--texto);
    font-size: 13.5px;
    font-weight: 500;
    outline: none;
  }

  /* Como en la maqueta: solo las fechas llevan los números del mismo ancho. */
  input[type='date'] {
    font-variant-numeric: tabular-nums;
  }

  input:focus {
    border-color: var(--suave);
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
