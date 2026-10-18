<!--
  Una cuenta (maqueta Mesero y cocina, estado «Mesa 4»). Arriba, lo anotado y todavía no mandado,
  punteado en «Por mandar»: vive solo en este aparato y se cambia o se quita sin permiso. Debajo,
  lo mandado, una comanda por bloque (la más nueva arriba) con su área y si ya está lista, y lo
  que no va a ninguna pantalla en «Lo sirve el mesero». El total es el de Postgres, y si ya tiene
  pagos, lo pagado y lo que falta (parte 4b). Abajo, Agregar y «Mandar a cocina», que sin internet
  dice «Sin conexión»; sin nada por mandar, el botón es «Cobrar» (maqueta La caja).
-->
<script lang="ts" module>
  // Lo que la cuenta pinta, ya en palabras: el componente no cuenta nada.
  export type LineaVista = { nombre: string; detalle: string; nota: string; cantidad: number; importe: number | null };
  export type EnviadoVista = {
    id: number;
    nombre: string;
    detalle: string;
    nota: string;
    cantidad: number;
    importe: number;
    por: string;
  };
  export type BloqueVista = { id: number; etiqueta: string; estado: 'pendiente' | 'lista'; renglones: EnviadoVista[] };
</script>

<script lang="ts">
  import type { Snippet } from 'svelte';
  import CajaError from '../../diseno/CajaError.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import { dinero } from '../../lib/formato';
  import MarcaEstado from './MarcaEstado.svelte';

  let {
    titulo,
    sub,
    volver,
    conCuenta,
    domicilio,
    lineas,
    bloques,
    sinArea,
    total,
    pagado,
    falta,
    donde,
    error,
    sinRed,
    enviando,
    aviso,
    alVolver,
    alMenu,
    alAgregar,
    alMandar,
    alCobrar,
    alCambiar,
    alQuitar,
  }: {
    titulo: string;
    sub: string;
    volver: string;
    conCuenta: boolean;
    domicilio: { telefono: string; direccion: string } | null;
    lineas: LineaVista[];
    bloques: BloqueVista[];
    sinArea: EnviadoVista[];
    total: number | null;
    pagado: number;
    falta: number | null; // lo que falta por pagar, solo para verlo
    donde: string;
    error: string | null;
    sinRed: boolean;
    enviando: boolean;
    aviso: Snippet;
    alVolver: () => void;
    alMenu: () => void;
    alAgregar: () => void;
    alMandar: () => void;
    alCobrar: () => void;
    alCambiar: (i: number, cuantos: number) => void;
    alQuitar: (i: number) => void;
  } = $props();

  const porMandar = $derived(lineas.reduce((s, l) => s + l.cantidad, 0));
</script>

{#snippet enviado(r: EnviadoVista)}
  <div class="renglon">
    <span class="cant">{r.cantidad}</span>
    <span class="que">
      <b>{r.nombre}</b>
      {#if r.detalle}<span class="det">{r.detalle}</span>{/if}
      {#if r.nota}<span class="nota-r">{r.nota}</span>{/if}
      <span class="por">{r.por}</span>
    </span>
    <span class="imp">{dinero(r.importe)}</span>
  </div>
{/snippet}

<div class="cel-arriba">
  <button type="button" class="cel-volver" onclick={alVolver}><Icono nombre="anterior" tamano={16} />{volver}</button>
  <div class="cuenta-titulo">
    <b>{titulo}</b>
    <span>{sub}</span>
  </div>
  <button type="button" class="cuadro" aria-label="Más acciones" title="Más acciones" disabled={!conCuenta} onclick={alMenu}>
    <Icono nombre="puntos" tamano={18} />
  </button>
</div>
{@render aviso()}
{#if sinRed}
  <div class="caja-pos" role="alert">
    <CajaError
      tipo="sinred"
      mensaje="Sin conexión. Lo anotado sigue en este {donde}; vuelve a pulsar «Mandar a cocina» cuando regrese el internet."
    />
  </div>
{:else if error}
  <div class="caja-pos" role="alert"><CajaError mensaje={error} /></div>
{/if}

<div class="desliza">
  {#if domicilio}
    <div class="renglon solo">
      <span class="que"><b>{domicilio.telefono}</b><span class="det">{domicilio.direccion}</span></span>
    </div>
  {/if}

  {#if lineas.length}
    <div class="bloque borrador">
      <div class="bloque-cabeza"><span class="etq">Por mandar · solo en este {donde}</span></div>
      {#each lineas as l, i (i)}
        <div class="renglon">
          <span class="que">
            <b>{l.nombre}</b>
            {#if l.detalle}<span class="det">{l.detalle}</span>{/if}
            {#if l.nota}<span class="nota-r">{l.nota}</span>{/if}
          </span>
          <span class="imp">{l.importe === null ? '—' : dinero(l.importe)}</span>
          <span class="abajo-r">
            <span class="paso">
              <button type="button" aria-label="Uno menos" onclick={() => alCambiar(i, -1)}>
                <Icono nombre="menos" tamano={14} />
              </button>
              <span>{l.cantidad}</span>
              <button type="button" aria-label="Uno más" onclick={() => alCambiar(i, 1)}><Icono nombre="mas" tamano={14} /></button>
            </span>
            <button type="button" class="quitar" onclick={() => alQuitar(i)}><Icono nombre="cerrar" tamano={14} />Quitar</button>
          </span>
        </div>
      {/each}
    </div>
  {/if}

  {#each bloques as k (k.id)}
    <div class="bloque">
      <div class="bloque-cabeza">
        <span class="etq">{k.etiqueta}</span>
        <span class="crece"></span>
        <MarcaEstado estado={k.estado} />
      </div>
      {#each k.renglones as r (r.id)}{@render enviado(r)}{/each}
    </div>
  {/each}
  {#if sinArea.length}
    <div class="bloque">
      <div class="bloque-cabeza"><span class="etq">Lo sirve el mesero</span></div>
      {#each sinArea as r (r.id)}{@render enviado(r)}{/each}
    </div>
  {/if}
  {#if total !== null}
    <div class="m-total">
      <b>Total<small>Lo mandado a cocina</small></b>
      <span>{dinero(total)}</span>
    </div>
    {#if pagado > 0 && falta !== null}
      <div class="resumen">
        <div class="resumen-fila"><span>Pagado</span><span>{dinero(pagado)}</span></div>
        <div class="resumen-fila fuerte"><span>Falta</span><span>{dinero(falta)}</span></div>
      </div>
    {/if}
  {/if}

  {#if total === null && !lineas.length}
    <div class="vacio">
      <b>{titulo}{volver === 'Mesas' ? ' está libre' : ''}</b>
      <span>Lo que anotes se queda en este {donde} hasta que lo mandes a cocina. Ahí se abre la cuenta.</span>
    </div>
  {/if}
</div>

<div class="cel-pie">
  <button type="button" class="cel-boton contorno" onclick={alAgregar}><Icono nombre="mas" tamano={18} />Agregar</button>
  {#if !porMandar && conCuenta && falta !== null && !sinRed}
    <button type="button" class="cel-boton" onclick={alCobrar}>Cobrar · {dinero(falta)}</button>
  {:else}
    <button type="button" class="cel-boton" class:sin-red={sinRed} disabled={!porMandar || enviando} onclick={alMandar}>
      {#if sinRed}
        <Icono nombre="sinred" tamano={18} />Sin conexión
      {:else}
        Mandar a cocina{porMandar ? ` · ${porMandar}` : ''}
      {/if}
    </button>
  {/if}
</div>
