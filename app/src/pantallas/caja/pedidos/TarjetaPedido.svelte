<!--
  Un pedido «Por confirmar» a lo ancho (adaptabilidad, encuesta 15 «A, Tablero»; maqueta planes/maquetas/adaptabilidad.html,
  pantalla Pedidos): la tarjeta de Crear anuncios con su cuadrito e ícono (la bolsa para llevar, la moto a domicilio), «#27 ·
  Rosa Ramírez», «Para llevar · llegó hace 3 min» y el total; el teléfono en su gris y, a domicilio, la dirección y «Paga
  con»; los renglones; la pista y los botones de diseno/Boton: «Rechazar» en rojo de contorno y «Confirmar» en verde. Lo
  que hacen los botones (las hojas de confirmar y rechazar) lo decide caja/Pedidos.svelte.

  Sin pedido es su esqueleto (solo en el panel, mientras llega la primera vez): la misma tarjeta con bloques que laten en
  el lugar de cada texto, del mismo tamaño, y sin su pista ni sus botones (ocupan su lugar, para que nada brinque).
-->
<script lang="ts">
  import Boton from '../../../diseno/Boton.svelte';
  import Esqueleto from '../../../diseno/Esqueleto.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import { pesos } from '../../../lib/formato';
  import type { PorConfirmar } from '../../../lib/pedidos.svelte';

  let {
    pedido,
    forma = { titulo: '134px', sub: '164px', renglones: 2 },
    llego = '',
    alRechazar = () => {},
    alConfirmar = () => {},
  }: {
    pedido: PorConfirmar | null;
    forma?: { titulo: string; sub: string; renglones: number };
    llego?: string;
    alRechazar?: () => void;
    alConfirmar?: () => void;
  } = $props();

  const telefono = (t: string) => `${t.slice(0, 3)} ${t.slice(3, 6)} ${t.slice(6)}`;
  const NOMBRES = ['64px', '44px', '92px'];
</script>

