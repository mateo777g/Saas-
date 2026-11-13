<!--
  Ajustes, en cajitas que se abren (12 de noviembre de 2026; maqueta FiHkjmT1meyTu7zuU3En2n, «Vista: Ajustes», aprobada
  en su versión 36; decisiones en planes/trabajo/estilo-cristal/ajustes.md y libreta 4, «Ajustes, en cajitas que se
  abren»). Una columna al centro, como Inicio: «TUS AJUSTES» con su nota y una cajita por tema, que llegan cerradas;
  cada cabecera dice cómo está. Las que vengan se agregan abajo. La usan los tres paneles: Fragmentless y los
  distribuidores tienen solo Interfaz; el gerente, también Mercado Pago, que es de la sucursal.

  · Interfaz: el tema (el botón del sol que se vuelve luna) y el estilo, Simple o Cristal. Los dos se guardan en este
    navegador (lib/tema.ts, lib/estilo.ts) y cambian todo el panel al momento. A la derecha, la ventanita de muestra,
    como la de «Modo de color» de la app de Claude (el developer, 12 nov 2026, noche; antes era el Inicio a un tercio):
    una ventana chiquita con dos rayitas y un punto del acento, en el tema que se tiene. En Simple es lisa; en Cristal
    es de vidrio, y detrás va el fondo de Cristal con una sola mancha al centro, para que se vea el vidrio.
  · Mercado Pago: sin conectar, conectado (la cuenta y desde cuándo) o «Se desconectó». La conexión de verdad la hace
    la sesión de la terminal (lib/mercadoPago.ts); hasta entonces cada sucursal sale «Sin conectar» (el developer, 12 nov
    2026: «que se vea ya»). Desde la franja de Inicio, llega abierta (`abrirMercadoPago`).

  La hora de corte ya no va aquí: se fue a Cortes y reportes (encuesta del 12 nov 2026).
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import Boton from '../../diseno/Boton.svelte';
  import BotonTema from '../../diseno/BotonTema.svelte';
  import CajaError from '../../diseno/CajaError.svelte';
  import Cajita from '../../diseno/Cajita.svelte';
  import Esqueleto from '../../diseno/Esqueleto.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import { esDeRed, SIN_CONEXION } from '../../lib/errores';
  import { cambiarEstilo, estiloActual, type Estilo } from '../../lib/estilo';
  import type { Sucursal } from '../../lib/gerente';
  import { leerMercadoPago, SE_PUEDE_CONECTAR, type EstadoMercadoPago } from '../../lib/mercadoPago';
  import { vidrio } from '../../diseno/vidrio';
  import { cambiarTema, temaActual } from '../../lib/tema';

  let {
    sucursal,
    abrirMercadoPago = false,
  }: {
    sucursal?: Sucursal;
    abrirMercadoPago?: boolean;
  } = $props();

  let tema = $state(temaActual());
  let estilo = $state(estiloActual());
  let interfaz = $state(false);
  // svelte-ignore state_referenced_locally
  let mercadoPago = $state(abrirMercadoPago);
  let caja = $state<HTMLElement | null>(null);

  const NOMBRE: Record<Estilo, string> = { simple: 'Simple', cristal: 'Cristal' };
  const PISTA: Record<Estilo, string> = {
    simple: 'Liso, como siempre. Solo cambia cómo se ve: todo sigue en su lugar.',
    cristal: 'De vidrio, con una luz que sigue al mouse. Solo cambia cómo se ve: todo sigue en su lugar.',
  };

  function alternarTema() {
    tema = tema === 'claro' ? 'oscuro' : 'claro';
    cambiarTema(tema);
  }

  function elegirEstilo(nuevo: Estilo) {
    if (nuevo === estilo) return;
    estilo = nuevo;
    cambiarEstilo(nuevo);
  }

  // ─── Mercado Pago (solo con sucursal) ───
  let estadoMp = $state<EstadoMercadoPago | null>(null);
  let errorMp = $state<string | null>(null);

  onMount(() => {
    // Desde la franja de Inicio: que se vea la cajita de Mercado Pago.
    if (abrirMercadoPago && caja) {
      const quieto = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
      setTimeout(() => caja?.scrollIntoView({ block: 'nearest', behavior: quieto ? 'auto' : 'smooth' }), 60);
    }
    if (!sucursal) return;
    leerMercadoPago(sucursal.id)
      .then((e) => (estadoMp = e))
      .catch((falla) => {
        console.error('[ajustes] no se pudo leer la conexión con Mercado Pago:', falla);
        errorMp = esDeRed(falla) ? SIN_CONEXION : 'No se pudo leer tu conexión con Mercado Pago. Intenta de nuevo en un momento.';
      });
  });

  function conectar() {
    // Todavía no hay a dónde llevar: lo conecta la sesión de la terminal (lib/mercadoPago.ts).
    if (!SE_PUEDE_CONECTAR) return;
  }

  // «12 de noviembre de 2026» y «12 de noviembre a las 14:32», de lo que diga la base.
  const MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
  function diaLargo(iso: string, conAno: boolean) {
    const [a, m, d] = iso.slice(0, 10).split('-').map(Number);
    return `${d} de ${MESES[m - 1]}${conAno ? ` de ${a}` : ''}`;
  }
