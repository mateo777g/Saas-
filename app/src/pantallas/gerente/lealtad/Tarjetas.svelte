<!--
  Tarjetas, la primera sección de «Tarjeta de lealtad» (maqueta v22, pantalla «Tarjeta de lealtad», SECCIÓN «Tarjetas»):
  · Con regla: su tarjeta («Tu regla y tu premio», con la muestra que se voltea en el estilo y el color guardados, la regla
    en tres renglones, «Editar tu regla» y el interruptor), la búsqueda con su filtro y la tabla de tarjetas en el marco de
    Mi menú: cliente, teléfono, lo juntado con su barrita, la última compra, cuándo la sacó, y «Premio listo» o «Pide otro
    celular» con «Confirmar». Apagada, la muestra en gris y por qué.
  · Sin regla: la muestra de lado, por qué sirve y «Poner tu regla» (verde).
  Mientras lee la primera vez, esqueletos del mismo tamaño. Buscar y filtrar es en memoria.
-->
<script lang="ts">
  import Boton from '../../../diseno/Boton.svelte';
  import CajaError from '../../../diseno/CajaError.svelte';
  import Esqueleto from '../../../diseno/Esqueleto.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import Interruptor from '../../../diseno/Interruptor.svelte';
  import NotaTabla from '../../../diseno/NotaTabla.svelte';
  import Tabla from '../../../diseno/Tabla.svelte';
  import TarjetaLealtad from '../../../diseno/TarjetaLealtad.svelte';
  import { anchos, filasDeLaUltimaVez, recordarFilas } from '../../../lib/esqueletos';
  import { dinero, plural } from '../../../lib/formato';
  import {
    colorDeTarjeta,
    conRegla,
    cuantos,
    diaDeTabla,
    MUESTRA_ATRAS,
    prenderLealtad,
    textosDeTarjeta,
    telefonoEscrito,
    type Lealtad,
    type TarjetaCliente,
    type Tarjetas,
  } from '../../../lib/lealtad';
  import type { Menu } from '../../../lib/menu';
  import { supabase } from '../../../lib/supabase';
  import Herramientas from '../inventario/Herramientas.svelte';
  import VentanaRegla from './VentanaRegla.svelte';

  let {
    restauranteId,
    restaurante,
    lealtad,
    tarjetas,
    menu,
    colorMenu,
    logo,
    errorLectura,
    errorTarjetas,
    alCambiar,
    alPasar,
  }: {
    restauranteId: string;
    restaurante: string;
    lealtad: Lealtad | null;
    tarjetas: Tarjetas | null;
    menu: Menu | null;
    colorMenu: string | null;
    logo: string | null;
    errorLectura: string | null;
    errorTarjetas: string | null;
    alCambiar: () => Promise<void>;
    alPasar: () => void;
  } = $props();

  let busqueda = $state('');
  let filtro = $state<'premio' | 'celular' | null>(null);
  let editando = $state(false);
  let prendiendo = $state(false);
  let errorPrender = $state<string | null>(null);

  // svelte-ignore state_referenced_locally
  const llaveFilas = `lealtad-tarjetas-${restauranteId}`;
  const filasEsqueleto = filasDeLaUltimaVez(llaveFilas);
  $effect(() => {
    if (tarjetas) recordarFilas(llaveFilas, tarjetas.tarjetas.length);
  });

  const regla = $derived(!!lealtad && conRegla(lealtad));
  const sellos = $derived(lealtad?.forma !== 'puntos');
  const premio = $derived(menu?.productos.find((p) => p.id === lealtad?.premio_producto_id) ?? null);
  const textos = $derived(lealtad ? textosDeTarjeta(lealtad.premio_tipo, premio?.nombre ?? null, lealtad.premio_pesos) : null);
  // La muestra: el 30 % de la meta (3 de 10 sellos, 30 de 100 puntos).
  const muestra = $derived(lealtad?.meta ? Math.round(lealtad.meta * 0.3) : 3);

  const lista = $derived(tarjetas?.tarjetas ?? []);
  const texto = $derived(busqueda.trim());
  const mostradas = $derived.by(() => {
    const q = texto.toLowerCase();
    const digitos = q.replace(/\D/g, '');
    return lista.filter(
      (t) =>
        (filtro === null || (filtro === 'premio' ? t.premio_listo : t.pide_celular)) &&
        (!q || t.nombre.toLowerCase().includes(q) || (digitos.length > 0 && t.telefono.includes(digitos))),
    );
  });
  const cargandoTabla = $derived(!tarjetas && !errorTarjetas);

  const ESQUELETO = ['110px', '92px', '130px', '84px', '100px'];
  const filas = $derived(anchos(ESQUELETO, filasEsqueleto));

  async function prender(v: boolean) {
    if (prendiendo) return;
    prendiendo = true;
    errorPrender = null;
    try {
      await prenderLealtad(supabase, restauranteId, v);
      await alCambiar();
    } catch (falla) {
      errorPrender = falla instanceof Error ? falla.message : 'No se pudo cambiar. Intenta de nuevo.';
    }
    prendiendo = false;
  }

  const barrita = (t: TarjetaCliente) => (lealtad?.meta ? Math.min(100, (Math.min(t.saldo, lealtad.meta) / lealtad.meta) * 100) : 0);
