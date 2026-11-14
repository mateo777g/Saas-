<!--
  «Tus carteles» (maqueta UDArhiEZceT7rmSKxqRA5r v59, «Que sea más fácil poner los carteles», 11 nov 2026): la ventana
  que abre el botón negro «Carteles» de la barra de arriba. Cinco espacios en columna, en su orden, cada uno una imagen
  que sube el restaurante o la foto de un producto de Mi menú, mezclados; tienen la forma de sus carteles (con «Bajito»,
  de 3 a 1). Los llenos llevan su número, sus flechas, su nombre, «Cambiar» y «Quitar»; el primero vacío se parte en
  dos: «Subir imagen» o «Foto de un producto». Todo se guarda al momento, como antes: no pasa por la barra de guardar.

  La imagen se sube antes de guardar (en 1600 × 900; si no es 16:9 sale entera con los lados desenfocados) y si el
  guardado falla se borra; la anterior se borra solo después de guardar. Mientras sube, «Subiendo…» con su rueda y lo
  demás se apaga. Los que se quedan se acomodan con el resorte de las ventanas; el que se quita se va como cierran ellas.
  Al abrir, sus espacios entran en cascada; si la vista todavía lee, van en esqueleto con tantos llenos como había.
-->
<script lang="ts">
  import { tick } from 'svelte';
  import { flip } from 'svelte/animate';
  import BotonCuadro from '../../../diseno/BotonCuadro.svelte';
  import CajaError from '../../../diseno/CajaError.svelte';
  import { cascada } from '../../../diseno/cascada';
  import Esqueleto from '../../../diseno/Esqueleto.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import Ventana from '../../../diseno/Ventana.svelte';
  import { quieto, RESORTE } from '../../../diseno/ventanaSeMueve';
  import { ALGO_SALIO_PANEL, Fallo } from '../../../lib/errores';
  import { filasDeLaUltimaVez, recordarFilas } from '../../../lib/esqueletos';
  import { borrarFoto, convertirCartel, revisarFoto, subirFoto, urlFoto } from '../../../lib/fotos';
  import type { Categoria, Producto } from '../../../lib/menu';
  import {
    agregarCartel,
    cambiarCartel,
    MAXIMO_CARTELES,
    moverCartel,
    quitarCartel,
    type Cartel,
    type LoDelCartel,
  } from '../../../lib/restaurante';
  import FotoDeProducto from './FotoDeProducto.svelte';

  let {
    restauranteId,
    carteles,
    productos,
    categorias,
    bajito,
    conNombre,
    cargando,
    alCambiar,
    alCerrar,
  }: {
    restauranteId: string;
    carteles: Cartel[];
    // Los de Mi menú (sin archivar ni envíos), para los carteles de producto y «Foto de un producto».
    productos: Producto[];
    categorias: Categoria[];
    bajito: boolean;
    // «Con nombre y precio» en sus carteles de producto: aquí también se ve encima de la foto.
    conNombre: boolean;
    cargando: boolean;
    alCambiar: () => Promise<void>;
    alCerrar: () => void;
  } = $props();

  const NOTA = 'Pasan solos en tu menú, en este orden: una imagen tuya o la foto de un producto de Mi menú.';
  const llave = $derived(`carteles-${restauranteId}`);
  // svelte-ignore state_referenced_locally
  const llenosEsqueleto = filasDeLaUltimaVez(`carteles-${restauranteId}`);
  const ANCHOS_NOMBRE = [88, 64, 104, 76, 92];
  $effect(() => {
    if (!cargando) recordarFilas(llave, carteles.length);
  });

  // Qué se está haciendo: subir uno nuevo o cambiar la imagen de uno (su id), o mover, quitar o poner un producto.
  let ocupado = $state<null | 'nuevo' | number | 'otro'>(null);
  let error = $state<string | null>(null);
  let elegirArchivo = $state<HTMLInputElement>();
  let paraCambiar: number | null = null;
  // «Foto de un producto»: para uno nuevo (null) o para cambiar el producto de uno (su id).
  let eligiendo = $state<{ cartel: number | null } | null>(null);
  let lista = $state<HTMLDivElement>();

  const vacios = $derived(Array.from({ length: Math.max(0, MAXIMO_CARTELES - carteles.length) }, (_, i) => carteles.length + i));
  const productoDe = (c: Cartel) => (c.producto_id === null ? null : (productos.find((p) => p.id === c.producto_id) ?? null));
  const precioCorto = (n: number) => `$${Number.isInteger(n) ? n : n.toFixed(2)}`;

  // Sus espacios entran en cascada al abrir; si la vista todavía lee, cuando lleguen los datos.
  let yaEntraron = false;
  $effect(() => {
    if (cargando || yaEntraron || !lista) return;
    yaEntraron = true;
    const el = lista;
    tick().then(() => cascada(el, '.espacio'));
  });

  function elegir(id: number | null) {
    if (ocupado !== null) return;
    paraCambiar = id;
    elegirArchivo?.click();
  }

  async function alElegirArchivo(e: Event & { currentTarget: HTMLInputElement }) {
    const archivo = e.currentTarget.files?.[0];
    e.currentTarget.value = '';
    if (!archivo || ocupado !== null) return;
    const problema = await revisarFoto(archivo);
    if (problema) {
      error = problema;
      return;
    }
    const id = paraCambiar;
    error = null;
    ocupado = id ?? 'nuevo';
    let ruta: string | null = null;
    let anterior: string | null = null;
    try {
      ruta = await subirFoto(restauranteId, await convertirCartel(archivo), 'carteles');
      if (id === null) await agregarCartel(restauranteId, { imagen: ruta });
      else anterior = await cambiarCartel(id, { imagen: ruta });
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[carteles] no se pudo guardar el cartel:', falla);
      // La imagen de un cartel que no se guardó no se queda en R2.
      if (ruta) await borrarFoto(ruta);
      error = falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL;
      ocupado = null;
      return;
    }
    if (anterior) await borrarFoto(anterior);
    await alCambiar();
    ocupado = null;
  }

  async function hacer(accion: () => Promise<string | null | void>) {
    if (ocupado !== null) return;
    ocupado = 'otro';
    error = null;
    try {
      const ruta = await accion();
      if (ruta) await borrarFoto(ruta);
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[carteles] no se pudo cambiar:', falla);
      error = falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL;
    }
    await alCambiar();
    ocupado = null;
  }

  function ponerProducto(productoId: number) {
    const cartel = eligiendo?.cartel ?? null;
    eligiendo = null;
    const lo: LoDelCartel = { producto: productoId };
    hacer(() => (cartel === null ? agregarCartel(restauranteId, lo) : cambiarCartel(cartel, lo)));
  }

  // El que se quita se va como cierran las ventanas (0.2 s, se achica y se desvanece); luego los demás suben.
  function sale(_el: Element) {
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) return { duration: 0 };
    return { duration: 200, css: (x: number) => `opacity: ${x}; transform: scale(${0.96 + 0.04 * x})` };
  }
  function nace(_el: Element) {
    if (matchMedia('(prefers-reduced-motion: reduce)').matches || !yaEntraron) return { duration: 0 };
    return { duration: 350, easing: RESORTE, css: (x: number) => `opacity: ${Math.min(1, x)}; transform: scale(${0.96 + 0.04 * x})` };
  }
  const resorte = () => (quieto() ? { duration: 0 } : { duration: 350, easing: RESORTE });
