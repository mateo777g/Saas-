<!--
  La primera pantalla del punto de venta (maqueta Mesero y cocina, estado «Mesas»): todas las mesas
  del restaurante, de quien sea, y los pedidos para llevar. Una mesa libre sale punteada; una
  ocupada, con su total y quién la abrió, y arriba «En cocina», «Lista» o «Pidió la cuenta». Un
  para llevar anotado aquí y todavía no mandado sale punteado en su lista, como una mesa libre.
  Con la parte 4b, una cuenta con pagos dice cuánto falta, y quien es mesero ve arriba el efectivo
  que trae para la caja (maqueta La caja). Una cuenta reabierta (parte 4c) ya no ocupa su mesa: sale
  con los pedidos para llevar, con su folio y «Reabierta».
-->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import Icono from '../../diseno/Icono.svelte';
  import Selector from '../../diseno/Selector.svelte';
  import { faltaDe } from '../../lib/caja';
  import { dinero } from '../../lib/formato';
  import type { Mesa, PedidoNuevo, Venta } from '../../lib/pos';
  import Lugar from './Lugar.svelte';
  import MarcaEstado from './MarcaEstado.svelte';

  type Estado = 'reabierta' | 'cocina' | 'lista' | 'cuenta' | 'ocupada';

  let {
    restaurante,
    linea,
    mesas,
    ventas,
    nuevos,
    anotadas,
    vista,
    estadoDe,
    quien,
    hora,
    efectivo,
    pestanas,
    aviso,
    alVista,
    alAbrir,
    alNuevoLlevar,
  }: {
    restaurante: string;
    linea: string;
    mesas: Mesa[];
    ventas: Venta[];
    nuevos: { llave: string; pedido: PedidoNuevo }[];
    anotadas: Set<number>; // las mesas libres con algo anotado en este aparato
    vista: 'mesas' | 'llevar';
    estadoDe: (v: Venta) => Estado;
    quien: (v: Venta) => string; // el nombre de pila de quien la abrió
    hora: (v: Venta) => string; // la hora en que se abrió, en la zona del restaurante
    efectivo: number | null; // lo que trae cobrado en efectivo en este turno; null si no se enseña
    pestanas?: Snippet;
    aviso: Snippet;
    alVista: (v: 'mesas' | 'llevar') => void;
    alAbrir: (llave: string) => void;
    alNuevoLlevar: () => void;
  } = $props();

  const enSuMesa = (v: Venta) => v.tipo === 'mesa' && v.folio === null;
  const deMesa = $derived(new Map(ventas.filter(enSuMesa).map((v) => [v.mesa_id, v])));
  const llevar = $derived(ventas.filter((v) => !enSuMesa(v)));
  const ocupadas = $derived(mesas.filter((m) => deMesa.has(m.id)).length);
</script>

<Lugar {restaurante} {linea} />
{@render pestanas?.()}
{@render aviso()}
{#if efectivo}
  <div class="efectivo-linea"><Icono nombre="billete" tamano={16} /><span>Traes <b>{dinero(efectivo)}</b> en efectivo para la caja</span></div>
{/if}

<div class="arriba-vista">
  <Selector
    etiqueta="Mesas o para llevar"
    lleno
    alto={30}
    opciones={[
      { valor: 'mesas', texto: `Mesas · ${ocupadas}/${mesas.length}` },
      { valor: 'llevar', texto: `Para llevar · ${llevar.length}` },
    ]}
    elegida={vista}
    alElegir={alVista}
  />
</div>

<div class="desliza">
  {#if vista === 'mesas'}
    {#if mesas.length === 0}
      <div class="vacio">
        <b>Todavía no hay mesas</b>
        <span>Tu gerente las agrega en Mesas, en su panel.</span>
      </div>
    {:else}
      <div class="rejilla-mesas">
        {#each mesas as m (m.id)}
          {@const v = deMesa.get(m.id)}
          {#if !v}
            <button type="button" class="mesa libre" onclick={() => alAbrir(`m${m.id}`)}>
              <span class="mesa-nombre">{m.nombre}</span>
              <span class="mesa-libre">Libre{anotadas.has(m.id) ? ' · anotado aquí' : ''}</span>
            </button>
          {:else}
            {@const e = estadoDe(v)}
            <button type="button" class="mesa" class:lista={e === 'lista'} onclick={() => alAbrir(`m${m.id}`)}>
              <span class="mesa-arriba">
                <span class="mesa-nombre">{m.nombre}</span>
                <MarcaEstado estado={e} />
              </span>
              <span class="mesa-abajo">
                <span class="mesa-total">{dinero(v.total)}</span>
                {#if v.pagado > 0}<span class="mesa-falta">Falta {dinero(faltaDe(v))}</span>{/if}
                <span class="mesa-quien">Abrió {quien(v)} · {hora(v)}</span>
              </span>
            </button>
          {/if}
        {/each}
      </div>
    {/if}
  {:else if llevar.length === 0 && nuevos.length === 0}
    <div class="vacio">
      <b>Sin pedidos para llevar</b>
      <span>Los que se abran con el nombre del cliente salen aquí, junto a las mesas.</span>
    </div>
  {:else}
    {#each nuevos as n (n.llave)}
      <button type="button" class="fila-llevar anotado" onclick={() => alAbrir(n.llave)}>
        <span class="cuadro-icono"><Icono nombre={n.pedido.tipo === 'domicilio' ? 'moto' : 'bolsa'} tamano={18} /></span>
        <span class="t">
          <b>{n.pedido.nombre}</b>
          <span class="tipo">{n.pedido.tipo === 'domicilio' ? 'Domicilio' : 'Para llevar'} · anotado aquí</span>
        </span>
      </button>
    {/each}
    {#each llevar as v (v.id)}
      <button type="button" class="fila-llevar" onclick={() => alAbrir(`v${v.id}`)}>
        <span class="cuadro-icono"><Icono nombre={v.tipo === 'domicilio' ? 'moto' : v.tipo === 'mesa' ? 'mesas' : 'bolsa'} tamano={18} /></span>
        <span class="t">
          <b>{v.tipo === 'mesa' ? v.mesa_nombre : v.cliente_nombre}</b>
          <span class="tipo">
            {v.folio !== null ? `Folio ${v.folio}` : v.tipo === 'domicilio' ? 'Domicilio' : 'Para llevar'} · abrió {quien(v)}, {hora(v)}
          </span>
          <MarcaEstado estado={estadoDe(v)} />
        </span>
        <span class="mesa-total">{dinero(v.total)}</span>
      </button>
    {/each}
  {/if}
</div>

{#if vista === 'llevar'}
  <div class="cel-pie">
    <button type="button" class="cel-boton" onclick={alNuevoLlevar}><Icono nombre="mas" tamano={18} />Para llevar</button>
  </div>
{/if}

<style>
  .arriba-vista {
    flex: none;
    margin-top: 14px;
  }

  .fila-llevar.anotado {
    background: transparent;
    border-style: dashed;
    border-color: var(--linea-fuerte);
  }
</style>
