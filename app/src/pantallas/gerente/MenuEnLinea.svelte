<!--
  «Tu menú en línea», que abre el cuadro «Menú digital» de Inicio (maqueta de la 6a
  Qx4C5CbKJYpeAsJCfw4ghn, sección 3; libreta 6, decidido el 20 de octubre de 2026): el link para su
  Instagram y su WhatsApp con «Copiar» y «Ver», el QR de las mesas, los carteles, cómo se ve (el
  tema, el color, a cuánto toma el dólar y, con la 6b, «Hago envíos») y, a la derecha, su menú de verdad como lo ven sus
  clientes, con lo que todavía no guarda. Los productos salen de Mi menú, y el logo y el horario de
  Tu restaurante. El chip de arriba dice si está abierto y cuántos productos están a la vista,
  contados por Postgres igual que el menú.

  Con la 6c (maqueta 2UPwZw31WrcYRZkH8jaT1Y, sección 3), si el asistente del menú no contesta, un
  aviso abajo de la descripción dice por qué y a quién pedírselo (encuesta 18 de
  planes/trabajo/6c/lista-6c.md).
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import BarraArriba from '../../diseno/BarraArriba.svelte';
  import Boton from '../../diseno/Boton.svelte';
  import BotonCuadro from '../../diseno/BotonCuadro.svelte';
  import CajaError from '../../diseno/CajaError.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import Interruptor from '../../diseno/Interruptor.svelte';
  import Selector from '../../diseno/Selector.svelte';
  import Vidrio from '../../diseno/Vidrio.svelte';
  import { casiNoSeVe, type TemaMenu } from '../../lib/color';
  import { ALGO_SALIO_PANEL, esDeRed, Fallo, SIN_CONEXION } from '../../lib/errores';
  import { diaYMes } from '../../lib/formato';
  import type { Sucursal } from '../../lib/gerente';
  import { leerEnvios, type Envio } from '../../lib/pedidos.svelte';
  import {
    guardarMenuEnLinea,
    leerCarteles,
    leerEstadoMenu,
    leerRestaurante,
    type Cartel,
    type EstadoMenu,
    type Restaurante,
  } from '../../lib/restaurante';
  import { supabase } from '../../lib/supabase';
  import { HOST_MENU, linkDelMenu } from '../../lib/vistaMenu';
  import CajaSucursales from './CajaSucursales.svelte';
  import Carteles from './menuEnLinea/Carteles.svelte';
  import Muestra from './menuEnLinea/Muestra.svelte';
  import QrMenu, { descargarQr } from './menuEnLinea/QrMenu.svelte';
  import VentanaColor from './menuEnLinea/VentanaColor.svelte';

  let {
    sucursal,
    sucursales,
    alElegir,
    alVolver,
  }: { sucursal: Sucursal; sucursales: Sucursal[]; alElegir: (s: Sucursal) => void; alVolver: () => void } = $props();

  const TEMAS: { valor: TemaMenu; texto: string; icono: string }[] = [
    { valor: 'claro', texto: 'Claro', icono: 'sol' },
    { valor: 'oscuro', texto: 'Oscuro', icono: 'luna' },
  ];

  let guardado = $state<Restaurante | null>(null);
  let carteles = $state<Cartel[]>([]);
  let estado = $state<EstadoMenu | null>(null);
  let errorLectura = $state<string | null>(null);

  let tema = $state<TemaMenu>('claro');
  let color = $state<string | null>(null);
  let cambio = $state('');
  let envios = $state(false);
  let productosEnvio = $state<Envio[] | null>(null);
  let eligiendoColor = $state(false);
  let copiado = $state(false);
  let paso = $state<null | 'guardando' | 'listo'>(null);
  let error = $state<string | null>(null);
  let muestra = $state<ReturnType<typeof Muestra>>();

  // svelte-ignore state_referenced_locally
  const link = linkDelMenu(sucursal.slug);

  function textoCambio(n: number | null) {
    return n === null ? '' : n.toFixed(2);
  }

  // El tipo de cambio escrito: vacío = sin dólares; si no es un número mayor que cero, no sirve.
  function leerCambio(texto: string): number | null | undefined {
    const t = texto.trim().replace(/,/g, '');
    if (!t) return null;
    if (!/^(\d+\.?\d*|\.\d+)$/.test(t)) return undefined;
    const n = Math.round(Number(t) * 100) / 100;
    return n > 0 && n < 1000000 ? n : undefined;
  }

  const cambioLeido = $derived(leerCambio(cambio));
  const sinGuardar = $derived(
    !!guardado &&
      (tema !== guardado.menu_tema ||
        color !== guardado.menu_color ||
        cambioLeido !== guardado.tipo_cambio_usd ||
        envios !== guardado.hace_envios),
  );
  const casi = $derived(casiNoSeVe(color, tema));

  async function leer() {
    try {
      const [r, c, e, pe] = await Promise.all([
        leerRestaurante(sucursal.id),
        leerCarteles(sucursal.id),
        leerEstadoMenu(sucursal.id),
        leerEnvios(supabase, sucursal.id),
      ]);
      guardado = r;
      carteles = c;
      estado = e;
      productosEnvio = pe;
      tema = r.menu_tema;
      color = r.menu_color;
      cambio = textoCambio(r.tipo_cambio_usd);
      envios = r.hace_envios;
      errorLectura = null;
    } catch (falla) {
      console.error('[menu en linea] no se pudo leer:', falla);
      errorLectura = esDeRed(falla) ? SIN_CONEXION : 'No se pudo leer tu menú en línea. Intenta de nuevo en un momento.';
    }
  }

  onMount(leer);

  // Después de cambiar un cartel: la lista, el chip y la vista previa.
  async function alCambiarCarteles() {
    try {
      carteles = await leerCarteles(sucursal.id);
    } catch (falla) {
      console.error('[menu en linea] no se pudieron volver a leer los carteles:', falla);
    }
    muestra?.recargar();
  }

  async function copiar() {
    try {
      await navigator.clipboard.writeText(link);
    } catch (falla) {
      console.error('[menu en linea] no se pudo copiar el link:', falla);
      error = 'No se pudo copiar. Selecciona el link y cópialo a mano.';
      return;
    }
    copiado = true;
    setTimeout(() => (copiado = false), 1600);
  }

  async function bajarQr() {
    try {
      await descargarQr(link, `qr-menu-${sucursal.slug}.png`);
    } catch (falla) {
      console.error('[menu en linea] no se pudo hacer el PNG del QR:', falla);
      error = 'No se pudo descargar el QR. Intenta de nuevo.';
    }
  }

  async function guardar() {
    if (!guardado || paso) return;
    if (cambioLeido === undefined) {
      error = 'Escribe a cuánto tomas el dólar, como 18.50';
      return;
    }
    error = null;
    paso = 'guardando';
    try {
      await guardarMenuEnLinea(sucursal.id, tema, color, cambioLeido, envios);
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[menu en linea] no se pudo guardar:', falla);
      error = falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL;
      paso = null;
      return;
    }
    guardado = { ...guardado, menu_tema: tema, menu_color: color, tipo_cambio_usd: cambioLeido, hace_envios: envios };
    cambio = textoCambio(cambioLeido);
    paso = 'listo';
    setTimeout(() => (paso = null), 1600);
  }

  // Los envíos de Mi menú como los elige quien confirma: «Envío $30 o Envío lejos $50».
  const precioCorto = (n: number) => `$${Number.isInteger(n) ? n : n.toFixed(2)}`;
  const listaEnvios = $derived(
    (productosEnvio ?? []).map((e) => `${e.nombre} ${precioCorto(e.precio)}`),
  );

  // «Abierto · 13 de 14 productos a la vista».
  const chip = $derived.by(() => {
    if (!estado) return { texto: errorLectura ? 'No se pudo leer' : 'Leyendo…', vivo: false };
    const abierto = estado.estado === null ? 'Sin horario' : estado.estado.abierto ? 'Abierto' : 'Cerrado';
    const vista = estado.productos ? `${estado.a_la_vista} de ${estado.productos} productos a la vista` : 'Todavía sin productos';
    return { texto: `${abierto} · ${vista}`, vivo: !!estado.estado?.abierto };
  });

  const avisoAsistente = $derived.by(() => {
    const a = estado?.asistente;
    if (!a || a.puede) return null;
    if (a.motivo === 'limite') {
      return `El asistente de tu menú llegó a su límite de este mes. Vuelve el ${diaYMes(a.vuelve)} o ${
        a.con_distribuidor ? 'pídele a tu distribuidor que lo suba' : 'escríbele a Fragmentless para que lo suba'
      }.`;
    }
    return `El asistente de tu menú todavía no está activo. ${
      a.con_distribuidor ? 'Pídele a tu distribuidor que lo active' : 'Escríbele a Fragmentless para que lo active'
    }.`;
  });
