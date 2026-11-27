<!--
  «Revisa tu menú» (el menú con IA; maqueta 1Y6NCBNSZwWCVatj17iCDA, «Lo que elegí yo» 8 a 12 de la v1): la carta como la
  leyó la IA, en su orden, una tabla de Mi menú por categoría con su ícono, su nombre y la marca «Nueva» o «Ya la tienes:
  entran ahí». Cada dato se corrige ahí mismo (se lee como texto y, al pasar o escribir, es la caja de texto de la app);
  el nombre de una categoría solo si es nueva. Lo corregido se queda en la lectura de la plática (`alCambiar`), así que
  cerrar con la ✕ no pierde nada. La cajita dice qué sube: «Ya lo tienes» (lo saca la app con lo que lee de Mi menú)
  empieza sin palomear. Las dudas, en ámbar. Abajo, fijo, cuántos se suben o qué falta, y «Subir a mi menú»
  (subir_a_mi_menu: todo o nada); después la IA traduce el inglés sola, como al guardar en Mi menú.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import Boton from '../../../diseno/Boton.svelte';
  import CajaError from '../../../diseno/CajaError.svelte';
  import Esqueleto from '../../../diseno/Esqueleto.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import IconoCategoria from '../../../diseno/IconoCategoria.svelte';
  import Tabla from '../../../diseno/Tabla.svelte';
  import Ventana from '../../../diseno/Ventana.svelte';
  import {
    comparar,
    dudaAhora,
    precioDeTexto,
    sube,
    subirAMiMenu,
    TEXTO_DUDA,
    type CartaGuardada,
    type CategoriaLeida,
    type ProductoLeido,
  } from '../../../lib/carta';
  import { esDeRed, Fallo, ALGO_SALIO_PANEL, SIN_CONEXION } from '../../../lib/errores';
  import { plural } from '../../../lib/formato';
  import { leerMenu } from '../../../lib/menu';
  import { traductor } from '../../../lib/traduccion';

  let {
    restauranteId,
    carta,
    alCambiar,
    alSubida,
    alCerrar,
  }: {
    restauranteId: string;
    carta: CartaGuardada;
    alCambiar: (categorias: CategoriaLeida[]) => void;
    alSubida: (subida: NonNullable<CartaGuardada['subida']>) => void;
    alCerrar: () => void;
  } = $props();

  // svelte-ignore state_referenced_locally
  let categorias = $state<CategoriaLeida[]>($state.snapshot(carta.categorias));
  let comparadas = $state<{ existe: boolean; tiene: boolean[] }[] | null>(null);
  let errorMenu = $state<string | null>(null);
  let error = $state<string | null>(null);
  let subiendo = $state(false);
  const quieto = typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;

  onMount(() => {
    leerMenu(restauranteId)
      .then((menu) => (comparadas = categorias.map((c) => comparar(menu, c))))
      .catch((falla) => {
        console.error('[carta] no se pudo leer Mi menú para compararlo con la carta:', falla);
        errorMenu = esDeRed(falla) ? SIN_CONEXION : 'No pudimos leer tu menú para compararlo con tu carta. Cierra y vuelve a intentarlo.';
      });
  });

  function guardar() {
    alCambiar($state.snapshot(categorias));
  }

  const tiene = (ci: number, pi: number) => comparadas?.[ci]?.tiene[pi] ?? false;

  // Lo que se va a subir y lo que falta para poder.
  const cuenta = $derived.by(() => {
    let n = 0;
    const sinPrecio: string[] = [];
    let sinNombre = 0;
    categorias.forEach((c, ci) =>
      c.productos.forEach((p, pi) => {
        if (!sube(p, tiene(ci, pi))) return;
        n++;
        if (!p.nombre.trim()) sinNombre++;
        if (!p.precio.trim()) sinPrecio.push(p.nombre.trim() || 'un producto');
      }),
    );
    return { n, sinPrecio, sinNombre };
  });

  const resumen = $derived.by(() => {
    const { n, sinPrecio, sinNombre } = cuenta;
    if (sinPrecio.length) {
      const nombres = sinPrecio.length > 3 ? `${sinPrecio.slice(0, 3).join(', ')} y ${sinPrecio.length - 3} más` : sinPrecio.join(', ');
      return { ambar: true, texto: `Ponle precio a ${nombres} para poder subir.` };
    }
    if (sinNombre) return { ambar: true, texto: `Ponle nombre a ${sinNombre === 1 ? 'un producto' : `${sinNombre} productos`} para poder subir.` };
    return { ambar: false, texto: `Se ${n === 1 ? 'sube 1 producto' : `suben ${n} productos`} a tu menú, sin fotos.` };
  });

  const puede = $derived(!!comparadas && !subiendo && !resumen.ambar && cuenta.n > 0);

  function alternar(p: ProductoLeido, ci: number, pi: number) {
    p.sube = !sube(p, tiene(ci, pi));
    error = null;
    guardar();
  }

  function escribirPrecio(p: ProductoLeido, e: Event & { currentTarget: HTMLInputElement }) {
    const limpio = e.currentTarget.value.replace(/[^\d.,]/g, '');
    if (limpio !== e.currentTarget.value) e.currentTarget.value = limpio;
    p.precio = limpio;
    if (p.duda === 'revisa_precio') p.arreglada = true;
    error = null;
    guardar();
  }

  async function subir() {
    if (!puede || !comparadas) return;
    const mandar: { nombre: string; icono: string; productos: { nombre: string; descripcion: string; precio: number }[] }[] = [];
    const nuevas: string[] = [];
    const existentes: string[] = [];
    for (const [ci, c] of categorias.entries()) {
      const productos = [];
      for (const [pi, p] of c.productos.entries()) {
        if (!sube(p, tiene(ci, pi))) continue;
        const precio = precioDeTexto(p.precio);
        if (precio === null) {
          error = `Revisa el precio de «${p.nombre.trim()}»: escríbelo como 45 o 45.50.`;
          return;
        }
        productos.push({ nombre: p.nombre, descripcion: p.descripcion, precio });
      }
      if (!productos.length) continue;
      mandar.push({ nombre: c.nombre, icono: c.icono, productos });
      const nombre = c.nombre.trim();
      if (comparadas[ci].existe) {
        if (!existentes.includes(nombre)) existentes.push(nombre);
      } else if (!nuevas.includes(nombre)) nuevas.push(nombre);
    }
    subiendo = true;
    error = null;
    try {
      const r = await subirAMiMenu(restauranteId, mandar);
      // El inglés lo traduce la IA sola, como después de guardar en Mi menú (sin esperarla).
      traductor(restauranteId, () => {}).correr();
      alSubida({ productos: r.productos, nuevas, existentes });
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[carta] no se pudo subir la carta:', falla);
      error = falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL;
      subiendo = false;
    }
  }

  // Las filas entran en cascada, como en Mi menú.
  function cascada(nodo: HTMLElement, orden: number) {
    if (quieto) return;
    nodo.animate(
      [
        { opacity: 0, transform: 'translateY(20px) scale(0.98)', filter: 'blur(4px)' },
        { opacity: 1, transform: 'none', filter: 'none' },
      ],
      { duration: 520, delay: 120 + orden * 40, easing: 'cubic-bezier(0.34, 1.3, 0.64, 1)', fill: 'backwards' },
    );
  }
