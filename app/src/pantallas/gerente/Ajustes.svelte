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
  · Mercado Pago (la terminal conectada, 16 nov 2026; maqueta de la terminal v2, pantalla Ajustes): sin conectar,
    conectada o «Se desconectó». Conectar y desconectar piden la contraseña otra vez (ajustes/VentanaContrasena.svelte).
    Conectada: la cuenta y desde cuándo; la Point ligada con «Imprimir el ticket al cobrar» (el selector de dos de Tu
    restaurante, «Imprime · No imprime») y, recién ligada, «Reinicia tu terminal una vez»; sin Point, la lista de las de
    la cuenta para elegir, o los 3 pasos para ligar una; si la ligada ya no está en la cuenta, lo dice y pide otra.
    Desde la franja de Inicio y al regresar de Mercado Pago, llega abierta (`abrirMercadoPago`, `regreso`).

  · Datos de tus clientes (21 nov 2026; maqueta Qvn42kQsyRX3m9vscikYfB; planes/trabajo/datos-de-clientes/): la copia de la
    de Mercado Pago, de la sucursal. Qué pide el menú y cuándo se borra, «Ver el aviso de privacidad» (el aviso del menú
    de esta sucursal, en otra pestaña) y «Borrar los datos de un cliente» (ajustes/VentanaBorrarDatos.svelte).

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
  import { enZona } from '../../lib/formato';
  import { cambiarEstilo, estiloActual, type Estilo } from '../../lib/estilo';
  import type { Sucursal } from '../../lib/gerente';
  import {
    fijarImprimirTicket,
    leerMercadoPago,
    leerTerminales,
    ligarTerminal,
    marcarReiniciar,
    tocaReiniciar,
    type EstadoMercadoPago,
    type Regreso,
    type Terminales,
  } from '../../lib/mercadoPago';
  import { nombrePoint } from '../../lib/terminal.svelte';
  import { vidrio } from '../../diseno/vidrio';
  import { cambiarTema, temaActual } from '../../lib/tema';
  import { linkDelAviso } from '../../lib/vistaMenu';
  import VentanaBorrarDatos from './ajustes/VentanaBorrarDatos.svelte';
  import VentanaContrasena from './ajustes/VentanaContrasena.svelte';

  let {
    sucursal,
    abrirMercadoPago = false,
    regreso = null,
    alCambiarMercadoPago,
  }: {
    sucursal?: Sucursal;
    abrirMercadoPago?: boolean;
    regreso?: Regreso | null; // lo que dijo Mercado Pago al regresar (?mp=…)
    alCambiarMercadoPago?: (estado: EstadoMercadoPago) => void; // para la franja de Inicio
  } = $props();

  let tema = $state(temaActual());
  let estilo = $state(estiloActual());
  let interfaz = $state(false);
  // svelte-ignore state_referenced_locally
  let mercadoPago = $state(abrirMercadoPago);
  let caja = $state<HTMLElement | null>(null);
  let datosClientes = $state(false);
  let borrarCliente = $state(false);

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
  // Las Point de la cuenta (por el Worker): se leen con la cajita conectada, para elegir una o ver si la ligada sigue.
  let terminales = $state<Terminales | null>(null);
  let errorPoints = $state<string | null>(null);
  let elegida = $state<string | null>(null);
  let ligando = $state(false);
  let errorLigar = $state<string | null>(null);
  let reinicia = $state(false);
  let contrasena = $state<null | 'conectar' | 'desconectar'>(null);
  let errorTicket = $state<string | null>(null);
  // Lo que dijo Mercado Pago al regresar: cancelado o error se dicen arriba de la cajita (conectado ya se ve).
  // svelte-ignore state_referenced_locally
  let avisoRegreso = $state<{ tipo: 'info' | 'alerta'; texto: string } | null>(
    regreso?.resultado === 'cancelado'
      ? { tipo: 'info', texto: 'No se conectó: en Mercado Pago no se dio el permiso.' }
      : regreso?.resultado === 'error'
        ? { tipo: 'alerta', texto: 'No pudimos conectar tu Mercado Pago. Intenta otra vez.' }
        : null,
  );

  onMount(() => {
    // Desde la franja de Inicio o al regresar de Mercado Pago: que se vea la cajita de Mercado Pago.
    if (abrirMercadoPago && caja) {
      const quieto = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
      setTimeout(() => caja?.scrollIntoView({ block: 'nearest', behavior: quieto ? 'auto' : 'smooth' }), 60);
    }
    if (!sucursal) return;
    if (regreso?.resultado === 'conectado' && regreso.reinicia) marcarReiniciar(sucursal.id, true);
    reinicia = tocaReiniciar(sucursal.id);
    leerMp();
  });

  function leerMp() {
    if (!sucursal) return;
    const id = sucursal.id;
    errorMp = null;
    leerMercadoPago(id)
      .then((e) => {
        estadoMp = e;
        alCambiarMercadoPago?.(e);
        if (e.estado === 'conectado') revisarPoints();
      })
      .catch((falla) => {
        console.error('[ajustes] no se pudo leer la conexión con Mercado Pago:', falla);
        errorMp = esDeRed(falla) ? SIN_CONEXION : 'No se pudo leer tu conexión con Mercado Pago. Intenta de nuevo en un momento.';
      });
  }

  // Las Point de la cuenta: si no hay ligada, para elegir (la primera libre ya elegida); si la ligada ya no está, el
  // Worker la quitó y aquí se pide otra.
  async function revisarPoints() {
    if (!sucursal) return;
    terminales = null;
    errorPoints = null;
    try {
      const t = await leerTerminales(sucursal.id);
      terminales = t;
      elegida = t.terminales.find((p) => !p.en)?.id ?? null;
      if (estadoMp?.estado === 'conectado' && estadoMp.terminalId !== t.ligada) {
        estadoMp = { ...estadoMp, terminalId: t.ligada };
        alCambiarMercadoPago?.(estadoMp);
      }
    } catch (falla) {
      const texto = falla instanceof Error ? falla.message : '';
      if (texto === 'Tu Mercado Pago se desconectó.') return leerMp();
      console.error('[ajustes] no se pudieron leer las Point de la cuenta:', falla);
      errorPoints = texto || 'No se pudieron leer tus Point. Intenta de nuevo.';
    }
  }

  async function usarPoint() {
    if (!sucursal || !elegida || ligando) return;
    ligando = true;
    errorLigar = null;
    try {
      const r = await ligarTerminal(sucursal.id, elegida);
      if (r.reinicia) {
        marcarReiniciar(sucursal.id, true);
        reinicia = true;
      }
      leerMp();
    } catch (falla) {
      errorLigar = falla instanceof Error ? falla.message : 'No se pudo ligar tu Point. Intenta de nuevo.';
    } finally {
      ligando = false;
    }
  }

  function yaReinicie() {
    if (!sucursal) return;
    marcarReiniciar(sucursal.id, false);
    reinicia = false;
  }

  // «Imprime · No imprime»: cambia al momento y se guarda; si no se pudo, regresa y lo dice.
  async function cambiarTicket(imprimir: boolean) {
    if (!sucursal || estadoMp?.estado !== 'conectado' || estadoMp.imprimirTicket === imprimir) return;
    const antes = estadoMp.imprimirTicket;
    estadoMp = { ...estadoMp, imprimirTicket: imprimir };
    errorTicket = null;
    try {
      await fijarImprimirTicket(sucursal.id, imprimir);
    } catch (falla) {
      if (estadoMp?.estado === 'conectado') estadoMp = { ...estadoMp, imprimirTicket: antes };
      errorTicket = falla instanceof Error ? falla.message : 'No se pudo cambiar. Intenta de nuevo.';
    }
  }

  function conectar() {
    avisoRegreso = null;
    contrasena = 'conectar';
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
            {#if avisoRegreso}<CajaError tipo={avisoRegreso.tipo} mensaje={avisoRegreso.texto} />{/if}
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
              {@const mp = estadoMp}
              <div class="cuenta">
                <span class="cuenta-icono"><Icono nombre="check" tamano={18} /></span>
                <span class="cuenta-texto">
                  <b>Conectado a {mp.cuenta}</b>
                  <span>La cuenta de Mercado Pago de esta sucursal, desde el {diaLargo(enZona(mp.desde, mp.zona).dia, true)}.</span>
                </span>
              </div>
              {#if mp.terminalId}
                <div class="cuenta">
                  <span class="cuenta-icono point"><Icono nombre="tarjeta" tamano={18} /></span>
                  <span class="cuenta-texto">
                    <b>{nombrePoint(mp.terminalId)}</b>
                    <span>{reinicia ? 'Ya está lista para recibir los cobros de esta sucursal.' : 'La terminal de esta sucursal. Durante el servicio, déjala en «Cobros vinculados».'}</span>
                  </span>
                </div>
                {#if reinicia}
                  <p class="aviso azul" role="status">
                    <Icono nombre="info" tamano={16} />
                    <span><b>Reinicia tu terminal una vez.</b> Apágala y préndela: así entra en modo de punto de venta. Luego déjala en «Cobros vinculados».</span>
                  </p>
                  <div class="acciones"><Boton etiqueta="Ya la reinicié" icono="check" onclick={yaReinicie} /></div>
                {/if}
                <div class="fila-ticket">
                  <span class="t">
                    <b>Imprimir el ticket al cobrar</b>
                    <span class="pista">
                      {mp.imprimirTicket
                        ? 'Cuando la cuenta se cierra, la Point imprime los productos, el total y el folio, además del comprobante de la tarjeta.'
                        : 'La Point solo imprime el comprobante de la tarjeta.'}
                    </span>
                  </span>
                  <div class="dos" role="group" aria-label="Imprimir el ticket al cobrar">
                    <button type="button" class="opcion si" aria-pressed={mp.imprimirTicket} onclick={() => cambiarTicket(true)}>Imprime</button>
                    <button type="button" class="opcion no" aria-pressed={!mp.imprimirTicket} onclick={() => cambiarTicket(false)}>No imprime</button>
                  </div>
                </div>
                {#if errorTicket}<CajaError mensaje={errorTicket} />{/if}
              {:else if errorPoints}
                <CajaError mensaje={errorPoints} />
                <div class="acciones"><Boton etiqueta="Buscar otra vez" icono="actualizar" onclick={revisarPoints} /></div>
              {:else if !terminales}
                <span class="solo-lector">Buscando tus Point…</span>
                <div class="mp-cargando" aria-hidden="true">
                  <Esqueleto ancho="60%" alto="10px" />
                  <div class="ops">
                    {#each [0, 1] as i (i)}<Esqueleto alto="54px" redondo="12px" />{/each}
                  </div>
                </div>
              {:else if terminales.terminales.length === 0}
                <p class="aviso">
                  <Icono nombre="alerta" tamano={16} />
                  <span><b>Tu cuenta de Mercado Pago todavía no tiene ninguna Point.</b> Mientras tanto, la terminal se cobra a mano.</span>
                </p>
                <ol class="pasos">
                  <li>Prende tu Point: en su pantalla sale un código QR.</li>
                  <li>Escanéalo con la app de Mercado Pago de esta misma cuenta y sigue sus pasos.</li>
                  <li>Regresa aquí y toca «Buscar otra vez».</li>
                </ol>
                <div class="acciones"><Boton etiqueta="Buscar otra vez" icono="actualizar" onclick={revisarPoints} /></div>
              {:else}
                {#if terminales.desligada}
                  <p class="aviso">
                    <Icono nombre="alerta" tamano={16} />
                    <span><b>Tu {nombrePoint(terminales.desligada)} ya no está en tu cuenta de Mercado Pago.</b> Mientras eliges otra, la terminal se cobra a mano.</span>
                  </p>
                {/if}
                <div class="elige-point">
                  <span class="elige-tit">
                    {terminales.desligada
                      ? 'Elige otra Point para esta sucursal:'
                      : terminales.terminales.length === 1
                        ? 'Tu cuenta tiene 1 terminal Point. ¿Es la de esta sucursal?'
                        : `Tu cuenta tiene ${terminales.terminales.length} terminales Point. ¿Cuál es la de esta sucursal?`}
                  </span>
                  <div class="ops" role="group" aria-label="Tus terminales Point">
                    {#each terminales.terminales as p (p.id)}
                      <button type="button" class="op" aria-pressed={elegida === p.id} disabled={!!p.en || ligando} onclick={() => (elegida = p.id)}>
                        <span class="op-icono"><Icono nombre="tarjeta" tamano={18} /></span>
                        <span class="op-texto"><b>{nombrePoint(p.id)}</b><span>{p.en ? `Ya está en ${p.en}` : 'Sin sucursal'}</span></span>
                        <span class="op-marca" aria-hidden="true"><Icono nombre="check" tamano={14} /></span>
                      </button>
                    {/each}
                  </div>
                </div>
                {#if errorLigar}<CajaError mensaje={errorLigar} />{/if}
                <div class="acciones">
                  <Boton etiqueta="Usar esta Point" tono="verde" apagado={!elegida} cargando={ligando} onclick={usarPoint} />
                </div>
                <p class="pista">Una Point va en una sola sucursal. Son los últimos números de la serie, la que viene atrás de la terminal.</p>
              {/if}
              <p class="texto">El cobro llega solo a tu terminal Point, sin teclear el monto, y el dinero cae directo en tu cuenta: Fragmentless nunca lo toca.</p>
              <div class="acciones">
                <Boton etiqueta="Desconectar" icono="desligar" tono="peligro" onclick={() => (contrasena = 'desconectar')} />
              </div>
              <p class="pista">No se puede desconectar mientras un cobro espera en la terminal.</p>
            {:else if estadoMp.estado === 'desconectado'}
              {@const cuando = enZona(estadoMp.cuando, estadoMp.zona)}
              <p class="aviso">
                <Icono nombre="alerta" tamano={16} />
                <span><b>Se desconectó el {diaLargo(cuando.dia, false)} a las {cuando.hora}.</b> Mientras tanto, la terminal se cobra a mano: se teclea el monto y se anota como tarjeta.</span>
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
      {#if contrasena}
        <VentanaContrasena
          para={contrasena}
          restauranteId={sucursal.id}
          sucursal={sucursal.nombre}
          alListo={() => {
            if (sucursal) marcarReiniciar(sucursal.id, false);
            reinicia = false;
            leerMp();
          }}
          alCerrar={() => (contrasena = null)}
        />
      {/if}

      <Cajita icono="usuarios" titulo="Datos de tus clientes" nota="De esta sucursal: {sucursal.nombre}." bind:abierta={datosClientes}>
        {#snippet resumen()}<span class="resumen-texto">Se borran a los 90 días</span>{/snippet}
        <div class="mp">
          <p class="texto">
            Tu menú les pide a tus clientes su nombre, su teléfono y, a domicilio, su dirección, solo para su pedido. El teléfono
            y la dirección se borran solos a los 90 días (a los 7 si no confirmaste el pedido); el pedido, el nombre y el total se
            quedan en tus cortes.
          </p>
          <div class="acciones envuelve">
            <Boton
              etiqueta="Ver el aviso de privacidad"
              icono="afuera"
              onclick={() => sucursal && window.open(linkDelAviso(sucursal.slug), '_blank', 'noopener')}
            />
            <Boton etiqueta="Borrar los datos de un cliente" icono="eliminar" tono="peligro" onclick={() => (borrarCliente = true)} />
          </div>
          <p class="pista">
            Si un cliente te pide borrar sus datos, que te escriba por WhatsApp desde ese número: así sabes que es suyo. Contéstale
            en menos de 20 días hábiles.
          </p>
        </div>
      </Cajita>
      {#if borrarCliente}
        <VentanaBorrarDatos restauranteId={sucursal.id} sucursal={sucursal.nombre} alCerrar={() => (borrarCliente = false)} />
      {/if}
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

  /* Datos de tus clientes: sus dos botones bajan de renglón si no caben. */
  .acciones.envuelve {
    flex-wrap: wrap;
  }

  .resumen-texto {
    font: 500 13px var(--jakarta);
    color: var(--suave);
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

  /* La Point ligada: su renglón como el de la cuenta, con el ícono en el azul del acento. */
  .cuenta-icono.point {
    background: color-mix(in srgb, var(--acento) 14%, transparent);
    color: var(--acento);
  }

  .aviso.azul {
    background: color-mix(in srgb, var(--acento) 10%, transparent);
  }

  .aviso.azul :global(svg) {
    color: var(--acento);
  }

  /* «Imprimir el ticket al cobrar»: el selector de dos de Tu restaurante (restaurante/Dias.svelte, «Abre · Cerrado»),
     la canaleta en --chip y la elegida en su pastilla, «Imprime» en el verde de los botones y «No imprime» en el rojo;
     a la izquierda su texto, en el gris de los campos (como «Es un costo de envío»). */
  .fila-ticket {
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 14px 16px;
    border-radius: 16px;
    background: var(--fondo);
  }

  .fila-ticket .t {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .fila-ticket b {
    font-size: 13.5px;
    font-weight: 700;
  }

  .dos {
    flex: none;
    width: 200px;
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 3px;
    padding: 3px;
    border-radius: 12px;
    background: var(--chip);
  }

  .opcion {
    height: 36px;
    min-width: 0;
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

  .opcion:hover {
    color: var(--texto);
  }

  .opcion:active {
    transform: scale(0.97);
  }

  .opcion:focus-visible {
    outline: none;
    box-shadow: 0 0 0 2px var(--campo-aro);
  }

  .opcion.si[aria-pressed='true'] {
    background: #2b8449;
    color: #ffffff;
    box-shadow: 0 1px 3px var(--sombra-segmento);
  }

  .opcion.no[aria-pressed='true'] {
    background: var(--rojo);
    color: var(--sobre-rojo);
    box-shadow: 0 1px 3px var(--sombra-segmento);
  }

  /* Elegir la Point: cuadros con el aro azul y su palomita, como lo que se elige en el panel. */
  .elige-point {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .elige-tit {
    font-size: 13px;
    font-weight: 600;
    color: var(--texto);
  }

  .ops {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 8px;
  }

  .op {
    position: relative;
    display: flex;
    align-items: center;
    gap: 10px;
    min-width: 0;
    padding: 10px 12px;
    border: 1px solid var(--borde-tarjeta);
    border-radius: 12px;
    background: var(--solido);
    color: var(--texto);
    font: inherit;
    text-align: left;
    cursor: pointer;
    transition:
      transform 0.15s ease,
      box-shadow 0.2s ease,
      border-color 0.2s ease;
  }

  .op:hover:not(:disabled) {
    background: var(--chip);
  }

  .op:active:not(:disabled) {
    transform: scale(0.97);
  }

  .op:focus-visible {
    outline: none;
    box-shadow: 0 0 0 2px var(--campo-aro);
  }

  .op[aria-pressed='true'] {
    box-shadow: 0 0 0 2px var(--campo-aro);
    border-color: transparent;
  }

  .op:disabled {
    opacity: 0.5;
    cursor: default;
  }

  .op-icono {
    width: 32px;
    height: 32px;
    flex: none;
    display: grid;
    place-items: center;
    border-radius: 10px;
    background: var(--chip);
    color: var(--suave);
  }

  .op[aria-pressed='true'] .op-icono {
    color: var(--campo-aro);
  }

  .op-texto {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .op-texto b {
    font-size: 13px;
    font-weight: 700;
  }

  .op-texto span {
    font-size: 11.5px;
    line-height: 1.35;
    color: var(--suave);
  }

  .op-marca {
    margin-left: auto;
    width: 20px;
    height: 20px;
    flex: none;
    display: grid;
    place-items: center;
    border-radius: 6px;
    background: var(--campo-aro);
    color: #fff;
    opacity: 0;
    transform: scale(0.6);
    transition:
      opacity 0.2s ease,
      transform 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275);
  }

  .op[aria-pressed='true'] .op-marca {
    opacity: 1;
    transform: none;
  }

  .pasos {
    margin: 0;
    padding-left: 20px;
    font-size: 13px;
    line-height: 1.7;
    color: var(--suave);
  }

  .pasos li::marker {
    font-family: var(--mono);
    font-size: 12px;
    color: var(--tenue);
  }

  @media (prefers-reduced-motion: reduce) {
    .opcion,
    .op,
    .op-marca {
      transition: none;
    }
  }

  /* Cristal: dentro de la cajita de material, rellenos transparentes (nunca vidrio sobre vidrio). La muestra: detrás, el
     fondo de Cristal con una sola mancha al centro (la de cada tema, con su grano); encima, la ventanita de vidrio, con
     una sombra a su medida. */
  :global(:root[data-estilo='cristal'][data-tema='oscuro']) :is(.formas, .cuenta, .fila-ticket, .dos, .op) {
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

  :global(:root[data-estilo='cristal'][data-tema='claro']) :is(.formas, .cuenta, .fila-ticket, .dos, .op) {
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
