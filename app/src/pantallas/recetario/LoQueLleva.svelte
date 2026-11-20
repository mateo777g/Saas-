<!--
  La tarjeta «Lo que lleva» de la página del recetario (maqueta DFVTWEB3eZBEKctyxWjGjg v1): lo que lleva sale de la
  receta tal cual, en el orden en que se escribió, sin abrir las preparaciones («30 ml de Salsa verde»), y debajo, en la
  misma tarjeta, «Si lleva»: las opciones que suman algo, con su nombre en negritas. Una preparación sale en azul con su
  flecha y abre su recetario (en la cocina y la caja, solo si tiene pasos).

  En su cabeza, «Para más porciones»: − el número +, o se escribe. Un platillo empieza en 1 y una preparación en lo que
  rinde (con su unidad); multiplica las cantidades de lo que lleva y de sus opciones y las escribe como el inventario
  (2,000 g sale «2 kg»). No guarda nada: al salir de la página vuelve a empezar. En «Editar» no va (`porciones` falso).
-->
<script lang="ts">
  import './recetario.css';
  import BotonCuadro from '../../diseno/BotonCuadro.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import { enCaja, SUFIJO_UNIDAD } from '../../lib/inventario';
  import { cantidadPorciones, leerPorciones, type Lleva, type Pagina } from '../../lib/recetario';

  let {
    pagina,
    porciones = true,
    enAparato = false,
    alAbrirPreparacion = null,
  }: {
    pagina: Pagina;
    porciones?: boolean;
    enAparato?: boolean;
    // Tocar una preparación de lo que lleva; sin esto (en «Editar»), su nombre no se toca.
    alAbrirPreparacion?: ((id: number) => void) | null;
  } = $props();

  // Para cuánto: un platillo desde 1; una preparación desde lo que rinde, y el − y el + van de una olla en una olla.
  // svelte-ignore state_referenced_locally
  const base = pagina.tipo === 'preparacion' && pagina.rinde ? pagina.rinde : 1;
  let escrito = $state(enCaja(base));
  const valor = $derived(leerPorciones(escrito));
  // Mientras lo que se escribió no es un número, se queda lo de antes.
  let ultimo = $state(base);
  $effect(() => {
    if (valor !== null) ultimo = valor;
  });
  const veces = $derived(porciones ? ultimo / base : 1);

  function mover(signo: 1 | -1) {
    const ahora = Math.round(ultimo / base) * base;
    const siguiente = Math.max(base, ahora + signo * base);
    escrito = enCaja(siguiente);
  }

  const sufijo = $derived(pagina.tipo === 'preparacion' && pagina.unidad ? SUFIJO_UNIDAD[pagina.unidad] : null);
  const abre = (l: Lleva) => alAbrirPreparacion !== null && l.preparacion_id !== null && (!enAparato || l.con_pasos === true);
</script>