{#if pedido}
  {@const p = pedido}
  {@const dom = p.tipo === 'domicilio'}
<section class="tarjeta pedido-t" data-pedido={p.id} aria-label="Pedido #{p.numero}">
  <div class="encabezado">
    <span class="cuadrito"><Icono nombre={dom ? 'moto' : 'r-bolsa'} tamano={18} /></span>
    <div class="titulos">
      <span class="titulo">#{p.numero} · {p.cliente_nombre}</span>
      <span class="sub">{dom ? 'A domicilio' : 'Para llevar'} · {llego}</span>
    </div>
    <b class="total">{pesos(p.total)}</b>
  </div>

  {#if p.cliente_telefono || dom}
    <div class="entrega">
      {#if p.cliente_telefono}
        <span><Icono nombre="celular" tamano={14} /><span class="mono">{telefono(p.cliente_telefono)}</span></span>
      {/if}
      {#if dom}
        <span>
          <Icono nombre="ubicacion" tamano={14} />
          <span>{p.cliente_direccion}{p.cliente_referencias ? ` · ${p.cliente_referencias}` : ''}</span>
        </span>
        {#if p.paga_con !== null}
          <span><Icono nombre="billete" tamano={14} /><span>Paga con {pesos(p.paga_con)}</span></span>
        {/if}
      {/if}
    </div>
  {/if}

  <div class="lineas-p">
    {#each p.renglones as r, i (i)}
      <div class="linea-p">
        <span class="cant">{r.cantidad} ×</span>
        <b>{r.nombre}</b>
        <span class="imp">{pesos(r.importe)}</span>
        {#if r.opciones.length}<span class="det">{r.opciones.map((o) => o.opcion).join(' · ')}</span>{/if}
        {#if r.nota}<span class="det">Nota: {r.nota}</span>{/if}
      </div>
    {/each}
  </div>

  <p class="aviso-wa"><Icono nombre="mensaje" tamano={14} />Confírmalo cuando te llegue su WhatsApp.</p>

  <div class="botones">
    <Boton etiqueta="Rechazar" icono="cerrar" tono="peligro" onclick={alRechazar} />
    <Boton etiqueta="Confirmar" tono="verde" onclick={alConfirmar} />
  </div>
</section>
{:else}
  <section class="tarjeta" aria-hidden="true">
    <div class="encabezado">
      <Esqueleto ancho="36px" alto="36px" redondo="11px" />
      <div class="titulos">
        <span class="titulo"><Esqueleto ancho={forma.titulo} alto="14px" /></span>
        <span class="sub"><Esqueleto ancho={forma.sub} alto="11px" /></span>
      </div>
      <b class="total"><Esqueleto ancho="63px" alto="14px" /></b>
    </div>
    <Esqueleto ancho="100%" alto="42px" redondo="12px" />
    <div class="lineas-p">
      {#each NOMBRES.slice(0, forma.renglones) as nombre, i (i)}
        <div class="linea-p">
          <span class="cant"><Esqueleto ancho="22px" alto="12px" /></span>
          <b><Esqueleto ancho={nombre} alto="12px" /></b>
          <span class="imp"><Esqueleto ancho="47px" alto="12px" /></span>
        </div>
      {/each}
    </div>
    <p class="aviso-wa escondida"><Icono nombre="mensaje" tamano={14} />Confírmalo cuando te llegue su WhatsApp.</p>
    <div class="botones escondida"><span class="lugar-boton"></span></div>
  </section>
{/if}

<style>
  /* La tarjeta de Crear anuncios (CrearContenido.svelte, .tarjeta): blanca, borde, 14 de esquina, sin sombra. */
  .tarjeta {
    padding: 20px;
    background: var(--solido);
    border: 1px solid var(--borde-tarjeta);
    border-radius: 14px;
    display: flex;
    flex-direction: column;
    gap: 16px;
    min-width: 0;
  }

  /* En Cristal la tarjeta es material: el gris del teléfono pasa al relleno de Cristal, nunca negro en oscuro (como Tu
     restaurante y Crear anuncios). */
  :global(:root[data-estilo='cristal'][data-tema='oscuro']) .tarjeta {
    --fondo: var(--cristal-relleno);
  }

  :global(:root[data-estilo='cristal'][data-tema='claro']) .tarjeta {
    --fondo: var(--cl-relleno);
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

  .titulo {
    font-size: 14.5px;
    font-weight: 700;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .sub {
    font-size: 12.5px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .total {
    font-family: var(--mono);
    font-size: 15px;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
    white-space: nowrap;
  }

  /* El teléfono, la dirección y con cuánto paga, en el gris de las vistas (como los campos que van juntos). */
  .entrega {
    display: flex;
    flex-direction: column;
    gap: 6px;
    padding: 12px 16px;
    border-radius: 12px;
    background: var(--fondo);
    font-size: 12.5px;
    line-height: 1.4;
  }

  .entrega > span {
    display: flex;
    gap: 8px;
    align-items: flex-start;
  }

  .entrega :global(svg) {
    margin-top: 1px;
    flex: none;
    color: var(--suave);
  }

  .mono {
    font-family: var(--mono);
    font-variant-numeric: tabular-nums;
  }

  .lineas-p {
    display: flex;
    flex-direction: column;
    gap: 9px;
  }

  .linea-p {
    display: grid;
    grid-template-columns: 30px minmax(0, 1fr) auto;
    gap: 2px 8px;
    font-size: 13px;
  }

  .linea-p .cant {
    font-family: var(--mono);
    font-weight: 600;
    font-variant-numeric: tabular-nums;
  }

  .linea-p b {
    font-weight: 700;
    min-width: 0;
  }

  .linea-p .det {
    grid-column: 2;
    font-size: 12px;
    color: var(--suave);
    line-height: 1.4;
  }

  .linea-p .imp {
    grid-row: 1;
    grid-column: 3;
    font-family: var(--mono);
    font-variant-numeric: tabular-nums;
    text-align: right;
  }

  /* La tarjeta llena su celda (Tablero, parejas por fila); el aviso y los botones se van abajo, alineados con los de al lado. */
  .pedido-t {
    flex: 1;
  }

  .aviso-wa {
    margin: auto 0 0;
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 12px;
    color: var(--tenue);
  }

  .botones {
    display: flex;
    justify-content: flex-end;
    gap: 10px;
  }

  /* El esqueleto guarda el lugar de la pista y de los botones (44 de alto), sin enseñarlos. */
  .escondida {
    visibility: hidden;
  }

  .lugar-boton {
    height: 44px;
  }
</style>
