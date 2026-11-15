<!--
  Lo abierto sin mesa, en la tarjeta de la derecha a lo ancho (adaptabilidad; maqueta GBWEGCsQFcwKkWm7Qe9FPA v4,
  «Abiertos»): lo que en el celular es «Para llevar». Arriba lo anotado aquí y todavía sin mandar, con su ícono punteado;
  luego cada cuenta con su ícono, su nombre («#22 · Sr. Ramírez»), cómo, quién la abrió y a qué hora, «WhatsApp» si llegó
  del menú en línea, y lo que falta por cobrar. Toca una para seguir.
-->
<script lang="ts">
  import Icono from '../../../diseno/Icono.svelte';
  import { faltaDe } from '../../../lib/caja';
  import { pesos } from '../../../lib/formato';
  import { ICONO_DE_TIPO, nombreDeCuenta, TIPO_EN_PALABRAS, type PedidoNuevo, type Venta } from '../../../lib/pos';

  type Estado = 'reabierta' | 'cocina' | 'lista' | 'cuenta' | 'ocupada';
  const MARCA: Partial<Record<Estado, string>> = { cocina: 'En cocina', lista: 'Lista', cuenta: 'Pidió la cuenta', reabierta: 'Reabierta' };

  let {
    nuevos,
    ventas,
    estadoDe,
    quien,
    hora,
    alAbrir,
  }: {
    nuevos: { llave: string; pedido: PedidoNuevo }[];
    ventas: Venta[];
    estadoDe: (v: Venta) => Estado;
    quien: (v: Venta) => string;
    hora: (v: Venta) => string;
    alAbrir: (llave: string) => void;
  } = $props();

  function como(v: Venta): string {
    if (v.folio !== null) return `Folio ${v.folio}`;
    return v.tipo === 'mesa' ? (v.mesa_nombre ?? 'Mesa') : TIPO_EN_PALABRAS[v.tipo];
  }
</script>

<div class="encabezado">
  <span class="cuadro-c"><Icono nombre="reloj" tamano={18} /></span>
  <div class="titulos">
    <span class="titulo">Abiertos · {nuevos.length + ventas.length}</span>
    <span class="sub">Anotados y sin cobrar. Toca uno para seguir.</span>
  </div>
</div>

{#if nuevos.length + ventas.length === 0}
  <div class="vacio-c">
    <b>Sin pedidos abiertos</b>
    <span>Los que anotes y falten de cobrar salen aquí.</span>
  </div>
{:else}
  <div class="abiertos">
    {#each nuevos as n (n.llave)}
      <button type="button" class="fila-c anotado" onclick={() => alAbrir(n.llave)}>
        <span class="ico-c"><Icono nombre={ICONO_DE_TIPO[n.pedido.tipo]} tamano={18} /></span>
        <span class="t">
          <b>{n.pedido.nombre || 'Pedido nuevo'}</b>
          <span>{TIPO_EN_PALABRAS[n.pedido.tipo]} · anotado aquí, sin mandar</span>
        </span>
      </button>
    {/each}
    {#each ventas as v (v.id)}
      {@const marca = MARCA[estadoDe(v)]}
      {@const enLinea = v.origen === 'menu_en_linea'}
      <button type="button" class="fila-c" onclick={() => alAbrir(`v${v.id}`)}>
        <span class="ico-c"><Icono nombre={ICONO_DE_TIPO[v.tipo]} tamano={18} /></span>
        <span class="t">
          <b>{nombreDeCuenta(v)}</b>
          <span>{como(v)} · {enLinea ? 'Llegó en línea' : `Abrió ${quien(v)}`} · {hora(v)}{marca ? ` · ${marca}` : ''}</span>
          {#if enLinea}<span class="wa">WhatsApp</span>{/if}
        </span>
        <span class="der"><b>{pesos(v.pagado > 0 ? faltaDe(v) : v.total)}</b></span>
      </button>
    {/each}
  </div>
{/if}