</script>

<Ventana centrado titulo="Tus carteles" nota={cargando ? NOTA : `${carteles.length} de ${MAXIMO_CARTELES}. ${NOTA}`} ancho={560} {alCerrar}>
  <div class="tc" class:bajito>
    <input bind:this={elegirArchivo} type="file" accept="image/png,image/jpeg" hidden onchange={alElegirArchivo} />
    {#if error}<CajaError mensaje={error} />{/if}
    {#if cargando}
      <span class="solo-lector">Cargando tus carteles…</span>
      <div class="rejilla" aria-hidden="true">
        {#each [0, 1, 2, 3, 4] as i (i)}
          <div class="espacio">
            <span class="esq-imagen"><Esqueleto ancho="100%" alto="100%" redondo="12px" /></span>
            {#if i < llenosEsqueleto}
              <div class="acciones"><span style:margin-left="84px"><Esqueleto ancho="{ANCHOS_NOMBRE[i]}px" alto="12px" /></span></div>
            {/if}
          </div>
        {/each}
      </div>
    {:else}
      <div class="rejilla" bind:this={lista}>
        {#each carteles as c, i (c.id)}
          {@const p = productoDe(c)}
          <div class="espacio lleno" class:subiendo={ocupado === c.id} animate:flip={resorte()} in:nace out:sale>
            <div class="imagen">
              {#if c.imagen_ruta}
                <img src={urlFoto(c.imagen_ruta)} alt="Cartel {i + 1}" />
              {:else if p?.imagen_ruta}
                <img src={urlFoto(p.imagen_ruta)} alt={p.nombre} />
                {#if conNombre}
                  <span class="cp-texto"><b>{p.nombre}</b><span>{precioCorto(p.precio)}</span></span>
                {/if}
              {:else}
                <!-- Un producto que perdió su foto se queda aquí y no sale en el menú. -->
                <span class="sin-foto"><Icono nombre="alerta" tamano={18} />{p ? 'Sin foto: no sale en tu menú' : 'Ya no está en Mi menú'}</span>
              {/if}
              {#if c.producto_id !== null}
                <span class="tipo"><Icono nombre="menu" tamano={13} />Mi menú</span>
              {/if}
              <span class="num">{i + 1}</span>
            </div>
            <div class="acciones">
              <BotonCuadro
                icono="arriba"
                ayuda="Subir"
                tamanoIcono={15}
                apagado={i === 0 || ocupado !== null}
                onclick={() => hacer(() => moverCartel(c.id, 'arriba'))}
              />
              <BotonCuadro
                icono="abajo"
                ayuda="Bajar"
                tamanoIcono={15}
                apagado={i === carteles.length - 1 || ocupado !== null}
                onclick={() => hacer(() => moverCartel(c.id, 'abajo'))}
              />
              <span class="nombre">{ocupado === c.id ? 'Subiendo…' : p ? p.nombre : 'Imagen'}</span>
              {#if c.producto_id !== null}
                <BotonCuadro
                  icono="menu"
                  ayuda="Cambiar producto"
                  tamanoIcono={15}
                  apagado={ocupado !== null}
                  onclick={() => (eligiendo = { cartel: c.id })}
                />
              {:else}
                <BotonCuadro icono="biblio" ayuda="Cambiar imagen" tamanoIcono={15} apagado={ocupado !== null} onclick={() => elegir(c.id)} />
              {/if}
              <BotonCuadro icono="eliminar" ayuda="Quitar cartel" tamanoIcono={15} apagado={ocupado !== null} onclick={() => hacer(() => quitarCartel(c.id))} />
            </div>
          </div>
        {/each}
        {#each vacios as n (n)}
          <div class="espacio vacio" class:primero={n === carteles.length}>
            <div class="imagen">
              <span class="num">{n + 1}</span>
              {#if n === carteles.length}
                <span class="poner">
                  <button type="button" class:subiendo={ocupado === 'nuevo'} disabled={ocupado !== null} onclick={() => elegir(null)}>
                    {#if ocupado === 'nuevo'}<span class="rueda" aria-hidden="true"></span>{:else}<Icono nombre="agregar" tamano={22} />{/if}
                    <span>{ocupado === 'nuevo' ? 'Subiendo…' : 'Subir imagen'}</span>
                  </button>
                  <button type="button" disabled={ocupado !== null} onclick={() => (eligiendo = { cartel: null })}>
                    <Icono nombre="menu" tamano={22} /><span>Foto de un producto</span>
                  </button>
                </span>
              {/if}
            </div>
          </div>
        {/each}
      </div>
    {/if}
    <p class="pista">
      Tus imágenes: {bajito ? '3:1, como 1500 × 500' : '16:9, como 1600 × 900'} · JPG o PNG. Las fotos de tus productos salen de Mi menú,
      recortadas al centro{bajito ? ' a lo bajito' : ''}.
    </p>
  </div>
</Ventana>

{#if eligiendo}
  <FotoDeProducto
    {productos}
    {categorias}
    yaPuestos={carteles.filter((c) => c.producto_id !== null && c.id !== eligiendo?.cartel).map((c) => c.producto_id!)}
    alElegir={ponerProducto}
    alCerrar={() => (eligiendo = null)}
  />
{/if}

<style>
  .tc {
    display: flex;
    flex-direction: column;
    gap: 16px;
  }

  .rejilla {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    gap: 20px;
  }

  .espacio {
    display: flex;
    flex-direction: column;
    gap: 8px;
    min-width: 0;
  }

  .imagen,
  .esq-imagen {
    position: relative;
    display: block;
    aspect-ratio: 16 / 9;
    border-radius: 12px;
    overflow: hidden;
    background: var(--fondo);
  }

  .bajito .imagen,
  .bajito .esq-imagen {
    aspect-ratio: 3 / 1;
  }

  .esq-imagen {
    background: transparent;
  }

  .imagen > img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
    transition: opacity 0.2s ease;
  }

  .subiendo .imagen > img {
    opacity: 0.5;
  }

  .vacio .imagen {
    background: transparent;
    box-shadow: inset 0 0 0 1.5px var(--borde-tarjeta);
  }

  .vacio:not(.primero) .imagen {
    opacity: 0.6;
  }

  .num {
    position: absolute;
    left: 8px;
    top: 8px;
    z-index: 2;
    min-width: 22px;
    height: 22px;
    padding: 0 6px;
    border-radius: 6px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    font: 600 11px var(--mono);
    background: rgba(0, 0, 0, 0.55);
    color: #fff;
    backdrop-filter: blur(6px);
    pointer-events: none;
  }

  .vacio .num {
    background: var(--chip);
    color: var(--tenue);
    backdrop-filter: none;
  }

  .tipo {
    position: absolute;
    right: 8px;
    top: 8px;
    z-index: 2;
    height: 22px;
    padding: 0 8px 0 6px;
    border-radius: 6px;
    display: inline-flex;
    align-items: center;
    gap: 4px;
    font-size: 11px;
    font-weight: 600;
    background: rgba(0, 0, 0, 0.55);
    color: #fff;
    backdrop-filter: blur(6px);
  }

  /* Su nombre y su precio encima de la foto, como los escribe el menú. */
  .cp-texto {
    position: absolute;
    left: 0;
    right: 0;
    bottom: 0;
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 2px;
    padding: 24px 10px 8px;
    text-align: left;
    color: #fff;
    background: linear-gradient(to top, rgba(0, 0, 0, 0.62), rgba(0, 0, 0, 0));
  }

  .cp-texto b {
    font-size: 13px;
    font-weight: 800;
    letter-spacing: -0.3px;
    line-height: 1.2;
  }

  .cp-texto span {
    font-size: 11.5px;
    font-weight: 600;
    opacity: 0.92;
  }

  .sin-foto {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    font-size: 13px;
    font-weight: 600;
    color: var(--suave);
  }

  .poner {
    position: absolute;
    inset: 0;
    display: grid;
    grid-template-columns: 1fr 1fr;
  }

  .poner button {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 8px;
    padding: 8px;
    border: 0;
    background: transparent;
    color: var(--texto);
    font: 600 14px var(--jakarta);
    cursor: pointer;
    transition: background 0.15s ease;
  }

  .poner button + button {
    box-shadow: inset 1.5px 0 0 var(--borde-tarjeta);
  }

  .poner button:hover:not(:disabled) {
    background: var(--chip);
  }

  .poner button:focus-visible {
    outline: 2px solid var(--campo-aro);
    outline-offset: -2px;
  }

  .poner button:disabled {
    cursor: default;
  }

  .poner button:disabled:not(.subiendo) {
    opacity: 0.45;
  }

  .bajito .poner button {
    flex-direction: row;
    font-size: 12px;
  }

  /* La rueda de Boton mientras sube. */
  .rueda {
    width: 20px;
    height: 20px;
    border-radius: 50%;
    border: 2px solid var(--linea-fuerte);
    border-top-color: var(--texto);
    animation: gira 0.8s linear infinite;
  }

  @keyframes gira {
    to {
      transform: rotate(360deg);
    }
  }

  .acciones {
    min-height: 36px;
    display: flex;
    align-items: center;
    gap: 4px;
  }

  .nombre {
    flex: 1;
    min-width: 0;
    padding: 0 4px;
    font-size: 13px;
    font-weight: 600;
    color: var(--texto);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .pista {
    margin: 0;
    font-size: 12.5px;
    line-height: 1.45;
    color: var(--tenue);
  }

  @media (prefers-reduced-motion: reduce) {
    .rueda {
      animation-duration: 2s;
    }

    .poner button,
    .imagen > img {
      transition: none;
    }
  }
</style>
