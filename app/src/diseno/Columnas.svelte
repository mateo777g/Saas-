<!--
  Las tres columnas de Inicio (maqueta V64Pv4gmANPRZuJW5hTe5D): Abrir, Atajos y Recientes, las últimas 5
  vistas que se abrieron en este navegador. Cada panel pone sus renglones. Sin atajos (el distribuidor no
  tiene acciones; encuesta del 8 nov 2026) son dos columnas: Abrir y Recientes.
-->
<script lang="ts" module>
  export type ItemColumna = {
    clave: string;
    texto: string;
    de?: string;
    icono: string;
    // Lo que abre aparte lleva la flecha hacia afuera.
    flecha?: 'r-derecha' | 'r-afuera';
    alPicar: () => void;
  };
</script>

<script lang="ts">
  import Icono from './Icono.svelte';

  let {
    abrir,
    atajos,
    recientes,
    entra = false,
  }: {
    abrir: ItemColumna[];
    atajos?: ItemColumna[];
    recientes: ItemColumna[];
    // Al llegar, las columnas salen en fila como las ideas del Agente IA (los tres Inicios, desde el 8 nov 2026).
    entra?: boolean;
  } = $props();
</script>

{#snippet renglones(lista: ItemColumna[])}
  {#each lista as a (a.clave)}
    <button type="button" class="item" onclick={a.alPicar}>
      <span class="icono"><Icono nombre={a.icono} tamano={18} /></span>
      <span class="t">{#if a.de}<span class="de">{a.de} /</span>{' '}{/if}{a.texto}</span>
      <span class="ir"><Icono nombre={a.flecha ?? 'r-derecha'} tamano={14} /></span>
    </button>
  {/each}
{/snippet}

<div class="columnas" class:entra class:dos={!atajos}>
  <div style="--i: 0">
    <div class="titulo">Abrir <Icono nombre="r-derecha" tamano={14} /></div>
    {@render renglones(abrir)}
  </div>

  {#if atajos}
    <div style="--i: 1">
      <div class="titulo">Atajos <Icono nombre="r-derecha" tamano={14} /></div>
      {@render renglones(atajos)}
    </div>
  {/if}

  <div style:--i={atajos ? 2 : 1}>
    <div class="titulo">Recientes</div>
    {#if !recientes.length}
      <p class="vacio">Aquí salen las vistas que abras</p>
    {/if}
    {@render renglones(recientes)}
  </div>
</div>

<style>
  .columnas {
    width: 100%;
    max-width: 1000px;
    margin: 34px auto 0;
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 32px;
  }

  .columnas.dos {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }

  /* Como las ideas del Agente IA (gerente/Agente.svelte, .aparece): suben 10 px desde 97 % con su rebote, a 220 ms
     + 80 ms × i. Aquí cuentan desde que sube el saludo de Inicio (0.1 s). Escondidas mientras esperan, para no
     picarlas sin verlas. */
  .entra > div {
    animation:
      columna-aparece 0.35s ease calc(0.32s + var(--i) * 80ms) both,
      columna-sube 0.45s cubic-bezier(0.175, 0.885, 0.32, 1.275) calc(0.32s + var(--i) * 80ms) both;
  }

  @keyframes columna-aparece {
    from {
      opacity: 0;
      visibility: hidden;
    }
  }

  @keyframes columna-sube {
    from {
      transform: translateY(10px) scale(0.97);
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .entra > div {
      animation: none;
    }
  }

  .titulo {
    display: flex;
    align-items: center;
    gap: 4px;
    padding-bottom: 8px;
    font-size: 13px;
    font-weight: 400;
    color: var(--suave);
  }

  .item {
    width: 100%;
    height: 52px;
    display: flex;
    align-items: center;
    gap: 11px;
    padding: 0;
    border: 0;
    border-bottom: 1px solid var(--linea);
    background: transparent;
    color: var(--texto);
    font-size: 14.5px;
    font-weight: 500;
    text-align: left;
  }

  .item:last-child {
    border-bottom: 0;
  }

  .icono {
    display: flex;
    color: var(--suave);
  }

  /* El relleno de arriba y abajo deja lugar al subrayado: el overflow del «…» lo recortaba. */
  .t {
    flex: 1;
    min-width: 0;
    padding: 6px 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .de {
    font-weight: 400;
    color: var(--tenue);
  }

  .ir {
    display: flex;
    color: var(--tenue);
  }

  /* Con el mouse encima, como en el inicio de Cloudflare: el texto subrayado y el ícono y la flecha en tinta
     (negro en claro, blanco en oscuro; el developer, 8 nov 2026). */
  .item:hover .t {
    text-decoration: underline;
    text-decoration-thickness: 1px;
    text-underline-offset: 5px;
  }

  .item:hover .icono,
  .item:hover .ir {
    color: var(--texto);
  }

  .vacio {
    margin: 0;
    padding-top: 8px;
    font-size: 13.5px;
    font-weight: 400;
    line-height: 1.45;
    color: var(--tenue);
  }
</style>