{#snippet renglon(l: Lleva)}
  <b class="cant">{cantidadPorciones(l.cantidad * veces, l.unidad)}</b><span class="de">de</span>
  {#if abre(l)}
    <button type="button" class="enlace" onclick={() => alAbrirPreparacion?.(l.preparacion_id!)}>{l.nombre} <Icono nombre="derecha" tamano={13} /></button>
  {:else}
    <span class="que">{l.nombre}</span>
  {/if}
{/snippet}

<div class="tarjeta rec-tarjeta rec-lleva">
  <div class="cabeza">
    <span class="rec-etq">LO QUE LLEVA</span>
    {#if porciones}
      <div class="porciones">
        <span class="rec-etq">PARA MÁS PORCIONES</span>
        <div class="control">
          <BotonCuadro icono="menos" ayuda="Menos" apagado={ultimo <= base} onclick={() => mover(-1)} />
          <span class="caja" class:con-sufijo={sufijo}>
            <input
              type="text"
              inputmode="decimal"
              aria-label={pagina.tipo === 'preparacion' ? 'Cuánto quieres hacer' : 'Para cuántos'}
              bind:value={escrito}
              onblur={() => valor === null && (escrito = enCaja(ultimo))}
            />
            {#if sufijo}<span class="sufijo">{sufijo}</span>{/if}
          </span>
          <BotonCuadro icono="mas" ayuda="Más" onclick={() => mover(1)} />
        </div>
      </div>
    {/if}
  </div>
  {#if pagina.lleva.length}
    <ul class="lista">
      {#each pagina.lleva as l, i (i)}
        <li class="renglon">{@render renglon(l)}</li>
      {/each}
    </ul>
  {:else}
    <p class="vacia">Todavía no tiene receta: no resta nada del inventario.</p>
  {/if}
  {#if pagina.opciones.length}
    <div class="opciones">
      <span class="rec-etq">SI LLEVA</span>
      <ul class="lista">
        {#each pagina.opciones as o, i (i)}
          <li class="renglon">
            <span class="op-nombre">{o.nombre}</span>
            {#each o.lleva as l, j (j)}
              {#if j}<span class="de">·</span>{/if}{@render renglon(l)}
            {/each}
          </li>
        {/each}
      </ul>
    </div>
  {/if}
</div>

<style>
  .rec-lleva {
    align-self: stretch;
    padding: 14px 16px 6px;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .cabeza {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    flex-wrap: wrap;
    min-height: 44px;
  }

  .porciones {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .control {
    display: flex;
    align-items: center;
    gap: 6px;
  }

  /* La caja de texto de Campo.svelte, angosta y con el número al centro, en mono. */
  .caja {
    position: relative;
    display: flex;
    width: 76px;
  }

  .caja.con-sufijo {
    width: 96px;
  }

  input {
    width: 100%;
    height: 44px;
    padding: 0 10px;
    border: 0;
    border-radius: 12px;
    background: var(--campo-fondo);
    box-shadow: var(--campo-sombra);
    color: var(--texto);
    font-family: var(--mono);
    font-size: 13.5px;
    font-weight: 600;
    text-align: center;
    outline: none;
    transition:
      background-color 0.15s ease,
      box-shadow 0.15s ease-out;
  }

  .con-sufijo input {
    padding-right: 30px;
  }

  input:hover:not(:focus) {
    background: var(--campo-encima);
  }

  /* Al escribir, el aro azul de las cajas de texto. */
  input:focus {
    box-shadow: 0 0 0 2px var(--campo-aro);
  }

  .sufijo {
    position: absolute;
    right: 12px;
    top: 0;
    height: 44px;
    display: flex;
    align-items: center;
    font-family: var(--mono);
    font-size: 12px;
    font-weight: 500;
    color: var(--tenue);
    pointer-events: none;
  }

  .lista {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
  }

  .renglon {
    display: flex;
    align-items: baseline;
    flex-wrap: wrap;
    gap: 6px;
    padding: 10px 0;
    border-top: 1px solid var(--linea);
    font-size: 14px;
    font-weight: 500;
    color: var(--texto);
  }

  .lista > .renglon:first-child {
    border-top: 0;
  }

  .cant {
    font-family: var(--mono);
    font-size: 13px;
    font-weight: 600;
    color: var(--texto);
  }

  .de {
    color: var(--tenue);
  }

  .enlace {
    display: inline-flex;
    align-items: center;
    gap: 2px;
    border: 0;
    padding: 0;
    background: none;
    font: inherit;
    color: var(--acento);
    cursor: pointer;
  }

  .enlace:hover {
    text-decoration: underline;
    text-underline-offset: 3px;
  }

  .opciones {
    border-top: 1px solid var(--linea);
    padding: 12px 0 4px;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .opciones .renglon {
    padding: 6px 0;
    border-top: 0;
  }

  .op-nombre {
    font-weight: 700;
    margin-right: 6px;
  }

  .vacia {
    margin: 0;
    padding: 10px 0 12px;
    font-size: 13px;
    font-weight: 500;
    color: var(--tenue);
  }
</style>
