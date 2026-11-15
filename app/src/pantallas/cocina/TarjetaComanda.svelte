<!--
  Una comanda en la Cocina nueva (rediseño, 14 nov 2026; planes/trabajo/rediseno/cocina.md): la tarjeta de Pedidos a lo
  ancho (caja/pedidos/TarjetaPedido.svelte), que es la de Crear anuncios, con su cuadrito e ícono del tipo de cuenta, «Mesa
  4», «Pepe · 14:05» y, a la derecha, los minutos que lleva esperando. Toda la tarjeta es el botón: un toque la marca
  «Lista» (o la quita, si se canceló todo), como siempre. A los 10 minutos se pone amarilla y a los 20, roja: el chip de
  los minutos se llena de ese color y la tarjeta lleva su aro.

  Lo cancelado (parte 4c) sale tachado en rojo con «Cancelado · «motivo»»; la tarjeta dice «Cambió» o «Todo cancelado».
  Sin comanda es su esqueleto: la misma tarjeta con bloques del mismo tamaño en el lugar de cada texto.
-->
<script lang="ts">
  import Esqueleto from '../../diseno/Esqueleto.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import { ICONO_DE_TIPO, type Tarjeta } from '../../lib/pos';

  let {
    comanda,
    sub = '',
    minutos = 0,
    forma = { titulo: '96px', sub: '120px', renglones: 2 },
    alTocar = () => {},
  }: {
    comanda: Tarjeta | null;
    sub?: string; // «Para llevar · WhatsApp · Lupita · 14:05»
    minutos?: number;
    forma?: { titulo: string; sub: string; renglones: number };
    alTocar?: () => void;
  } = $props();

  // «Cambió» si se canceló algo; «Todo cancelado» si se canceló todo.
  const cambio = $derived.by((): 'todo' | 'algo' | null => {
    if (!comanda) return null;
    const cancelados = comanda.renglones.filter((r) => r.estado === 'cancelado').length;
    if (cancelados === 0) return null;
    return cancelados === comanda.renglones.length ? 'todo' : 'algo';
  });
  const NOMBRES = ['118px', '86px', '140px'];
</script>

