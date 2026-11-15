<!--
  La cuenta en la tarjeta de la derecha a lo ancho (adaptabilidad; maqueta GBWEGCsQFcwKkWm7Qe9FPA v4, «Vender» y «Mesa 4»):
  la cabeza de las tarjetas de Crear anuncios (cuadrito con su ícono, título, su texto y, a la derecha, lo que le pasen:
  «Abiertos · 3» o el «⋯»). Un pedido nuevo trae cómo se entrega (Comer aquí · Para llevar · Domicilio, como los roles de
  Empleados) y el nombre del cliente, opcional (a domicilio, también teléfono y dirección), en su gris. Luego lo anotado
  en este aparato, con − n + y Quitar; después lo mandado, una comanda por bloque con su área y si ya está lista, y lo
  que «Se entrega directo». Lo mandado se toca para cancelarlo o descontarlo (parte 4c), como en el celular. El total va
  en la barra de abajo; aquí solo el subtotal, el descuento, lo pagado y lo que falta, cuando los hay.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import CajaError from '../../../diseno/CajaError.svelte';
  import Campo from '../../../diseno/Campo.svelte';
  import GrupoCampos from '../../../diseno/GrupoCampos.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import { pesos } from '../../../lib/formato';
  import { TIPO_EN_PALABRAS, type PedidoNuevo } from '../../../lib/pos';
  import type { BloqueVista, DescuentoVista, EnviadoVista, LineaVista } from '../Cuenta.svelte';

  let {
    titulo,
    sub,
    icono,
    accion,
    nuevo = null,
    idCampos,
    alNuevo,
    etiquetaLineas,
    lineas,
    bloques,
    sinArea,
    conCuenta,
    domicilio,
    subtotal,
    descuento,
    pagado,
    falta,
    error,
    sinRed,
    mandarTexto,
    donde,
    alCambiar,
    alQuitar,
    alRenglon,
  }: {
    titulo: string;
    sub: string;
    icono: string;
    accion?: Snippet;
    nuevo?: PedidoNuevo | null; // un pedido sin mandar todavía: lleva su forma
    idCampos: string;
    alNuevo: (cambio: Partial<PedidoNuevo>) => void;
    etiquetaLineas: string; // «Por anotar · solo en este aparato»
    lineas: LineaVista[];
    bloques: BloqueVista[];
    sinArea: EnviadoVista[];
    conCuenta: boolean;
    domicilio: { telefono: string; direccion: string } | null; // el de una cuenta ya abierta
    subtotal: number;
    descuento: DescuentoVista | null;
    pagado: number;
    falta: number | null;
    error: string | null;
    sinRed: boolean;
    mandarTexto: string;
    donde: string;
    alCambiar: (i: number, cuantos: number) => void;
    alQuitar: (i: number) => void;
    alRenglon: (id: number) => void;
  } = $props();

  const TIPOS = Object.entries(TIPO_EN_PALABRAS) as [PedidoNuevo['tipo'], string][];
  const hasta = $derived(mandarTexto === 'Anotar' ? 'lo anotes' : 'lo mandes');
</script>