</script>

<main class="cuerpo">
  <section class="tl-seccion" aria-label="Tarjeta de lealtad">
    {#if errorLectura}
      <CajaError mensaje={errorLectura} />
    {:else if !lealtad || !textos}
      <!-- La primera lectura: la tarjeta de la regla en esqueleto, del mismo tamaño. -->
      <span class="solo-lector" role="status">Leyendo tu tarjeta de lealtad…</span>
      <div class="tarjeta-p quieta" aria-hidden="true">
        <div class="cabeza-p">
          <Esqueleto ancho="36px" alto="36px" redondo="11px" />
          <span class="titulos-p"><Esqueleto ancho="150px" alto="14px" /><Esqueleto ancho="300px" alto="11px" /></span>
        </div>
        <div class="regla-cuerpo">
          <Esqueleto ancho="300px" alto="190px" redondo="14px" />
          <div class="reglas-esq">
            {#each [0, 1, 2] as i (i)}<div><Esqueleto ancho="90px" alto="10px" /><Esqueleto ancho="{[300, 220, 260][i]}px" alto="13px" /></div>{/each}
            <Esqueleto ancho="140px" alto="42px" redondo="12px" />
          </div>
        </div>
      </div>
    {:else if !regla}
      <section class="tarjeta-p sin-regla" aria-label="Tu tarjeta de lealtad">
        <div class="sin-muestra">
          <TarjetaLealtad estilo={lealtad.estilo} color={colorDeTarjeta(lealtad.color, colorMenu)} forma={lealtad.forma} meta={sellos ? 10 : 100} saldo={sellos ? 3 : 30} premioListo={false} t={textos} />
        </div>
        <div class="sin-texto">
          <span class="etq-p">TARJETA DE LEALTAD</span>
          <h2>Que tus clientes regresen</h2>
          <p>
            Tus clientes sacan su tarjeta en tu menú con su nombre y su teléfono. Juntan sellos o puntos cada vez que pagan, aquí
            o en tu menú, y se ganan el premio que tú eliges. Nace apagada: la prendes cuando quieras.
          </p>
          <div class="botones-p"><Boton etiqueta="Poner tu regla" tono="verde" onclick={() => (editando = true)} /></div>
        </div>
      </section>
    {:else}
      <section class="tarjeta-p" class:apagada={!lealtad.prendida} aria-label="Tu regla">
        <div class="cabeza-p">
          <span class="cuadro-icono"><Icono nombre="r-lealtad" tamano={18} /></span>
          <span class="titulos-p">
            <span class="titulo-p">Tu regla y tu premio</span>
            <span class="sub-p">Así la ven tus clientes en tu menú, y así suma en la caja.</span>
          </span>
          <span class="crece"></span>
          <span class="prende">
            <span>{lealtad.prendida ? 'Prendida' : 'Apagada'}</span>
            <Interruptor
              prendido={lealtad.prendida}
              ayuda={lealtad.prendida ? 'Apagar tu tarjeta de lealtad' : 'Prender tu tarjeta de lealtad'}
              apagado={prendiendo}
              alCambiar={(v: boolean) => prender(v)}
            />
          </span>
        </div>
        {#if errorPrender}<div class="error-p"><CajaError mensaje={errorPrender} /></div>{/if}
        <div class="regla-cuerpo">
          <div class="muestra">
            <TarjetaLealtad
              estilo={lealtad.estilo}
              color={colorDeTarjeta(lealtad.color, colorMenu)}
              forma={lealtad.forma}
              meta={lealtad.meta ?? 10}
              saldo={muestra}
              premioListo={false}
              t={textos}
              atras={{ ...MUESTRA_ATRAS, restaurante, logo }}
            />
            <p class="pista-p"><Icono nombre="girar" tamano={14} />Tócala: atrás va su QR</p>
          </div>
          <div class="regla-der">
            <dl class="reglas">
              <div>
                <dt>Cómo se junta</dt>
                <dd>
                  {#if sellos}
                    {#if lealtad.minimo}Con sellos: cada cuenta pagada desde <b>{dinero(lealtad.minimo)}</b> es un sello{:else}Con sellos: cada cuenta pagada es un sello{/if}
                  {:else}
                    Con puntos: un punto por cada <b>{dinero(lealtad.pesos_por_punto ?? 0)}</b> pagados
                  {/if}
                </dd>
              </div>
              <div>
                <dt>El premio</dt>
                <dd>
                  Con <b>{cuantos(lealtad.forma, lealtad.meta ?? 0)}</b>,
                  {#if lealtad.premio_tipo === 'producto'}<b>{premio?.nombre ?? 'su producto'}</b> gratis{:else}<b>{dinero(lealtad.premio_pesos ?? 0)}</b> de descuento{/if}
                </dd>
              </div>
              <div>
                <dt>Cuánto dura</dt>
                <dd>Se borra sola a los 12 meses sin compras</dd>
              </div>
            </dl>
            {#if tarjetas?.aviso_premio}
              <p class="nota-ambar"><Icono nombre="alerta" tamano={15} /><span>{tarjetas.aviso_premio}</span></p>
            {/if}
            <div class="botones-p"><Boton etiqueta="Editar tu regla" icono="crear" onclick={() => (editando = true)} /></div>
            {#if !lealtad.prendida}
              <p class="nota-ambar">
                <Icono nombre="info" tamano={15} /><span
                  >Apagada, tu menú no la ofrece y la caja no suma ni canjea. {lista.length === 1
                    ? 'La tarjeta guarda lo que lleva.'
                    : lista.length
                      ? `Las ${lista.length.toLocaleString('en-US')} tarjetas guardan lo que llevan.`
                      : ''}</span
                >
              </p>
            {/if}
          </div>
        </div>
      </section>
    {/if}

    {#if !errorLectura && (!lealtad || regla)}
      <Herramientas
        bind:busqueda
        placeholder="Busca por nombre o teléfono…"
        cuenta={plural(mostradas.length, 'TARJETA', 'TARJETAS')}
        cargando={cargandoTabla}
        filtro={{
          titulo: 'TARJETAS',
          todas: { boton: 'Todas las tarjetas', nombre: 'Todas', icono: 'r-lealtad' },
          opciones: [
            { valor: 'premio', nombre: 'Premio listo', cuenta: lista.filter((t) => t.premio_listo).length, color: 'verde' },
            { valor: 'celular', nombre: 'Pide otro celular', cuenta: lista.filter((t) => t.pide_celular).length, color: 'amarillo' },
          ],
          total: lista.length,
          elegida: filtro,
          alElegir: (v) => (filtro = v as 'premio' | 'celular' | null),
        }}
      />

      <Tabla
        columnas="2fr 1.3fr 1.5fr 1.1fr 0.9fr 290px"
        relleno="0 16px"
        altoFila={64}
        marco
        encabezados={[
          { texto: 'Cliente' },
          { texto: 'Teléfono' },
          { texto: sellos ? 'Sellos' : 'Puntos' },
          { texto: 'Última compra' },
          { texto: 'La sacó' },
          { texto: '' },
        ]}
      >
        {#if cargandoTabla}
          <span class="solo-lector">Cargando tus tarjetas…</span>
          {#each filas as ancho, i (i)}
            <div class="fila quieta" aria-hidden="true">
              <span class="cliente"><Esqueleto ancho="34px" alto="34px" redondo="17px" /><Esqueleto {ancho} alto="11px" /></span>
              <span><Esqueleto ancho="92px" alto="11px" /></span>
              <span><Esqueleto ancho="110px" alto="11px" /></span>
              <span><Esqueleto ancho="60px" alto="11px" /></span>
              <span><Esqueleto ancho="44px" alto="11px" /></span>
              <span></span>
            </div>
          {/each}
        {:else if errorTarjetas}
          <NotaTabla relleno={48} angosta titulo="No se pudieron leer tus tarjetas." texto={errorTarjetas} />
        {:else if !lista.length}
          <NotaTabla
            relleno={48}
            angosta
            titulo="Todavía nadie saca su tarjeta."
            texto={lealtad?.prendida
              ? 'Tus clientes la sacan en tu menú, en la pestaña Tarjeta, con su nombre y su teléfono.'
              : 'Préndela arriba: tus clientes la sacan en tu menú con su nombre y su teléfono.'}
          />
        {:else if !mostradas.length}
          <NotaTabla
            relleno={48}
            angosta
            titulo={texto ? `No encontramos tarjetas para "${texto}".` : 'No hay tarjetas así.'}
            texto="Prueba con otro nombre o con Todas las tarjetas."
          />
        {:else}
          {#each mostradas as t (t.id)}
            {@const ultima = t.ultima_compra ? diaDeTabla(t.ultima_compra, tarjetas!.hoy) : null}
            <div class="fila">
              <span class="cliente"><span class="inicial">{t.nombre.charAt(0).toUpperCase()}</span><span class="nombre">{t.nombre}</span></span>
              <span class="mono">{telefonoEscrito(t.telefono)}</span>
              <span class="junta">
                <span class="mini-barra"><i style:width="{barrita(t)}%"></i></span>
                <span class="mono fuerte">{t.saldo.toLocaleString('en-US')} de {(lealtad?.meta ?? 0).toLocaleString('en-US')}</span>
              </span>
              <span class="tenue" class:gris={!ultima}>{ultima ?? 'Sin compras'}</span>
              <span class="tenue">{diaDeTabla(t.sacada, tarjetas!.hoy)}</span>
              <span class="estado">
                {#if t.pide_celular}
                  <span class="chip-t ambar"><Icono nombre="celular" tamano={13} />Pide otro celular</span>
                  <button type="button" class="confirmar-fila" onclick={alPasar}>Confirmar</button>
                {:else if t.premio_listo}
                  <span class="chip-t verde"><Icono nombre="regalo" tamano={13} />Premio listo</span>
                {/if}
              </span>
            </div>
          {/each}
        {/if}
      </Tabla>
    {/if}
  </section>
</main>

{#if editando && lealtad}
  <VentanaRegla
    {restauranteId}
    {lealtad}
    {menu}
    alGuardar={alCambiar}
    alCerrar={() => (editando = false)}
  />
{/if}

<style>
  /* El cuerpo de la vista se desliza entero: la tarjeta de la regla arriba y la tabla abajo (maqueta, .tl-cuerpo-p). */
  .cuerpo {
    position: absolute;
    left: var(--vista-izquierda);
    right: var(--vista-derecha);
    top: var(--vista-arriba);
    bottom: var(--vista-abajo);
    overflow-y: auto;
    scrollbar-width: thin;
  }

  .tl-seccion {
    display: flex;
    flex-direction: column;
    gap: 16px;
    padding-bottom: 8px;
  }

  .tarjeta-p {
    flex: none;
    background: var(--solido);
    border: 1px solid var(--borde-tarjeta);
    border-radius: 14px;
    padding: 18px 20px 20px;
  }

  .cabeza-p {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .cuadro-icono {
    width: 36px;
    height: 36px;
    flex: none;
    display: grid;
    place-items: center;
    border-radius: 11px;
    background: var(--chip);
    color: var(--texto);
  }

  .titulos-p {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .tarjeta-p.quieta .titulos-p {
    gap: 6px;
  }

  .titulo-p {
    font-size: 15px;
    font-weight: 700;
    color: var(--texto);
  }

  .sub-p {
    font-size: 12.5px;
    color: var(--suave);
  }

  .crece {
    flex: 1;
  }

  .prende {
    display: inline-flex;
    align-items: center;
    gap: 10px;
    font-size: 13px;
    font-weight: 600;
    color: var(--texto);
  }

  .error-p {
    margin-top: 14px;
  }

  .regla-cuerpo {
    display: grid;
    grid-template-columns: 300px 1fr;
    gap: 32px;
    align-items: center;
    margin-top: 18px;
  }

  .muestra {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 8px;
  }

  .muestra :global(.tl-tarjeta) {
    width: 300px;
  }

  .apagada .muestra :global(.tl-tarjeta) {
    filter: grayscale(0.85);
    opacity: 0.7;
  }

  .pista-p {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    margin: 0;
    font-size: 12px;
    color: var(--tenue);
  }

  .reglas {
    display: flex;
    flex-direction: column;
    margin: 0;
  }

  .reglas > div {
    display: grid;
    grid-template-columns: 150px 1fr;
    align-items: baseline;
    padding: 12px 0;
    border-bottom: 1px solid var(--linea);
  }

  .reglas > div:first-child {
    padding-top: 0;
  }

  .reglas dt {
    font: 600 10.5px var(--mono);
    letter-spacing: 0.1em;
    text-transform: uppercase;
    color: var(--tenue);
  }

  .reglas dd {
    margin: 0;
    font-size: 14px;
    color: var(--texto);
  }

  .reglas b {
    font-weight: 700;
  }

  .reglas-esq {
    display: flex;
    flex-direction: column;
    gap: 22px;
  }

  .reglas-esq > div {
    display: flex;
    gap: 60px;
    align-items: center;
  }

  .botones-p {
    display: flex;
    gap: 10px;
    margin-top: 16px;
  }

  .nota-ambar {
    display: flex;
    align-items: flex-start;
    gap: 8px;
    margin: 14px 0 0;
    padding: 10px 12px;
    border-radius: 10px;
    font-size: 13px;
    line-height: 1.45;
    background: rgba(245, 166, 35, 0.13);
    color: #8a5a10;
  }

  :global(:root[data-tema='oscuro']) .nota-ambar {
    color: #f5c26b;
  }

  .nota-ambar :global(svg) {
    flex: none;
    margin-top: 2px;
  }

  /* Sin regla: la muestra de lado y por qué sirve, con su botón verde. */
  .sin-regla {
    display: grid;
    grid-template-columns: 330px 1fr;
    gap: 44px;
    align-items: center;
    margin-top: 56px;
    padding: 40px 44px;
  }

  .sin-muestra :global(.tl-tarjeta) {
    width: 330px;
    transform: rotate(-4deg);
  }

  .etq-p {
    font: 600 10.5px var(--mono);
    letter-spacing: 0.12em;
    color: var(--tenue);
  }

  .sin-texto h2 {
    margin: 8px 0 10px;
    font-size: 26px;
    font-weight: 800;
    letter-spacing: -0.02em;
    color: var(--texto);
  }

  .sin-texto p {
    max-width: 540px;
    margin: 0;
    font-size: 14.5px;
    line-height: 1.6;
    color: var(--suave);
  }

  .sin-texto .botones-p {
    margin-top: 22px;
  }

  /* La tabla. */
  .fila > :global(*) {
    min-width: 0;
  }

  .cliente {
    min-width: 0;
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .nombre {
    font-size: 13.5px;
    font-weight: 700;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .inicial {
    width: 34px;
    height: 34px;
    flex: none;
    display: grid;
    place-items: center;
    border-radius: 50%;
    background: var(--chip);
    color: var(--texto);
    font-size: 13px;
    font-weight: 700;
  }

  .mono {
    font-family: var(--mono);
    font-size: 12.5px;
    color: var(--suave);
  }

  .mono.fuerte {
    color: var(--texto);
    white-space: nowrap;
  }

  .junta {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .mini-barra {
    width: 56px;
    height: 6px;
    flex: none;
    border-radius: 3px;
    background: var(--chip);
    overflow: hidden;
  }

  .mini-barra i {
    display: block;
    height: 100%;
    border-radius: inherit;
    background: var(--grafica, #1355e8);
  }

  .tenue {
    font-size: 13px;
    color: var(--suave);
  }

  .tenue.gris {
    color: var(--tenue);
  }

  .estado {
    display: flex;
    align-items: center;
    justify-content: flex-end;
    gap: 8px;
  }

  .chip-t {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 26px;
    padding: 0 10px;
    border-radius: 999px;
    font-size: 12px;
    font-weight: 600;
    white-space: nowrap;
  }

  .chip-t.verde {
    background: color-mix(in srgb, var(--verde) 14%, transparent);
    color: var(--verde);
  }

  .chip-t.ambar {
    background: rgba(245, 166, 35, 0.15);
    color: #9a6411;
  }

  :global(:root[data-tema='oscuro']) .chip-t.ambar {
    color: #f5c26b;
  }

  .confirmar-fila {
    height: 30px;
    padding: 0 12px;
    border: 1px solid var(--borde-tarjeta);
    border-radius: 10px;
    background: var(--solido);
    color: var(--texto);
    font: 600 12.5px var(--jakarta);
    cursor: pointer;
    transition: background-color 0.15s;
  }

  .confirmar-fila:hover {
    background: var(--chip);
  }
</style>