{#if comanda}
  {@const t = comanda}
  {@const k = cambio}
  <button
    type="button"
    class="tarjeta comanda"
    class:todo={k === 'todo'}
    class:amarilla={k !== 'todo' && minutos >= 10 && minutos < 20}
    class:roja={k !== 'todo' && minutos >= 20}
    data-comanda={t.id}
    aria-label="{k === 'todo' ? 'Quitar' : 'Marcar lista'} la comanda de {t.titulo}"
    onclick={alTocar}
  >
    <span class="encabezado">
      <span class="cuadrito"><Icono nombre={ICONO_DE_TIPO[t.tipo]} tamano={18} /></span>
      <span class="titulos">
        <span class="titulo">{t.titulo}</span>
        <span class="sub">{sub}</span>
      </span>
      {#if k !== 'todo'}<span class="minutos">{minutos} min</span>{/if}
    </span>

    <!-- En su renglón, debajo de la cabeza: así no le quita lugar a quién la mandó y la hora. -->
    {#if k}
      <span class="marca-cambio"><Icono nombre="alerta" tamano={13} />{k === 'todo' ? 'Todo cancelado' : 'Cambió'}</span>
    {/if}

    <span class="lineas">
      {#each t.renglones as r (r.id)}
        <span class="linea" class:cancelado={r.estado === 'cancelado'}>
          <span class="cant">{r.cantidad} ×</span>
          <b>{r.nombre}</b>
          {#if r.opciones.length}<span class="det">{r.opciones.map((o) => o.opcion).join(' · ')}</span>{/if}
          {#if r.nota && r.estado === 'activo'}<span class="nota">{r.nota}</span>{/if}
          {#if r.estado === 'cancelado'}<span class="cancel">Cancelado · «{r.cancelado_motivo}»</span>{/if}
        </span>
      {/each}
    </span>

    <span class="pista">
      <Icono nombre={k === 'todo' ? 'cerrar' : 'check-delgado'} tamano={14} />{k === 'todo' ? 'Toca para quitarla' : 'Toca cuando salga todo'}
    </span>
  </button>
{:else}
  <div class="tarjeta comanda" aria-hidden="true">
    <span class="encabezado">
      <Esqueleto ancho="36px" alto="36px" redondo="11px" />
      <span class="titulos">
        <span class="titulo"><Esqueleto ancho={forma.titulo} alto="15px" /></span>
        <span class="sub"><Esqueleto ancho={forma.sub} alto="11px" /></span>
      </span>
      <Esqueleto ancho="54px" alto="28px" redondo="8px" />
    </span>
    <span class="lineas">
      {#each NOMBRES.slice(0, forma.renglones) as nombre, i (i)}
        <span class="linea">
          <span class="cant"><Esqueleto ancho="24px" alto="14px" /></span>
          <b><Esqueleto ancho={nombre} alto="14px" /></b>
        </span>
      {/each}
    </span>
    <span class="pista escondida"><Icono nombre="check-delgado" tamano={14} />Toca cuando salga todo</span>
  </div>
{/if}

<style>
  /* La tarjeta de Crear anuncios (la de Pedidos a lo ancho): blanca, borde, 14 de esquina, sin sombra. Es un botón. */
  .tarjeta {
    width: 100%;
    padding: 20px;
    background: var(--solido);
    border: 1px solid var(--borde-tarjeta);
    border-radius: 14px;
    display: flex;
    flex-direction: column;
    gap: 16px;
    min-width: 0;
    color: var(--texto);
    text-align: left;
    font: inherit;
  }

  button.tarjeta {
    cursor: pointer;
    transition:
      transform 0.15s ease,
      box-shadow 0.2s ease,
      border-color 0.2s ease;
  }

  button.tarjeta:active {
    transform: scale(0.98);
  }

  button.tarjeta:focus-visible {
    outline: none;
    box-shadow: 0 0 0 2px var(--campo-aro);
  }

  /* A los 10 minutos, amarilla; a los 20, roja: su aro de 2 y el chip de los minutos lleno. */
  .comanda.amarilla {
    border-color: var(--amarillo);
    box-shadow: 0 0 0 1px var(--amarillo);
  }

  .comanda.roja {
    border-color: var(--rojo);
    box-shadow: 0 0 0 1px var(--rojo);
  }

  .encabezado {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .cuadrito {
    width: 36px;
    height: 36px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 11px;
    background: var(--chip);
    color: var(--texto);
  }

  .titulos {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  /* Un poco más grande que en Pedidos: la cocina se lee de lejos. */
  .titulo {
    font-size: 16px;
    font-weight: 800;
    letter-spacing: -0.2px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  /* Baja a otro renglón si no cabe: el tipo, quién la mandó y la hora se leen siempre completos. */
  .sub {
    font-size: 12.5px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .minutos {
    height: 28px;
    min-width: 54px;
    padding: 0 9px;
    flex: none;
    display: grid;
    place-items: center;
    border-radius: 8px;
    background: var(--chip);
    font-family: var(--mono);
    font-size: 14px;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
    white-space: nowrap;
  }

  .amarilla .minutos {
    background: var(--amarillo);
    color: var(--sobre-amarillo);
  }

  .roja .minutos {
    background: var(--rojo);
    color: var(--sobre-rojo);
  }

  .marca-cambio {
    height: 28px;
    flex: none;
    align-self: flex-start;
    margin-top: -4px;
    display: inline-flex;
    align-items: center;
    gap: 5px;
    padding: 0 9px;
    border-radius: 8px;
    background: var(--tinta);
    color: var(--sobre-tinta);
    font-size: 12px;
    font-weight: 700;
    white-space: nowrap;
  }

  .lineas {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .linea {
    display: grid;
    grid-template-columns: 34px minmax(0, 1fr);
    gap: 2px 8px;
    font-size: 15px;
    line-height: 1.3;
  }

  .linea .cant {
    font-family: var(--mono);
    font-weight: 600;
    font-variant-numeric: tabular-nums;
  }

  .linea b {
    font-weight: 700;
    min-width: 0;
  }

  .linea .det {
    grid-column: 2;
    font-size: 13px;
    color: var(--suave);
    line-height: 1.4;
  }

  .linea .nota {
    grid-column: 2;
    font-size: 13px;
    font-weight: 700;
    line-height: 1.4;
  }

  .linea .nota::before {
    content: 'Nota: ';
    font-weight: 500;
    color: var(--tenue);
  }

  /* Lo cancelado (parte 4c): tachado en rojo, con su motivo. */
  .linea.cancelado .cant,
  .linea.cancelado b {
    text-decoration: line-through;
    color: var(--rojo);
  }

  .linea .cancel {
    grid-column: 2;
    font-size: 13px;
    font-weight: 700;
    color: var(--rojo);
    line-height: 1.4;
  }

  /* La pista de abajo, como «Confírmalo cuando te llegue su WhatsApp.» de Pedidos. */
  /* La comanda llena su celda (Tablero, parejas por fila); la pista se va abajo, alineada con las de al lado. */
  .pista {
    margin-top: auto;
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 12px;
    color: var(--tenue);
  }

  .todo .pista {
    color: var(--texto);
    font-weight: 600;
  }

  .escondida {
    visibility: hidden;
  }

  @media (prefers-reduced-motion: reduce) {
    button.tarjeta {
      transition: none;
    }

    button.tarjeta:active {
      transform: none;
    }
  }
</style>