</script>

<div class="desliza">
  <div class="ajustes">
    <div class="cabeza">
      <span class="etiqueta">TUS AJUSTES</span>
      <p class="nota">
        {sucursal ? 'Cómo se ve tu panel en esta compu y lo que conectas a esta sucursal.' : 'Cómo se ve tu panel en esta compu.'}
      </p>
    </div>

    <Cajita icono="contraste" titulo="Interfaz" nota="Cómo se ve tu panel en este navegador." bind:abierta={interfaz}>
      {#snippet resumen()}{tema === 'claro' ? 'Claro' : 'Oscuro'} · {NOMBRE[estilo]}{/snippet}
      <div class="interfaz">
        <div class="izquierda">
          <div class="grupo">
            <span class="etiqueta">TEMA</span>
            <div class="control">
              <BotonTema {tema} ayuda={tema === 'claro' ? 'Cambiar tu panel a oscuro' : 'Cambiar tu panel a claro'} alCambiar={alternarTema} />
              <span class="tema-texto">Tu panel va en {tema}</span>
            </div>
            <p class="pista">Se guarda en este navegador y se ve al momento en todo el panel.</p>
          </div>
          <div class="grupo">
            <span class="etiqueta">ESTILO</span>
            <div class="formas" role="group" aria-label="Estilo">
              {#each ['simple', 'cristal'] as const as e (e)}
                <button type="button" class="forma" aria-pressed={estilo === e} onclick={() => elegirEstilo(e)}>{NOMBRE[e]}</button>
              {/each}
            </div>
            <p class="pista">{PISTA[estilo]}</p>
          </div>
        </div>
        <figure class="muestra">
          <div class="muestra-fondo" aria-hidden="true">
            <!-- En Cristal, la ventanita es una hoja de vidrio (su receta en cristal.css). -->
            <div class="muestra-ventana" use:vidrio={'hoja'}>
              <span class="rayita"></span>
              <span class="rayita corta"></span>
              <span class="punto-acento"></span>
            </div>
          </div>
          <figcaption class="pista">Así se ve tu panel en {NOMBRE[estilo]} {tema}.</figcaption>
        </figure>
      </div>
    </Cajita>

    {#if sucursal}
      <div class="caja-mp" bind:this={caja}>
        <Cajita icono="tarjeta" titulo="Mercado Pago" nota="De esta sucursal: {sucursal.nombre}." bind:abierta={mercadoPago}>
          {#snippet resumen()}
            {#if errorMp}
              <span class="estado"><span class="punto"></span>No se pudo leer</span>
            {:else if !estadoMp}
              <Esqueleto ancho="96px" alto="12px" />
            {:else if estadoMp.estado === 'conectado'}
              <span class="estado"><span class="punto verde"></span>Conectado</span>
            {:else if estadoMp.estado === 'desconectado'}
              <span class="estado ambar"><span class="punto ambar"></span>Se desconectó</span>
            {:else}
              <span class="estado"><span class="punto"></span>Sin conectar</span>
            {/if}
          {/snippet}
          <div class="mp">
            {#if errorMp}
              <CajaError mensaje={errorMp} />
            {:else if !estadoMp}
              <span class="solo-lector">Cargando tu conexión con Mercado Pago…</span>
              <div class="mp-cargando" aria-hidden="true">
                <Esqueleto ancho="92%" alto="10px" />
                <Esqueleto ancho="64%" alto="10px" />
                <span class="mp-esqueleto-boton"><Esqueleto ancho="190px" alto="40px" redondo="12px" /></span>
              </div>
            {:else if estadoMp.estado === 'conectado'}
              <div class="cuenta">
                <span class="cuenta-icono"><Icono nombre="check" tamano={18} /></span>
                <span class="cuenta-texto">
                  <b>Conectado a {estadoMp.cuenta}</b>
                  <span>La cuenta de Mercado Pago de esta sucursal, desde el {diaLargo(estadoMp.desde, true)}.</span>
                </span>
              </div>
              <p class="texto">El cobro llega solo a tu terminal Point, sin teclear el monto, y el dinero cae directo en tu cuenta: Fragmentless nunca lo toca.</p>
              <div class="acciones"><Boton etiqueta="Desconectar" icono="desligar" tono="peligro" /></div>
              <p class="pista">No se puede desconectar mientras un cobro espera en la terminal.</p>
            {:else if estadoMp.estado === 'desconectado'}
              <p class="aviso">
                <Icono nombre="alerta" tamano={16} />
                <span><b>Se desconectó el {diaLargo(estadoMp.cuando, false)} a las {estadoMp.cuando.slice(11, 16)}.</b> Mientras tanto, la terminal se cobra a mano: se teclea el monto y se anota como tarjeta.</span>
              </p>
              <div class="acciones"><Boton etiqueta="Conectar otra vez" icono="afuera" tono="tinta" onclick={conectar} /></div>
              <p class="pista">Pasa, por ejemplo, si se quitó el permiso desde la app de Mercado Pago.</p>
            {:else}
              <p class="texto">
                Conecta la cuenta de Mercado Pago de esta sucursal y el cobro llega solo a tu terminal Point, sin teclear el monto. El
                dinero cae directo en tu cuenta: Fragmentless nunca lo toca.
              </p>
              <div class="acciones"><Boton etiqueta="Conectar Mercado Pago" icono="afuera" tono="tinta" onclick={conectar} /></div>
              <p class="pista">Te lleva a Mercado Pago para que des el permiso, y regresas aquí. Cada sucursal conecta la suya.</p>
            {/if}
          </div>
        </Cajita>
      </div>
    {/if}
  </div>
</div>

<style>
  .desliza {
    position: absolute;
    inset: 0;
    overflow-y: auto;
    scrollbar-gutter: stable;
  }

  .ajustes {
    max-width: 940px;
    margin: 0 auto;
    padding: 24px 24px 40px;
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  .cabeza {
    padding: 2px 4px 4px;
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

  /* Interfaz: a la izquierda el tema y el estilo; a la derecha, la ventanita de muestra. */
  .interfaz {
    display: grid;
    grid-template-columns: minmax(0, 1fr) 280px;
    gap: 32px;
    align-items: start;
  }

  .izquierda {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 22px;
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
    text-wrap: pretty;
  }

  .control {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .tema-texto {
    font-size: 13px;
    font-weight: 600;
    color: var(--suave);
  }

  /* Las formas, como las de «Tu menú en línea». */
  .formas {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 3px;
    padding: 3px;
    border-radius: 12px;
    background: var(--chip);
  }

  .forma {
    position: relative;
    height: 40px;
    min-width: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0 8px;
    border: 0;
    border-radius: 9px;
    background: transparent;
    color: var(--suave);
    font: 600 12.5px var(--jakarta);
    white-space: nowrap;
    cursor: pointer;
    transition:
      background-color 0.18s ease,
      color 0.18s ease,
      box-shadow 0.18s ease,
      transform 0.15s ease;
  }

  .forma:hover {
    color: var(--texto);
  }

  .forma:active {
    transform: scale(0.97);
  }

  .forma:focus-visible {
    outline: none;
    box-shadow: 0 0 0 2px var(--campo-aro);
  }

  .forma[aria-pressed='true'] {
    background: var(--solido);
    color: var(--texto);
    box-shadow: 0 1px 3px var(--sombra-segmento);
  }

  /* La ventanita de muestra, como la de «Modo de color» de la app de Claude: el fondo del panel y, encima, una ventana
     con dos rayitas y un punto del acento. Quieta: es un dibujo. */
  .muestra {
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .muestra figcaption {
    text-align: center;
  }

  .muestra-fondo {
    position: relative;
    height: 172px;
    display: flex;
    align-items: center;
    justify-content: center;
    overflow: hidden;
    border-radius: 16px;
    background: var(--fondo);
    box-shadow: 0 0 0 1px var(--linea-fuerte);
    pointer-events: none;
    user-select: none;
  }

  .muestra-ventana {
    position: relative;
    width: 200px;
    height: 116px;
    box-sizing: border-box;
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 8px;
    border: 1px solid var(--borde-tarjeta);
    border-radius: 14px;
    background: var(--solido);
  }

  .rayita {
    width: 92px;
    height: 6px;
    border-radius: 3px;
    background: color-mix(in srgb, var(--texto) 22%, transparent);
  }

  .rayita.corta {
    width: 64px;
  }

  .punto-acento {
    position: absolute;
    right: 14px;
    bottom: 14px;
    width: 16px;
    height: 16px;
    border-radius: 50%;
    background: var(--acento);
  }

  /* Mercado Pago */
  .estado {
    display: inline-flex;
    align-items: center;
    gap: 8px;
  }

  .estado.ambar {
    color: var(--amarillo-texto);
  }

  .punto {
    width: 8px;
    height: 8px;
    flex: none;
    border-radius: 50%;
    background: var(--tenue);
  }

  .punto.verde {
    background: var(--verde);
  }

  .punto.ambar {
    background: var(--amarillo);
  }

  .mp,
  .mp-cargando {
    max-width: 640px;
    display: flex;
    flex-direction: column;
    gap: 14px;
    animation: llega 0.2s ease;
  }

  .mp-cargando {
    gap: 10px;
  }

  .mp-esqueleto-boton {
    display: flex;
    margin-top: 8px;
  }

  @keyframes llega {
    from {
      opacity: 0;
    }
  }

  .cuenta {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px 14px;
    border-radius: 12px;
    background: var(--chip);
  }

  .cuenta-icono {
    width: 32px;
    height: 32px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 10px;
    background: rgba(63, 155, 90, 0.16);
    color: var(--verde);
  }

  .cuenta-texto {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
    font-size: 13px;
    line-height: 1.4;
    color: var(--suave);
  }

  .cuenta-texto b {
    font-weight: 700;
    color: var(--texto);
  }

  .cuenta-texto span {
    font-size: 12.5px;
    font-weight: 500;
    text-wrap: pretty;
  }

  .texto {
    margin: 0;
    font-size: 13px;
    font-weight: 500;
    line-height: 1.5;
    color: var(--suave);
    text-wrap: pretty;
  }

  .acciones {
    display: flex;
    gap: 10px;
  }

  .aviso {
    display: flex;
    align-items: flex-start;
    gap: 10px;
    margin: 0;
    padding: 11px 14px;
    border-radius: 12px;
    background: var(--amarillo-fondo);
    font-size: 12.5px;
    line-height: 1.5;
    color: var(--suave);
  }

  .aviso :global(svg) {
    flex: none;
    margin-top: 2px;
    color: var(--amarillo-texto);
  }

  .aviso b {
    color: var(--texto);
    font-weight: 600;
  }

  /* Cristal: dentro de la cajita de material, rellenos transparentes (nunca vidrio sobre vidrio). La muestra: detrás, el
     fondo de Cristal con una sola mancha al centro (la de cada tema, con su grano); encima, la ventanita de vidrio, con
     una sombra a su medida. */
  :global(:root[data-estilo='cristal'][data-tema='oscuro']) :is(.formas, .cuenta) {
    background: rgba(255, 255, 255, 0.06);
  }

  :global(:root[data-estilo='cristal'][data-tema='oscuro']) .forma[aria-pressed='true'] {
    background: linear-gradient(180deg, rgba(255, 255, 255, 0.16), rgba(255, 255, 255, 0.07));
    box-shadow:
      inset 0 1px 0 rgba(255, 255, 255, 0.18),
      0 4px 12px -6px rgba(0, 0, 0, 0.6);
  }

  :global(:root[data-estilo='cristal'][data-tema='oscuro']) .muestra-fondo {
    background:
      var(--grano),
      radial-gradient(62% 82% at 50% 50%, rgba(var(--mancha), 0.62), rgba(var(--mancha), 0.44) 30%, rgba(var(--mancha), 0.22) 58%, rgba(var(--mancha), 0.06) 84%, transparent 100%),
      #000000;
    box-shadow: 0 0 0 1px rgba(255, 255, 255, 0.12);
  }

  :global(:root[data-estilo='cristal'][data-tema='oscuro']) .muestra-ventana {
    box-shadow:
      inset 0 1px 0 rgba(255, 255, 255, 0.14),
      0 14px 30px -12px rgba(0, 0, 0, 0.7);
  }

  :global(:root[data-estilo='cristal'][data-tema='oscuro']) .rayita {
    background: rgba(255, 255, 255, 0.18);
  }

  :global(:root[data-estilo='cristal'][data-tema='claro']) :is(.formas, .cuenta) {
    background: var(--cl-relleno);
  }

  :global(:root[data-estilo='cristal'][data-tema='claro']) .forma[aria-pressed='true'] {
    background: rgba(255, 255, 255, 0.9);
    box-shadow:
      inset 0 1px 0 #ffffff,
      0 4px 12px -6px var(--cl-sombra);
  }

  :global(:root[data-estilo='cristal'][data-tema='claro']) .muestra-fondo {
    background:
      var(--grano-claro),
      radial-gradient(62% 82% at 50% 50%, #ffffff, rgba(255, 255, 255, 0.8) 30%, rgba(255, 255, 255, 0.38) 58%, rgba(255, 255, 255, 0.1) 84%, transparent 100%),
      linear-gradient(180deg, #d4d7dd, #c8ccd3);
    box-shadow: 0 0 0 1px rgba(255, 255, 255, 0.8);
  }

  :global(:root[data-estilo='cristal'][data-tema='claro']) .muestra-ventana {
    box-shadow:
      inset 0 1px 0 #ffffff,
      0 14px 30px -12px rgba(20, 30, 50, 0.3);
  }

  :global(:root[data-estilo='cristal'][data-tema='claro']) .rayita {
    background: rgba(30, 40, 60, 0.14);
  }

  @media (prefers-reduced-motion: reduce) {
    .forma {
      transition: none;
    }

    .mp,
    .mp-cargando {
      animation: none;
    }
  }
</style>
