<!--
  campo() de diseno.py: una caja de texto en sólido con su etiqueta encima ("NOMBRE", mono) y,
  si hace falta, una pista debajo. Borde fino (más marcado mientras se escribe), radio 12, 44 de
  alto, letra 13.5. Sin relleno propio: toma el sólido de la ventana en la que va.
  `valor` siempre es texto, también en las fechas ('aaaa-mm-dd') y los números: quien guarda lo
  convierte. Como en Flet, puede llevar un `prefijo` adentro, a la izquierda ("$" en el precio), o
  ser `multilinea` (la descripción de un producto: 72 de alto).
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
    prefijo,
    multilinea = false,
    modoTeclado,
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
    prefijo?: string;
    multilinea?: boolean;
    modoTeclado?: 'decimal' | 'numeric' | 'tel' | 'email';
  } = $props();
</script>

<div class="campo">
  <label class="etiqueta" for={id}>{etiqueta}</label>
  {#if multilinea}
    <textarea
      {id}
      value={valor}
      oninput={(e) => (valor = e.currentTarget.value)}
      {placeholder}
      spellcheck={corrector}
    ></textarea>
  {:else}
    <div class="caja" class:con-prefijo={prefijo}>
      {#if prefijo}<span class="prefijo">{prefijo}</span>{/if}
      <input
        {id}
        type={tipo}
        value={valor}
        oninput={(e) => (valor = e.currentTarget.value)}
        {placeholder}
        {autocomplete}
        spellcheck={corrector}
        inputmode={modoTeclado}
        {min}
        {step}
      />
    </div>
  {/if}
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

  input,
  textarea {
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

  textarea {
    display: block;
    height: 72px;
    padding: 11px 14px;
    line-height: 1.45;
    resize: none;
  }

  .caja {
    position: relative;
    display: flex;
  }

  .prefijo {
    position: absolute;
    left: 14px;
    top: 0;
    height: 44px;
    display: flex;
    align-items: center;
    font-size: 13.5px;
    color: var(--suave);
    pointer-events: none;
  }

  .con-prefijo input {
    padding-left: 30px;
    font-variant-numeric: tabular-nums;
  }

  /* Como en la maqueta: solo las fechas llevan los números del mismo ancho. */
  input[type='date'] {
    font-variant-numeric: tabular-nums;
  }

  input:focus,
  textarea:focus {
    border-color: var(--suave);
  }

  input::placeholder,
  textarea::placeholder {
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