{#snippet adentro(r: EnviadoVista)}
  <span class="que">
    <b><span class="cant-e">{r.cantidad}</span>{r.nombre}</b>
    {#if r.detalle}<span class="det">{r.detalle}</span>{/if}
    {#if r.nota}<span class="nota-r">{r.nota}</span>{/if}
    {#if r.cancelado}<span class="cancel-r">{r.cancelado}</span>{:else if r.descuento}<span class="desc-r">{r.descuento}</span>{/if}
    <span class="det">{r.por}</span>
  </span>
  <span class="imp">{#if r.antes !== null}<span class="antes">{pesos(r.antes)}</span>{/if}{pesos(r.importe)}</span>
{/snippet}

{#snippet enviado(r: EnviadoVista)}
  {#if r.cancelado || !conCuenta}
    <div class="renglon" class:cancelado={!!r.cancelado}>{@render adentro(r)}</div>
  {:else}
    <button type="button" class="renglon" onclick={() => alRenglon(r.id)}>{@render adentro(r)}</button>
  {/if}
{/snippet}

<div class="encabezado">
  <span class="cuadro-c"><Icono nombre={icono} tamano={18} /></span>
  <div class="titulos">
    <span class="titulo">{titulo}</span>
    <span class="sub">{sub}</span>
  </div>
  {@render accion?.()}
</div>

{#if sinRed}
  <CajaError tipo="sinred" mensaje="Sin conexión. Lo anotado sigue en este {donde}; vuelve a pulsar «{mandarTexto}» cuando regrese el internet." />
{:else if error}
  <CajaError mensaje={error} />
{/if}

{#if nuevo}
  <div class="bloque-c">
    <span class="etiqueta-c">Cómo se entrega</span>
    <div class="elige" role="group" aria-label="Cómo se entrega">
      {#each TIPOS as [valor, texto] (valor)}
        <button type="button" class="elige-op" aria-pressed={nuevo.tipo === valor} onclick={() => alNuevo({ tipo: valor })}>{texto}</button>
      {/each}
    </div>
  </div>
  <GrupoCampos>
    <Campo
      id="{idCampos}-nombre"
      etiqueta="NOMBRE DEL CLIENTE · OPCIONAL"
      placeholder="Ej. Rosa"
      largoMaximo={80}
      bind:valor={() => nuevo.nombre, (v) => alNuevo({ nombre: v })}
    />
    {#if nuevo.tipo === 'domicilio'}
      <Campo
        id="{idCampos}-tel"
        etiqueta="TELÉFONO"
        tipo="tel"
        placeholder="10 dígitos"
        largoMaximo={30}
        bind:valor={() => nuevo.telefono, (v) => alNuevo({ telefono: v })}
      />
      <Campo
        id="{idCampos}-dir"
        etiqueta="DIRECCIÓN"
        placeholder="Calle, número, colonia y referencias"
        largoMaximo={200}
        bind:valor={() => nuevo.direccion, (v) => alNuevo({ direccion: v })}
      />
    {/if}
  </GrupoCampos>
{/if}

{#if domicilio}
  <div class="datos-c">
    <span><Icono nombre="celular" tamano={14} /><span class="mono">{domicilio.telefono}</span></span>
    {#if domicilio.direccion}<span><Icono nombre="ubicacion" tamano={14} /><span>{domicilio.direccion}</span></span>{/if}
  </div>
{/if}

{#if lineas.length || nuevo}
  <div class="bloque-c">
    <span class="etiqueta-c">{etiquetaLineas}</span>
    {#if lineas.length}
      <div class="renglones">
        {#each lineas as l, i (i)}
          <div class="renglon">
            <span class="que">
              <b>{l.nombre}</b>
              {#if l.detalle}<span class="det">{l.detalle}</span>{/if}
              {#if l.nota}<span class="nota-r">{l.nota}</span>{/if}
            </span>
            <span class="imp">{l.importe === null ? '—' : pesos(l.importe)}</span>
            <span class="abajo-r">
              <span class="paso">
                <button type="button" aria-label="Uno menos" onclick={() => alCambiar(i, -1)}><Icono nombre="menos" tamano={14} /></button>
                <span>{l.cantidad}</span>
                <button type="button" aria-label="Uno más" onclick={() => alCambiar(i, 1)}><Icono nombre="mas" tamano={14} /></button>
              </span>
              <button type="button" class="quitar" onclick={() => alQuitar(i)}><Icono nombre="cerrar" tamano={14} />Quitar</button>
            </span>
          </div>
        {/each}
      </div>
    {:else}
      <div class="vacio-c">
        <b>Toca un producto para empezar</b>
        <span>Lo anotado se queda en este {donde} hasta que {hasta} o lo cobres.</span>
      </div>
    {/if}
  </div>
{/if}

{#each bloques as k (k.id)}
  <div class="bloque-c">
    <div class="bloque-cabeza">
      <span class="etiqueta-c">{k.etiquetaAncha ?? k.etiqueta}</span>
      <span class="crece"></span>
      <span class="marca-e" class:lista={k.estado === 'lista'}>{k.estado === 'lista' ? 'Lista' : 'En cocina'}</span>
    </div>
    <div class="renglones">{#each k.renglones as r (r.id)}{@render enviado(r)}{/each}</div>
  </div>
{/each}
{#if sinArea.length}
  <div class="bloque-c">
    <div class="bloque-cabeza"><span class="etiqueta-c">Se entrega directo</span></div>
    <div class="renglones">{#each sinArea as r (r.id)}{@render enviado(r)}{/each}</div>
  </div>
{/if}

{#if !nuevo && !lineas.length && !bloques.length && !sinArea.length}
  <div class="vacio-c">
    <b>{titulo} está libre</b>
    <span>Lo que anotes se queda en este {donde} hasta que {hasta}. Ahí se abre la cuenta.</span>
  </div>
{/if}

{#if conCuenta && (descuento || pagado > 0)}
  <div class="resumen-c">
    {#if descuento}
      <div><span>Subtotal</span><span>{pesos(subtotal)}</span></div>
      <div class="desc"><span>Descuento {descuento.texto} · «{descuento.motivo}»</span><span>−{pesos(descuento.monto)}</span></div>
    {/if}
    {#if pagado > 0}<div><span>Pagado</span><span>{pesos(pagado)}</span></div>{/if}
    {#if falta !== null}<div class="fuerte"><span>Falta</span><span>{pesos(falta)}</span></div>{/if}
  </div>
{/if}
