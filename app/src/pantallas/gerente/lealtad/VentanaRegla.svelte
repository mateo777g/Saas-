<!--
  «Tu regla y tu premio» (maqueta v22, VENTANA «Editar regla»): cuántos se piden (con sellos: cuántos sellos y desde cuánto
  cuenta un sello; con puntos: cuántos pesos vale un punto y cuántos puntos pide el premio; sellos o puntos se cambia en Tu
  tarjeta) y qué se ganan (un producto de Mi menú gratis, en cuadros como los de Crear anuncios con lo elegido en el azul
  del aro, o un descuento en pesos). Las dos partes se guardan juntas (guardar_regla_lealtad); Postgres revisa todo.
  Los productos que piden elegir opciones no salen: el premio entra a la cuenta solo, sin opciones.
-->
<script lang="ts">
  import Boton from '../../../diseno/Boton.svelte';
  import Campo from '../../../diseno/Campo.svelte';
  import Formulario from '../../../diseno/Formulario.svelte';
  import GrupoCampos from '../../../diseno/GrupoCampos.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import Ventana from '../../../diseno/Ventana.svelte';
  import { leerMonto } from '../../../lib/caja';
  import { urlFoto } from '../../../lib/fotos';
  import { pesos } from '../../../lib/formato';
  import { guardarRegla, type Lealtad, type TipoPremio } from '../../../lib/lealtad';
  import type { Menu } from '../../../lib/menu';
  import { supabase } from '../../../lib/supabase';

  let {
    restauranteId,
    lealtad,
    menu,
    alGuardar,
    alCerrar,
  }: {
    restauranteId: string;
    lealtad: Lealtad;
    menu: Menu | null;
    alGuardar: () => Promise<void>;
    alCerrar: () => void;
  } = $props();

  const id = $props.id();
  // svelte-ignore state_referenced_locally
  const l = lealtad;
  const sellos = l.forma === 'sellos';
  const escrito = (n: number | null) => (n === null ? '' : pesos(n));

  let meta = $state(l.meta !== null ? String(l.meta) : '');
  let minimo = $state(escrito(l.minimo));
  let porPunto = $state(escrito(l.pesos_por_punto));
  let tipo = $state<TipoPremio>(l.premio_tipo ?? 'producto');
  let productoId = $state<number | null>(l.premio_producto_id);
  let premioPesos = $state(escrito(l.premio_pesos));
  let error = $state<string | null>(null);

  // Los que pueden ser premio: los de Mi menú (sin los de envío) que no piden elegir opciones. El que ya es premio sale
  // aunque esté oculto.
  const piden = $derived(new Set((menu?.grupos ?? []).filter((g) => g.minimo > 0).flatMap((g) => g.productos)));
  const productos = $derived(
    (menu?.productos ?? []).filter((p) => !p.es_envio && !piden.has(p.id) && (p.visible || p.id === l.premio_producto_id)),
  );

  async function guardar(): Promise<{ listo: string } | { error: string }> {
    const n = Number(meta.trim());
    if (!Number.isInteger(n) || n <= 0) return { error: sellos ? 'Escribe cuántos sellos pide el premio.' : 'Escribe cuántos puntos pide el premio.' };
    const m = sellos ? leerMonto(minimo.trim() || '0') : null;
    if (sellos && m === null) return { error: 'Escribe desde cuánto cuenta un sello, como $50.00.' };
    const pp = sellos ? null : leerMonto(porPunto.trim());
    if (!sellos && !pp) return { error: 'Escribe cuántos pesos vale un punto, como $10.00.' };
    if (tipo === 'producto' && productoId === null) return { error: 'Pica el producto que se ganan.' };
    const pr = tipo === 'pesos' ? leerMonto(premioPesos.trim()) : null;
    if (tipo === 'pesos' && !pr) return { error: 'Escribe de cuánto es el descuento, como $50.00.' };
    try {
      await guardarRegla(supabase, restauranteId, {
        meta: n,
        minimo: m,
        pesos_por_punto: pp,
        premio_tipo: tipo,
        premio_producto_id: tipo === 'producto' ? productoId : null,
        premio_pesos: pr,
      });
    } catch (falla) {
      return { error: falla instanceof Error ? falla.message : 'No se pudo guardar tu regla.' };
    }
    await alGuardar();
    return { listo: 'Regla guardada' };
  }
</script>

<Ventana
  etiqueta="TARJETA DE LEALTAD"
  titulo="Tu regla y tu premio"
  nota="Lo que ya juntaron tus clientes se respeta. Sellos o puntos se cambia en Tu tarjeta."
  ancho={640}
  centrado
  {alCerrar}
