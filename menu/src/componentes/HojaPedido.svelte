<!--
  «Tu pedido» (maqueta de la 6b, estados «Tu pedido», «A domicilio», «Cambió algo» y «Límite»): sus
  renglones con − / + (con 1, el − lo quita), para llevar o a domicilio (solo si Don Chuy hace envíos),
  los datos que pide cada uno, el total y «Hacer pedido». Al tocar un renglón se reabre su hoja. Si
  Postgres dijo que algo cambió, cada renglón dice qué; lo que ya no hay sale tachado y se quita al
  volver a tocar «Hacer pedido». La revisión de Cloudflare vive en su hueco, abajo: invisible, salvo
  si duda.
-->
<script lang="ts">
  import { dinero } from '@app/lib/formato';
  import type { Producto } from '../lib/datos';
  import { precioUnitario, type Cliente, type EnCarrito, type Tipo } from '../lib/pedido';
  import { quitarRevision } from '../lib/turnstile';
  import type { Moneda } from '../lib/preferencias';
  import { enSuLengua, type Lengua, type Textos } from '../lib/textos';
  import Hoja from './Hoja.svelte';
  import Icono from './Icono.svelte';

  let {
    renglones,
    productos,
    lengua,
    moneda,
    t,
    haceEnvios,
    tipoCambio,
    tipo = $bindable(),
    cliente = $bindable(),
    aviso,
    limite,
    telefono,
    ocupado,
    hueco = $bindable(),
    alCantidad,
    alAbrirRenglon,
    alHacer,
    alCerrar,
  }: {
    renglones: EnCarrito[];
    productos: Map<number, Producto>;
    lengua: Lengua;
    moneda: Moneda;
    t: Textos;
    haceEnvios: boolean;
    tipoCambio: number | null;
    tipo: Tipo;
    cliente: Cliente & { pagaCon: string };
    aviso: { titulo?: string; texto: string } | null;
    limite: boolean;
    telefono: string;
    ocupado: boolean;
    hueco: HTMLDivElement | undefined;
    alCantidad: (i: number, cambio: number) => void;
    alAbrirRenglon: (i: number) => void;
    alHacer: () => void;
    alCerrar: () => void;
  } = $props();

  // La revisión de Cloudflare vive mientras la hoja está abierta.
  $effect(() => () => quitarRevision());

  const dom = $derived(tipo === 'domicilio');
  // El pedido va siempre en pesos; con dólares, «MX$» y abajo del total su «≈ US$».
  const pesos = (n: number) => `${moneda === 'usd' ? 'MX' : ''}${dinero(n)}`;
  const importe = (r: EnCarrito) => {
    const p = productos.get(r.producto_id);
    return Math.round((p ? precioUnitario(p, r.opciones) : r.precio) * r.cantidad * 100) / 100;
  };
  const total = $derived(Math.round(renglones.filter((r) => !r.aviso?.fuera).reduce((s, r) => s + importe(r), 0) * 100) / 100);
  // Solo un «aprox.» para orientarse, con el tipo de cambio de Don Chuy: el pedido se cobra en pesos.
  const usd = $derived(tipoCambio ? (total / tipoCambio).toFixed(2) : null);

  function opcionesTexto(r: EnCarrito): string {
    const p = productos.get(r.producto_id);
    if (!p) return '';
    return p.grupos
      .flatMap((g) => g.opciones)
      .filter((o) => r.opciones.includes(o.id))
      .map((o) => enSuLengua(o.nombre, o.nombre_en, lengua))
      .join(' · ');
  }

  const digitos = (s: string) => s.replace(/[\s().-]/g, '');
  const listo = $derived(
    renglones.some((r) => !r.aviso?.fuera) &&
      cliente.nombre.trim() !== '' &&
      (!dom || (/^\d{10}$/.test(digitos(cliente.telefono)) && cliente.direccion.trim() !== '')) &&
      (!dom || cliente.pagaCon.trim() === '' || Number.isFinite(Number(cliente.pagaCon.trim()))),
  );
</script>

