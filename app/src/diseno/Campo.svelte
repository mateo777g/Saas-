<!--
  campo() de diseno.py: una caja de texto con su etiqueta encima ("NOMBRE", mono) y, si hace falta,
  una pista debajo. Radio 12, 44 de alto, letra 13.5. Desde el 9 nov 2026, como el Input de HeroUI:
  sin borde, en --campo-fondo con su sombra suave, un poco más gris con el mouse encima y, mientras se
  escribe, un aro azul de 2 px (--campo-aro); el dato que no se pudo guardar lleva el aro en rojo.
  `valor` siempre es texto, también en las fechas ('aaaa-mm-dd') y los números: quien guarda lo
  convierte. Como en Flet, puede llevar un `prefijo` adentro, a la izquierda ("$" en el precio), o
  ser `multilinea` (la descripción de un producto: 72 de alto). Con `contador`, a la derecha de la etiqueta
  va cuántas letras lleva de `largoMaximo` («23 / 80», lo que dice el cuadro de un estilo). `marca` va adentro de la
  caja, después del campo (la marquita «EN» del grupo en inglés de Mi menú).
-->
<script lang="ts">
  import type { Snippet } from 'svelte';

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
    largoMaximo,
    mal = false,
    mono = false,
    contador = false,
    marca,
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
    largoMaximo?: number;
    // El borde rojo del dato que no se pudo guardar (el teléfono de Tu restaurante).
    mal?: boolean;
    mono?: boolean;
    contador?: boolean;
    marca?: Snippet;
  } = $props();
</script>

<div class="campo">
  {#if contador && largoMaximo}
    <div class="etiqueta-fila">
      <label class="etiqueta" for={id}>{etiqueta}</label>
      <span class="letras">{valor.length} / {largoMaximo}</span>
    </div>
  {:else}
    <label class="etiqueta" for={id}>{etiqueta}</label>
  {/if}
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
        maxlength={largoMaximo}
        class:mal
        class:mono
        aria-invalid={mal || undefined}
      />
      {@render marca?.()}
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

  .etiqueta-fila {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 12px;
  }

  .letras {
    font-family: var(--mono);
    font-size: 11px;
    color: var(--tenue);
    font-variant-numeric: tabular-nums;
  }

  input,
  textarea {
    width: 100%;
    height: 44px;
    padding: 0 14px;
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

  input:hover:not(:focus),
  textarea:hover:not(:focus) {
    background: var(--campo-encima);
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
    box-shadow: 0 0 0 2px var(--campo-aro);
  }

  input.mal {
    box-shadow: 0 0 0 1px var(--rojo);
  }

  input.mal:focus {
    box-shadow: 0 0 0 2px var(--rojo);
  }

  @media (prefers-reduced-motion: reduce) {
    input,
    textarea {
      transition: none;
    }
  }

  input.mono {
    font-family: var(--mono);
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