>
  <Formulario verde boton={{ etiqueta: 'Guardar', icono: 'check' }} {guardar} alTerminar={alCerrar} bind:error espacio={26} antesDelBoton={26}>
    <div class="bloque">
      <span class="bloque-t">¿Cuántos se piden?</span>
      <p class="nota">Con <b>{sellos ? 'sellos' : 'puntos'}</b>, como lo elegiste en Tu tarjeta.</p>
      <GrupoCampos>
        <div class="dos">
          {#if sellos}
            <Campo id="{id}-meta" etiqueta="SELLOS PARA EL PREMIO" bind:valor={meta} placeholder="De 2 a 20" modoTeclado="numeric" mono />
            <Campo id="{id}-minimo" etiqueta="UN SELLO POR CUENTA DESDE" bind:valor={minimo} placeholder="Ej. $100.00" modoTeclado="decimal" mono pista="En $0, cualquier cuenta pagada." />
          {:else}
            <Campo id="{id}-pesos" etiqueta="UN PUNTO POR CADA" bind:valor={porPunto} placeholder="Ej. $10.00" modoTeclado="decimal" mono pista="$95 son 9 puntos." />
            <Campo id="{id}-meta" etiqueta="PUNTOS PARA EL PREMIO" bind:valor={meta} placeholder="Hasta 10,000" modoTeclado="numeric" mono />
          {/if}
        </div>
      </GrupoCampos>
    </div>

    <div class="bloque">
      <span class="bloque-t">¿Qué se ganan?</span>
      <div class="opciones" role="group" aria-label="Qué se ganan">
        {#each [{ v: 'producto', t: 'Un producto gratis', s: 'De tu menú; va a la cocina en $0', i: 'r-producto' }, { v: 'pesos', t: 'Un descuento', s: 'Se resta de su cuenta', i: 'porcentaje' }] as o (o.v)}
          <button type="button" class="opcion" aria-pressed={tipo === o.v} onclick={() => (tipo = o.v as TipoPremio)}>
            <span class="op-icono"><Icono nombre={o.i} tamano={18} /></span>
            <span class="op-t"><b>{o.t}</b><span>{o.s}</span></span>
            <span class="check"><Icono nombre="check" tamano={13} /></span>
          </button>
        {/each}
      </div>
      {#if tipo === 'producto'}
        <div class="prods">
          <span class="nota">Pica uno: entra a la cuenta en $0, con «Premio de la tarjeta».</span>
          {#if !menu}
            <p class="nota">Leyendo tu menú…</p>
          {:else if !productos.length}
            <p class="nota">Todavía no hay productos en Mi menú que puedan ser premio (los que piden elegir opciones no pueden).</p>
          {:else}
            <div class="rejilla">
              {#each productos as p (p.id)}
                <button type="button" class="prod" class:elegido={productoId === p.id} aria-pressed={productoId === p.id} onclick={() => (productoId = p.id)}>
                  <span class="prod-foto" style:background-image={p.imagen_ruta ? `url(${urlFoto(p.imagen_ruta)})` : undefined}></span>
                  <span class="prod-textos"><span class="prod-nombre">{p.nombre}</span><span class="prod-precio">{pesos(p.precio)}</span></span>
                  <span class="check"><Icono nombre="check" tamano={13} /></span>
                </button>
              {/each}
            </div>
          {/if}
        </div>
      {:else}
        <GrupoCampos>
          <Campo id="{id}-premio" etiqueta="DESCUENTO" bind:valor={premioPesos} placeholder="Ej. $50.00" modoTeclado="decimal" mono pista="Solo se canjea si la cuenta vale al menos eso." />
        </GrupoCampos>
      {/if}
    </div>

    {#snippet izquierda()}
      <Boton etiqueta="Cancelar" icono="cerrar" tono="alarga" onclick={alCerrar} />
    {/snippet}
  </Formulario>
</Ventana>

<style>
  .bloque {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .bloque-t {
    font: 600 10.5px var(--mono);
    letter-spacing: 0.1em;
    text-transform: uppercase;
    color: var(--tenue);
  }

  .nota {
    margin: 0;
    font-size: 12.5px;
    color: var(--suave);
  }

  .dos {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 14px;
    align-items: start;
  }

  .opciones {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 10px;
  }

  .opcion {
    position: relative;
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px 14px;
    border: 1px solid var(--borde-tarjeta);
    border-radius: 12px;
    background: var(--solido);
    color: var(--texto);
    font: inherit;
    text-align: left;
    cursor: pointer;
    transition:
      box-shadow 0.15s,
      border-color 0.15s;
  }

  .opcion[aria-pressed='true'],
  .prod.elegido {
    box-shadow: 0 0 0 2px var(--campo-aro);
    border-color: transparent;
  }

  .op-icono {
    width: 36px;
    height: 36px;
    flex: none;
    display: grid;
    place-items: center;
    border-radius: 10px;
    background: var(--chip);
  }

  .op-t {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .op-t b {
    font-size: 14px;
    font-weight: 700;
  }

  .op-t span {
    font-size: 12.5px;
    color: var(--suave);
  }

  /* La palomita sale con el rebote de lo que se abre. */
  .check {
    position: absolute;
    top: 10px;
    right: 10px;
    width: 20px;
    height: 20px;
    display: grid;
    place-items: center;
    border-radius: 6px;
    background: var(--campo-aro);
    color: #fff;
    transform: scale(0);
    transition: transform 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275);
  }

  .opcion[aria-pressed='true'] .check,
  .prod.elegido .check {
    transform: scale(1);
  }

  .prods {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .rejilla {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 10px;
  }

  /* Los cuadros de productos de Crear anuncios. */
  .prod {
    position: relative;
    display: flex;
    flex-direction: column;
    gap: 10px;
    padding: 8px 8px 12px;
    border-radius: 14px;
    border: 1px solid var(--borde-tarjeta);
    background: var(--solido);
    color: var(--texto);
    font: inherit;
    text-align: left;
    cursor: pointer;
    transition:
      box-shadow 0.15s,
      border-color 0.15s;
  }

  .prod .check {
    top: 14px;
    right: 14px;
  }

  .prod-foto {
    aspect-ratio: 4 / 3;
    border-radius: 10px;
    background: #000000 center / cover no-repeat;
  }

  .prod-textos {
    padding: 0 4px;
    display: flex;
    flex-direction: column;
    gap: 4px;
    min-width: 0;
  }

  .prod-nombre {
    font-size: 14px;
    font-weight: 700;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .prod-precio {
    font-family: var(--mono);
    font-size: 12px;
    color: var(--tenue);
  }

  @media (prefers-reduced-motion: reduce) {
    .check {
      transition: none;
    }
  }
</style>
