<!--
  La ventana del producto, como la de SOHO (maqueta de la 6a, estado «Producto»): su foto grande (al
  tocarla se ve entera), su nombre, su precio, su descripción y sus grupos de opciones. En la 6a las
  opciones solo se leen; con la 6b se eligen aquí. Sin foto, la X va junto al nombre. Mientras recibe
  pedidos lleva su nota y, abajo, la cantidad y «Agregar al pedido · $50» (o «Elige Salsa» apagado
  mientras falte un grupo obligatorio). Desde «Tu pedido» se abre con lo que ya llevaba ese renglón.
-->
<script lang="ts">
  import { dinero } from '@app/lib/formato';
  import { urlImagen, type Grupo, type Producto } from '../lib/datos';
  import { precioUnitario, type Renglon } from '../lib/pedido';
  import { monto } from '../lib/precio';
  import type { Moneda } from '../lib/preferencias';
  import { enSuLengua, textoRegla, type Lengua, type Textos } from '../lib/textos';
  import Hoja from './Hoja.svelte';
  import Icono from './Icono.svelte';
  import Precio from './Precio.svelte';

  let {
    producto,
    lengua,
    moneda,
    t,
    recibe,
    inicial,
    alVerFoto,
    alAgregar,
    alCerrar,
  }: {
    producto: Producto;
    lengua: Lengua;
    moneda: Moneda;
    t: Textos;
    recibe: boolean;
    inicial: Renglon | null;
    alVerFoto: () => void;
    alAgregar: (r: Renglon) => void;
    alCerrar: () => void;
  } = $props();

  const nombre = $derived(enSuLengua(producto.nombre, producto.nombre_en, lengua));
  const descripcion = $derived(enSuLengua(producto.descripcion, producto.descripcion_en, lengua));

  // Lo elegido, por grupo, con las reglas del celular de Pepe (HojaOpciones del punto de venta): en
  // un grupo de una, tocar otra la cambia y tocar la elegida la quita solo si es opcional; en uno de
  // varias, se prenden y apagan hasta su máximo. Se arma una vez, al abrir la hoja.
  function alAbrir() {
    const ids = inicial?.opciones ?? [];
    return {
      elegidas: Object.fromEntries(producto.grupos.map((g) => [g.id, g.opciones.filter((o) => ids.includes(o.id)).map((o) => o.id)])),
      nota: inicial?.nota ?? '',
      cantidad: inicial?.cantidad ?? 1,
    };
  }
  const inicio = alAbrir();
  let elegidas = $state<Record<number, number[]>>(inicio.elegidas);
  let nota = $state(inicio.nota);
  let cantidad = $state(inicio.cantidad);

  function tocar(g: Grupo, id: number) {
    const ya = elegidas[g.id] ?? [];
    if (g.maximo === 1) elegidas[g.id] = ya.includes(id) && g.minimo === 0 ? [] : [id];
    else if (ya.includes(id)) elegidas[g.id] = ya.filter((x) => x !== id);
    else if (ya.length < g.maximo) elegidas[g.id] = [...ya, id];
  }

  const falta = $derived(producto.grupos.find((g) => (elegidas[g.id]?.length ?? 0) < g.minimo) ?? null);
  const opciones = $derived(producto.grupos.flatMap((g) => elegidas[g.id] ?? []));
  // Solo la vista, como en el celular de Pepe: el precio que vale lo pone Postgres.
  const importe = $derived(Math.round(precioUnitario(producto, opciones) * cantidad * 100) / 100);

  function agregar() {
    if (falta) return;
    alAgregar({ producto_id: producto.id, cantidad, opciones, nota: nota.trim() });
  }
</script>