</script>

<BarraArriba titulo="Tu menú en línea" estado={chip}>
  {#snippet antes()}
    <BotonCuadro icono="regresar" ayuda="Volver a Inicio" grande tamanoIcono={18} onclick={alVolver} />
  {/snippet}
  <CajaSucursales {sucursales} actual={sucursal} {alElegir} />
</BarraArriba>

<main class="cuerpo">
  <Vidrio como="section" class="menu-en-linea" radio={26} aria-label="Tu menú en línea">
    <div class="cabeza">
      <span class="etiqueta">TU MENÚ EN LÍNEA</span>
      <p class="nota">
        Tu link para Instagram y WhatsApp, el QR de tus mesas, tus carteles y cómo se ve tu menú. Los productos salen
        de Mi menú, y tu logo y tu horario de Tu restaurante.
      </p>
      {#if avisoAsistente}
        <p class="aviso asistente"><Icono nombre="info" tamano={16} /><span>{avisoAsistente}</span></p>
      {/if}
    </div>

    {#if errorLectura}
      <CajaError mensaje={errorLectura} />
    {:else}
      <div class="fila">
        <div class="col-izq">
          <div class="tarjeta">
            <div class="encabezado">
              <span class="cuadro-icono"><Icono nombre="celular" tamano={18} /></span>
              <span class="titulos">
                <span class="titulo">Tu link y tu QR</span>
                <span class="nota">Ponlo en tu Instagram, tu WhatsApp y Google Maps.</span>
              </span>
            </div>
            <div class="raya chica"></div>
            <div class="link-caja"><span class="mono">{HOST_MENU}/<b>{sucursal.slug}</b></span></div>
            <div class="qr-fila">
              <QrMenu texto={link} />
              <div class="qr-texto">
                <div class="link-fila">
                  <Boton etiqueta={copiado ? 'Copiado' : 'Copiar'} icono="copiar" exito={copiado} onclick={copiar} />
                  <Boton etiqueta="Ver" icono="afuera" onclick={() => window.open(link, '_blank', 'noopener')} />
                </div>
                <p class="nota">Imprime el QR para tus mesas: al escanearlo se abre tu menú.</p>
                <button type="button" class="boton-chico" onclick={bajarQr}><Icono nombre="exportar" tamano={14} />Descargar QR</button>
              </div>
            </div>
          </div>

          <Carteles restauranteId={sucursal.id} {carteles} alCambiar={alCambiarCarteles} />
        </div>

        <div class="tarjeta como">
          <div class="encabezado">
            <span class="cuadro-icono"><Icono nombre="contraste" tamano={18} /></span>
            <span class="titulos">
              <span class="titulo">Cómo se ve</span>
              <span class="nota">Escoge lo que vaya con tu logo.</span>
            </span>
          </div>
          <div class="raya"></div>
          <span class="etiqueta">TEMA</span>
          <div class="selector">
            <Selector opciones={TEMAS} elegida={tema} alElegir={(t) => (tema = t)} etiqueta="Tema de tu menú" alto={38} lleno />
          </div>
          <div class="raya"></div>
          <span class="etiqueta">COLOR</span>
          <div class="color-fila">
            <div class="muestra-color">
              {#if color}
                <span class="gota" style:background={color}></span><span class="mono">{color}</span>
              {:else}
                <span class="gota" style:background={tema === 'claro' ? '#121212' : '#1f1f1f'}></span>
                <span class="sin">Sin color · barra {tema === 'claro' ? 'negra' : 'gris oscuro'}</span>
              {/if}
            </div>
            <Boton etiqueta={color ? 'Cambiar' : 'Elegir color'} onclick={() => (eligiendoColor = true)} />
            {#if color}
              <BotonCuadro icono="cerrar" ayuda="Quitar color" grande onclick={() => (color = null)} />
            {/if}
          </div>
          {#if casi}
            <p class="aviso">
              <Icono nombre="alerta" tamano={16} /><span
                ><b>Este color casi no se ve en tu menú {tema}.</b> Escoge uno más {tema === 'claro' ? 'oscuro' : 'claro'} o cambia el tema.</span
              >
            </p>
          {/if}
          <p class="pista arriba">Pinta la barra de arriba, la raya de la categoría, el «+» y los botones del pedido.</p>
          <div class="raya"></div>
          <label class="etiqueta" for="tipo-cambio">DÓLARES</label>
          <div class="dolar-fila">
            <div class="con-prefijo">
              <span>$</span>
              <input id="tipo-cambio" bind:value={cambio} inputmode="decimal" placeholder="Ej. 18.50" autocomplete="off" />
            </div>
            <span class="pista crece">A cuánto tomas el dólar. Así tus clientes ven «US$1.19 aprox.»; vacío, tu menú solo enseña pesos.</span>
          </div>
          <div class="raya"></div>
          <span class="etiqueta">PEDIDOS</span>
          <div class="envios-fila">
            <Interruptor prendido={envios} texto="Hago envíos" alCambiar={(v) => (envios = v)} />
            <span class="pista crece">
              {#if !envios}
                Tus clientes solo piden para llevar.
              {:else if !listaEnvios.length}
                Tus clientes también piden a domicilio. Para cobrar el envío, crea un producto en Mi menú y prende «Es un costo de
                envío».
              {:else}
                Tus clientes también piden a domicilio. Al confirmar, eliges el envío:
                {#each listaEnvios as e, i (i)}{i === 0 ? '' : i === listaEnvios.length - 1 ? ' o ' : ', '}<b>{e}</b>{/each}, de Mi menú.
              {/if}
            </span>
          </div>
          <span class="crece"></span>
          {#if error}<div class="error"><CajaError mensaje={error} /></div>{/if}
          <div class="guardar-fila">
            <p class="pista crece">Tus clientes lo ven así en cuanto guardas.</p>
            <Boton
              etiqueta={paso === 'guardando' ? 'Guardando…' : paso === 'listo' ? 'Guardado' : 'Guardar'}
              icono="guardar"
              tono="tinta"
              apagado={!sinGuardar && paso === null}
              cargando={paso === 'guardando'}
              exito={paso === 'listo'}
              onclick={guardar}
            />
          </div>
        </div>

        <div class="tarjeta vista">
          <span class="etiqueta">ASÍ LO VEN TUS CLIENTES</span>
          <div class="marco">
            <Muestra
              bind:this={muestra}
              slug={sucursal.slug}
              como="menu"
              muestra={{ tema, color, tipo_cambio_usd: cambioLeido ?? null }}
            />
          </div>
        </div>
      </div>
    {/if}
  </Vidrio>
</main>

{#if eligiendoColor && guardado}
  <VentanaColor
    inicial={color}
    {tema}
    slug={sucursal.slug}
    tipoCambio={cambioLeido ?? null}
    alUsar={(c) => {
      color = c;
      eligiendoColor = false;
    }}
    alCerrar={() => (eligiendoColor = false)}
  />
{/if}

<style>
  /* Debajo de la barra de arriba (16 + 60 + 16) y a la derecha de la lateral (16 + 244 + 16). */
  .cuerpo {
    position: absolute;
    left: 276px;
    right: 16px;
    top: 92px;
    bottom: 16px;
    display: flex;
    flex-direction: column;
  }

  :global(.menu-en-linea) {
    flex: 1;
    min-height: 0;
    padding: 20px;
    display: flex;
    flex-direction: column;
    gap: 16px;
  }

  .cabeza {
    padding: 4px 4px 0;
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

  .fila {
    flex: 1;
    min-height: 0;
    display: flex;
    gap: 16px;
  }

  .col-izq {
    flex: 1.1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 16px;
  }

  .tarjeta {
    min-width: 0;
    padding: 20px;
    display: flex;
    flex-direction: column;
    background: var(--solido);
    border: 1px solid var(--linea);
    border-radius: 18px;
  }

  .col-izq > .tarjeta {
    flex: none;
  }

  .como {
    flex: 1;
  }

  .vista {
    width: 300px;
    flex: none;
    align-items: center;
  }

  .vista .etiqueta {
    align-self: flex-start;
  }

  .marco {
    margin-top: 14px;
  }

  .encabezado {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .cuadro-icono {
    width: 36px;
    height: 36px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 11px;
    background: var(--chip);
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
  }

  .raya {
    height: 1px;
    margin: 18px 0;
    background: var(--linea);
    flex: none;
  }

  .raya.chica {
    margin: 14px 0;
  }

  .link-caja {
    display: flex;
    align-items: center;
    height: 44px;
    padding: 0 14px;
    border: 1px solid var(--linea);
    border-radius: 12px;
  }

  .link-caja .mono {
    flex: 1;
    min-width: 0;
    font-size: 13.5px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .link-caja b {
    font-weight: 600;
  }

  .qr-fila {
    margin-top: 14px;
    display: flex;
    gap: 16px;
    align-items: center;
  }

  .qr-texto {
    display: flex;
    flex-direction: column;
    gap: 10px;
    align-items: flex-start;
  }

  .link-fila {
    display: flex;
    gap: 10px;
    align-items: center;
  }

  .boton-chico {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 34px;
    padding: 0 12px;
    border-radius: 12px;
    border: 1px solid var(--linea);
    background: transparent;
    color: var(--texto);
    font-size: 12.5px;
    font-weight: 600;
    white-space: nowrap;
    transition: opacity 150ms;
  }

  .boton-chico:hover {
    opacity: 0.86;
  }

  .selector {
    margin-top: 8px;
  }

  .color-fila {
    margin-top: 8px;
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .muestra-color {
    flex: 1;
    min-width: 0;
    height: 44px;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 14px;
    border: 1px solid var(--linea);
    border-radius: 12px;
  }

  .gota {
    width: 20px;
    height: 20px;
    border-radius: 6px;
    border: 1px solid var(--linea-fuerte);
    flex: none;
  }

  .muestra-color .mono {
    font-size: 13px;
  }

  .sin {
    font-size: 13px;
    color: var(--suave);
  }

  .aviso {
    display: flex;
    align-items: flex-start;
    gap: 10px;
    margin: 12px 0 0;
    padding: 11px 14px;
    border-radius: 12px;
    background: var(--chip);
    font-size: 12.5px;
    line-height: 1.5;
    color: var(--suave);
  }

  .aviso.asistente {
    margin-top: 4px;
  }

  .aviso :global(svg) {
    flex: none;
    margin-top: 2px;
  }

  .aviso b {
    color: var(--texto);
    font-weight: 600;
  }

  .pista {
    margin: 0;
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--tenue);
  }

  .pista.arriba {
    margin-top: 8px;
  }

  .envios-fila {
    margin-top: 10px;
    display: flex;
    align-items: flex-start;
    gap: 14px;
  }

  .envios-fila :global(.interruptor) {
    margin-top: 1px;
  }

  .envios-fila b {
    color: var(--texto);
    font-weight: 600;
  }

  .dolar-fila {
    margin-top: 8px;
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .con-prefijo {
    position: relative;
    display: flex;
    width: 160px;
    flex: none;
  }

  .con-prefijo span {
    position: absolute;
    left: 14px;
    top: 0;
    height: 44px;
    display: flex;
    align-items: center;
    font-size: 13.5px;
    color: var(--suave);
    pointer-events: none;
  }

  .con-prefijo input {
    height: 44px;
    width: 100%;
    padding: 0 14px 0 28px;
    border: 1px solid var(--linea);
    border-radius: 12px;
    background: transparent;
    color: var(--texto);
    font-family: var(--mono);
    font-size: 13.5px;
    font-weight: 500;
    font-variant-numeric: tabular-nums;
    outline: none;
  }

  .con-prefijo input:focus {
    border-color: var(--suave);
  }

  .con-prefijo input::placeholder {
    color: var(--tenue);
  }

  .error {
    margin-top: 14px;
  }

  .guardar-fila {
    margin-top: 18px;
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .crece {
    flex-grow: 1;
  }

  @media (prefers-reduced-motion: reduce) {
    .boton-chico {
      transition: none;
    }
  }
</style>