</script>

<Ventana
  etiqueta="TU CARTA"
  titulo="Revisa tu menú"
  ancho={1080}
  centrado
  textoArriba
  texto="Así lo leí, en el orden de tu carta. Corrige lo que haga falta: nada se guarda hasta «Subir a mi menú»."
  alCerrar={() => {
    if (!subiendo) alCerrar();
  }}
>
  <div class="revision">
    {#if errorMenu}
      <CajaError mensaje={errorMenu} />
    {:else}
      {#if !comparadas}<span class="solo-lector">Comparando tu carta con tu menú…</span>{/if}
      {#each categorias as c, ci (ci)}
        {@const cmp = comparadas?.[ci]}
        <section class="cat">
          <div class="cat-cabeza">
            <span class="cuadro"><IconoCategoria id={c.icono} tamano={20} /></span>
            <input
              class="cat-nombre"
              aria-label="Nombre de la categoría"
              bind:value={c.nombre}
              readonly={!cmp || cmp.existe}
              oninput={guardar}
            />
            {#if !cmp}
              <Esqueleto ancho="64px" alto="22px" redondo="6px" />
            {:else if cmp.existe}
              <span class="marca">Ya la tienes: entran ahí</span>
            {:else}
              <span class="marca nueva">Nueva</span>
            {/if}
            <span class="crece"></span>
            <span class="cuenta">{plural(c.productos.length, 'PRODUCTO', 'PRODUCTOS')}</span>
          </div>
          <div class="tabla-carta">
            <Tabla
              columnas="20px 1.15fr 1.6fr 108px 176px"
              relleno="0 14px"
              altoFila={56}
              marco
              encabezados={[{ texto: '' }, { texto: 'Producto' }, { texto: 'Descripción' }, { texto: 'Precio' }, { texto: '' }]}
            >
              {#if !cmp}
                {#each c.productos.slice(0, 3) as _, pi (pi)}
                  <div class="fila quieta" aria-hidden="true">
                    <Esqueleto ancho="20px" alto="20px" redondo="6px" />
                    <Esqueleto ancho="120px" alto="11px" />
                    <Esqueleto ancho="180px" alto="10px" />
                    <Esqueleto ancho="36px" alto="11px" />
                    <span></span>
                  </div>
                {/each}
              {:else}
                {#each c.productos as p, pi (pi)}
                  {@const si = sube(p, cmp.tiene[pi])}
                  {@const duda = dudaAhora(p)}
                  <div class="fila" class:fuera={!si} class:con-duda={!!duda} use:cascada={ci * 7 + pi}>
                    <button
                      type="button"
                      class="cajita"
                      class:si
                      role="checkbox"
                      aria-checked={si}
                      aria-label={si ? 'Se sube' : 'No se sube'}
                      onclick={() => alternar(p, ci, pi)}>{#if si}<Icono nombre="check" tamano={13} />{/if}</button
                    >
                    <input
                      class="celda nombre"
                      class:duda={duda === 'sin_nombre'}
                      aria-label="Nombre"
                      placeholder="Nombre"
                      spellcheck="true"
                      bind:value={p.nombre}
                      oninput={() => {
                        if (p.duda === 'sin_nombre') p.arreglada = true;
                        error = null;
                        guardar();
                      }}
                    />
                    <input
                      class="celda"
                      aria-label="Sin descripción"
                      placeholder="Sin descripción"
                      spellcheck="true"
                      bind:value={p.descripcion}
                      oninput={guardar}
                    />
                    <label class="precio" class:duda={duda === 'sin_precio' || duda === 'revisa_precio' || duda === 'falta_precio'}>
                      <span>$</span>
                      <input
                        class="celda"
                        aria-label="Precio"
                        placeholder="—"
                        inputmode="decimal"
                        value={p.precio}
                        oninput={(e) => escribirPrecio(p, e)}
                      />
                    </label>
                    <span class="nota-celda">
                      {#if duda}
                        <span class="chip ambar"><Icono nombre="alerta" tamano={13} /><span>{TEXTO_DUDA[duda]}</span></span>
                      {:else if cmp.tiene[pi]}
                        <span class="chip">Ya lo tienes</span>
                      {/if}
                    </span>
                  </div>
                {/each}
              {/if}
            </Tabla>
          </div>
        </section>
      {/each}
    {/if}
  </div>

  {#snippet pie()}
    {#if error}
      <div class="error-pie"><CajaError mensaje={error} compacta /></div>
    {:else if comparadas}
      <p class="resumen" class:nota-ambar={resumen.ambar}>
        {#if resumen.ambar}<Icono nombre="alerta" tamano={15} />{/if}<span>{resumen.texto}</span>
      </p>
    {:else}
      <p class="resumen"><Esqueleto ancho="220px" alto="10px" /></p>
    {/if}
    <span class="crece"></span>
    <Boton
      tono="verde"
      etiqueta={subiendo ? 'Subiendo…' : 'Subir a mi menú'}
      iconoVerde="flecha-sube"
      apagado={!puede}
      onclick={subir}
    />
  {/snippet}
</Ventana>

<style>
  .revision {
    display: flex;
    flex-direction: column;
    gap: 26px;
    padding-top: 20px;
  }

  .cat {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .cat-cabeza {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .cuadro {
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

  .cat-nombre {
    field-sizing: content;
    min-width: 60px;
    max-width: 340px;
    height: 36px;
    padding: 0 10px;
    margin-left: -4px;
    border: 0;
    border-radius: 10px;
    background: transparent;
    font: inherit;
    font-size: 17px;
    font-weight: 700;
    letter-spacing: -0.01em;
    color: var(--texto);
    outline: none;
    transition:
      background 0.15s,
      box-shadow 0.15s;
  }

  .cat-nombre:not([readonly]):hover {
    background: var(--campo-encima);
  }

  .cat-nombre:not([readonly]):focus {
    background: var(--campo-fondo);
    box-shadow: 0 0 0 2px var(--campo-aro);
  }

  .cat-nombre[readonly] {
    cursor: default;
  }

  .marca {
    padding: 3px 9px;
    border-radius: 6px;
    background: var(--chip);
    font-size: 12px;
    font-weight: 600;
    color: var(--suave);
    white-space: nowrap;
  }

  .marca.nueva {
    color: var(--acento);
    background: color-mix(in oklab, var(--acento) 12%, transparent);
  }

  .cuenta {
    font-family: var(--mono);
    font-size: 10.5px;
    letter-spacing: 0.12em;
    color: var(--tenue);
  }

  .crece {
    flex: 1;
  }

  /* La tabla mide lo que sus filas: lo que se desliza es la ventana. */
  .tabla-carta {
    display: flex;
    flex-direction: column;
  }

  .tabla-carta :global(.tabla) {
    flex: none;
    overflow: visible;
  }

  .tabla-carta :global(.cuerpo) {
    overflow: visible;
  }

  .fila {
    transition: background 0.15s;
  }

  .tabla-carta :global(.fila:last-child) {
    border-bottom: 0;
  }

  /* Más fuerte que el blanco de las filas de la tabla con marco (diseno/Tabla.svelte). */
  .tabla-carta :global(.tabla.marco .cuerpo > .fila.con-duda) {
    background: color-mix(in oklab, var(--amarillo-fondo) 55%, transparent);
  }

  .cajita {
    width: 20px;
    height: 20px;
    padding: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    border: 1.5px solid var(--tenue);
    border-radius: 6px;
    background: var(--solido);
    color: var(--sobre-tinta);
  }

  .cajita.si {
    border: 0;
    background: var(--tinta);
  }

  .fila.fuera .celda,
  .fila.fuera .precio {
    opacity: 0.45;
  }

  /* Cada dato se corrige ahí mismo: se lee como texto y, al pasar o escribir, es la caja de texto de la app. */
  .celda {
    width: 100%;
    min-width: 0;
    height: 38px;
    padding: 0 10px;
    margin-left: -10px;
    border: 0;
    border-radius: 10px;
    background: transparent;
    font: inherit;
    font-size: 13.5px;
    color: var(--texto);
    outline: none;
    text-overflow: ellipsis;
    transition:
      background 0.15s,
      box-shadow 0.15s;
  }

  .celda.nombre {
    font-weight: 600;
  }

  .celda::placeholder {
    color: var(--tenue);
    font-weight: 400;
  }

  .celda:hover {
    background: var(--campo-encima);
  }

  .celda:focus {
    background: var(--campo-fondo);
    box-shadow: 0 0 0 2px var(--campo-aro);
  }

  .precio {
    display: flex;
    align-items: center;
    gap: 2px;
    height: 38px;
    margin-left: -10px;
    padding-left: 10px;
    border-radius: 10px;
    font-size: 13.5px;
    font-weight: 600;
    color: var(--suave);
    transition:
      background 0.15s,
      box-shadow 0.15s;
    cursor: text;
  }

  .precio .celda {
    margin-left: 0;
    padding-left: 2px;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
  }

  .precio .celda:hover,
  .precio .celda:focus {
    background: transparent;
    box-shadow: none;
  }

  .precio:hover {
    background: var(--campo-encima);
  }

  .precio:focus-within {
    background: var(--campo-fondo);
    box-shadow: 0 0 0 2px var(--campo-aro);
  }

  .precio.duda,
  .celda.duda {
    box-shadow: inset 0 0 0 1.5px var(--amarillo);
    background: var(--amarillo-fondo);
  }

  .precio.duda:focus-within {
    box-shadow: 0 0 0 2px var(--campo-aro);
    background: var(--campo-fondo);
  }

  .nota-celda {
    display: flex;
    justify-content: flex-start;
    min-width: 0;
  }

  .chip {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    max-width: 100%;
    padding: 4px 9px;
    border-radius: 7px;
    background: var(--chip);
    font-size: 12px;
    font-weight: 600;
    color: var(--suave);
    white-space: nowrap;
  }

  .chip.ambar {
    background: var(--amarillo-fondo);
    color: var(--amarillo-texto);
  }

  .chip :global(svg) {
    flex: none;
  }

  .resumen {
    margin: 0;
    font-size: 13px;
    font-weight: 500;
    color: var(--suave);
  }

  .nota-ambar {
    display: flex;
    align-items: flex-start;
    gap: 8px;
    padding: 10px 12px;
    border-radius: 10px;
    background: var(--amarillo-fondo);
    color: var(--amarillo-texto);
    line-height: 1.45;
  }

  .nota-ambar :global(svg) {
    flex: none;
    margin-top: 1px;
  }

  .error-pie {
    min-width: 0;
    flex: 0 1 620px;
  }
</style>