<Hoja etiqueta={nombre} {alCerrar} pie={recibe ? pie : undefined}>
  {#if producto.imagen_ruta}
    <div class="arriba">
      <button type="button" class="foto-grande" aria-label={t.verFoto} onclick={alVerFoto}>
        <img src={urlImagen(producto.imagen_ruta)} alt="" />
        <span class="lupa"><Icono nombre="lupa" tamano={18} /></span>
      </button>
      <button type="button" class="cerrar-flota" aria-label={t.cerrar} onclick={alCerrar}><Icono nombre="cerrar" tamano={18} /></button>
    </div>
    <h3 class="nombre">{nombre}</h3>
  {:else}
    <div class="cabeza">
      <h3 class="nombre sin-foto">{nombre}</h3>
      <button type="button" class="cerrar" aria-label={t.cerrar} onclick={alCerrar}><Icono nombre="cerrar" tamano={18} /></button>
    </div>
  {/if}
  <div class="precio"><Precio {producto} {moneda} {t} /></div>
  {#if descripcion}<p class="desc">{descripcion}</p>{/if}
  {#each producto.grupos as g (g.id)}
    {@const faltaAqui = recibe && (elegidas[g.id]?.length ?? 0) < g.minimo}
    <div class="grupo">
      <div class="grupo-cabeza">
        <span class="grupo-titulo">{enSuLengua(g.nombre, g.nombre_en, lengua)}</span>
        <span class="regla" class:falta={faltaAqui}>{textoRegla(g.minimo, g.maximo, lengua)}{faltaAqui ? ` · ${t.falta}` : ''}</span>
      </div>
      {#each g.opciones as o (o.id)}
        {@const si = elegidas[g.id]?.includes(o.id) ?? false}
        {#if recibe}
          <button type="button" class="op elegible" role={g.maximo === 1 ? 'radio' : 'checkbox'} aria-checked={si} onclick={() => tocar(g, o.id)}>
            <span class="izq">
              <span class="marca" class:redonda={g.maximo === 1}>{#if si}<Icono nombre="check" tamano={12} />{/if}</span>
              {enSuLengua(o.nombre, o.nombre_en, lengua)}
            </span>
            <span class="extra" class:cero={!o.precio_extra}>
              {o.precio_extra ? `+${monto(o.precio_extra, o.precio_extra_usd, moneda)}` : t.incluido}
            </span>
          </button>
        {:else}
          <div class="op">
            <span>{enSuLengua(o.nombre, o.nombre_en, lengua)}</span>
            <span class="extra" class:cero={!o.precio_extra}>
              {o.precio_extra ? `+${monto(o.precio_extra, o.precio_extra_usd, moneda)}` : t.incluido}
            </span>
          </div>
        {/if}
      {/each}
    </div>
  {/each}
  {#if recibe}
    <div class="m-campo">
      <label for="m-nota">{t.nota}</label>
      <input id="m-nota" bind:value={nota} placeholder={t.notaEjemplo} maxlength="140" autocomplete="off" />
    </div>
  {/if}
</Hoja>

<!-- El pedido va siempre en pesos: con dólares, el botón dice «MX$». -->
{#snippet pie()}
  <span class="m-paso" role="group" aria-label={t.cantidad}>
    <button type="button" aria-label={t.unoMenos} disabled={cantidad <= 1} onclick={() => (cantidad = Math.max(1, cantidad - 1))}>
      <Icono nombre="menos" tamano={16} />
    </button>
    <span>{cantidad}</span>
    <button type="button" aria-label={t.unoMas} disabled={cantidad >= 99} onclick={() => (cantidad = Math.min(99, cantidad + 1))}>
      <Icono nombre="mas" tamano={16} />
    </button>
  </span>
  <button type="button" class="m-boton" disabled={!!falta} onclick={agregar}>
    {falta ? `${t.elige} ${enSuLengua(falta.nombre, falta.nombre_en, lengua)}` : `${inicial ? t.guardarCambios : t.agregar} · ${moneda === 'usd' ? 'MX' : ''}${dinero(importe)}`}
  </button>
{/snippet}

<style>
  .arriba {
    position: relative;
  }

  .foto-grande {
    position: relative;
    width: 100%;
    aspect-ratio: 16 / 11;
    border-radius: 20px;
    overflow: hidden;
    border: 0;
    padding: 0;
    display: block;
    background: var(--m-chip);
  }

  .foto-grande img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .lupa {
    position: absolute;
    right: 10px;
    bottom: 10px;
    width: 34px;
    height: 34px;
    border-radius: 17px;
    background: rgba(0, 0, 0, 0.45);
    color: #fff;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .cerrar-flota {
    position: absolute;
    top: 12px;
    right: 12px;
    width: 36px;
    height: 36px;
    border-radius: 18px;
    border: 0;
    background: rgba(0, 0, 0, 0.45);
    color: #fff;
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1;
    padding: 0;
  }

  .cabeza {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 12px;
  }

  .cerrar {
    width: 40px;
    height: 40px;
    flex: none;
    border-radius: 20px;
    border: 1px solid var(--m-linea);
    background: transparent;
    color: var(--m-texto);
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0;
  }

  .nombre {
    margin: 16px 0 0;
    font-size: 23px;
    font-weight: 800;
    letter-spacing: -0.4px;
    line-height: 1.2;
  }

  .nombre.sin-foto {
    margin-top: 6px;
  }

  .precio {
    margin-top: 6px;
    font-size: 17px;
    font-weight: 800;
    font-variant-numeric: tabular-nums;
  }

  .desc {
    margin: 8px 0 0;
    font-size: 14px;
    line-height: 1.55;
    color: var(--m-suave);
  }

  .grupo {
    margin-top: 22px;
  }

  .grupo-cabeza {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 10px;
    padding-bottom: 8px;
    border-bottom: 1px solid var(--m-linea);
  }

  .grupo-titulo {
    font-family: var(--mono);
    font-size: 11px;
    letter-spacing: 0.14em;
    text-transform: uppercase;
    color: var(--m-texto);
    font-weight: 600;
  }

  .regla {
    font-size: 12px;
    color: var(--m-tenue);
  }

  .op {
    display: flex;
    justify-content: space-between;
    gap: 10px;
    padding: 12px 0;
    border-bottom: 1px solid var(--m-linea);
    font-size: 14.5px;
  }

  .op:last-child {
    border-bottom: 0;
  }

  .op.elegible {
    width: 100%;
    align-items: center;
    border-top: 0;
    border-left: 0;
    border-right: 0;
    background: transparent;
    color: var(--m-texto);
    text-align: left;
    font: inherit;
    font-size: 14.5px;
  }

  .op[aria-checked='true'] {
    font-weight: 700;
  }

  .izq {
    display: flex;
    align-items: center;
    gap: 12px;
    min-width: 0;
  }

  .marca {
    width: 20px;
    height: 20px;
    flex: none;
    border: 1.6px solid var(--m-tenue);
    border-radius: 6px;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .marca.redonda {
    border-radius: 10px;
  }

  .op[aria-checked='true'] .marca {
    border: 0;
    background: var(--m-acento);
    color: var(--m-sobre-acento);
  }

  .regla.falta {
    color: var(--m-texto);
    font-weight: 700;
  }

  .extra {
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    white-space: nowrap;
  }

  .extra.cero {
    color: var(--m-tenue);
    font-weight: 500;
  }
</style>
