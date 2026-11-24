<!--
  Tu tarjeta, la segunda sección de «Tarjeta de lealtad» (maqueta v22, SECCIÓN «Tu tarjeta»), copiada de «Tu menú en
  línea»: a la izquierda las tarjetas Cómo se junta (Sellos · Puntos, con el aviso ámbar de que al guardar las tarjetas
  regresan a 0 y la tarjeta se apaga hasta poner la regla nueva), Estilo (los seis en cuadros, dos por fila, lo elegido con
  el aro azul) y Color («Del color de tu menú» o el suyo, «Elegir color» con la ventana del color y la tarjeta en vivo, la
  X y los colores rápidos); a la derecha el teléfono con la pestaña Tarjeta (?muestra=tarjeta) pintada con lo que todavía
  no se guarda. Abajo, la barra de guardar de «Tu menú en línea»; al salir con cambios, «Tienes cambios sin guardar».
  Nace en Metal y negra (#121212). Se guarda aunque no haya regla (guardar_tu_tarjeta).
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import BarraGuardar from '../../../diseno/BarraGuardar.svelte';
  import Boton from '../../../diseno/Boton.svelte';
  import BotonCuadro from '../../../diseno/BotonCuadro.svelte';
  import CajaError from '../../../diseno/CajaError.svelte';
  import Esqueleto from '../../../diseno/Esqueleto.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import TarjetaLealtad, { type EstiloTarjeta } from '../../../diseno/TarjetaLealtad.svelte';
  import { ALGO_SALIO_PANEL, Fallo } from '../../../lib/errores';
  import type { Sucursal } from '../../../lib/gerente';
  import {
    colorDeTarjeta,
    COLORES_RAPIDOS,
    conRegla,
    ESTILOS,
    guardarTuTarjeta,
    textosDeTarjeta,
    type FormaLealtad,
    type Lealtad,
  } from '../../../lib/lealtad';
  import type { Menu } from '../../../lib/menu';
  import { ponerGuardia } from '../../../lib/salida';
  import { supabase } from '../../../lib/supabase';
  import Fila from '../menuEnLinea/Fila.svelte';
  import Formas from '../menuEnLinea/Formas.svelte';
  import Telefono from '../menuEnLinea/Telefono.svelte';
  import VentanaColor from '../menuEnLinea/VentanaColor.svelte';
  import VentanaSalir from '../menuEnLinea/VentanaSalir.svelte';

  let {
    sucursal,
    lealtad,
    menu,
    colorMenu,
    cuantasTarjetas,
    errorLectura,
    alCambiar,
  }: {
    sucursal: Sucursal;
    lealtad: Lealtad | null;
    menu: Menu | null;
    colorMenu: string | null;
    cuantasTarjetas: number;
    errorLectura: string | null;
    alCambiar: () => Promise<void>;
  } = $props();

  type Diseno = { forma: FormaLealtad; estilo: EstiloTarjeta; color: string | null };
  const deLealtad = (l: Lealtad): Diseno => ({ forma: l.forma, estilo: l.estilo, color: l.color });

  // svelte-ignore state_referenced_locally
  let guardado = $state<Diseno | null>(lealtad ? deLealtad(lealtad) : null);
  // svelte-ignore state_referenced_locally
  let s = $state<Diseno>(lealtad ? deLealtad(lealtad) : { forma: 'sellos', estilo: 'metal', color: '#121212' });
  // La primera lectura llega después de abrir: lo que se elige arranca con ella.
  $effect(() => {
    if (lealtad && !guardado) {
      guardado = deLealtad(lealtad);
      s = deLealtad(lealtad);
    }
  });

  let paso = $state<null | 'guardando' | 'listo'>(null);
  let errorGuardar = $state<string | null>(null);
  let colorAbierto = $state(false);
  let salida = $state<(() => void) | null>(null);
  let telefono = $state<ReturnType<typeof Telefono>>();

  const cargando = $derived(!guardado && !errorLectura);
  const cambios = $derived(guardado ? (['forma', 'estilo', 'color'] as const).filter((k) => s[k] !== guardado![k]).length : 0);
  const color = $derived(colorDeTarjeta(s.color, colorMenu));
  const premio = $derived(menu?.productos.find((p) => p.id === lealtad?.premio_producto_id) ?? null);
  const textos = $derived(textosDeTarjeta(lealtad?.premio_tipo ?? null, premio?.nombre ?? null, lealtad?.premio_pesos ?? null));
  const meta = $derived(lealtad?.meta && s.forma === lealtad.forma ? lealtad.meta : s.forma === 'sellos' ? 10 : 100);
  // Rosa, como en el teléfono: 2 sellos antes de la meta o el 86 % de los puntos.
  const saldo = $derived(s.forma === 'sellos' ? Math.max(1, meta - 2) : Math.round(meta * 0.86));
  const cambiaForma = $derived(!!guardado && !!lealtad && conRegla(lealtad) && s.forma !== guardado.forma);

  // Lo que se le manda al teléfono: la regla con lo que todavía no se guarda. Sin regla, la de muestra (10 sellos desde
  // $0, o un punto por cada $10 y 100 puntos, por $50 de descuento): así se ve el estilo y el color.
  const reglaTelefono = $derived.by(() => {
    const l = lealtad;
    const mismos = !!l && conRegla(l) && s.forma === l.forma;
    return {
      prendida: true,
      forma: s.forma,
      meta,
      minimo: s.forma === 'sellos' ? (mismos ? (l!.minimo ?? 0) : 0) : null,
      pesos_por_punto: s.forma === 'puntos' ? (mismos ? (l!.pesos_por_punto ?? 10) : 10) : null,
      estilo: s.estilo,
      color,
      premio:
        l && conRegla(l)
          ? {
              tipo: l.premio_tipo,
              producto_id: l.premio_producto_id,
              nombre: premio?.nombre ?? null,
              nombre_en: premio?.nombre_en ?? null,
              pesos: l.premio_pesos,
              pesos_usd: null,
            }
          : { tipo: 'pesos', producto_id: null, nombre: null, nombre_en: null, pesos: 50, pesos_usd: null },
    };
  });

  // Cada cambio se pinta en el teléfono.
  $effect(() => {
    void reglaTelefono;
    telefono?.pintar();
  });

  function elegir<K extends keyof Diseno>(k: K, v: Diseno[K]) {
    s[k] = v;
    errorGuardar = null;
  }

  async function guardar(): Promise<string | null> {
    if (!guardado || paso) return null;
    errorGuardar = null;
    paso = 'guardando';
    const lo = { ...s };
    try {
      await guardarTuTarjeta(supabase, sucursal.id, lo);
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[lealtad] no se pudo guardar Tu tarjeta:', falla);
      errorGuardar = falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL;
      paso = null;
      return errorGuardar;
    }
    guardado = lo;
    paso = 'listo';
    setTimeout(() => (paso = null), 1600);
    void alCambiar();
    return null;
  }

  function descartar() {
    if (!guardado || paso) return;
    s = { ...guardado };
    errorGuardar = null;
  }

  onMount(() => {
    // Si se va con cambios (la barra lateral, la búsqueda, otra sucursal, cerrar sesión), primero lo pregunta.
    const quitarGuardia = ponerGuardia((seguir) => {
      if (!cambios || paso) return false;
      salida = seguir;
      return true;
    });
    const alIrse = (e: BeforeUnloadEvent) => {
      if (cambios) e.preventDefault();
    };
    window.addEventListener('beforeunload', alIrse);
    return () => {
      quitarGuardia();
      window.removeEventListener('beforeunload', alIrse);
    };
  });

  const avisoForma = $derived.by(() => {
    if (!cambiaForma || !lealtad) return null;
    const otra = s.forma === 'puntos' ? 'puntos' : 'sellos';
    const tarjetas =
      cuantasTarjetas === 1 ? 'tu tarjeta regresa a 0' : cuantasTarjetas ? `las ${cuantasTarjetas.toLocaleString('en-US')} tarjetas regresan a 0` : '';
    const apaga = lealtad.prendida ? 'tu tarjeta se apaga hasta que pongas tu regla nueva' : 'pones tu regla nueva en Tarjetas';
    return { tarjetas, otra, apaga };
  });
</script>

<main class="cuerpo" aria-label="Tu tarjeta">
  <div class="col">
    <div class="cabeza">
      <span class="etiqueta">TU TARJETA</span>
      <p class="nota">Cómo ven tu tarjeta tus clientes en tu menú: cómo se junta, su estilo y su color. Tu regla y tu premio están en Tarjetas.</p>
    </div>
    {#if errorLectura}
      <CajaError mensaje={errorLectura} />
    {:else}
      <Fila clave="junta" icono="r-lealtad" titulo="Cómo se junta" nota="Lo que ven en su tarjeta cada vez que pagan." {cargando}>
        <Formas
          etiqueta="FORMA"
          opciones={[
            { valor: 'sellos', texto: 'Sellos' },
            { valor: 'puntos', texto: 'Puntos' },
          ]}
          elegida={s.forma}
          alElegir={(v) => elegir('forma', v as FormaLealtad)}
          pista="Sellos: un círculo por cada cuenta pagada desde tu mínimo. Puntos: el número con su barra. Cuántos se piden y el premio están en Tarjetas, en «Editar tu regla»."
          {cargando}
        />
        {#if avisoForma}
          <p class="cambia">
            <Icono nombre="alerta" tamano={15} /><span
              >Al guardar, {avisoForma.tarjetas ? `${avisoForma.tarjetas} (` : ''}<b>{avisoForma.otra}</b> empieza de nuevo{avisoForma.tarjetas ? ')' : ''} y
              {avisoForma.apaga}. Tus clientes lo ven en su tarjeta.</span
            >
          </p>
        {/if}
      </Fila>

      <Fila clave="estilo" icono="cartel" titulo="Estilo" nota="El diseño de tu tarjeta. En cualquiera, el color lo eliges tú." {cargando}>
        <div class="grupo">
          <span class="etiqueta">ESTILO</span>
          <div class="estilos">
            {#each ESTILOS as e (e.valor)}
              <button type="button" class="estilo" aria-pressed={!cargando && s.estilo === e.valor} disabled={cargando} onclick={() => elegir('estilo', e.valor)}>
                <span class="estilo-muestra">
                  {#if cargando}
                    <Esqueleto proporcion="1.586 / 1" redondo="12px" />
                  {:else}
                    <TarjetaLealtad estilo={e.valor} {color} forma={s.forma} {meta} {saldo} premioListo={false} t={textos} />
                  {/if}
                </span>
                <span class="estilo-pie"><b>{e.nombre}</b><span>{e.sub}</span></span>
                <span class="check"><Icono nombre="check" tamano={13} /></span>
              </button>
            {/each}
          </div>
          <p class="pista">Tus clientes la voltean con un toque: atrás va su QR, en el mismo estilo.</p>
        </div>
      </Fila>

      <Fila clave="color" icono="contraste" titulo="Color" nota="Aparte del color de tu menú." {cargando}>
        <div class="grupo">
          <span class="etiqueta">COLOR DE TU TARJETA</span>
          <div class="control">
            {#if cargando}
              <span class="crece"><Esqueleto ancho="100%" alto="40px" redondo="12px" /></span>
              <Esqueleto ancho="110px" alto="40px" redondo="12px" />
            {:else}
              <div class="muestra">
                <span class="gota" style:background={color}></span>
                {#if s.color}<span class="mono">{s.color}</span>{:else}<span class="sin">Del color de tu menú</span>{/if}
              </div>
              <Boton etiqueta={s.color ? 'Cambiar' : 'Elegir color'} onclick={() => (colorAbierto = true)} />
              {#if s.color}<BotonCuadro icono="cerrar" ayuda="Usar el de tu menú" grande onclick={() => elegir('color', null)} />{/if}
            {/if}
          </div>
          <div class="rapidos" role="group" aria-label="Colores rápidos">
            {#each COLORES_RAPIDOS as c (c.color)}
              <button
                type="button"
                class="rapido"
                style:--c={c.color}
                aria-pressed={!cargando && s.color === c.color}
                aria-label={c.nombre}
                disabled={cargando}
                onclick={() => elegir('color', c.color)}
              ></button>
            {/each}
          </div>
          <p class="pista">Si no lo eliges, va del color de tu menú. Las letras se ponen blancas o negras solas, para que se lean.</p>
        </div>
      </Fila>
    {/if}
  </div>

  {#if !errorLectura}
    <Telefono
      bind:this={telefono}
      slug={sucursal.slug}
      restauranteId={sucursal.id}
      muestra={{ tema: 'claro', color: null }}
      modo="menu"
      leido={!!guardado}
      como="tarjeta"
      tarjeta={reglaTelefono}
    />
  {/if}
</main>

<BarraGuardar {cambios} {paso} cargando={cargando || !!errorLectura} error={errorGuardar} alGuardar={guardar} alDescartar={descartar} />

{#if colorAbierto}
  <VentanaColor
    clave="color"
    colores={{ tema: 'claro', color: s.color, colorBarra: null, fondo: null }}
    textos={{
      titulo: 'Color de tu tarjeta',
      nota: 'Pinta el fondo de tu tarjeta, aparte de tu menú.',
      quitar: 'Usar el de tu menú',
      usar: 'Usar este color',
    }}
    inicial={color}
    alUsar={(c) => {
      elegir('color', c);
      colorAbierto = false;
    }}
    alCerrar={() => (colorAbierto = false)}
  >
    {#snippet prueba(hex: string)}
      <div class="color-prueba">
        <TarjetaLealtad estilo={s.estilo} color={hex} forma={s.forma} {meta} {saldo} premioListo={false} t={textos} />
      </div>
    {/snippet}
  </VentanaColor>
{/if}

{#if salida}
  <VentanaSalir
    {cambios}
    alSalir={() => {
      const ir = salida;
      salida = null;
      if (guardado) s = { ...guardado };
      ir?.();
    }}
    alGuardar={guardar}
    alCerrar={() => (salida = null)}
  />
{/if}

<style>
  /* Como «Tu menú en línea»: entre la barra de arriba (56) y la de guardar (64), las tarjetas a la izquierda y el
     teléfono a la derecha. */
  .cuerpo {
    position: absolute;
    left: 0;
    right: 0;
    top: 56px;
    bottom: 64px;
    overflow-y: auto;
    scrollbar-gutter: stable;
    padding: 20px 14px 28px 24px;
    display: grid;
    grid-template-columns: minmax(0, 1fr) 418px;
    align-items: start;
    gap: 0 24px;
  }

  :global(:root[data-estilo='cristal']) .cuerpo {
    bottom: 0;
    padding-bottom: 92px;
  }

  .col {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  .cabeza {
    padding: 2px 4px 0;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .nota {
    margin: 0;
    font-size: 12.5px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .grupo {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .pista {
    margin: 0;
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--tenue);
  }

  .cambia {
    display: flex;
    align-items: flex-start;
    gap: 8px;
    margin: 12px 0 0;
    padding: 10px 12px;
    border-radius: 10px;
    font-size: 13px;
    line-height: 1.45;
    background: rgba(245, 166, 35, 0.13);
    color: #8a5a10;
  }

  :global(:root[data-tema='oscuro']) .cambia {
    color: #f5c26b;
  }

  .cambia :global(svg) {
    flex: none;
    margin-top: 2px;
  }

  /* Los estilos, en cuadros como los de Crear anuncios: lo elegido con el aro azul y su palomita. */
  .estilos {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 12px;
  }

  .estilo {
    position: relative;
    isolation: isolate;
    display: flex;
    flex-direction: column;
    gap: 10px;
    padding: 12px;
    border: 1px solid var(--borde-tarjeta);
    border-radius: 14px;
    background: var(--solido);
    color: var(--texto);
    font: inherit;
    text-align: left;
    cursor: pointer;
    transition:
      box-shadow 160ms ease,
      transform 160ms ease;
  }

  .estilo:not(:disabled):hover {
    background: color-mix(in srgb, var(--chip) 45%, var(--solido));
  }

  .estilo:not(:disabled):active {
    transform: scale(0.985);
  }

  .estilo[aria-pressed='true'] {
    box-shadow: 0 0 0 2px var(--campo-aro);
    border-color: transparent;
  }

  .check {
    position: absolute;
    top: 18px;
    right: 18px;
    z-index: 2;
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

  .estilo[aria-pressed='true'] .check {
    transform: scale(1);
  }

  .estilo-muestra {
    display: block;
    pointer-events: none;
  }

  /* La tarjeta chica de cada estilo (maqueta, .tl-estilo-muestra). */
  .estilo-muestra :global(.tl-cara) {
    border-radius: 12px;
  }

  .estilo-muestra :global(.tl-frente) {
    padding: 10px 12px 9px;
  }

  .estilo-muestra :global(.tl-sello) {
    width: 20px;
    height: 20px;
  }

  .estilo-muestra :global(.tl-sello svg) {
    width: 11px;
    height: 11px;
  }

  .estilo-muestra :global(.tl-sellos) {
    gap: 4px 0;
  }

  .estilo-muestra :global(.tl-etq) {
    font-size: 7.5px;
  }

  .estilo-muestra :global(.tl-arriba) {
    min-height: 14px;
  }

  .estilo-muestra :global(.tl-abajo b) {
    font-size: 11px;
  }

  .estilo-muestra :global(.tl-abajo span) {
    font-size: 9px;
  }

  .estilo-muestra :global(.tl-puntos-n b) {
    font-size: 28px;
  }

  .estilo-muestra :global(.tl-puntos-n span) {
    font-size: 10px;
  }

  .estilo-muestra :global(.tl-barra) {
    height: 6px;
  }

  .estilo-pie {
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: 0 2px;
  }

  .estilo-pie b {
    font-size: 13.5px;
    font-weight: 700;
  }

  .estilo-pie span {
    font-size: 12px;
    color: var(--suave);
  }

  /* El color, como el de «Tu menú en línea». */
  .control {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .crece {
    flex: 1;
    min-width: 0;
    display: flex;
  }

  .muestra {
    flex: 1;
    min-width: 0;
    height: 40px;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 12px;
    border: 1px solid var(--linea);
    border-radius: 12px;
  }

  .gota {
    width: 20px;
    height: 20px;
    flex: none;
    border-radius: 6px;
    border: 1px solid var(--linea-fuerte);
  }

  .muestra .mono {
    font-size: 13px;
  }

  .sin {
    font-size: 13px;
    color: var(--suave);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  /* Los colores rápidos: cuadritos (en el panel nada es círculo), el elegido con el aro azul. */
  .rapidos {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    margin-top: 10px;
  }

  .rapido {
    width: 32px;
    height: 32px;
    padding: 0;
    border: 0;
    border-radius: 8px;
    background: var(--c);
    cursor: pointer;
    box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.12);
    transition:
      transform 160ms cubic-bezier(0.175, 0.885, 0.32, 1.275),
      box-shadow 160ms ease;
  }

  .rapido:not(:disabled):hover {
    transform: scale(1.08);
  }

  .rapido[aria-pressed='true'] {
    box-shadow:
      0 0 0 2px var(--solido),
      0 0 0 4px var(--campo-aro);
  }

  /* La tarjeta en vivo dentro de la ventana del color (donde «Tu menú en línea» enseña la barra del menú). */
  .color-prueba {
    width: 300px;
    margin: 18px auto 4px;
  }

  @media (prefers-reduced-motion: reduce) {
    .estilo,
    .rapido,
    .check {
      transition: none;
    }
  }
</style>
