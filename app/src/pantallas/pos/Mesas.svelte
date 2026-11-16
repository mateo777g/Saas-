<!--
  La primera pantalla del punto de venta (maqueta Mesero y cocina, estado «Mesas»): todas las mesas
  del restaurante, de quien sea, y los pedidos para llevar. Una mesa libre sale punteada; una
  ocupada, con su total y quién la abrió, y arriba «En cocina», «Lista» o «Pidió la cuenta». Un
  para llevar anotado aquí y todavía no mandado sale punteado en su lista, como una mesa libre.
  Con la parte 4b, una cuenta con pagos dice cuánto falta, y quien es mesero ve arriba el efectivo
  que trae para la caja (maqueta La caja). Una cuenta reabierta (parte 4c) ya no ocupa su mesa: sale
  con los pedidos para llevar, con su folio y «Reabierta».

  Adaptabilidad («Lo que decidí yo» 5): sin mesas no sale el selector Mesas · Para llevar, solo los
  pedidos; el pedido nuevo puede ser para comer aquí, y sin nombre sale con su número del día.
  Con la terminal conectada (maqueta 8aJ1RUKVd2xA5kgawVpDkQ v2, «Celular · Mesas»): la mesa cuyo cobro espera dice «En la
  terminal» en azul y lo que se mandó ($489.50) en lugar del total; «Revisa la terminal» en ámbar; «No se cobró» en rojo.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import Icono from '../../diseno/Icono.svelte';
  import Selector from '../../diseno/Selector.svelte';
  import { faltaDe } from '../../lib/caja';
  import { dinero } from '../../lib/formato';
  import { ICONO_DE_TIPO, nombreDeCuenta, TIPO_EN_PALABRAS, type Mesa, type PedidoNuevo, type Venta } from '../../lib/pos';
  import type { VigiaTerminal } from '../../lib/terminal.svelte';
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
    terminal = null,
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
    terminal?: VigiaTerminal | null;
  } = $props();

  const enSuMesa = (v: Venta) => v.tipo === 'mesa' && v.folio === null;
  const deMesa = $derived(new Map(ventas.filter(enSuMesa).map((v) => [v.mesa_id, v])));
  const llevar = $derived(ventas.filter((v) => !enSuMesa(v)));
  const ocupadas = $derived(mesas.filter((m) => deMesa.has(m.id)).length);
  // Sin mesas, solo los pedidos.
  const enVista = $derived(mesas.length === 0 ? 'llevar' : vista);
</script>

<Lugar {restaurante} {linea} />
{@render pestanas?.()}
{@render aviso()}
{#if efectivo}
  <div class="efectivo-linea"><Icono nombre="billete" tamano={16} /><span>Traes <b>{dinero(efectivo)}</b> en efectivo para la caja</span></div>
{/if}

{#if mesas.length > 0}
<div class="arriba-vista">
  <Selector
    vidrio
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
{/if}

<div class="desliza">
  {#if enVista === 'mesas'}
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
            {@const t = terminal?.marca(v.id) ?? null}
            <button type="button" class="mesa" class:lista={e === 'lista'} onclick={() => alAbrir(`m${m.id}`)}>
              <span class="mesa-arriba">
                <span class="mesa-nombre">{m.nombre}</span>
                {#if t?.tipo === 'terminal'}
                  <span class="marca-estado t-marca azul"><Icono nombre="tarjeta" tamano={13} />En la terminal</span>
                {:else if t?.tipo === 'revisa'}
                  <span class="marca-estado t-marca ambar"><Icono nombre="alerta" tamano={13} />Revisa la terminal</span>
                {:else if t?.tipo === 'no-cobro'}
                  <span class="marca-estado t-marca roja"><Icono nombre="alerta" tamano={13} />No se cobró</span>
                {:else}
                  <MarcaEstado estado={e} />
                {/if}
              </span>
              <span class="mesa-abajo">
                <span class="mesa-total">{dinero(t && t.tipo !== 'no-cobro' ? t.monto : v.total)}</span>
                {#if v.pagado > 0}<span class="mesa-falta">Falta {dinero(faltaDe(v))}</span>{/if}
                <span class="mesa-quien">Abrió {quien(v)} · {hora(v)}</span>
              </span>
            </button>
          {/if}
        {/each}
    </div>
  {:else if llevar.length === 0 && nuevos.length === 0}
    <div class="vacio">
      <b>{mesas.length ? 'Sin pedidos para llevar' : 'Sin pedidos abiertos'}</b>
      <span>{mesas.length ? 'Los que se abran sin mesa salen aquí, junto a las mesas.' : 'Los que anotes y falten de cobrar salen aquí.'}</span>
    </div>
  {:else}
    {#each nuevos as n (n.llave)}
      <button type="button" class="fila-llevar anotado" onclick={() => alAbrir(n.llave)}>
        <span class="cuadro-icono"><Icono nombre={ICONO_DE_TIPO[n.pedido.tipo]} tamano={18} /></span>
        <span class="t">
          <b>{n.pedido.nombre || 'Pedido nuevo'}</b>
          <span class="tipo">{TIPO_EN_PALABRAS[n.pedido.tipo]} · anotado aquí</span>
        </span>
      </button>
    {/each}
    {#each llevar as v (v.id)}
      <button type="button" class="fila-llevar" onclick={() => alAbrir(`v${v.id}`)}>
        <span class="cuadro-icono"><Icono nombre={ICONO_DE_TIPO[v.tipo]} tamano={18} /></span>
        <span class="t">
          <b>{nombreDeCuenta(v)}</b>
          <span class="tipo">
            {v.folio !== null ? `Folio ${v.folio}` : v.tipo === 'mesa' ? 'Mesa' : TIPO_EN_PALABRAS[v.tipo]} · abrió {quien(v)}, {hora(v)}
          </span>
          <MarcaEstado estado={estadoDe(v)} whatsapp={v.origen === 'menu_en_linea'} />
        </span>
        <span class="mesa-total">{dinero(v.total)}</span>
      </button>
    {/each}
  {/if}
</div>

{#if enVista === 'llevar'}
  <div class="cel-pie">
    <button type="button" class="cel-boton" onclick={alNuevoLlevar}><Icono nombre="mas" tamano={18} />Pedido nuevo</button>
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