<Hoja etiqueta={t.tuPedido} {alCerrar} {pie}>
  <div class="cabeza">
    <h3 class="titulo">{t.tuPedido}</h3>
    <button type="button" class="cerrar" aria-label={t.cerrar} onclick={alCerrar}><Icono nombre="cerrar" tamano={18} /></button>
  </div>

  {#if aviso}
    <div class="m-aviso" role="alert">
      <Icono nombre="alerta" tamano={17} />
      <span>
        {#if aviso.titulo}<b>{aviso.titulo}.</b>{/if}
        {aviso.texto}
        {#if limite}
          <a class="boton-wa" href={`https://wa.me/52${telefono}`} target="_blank" rel="noopener">
            <Icono nombre="mensaje" tamano={15} />{t.escribir}
          </a>
        {/if}
      </span>
    </div>
  {/if}

  <div class="lineas">
    {#each renglones as r, i (i)}
      {@const ops = opcionesTexto(r)}
      {@const fuera = !!r.aviso?.fuera}
      <div class="linea" class:fuera>
        <button type="button" class="q" disabled={fuera} onclick={() => alAbrirRenglon(i)}>
          <b>{enSuLengua(r.nombre, r.nombre_en, lengua)}</b>
          {#if ops}<span class="d">{ops}</span>{/if}
          {#if r.nota}<span class="d">{t.notaRenglon}{r.nota}</span>{/if}
        </button>
        <span class="imp">{pesos(importe(r))}</span>
        {#if fuera}
          <span class="aviso-linea"><Icono nombre="alerta" tamano={14} />{r.aviso?.texto}</span>
        {:else}
          <span class="abajo">
            <span class="m-paso chico" role="group" aria-label={t.cantidad}>
              <button type="button" aria-label={r.cantidad === 1 ? t.quitar : t.unoMenos} onclick={() => alCantidad(i, -1)}>
                <Icono nombre={r.cantidad === 1 ? 'eliminar' : 'menos'} tamano={15} />
              </button>
              <span>{r.cantidad}</span>
              <button type="button" aria-label={t.unoMas} disabled={r.cantidad >= 99} onclick={() => alCantidad(i, 1)}>
                <Icono nombre="mas" tamano={15} />
              </button>
            </span>
            {#if r.aviso}<span class="aviso-linea"><Icono nombre="alerta" tamano={14} />{r.aviso.texto}</span>{/if}
          </span>
        {/if}
      </div>
    {/each}
  </div>

  {#if haceEnvios}
    <div class="seg" role="group" aria-label={t.comoLoRecibes}>
      <button type="button" aria-pressed={!dom} onclick={() => (tipo = 'para_llevar')}><Icono nombre="bolsa" tamano={16} />{t.llevar}</button>
      <button type="button" aria-pressed={dom} onclick={() => (tipo = 'domicilio')}><Icono nombre="moto" tamano={16} />{t.domicilio}</button>
    </div>
  {/if}

  <div class="m-campo">
    <label for="m-nombre">{t.tuNombre}</label>
    <input id="m-nombre" bind:value={cliente.nombre} placeholder={t.nombreEjemplo} maxlength="60" autocomplete="name" />
  </div>
  {#if dom}
    <div class="m-campo">
      <label for="m-tel">{t.telefono}</label>
      <input id="m-tel" bind:value={cliente.telefono} placeholder={t.telefonoEjemplo} inputmode="tel" autocomplete="tel-national" />
    </div>
    <div class="m-campo">
      <label for="m-dir">{t.tuDireccion}</label>
      <input id="m-dir" bind:value={cliente.direccion} placeholder={t.direccionEjemplo} maxlength="200" autocomplete="street-address" />
    </div>
    <div class="m-campo">
      <label for="m-ref">{t.referencias}</label>
      <input id="m-ref" bind:value={cliente.referencias} placeholder={t.referenciasEjemplo} maxlength="120" autocomplete="off" />
    </div>
    <div class="m-campo">
      <label for="m-paga">{t.pagaCon}</label>
      <input id="m-paga" bind:value={cliente.pagaCon} placeholder={t.pagaConEjemplo} inputmode="decimal" autocomplete="off" />
    </div>
  {/if}

  <div class="total">
    <b>{t.total}</b>
    <span>
      {pesos(total)}{#if dom}<small>{t.masEnvio}</small>{/if}
      {#if moneda === 'usd' && usd !== null}<small class="aprox">≈ US${usd} {t.aprox}</small>{/if}
    </span>
  </div>
  {#if dom}<p class="pista">{t.envioPista}</p>{/if}
  <p class="pista">{t.hacerPista}</p>
  <div class="hueco" bind:this={hueco}></div>
</Hoja>

{#snippet pie()}
  <button type="button" class="m-boton" disabled={!listo || limite || ocupado} onclick={alHacer}>
    {t.hacer} · {pesos(total)}{dom ? t.masEnvio : ''}
  </button>
{/snippet}

<style>
  .cabeza {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
  }

  .titulo {
    margin: 0;
    font-size: 20px;
    font-weight: 800;
    letter-spacing: -0.3px;
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

  .boton-wa {
    margin-top: 10px;
    text-decoration: none;
    display: inline-flex;
    align-items: center;
    gap: 8px;
    height: 36px;
    padding: 0 14px;
    border-radius: 18px;
    border: 1px solid var(--m-linea);
    color: var(--m-texto);
    font-size: 13px;
    font-weight: 600;
  }

  .lineas {
    margin-top: 6px;
  }

  .linea {
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    gap: 3px 12px;
    padding: 14px 0;
    border-bottom: 1px solid var(--m-linea);
  }

  .q {
    width: 100%;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 3px;
    border: 0;
    padding: 0;
    background: transparent;
    color: inherit;
    text-align: left;
    font: inherit;
  }

  .q:disabled {
    cursor: default;
  }

  .q b {
    font-size: 15px;
    font-weight: 700;
    line-height: 1.3;
  }

  .d {
    font-size: 13px;
    line-height: 1.4;
    color: var(--m-suave);
  }

  .imp {
    font-size: 14.5px;
    font-weight: 800;
    font-variant-numeric: tabular-nums;
    text-align: right;
    white-space: nowrap;
  }

  .abajo {
    grid-column: 1 / -1;
    display: flex;
    align-items: center;
    gap: 12px;
    margin-top: 8px;
  }

  .aviso-linea {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: 12.5px;
    font-weight: 700;
    color: var(--m-texto);
  }

  .linea > .aviso-linea {
    grid-column: 1 / -1;
    margin-top: 6px;
  }

  .linea.fuera b,
  .linea.fuera .imp {
    color: var(--m-tenue);
    text-decoration: line-through;
  }

  .linea.fuera .d {
    color: var(--m-tenue);
  }

  .seg {
    display: flex;
    gap: 3px;
    padding: 3px;
    margin-top: 18px;
    border-radius: 14px;
    background: var(--m-chip);
  }

  .seg button {
    flex: 1;
    height: 42px;
    border: 0;
    border-radius: 11px;
    background: transparent;
    color: var(--m-suave);
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    font: inherit;
    font-size: 14px;
    font-weight: 700;
  }

  .seg button[aria-pressed='true'] {
    background: var(--m-seg);
    color: var(--m-texto);
    box-shadow: 0 1px 3px var(--m-sombra);
  }

  .total {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 12px;
    margin-top: 18px;
    padding-top: 14px;
    border-top: 1px solid var(--m-linea);
  }

  .total b {
    font-size: 16px;
    font-weight: 800;
  }

  .total > span {
    font-size: 21px;
    font-weight: 800;
    font-variant-numeric: tabular-nums;
    text-align: right;
  }

  .total small {
    font-size: 14px;
    font-weight: 700;
    color: var(--m-suave);
  }

  .total small.aprox {
    display: block;
    font-size: 11.5px;
    font-weight: 600;
    color: var(--m-tenue);
  }

  .pista {
    margin: 8px 0 0;
    font-size: 12.5px;
    line-height: 1.45;
    color: var(--m-suave);
  }

  .hueco:not(:empty) {
    margin-top: 14px;
    display: flex;
    justify-content: center;
  }
</style>
