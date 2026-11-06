<!--
  El Agente IA del gerente (libreta 1; rediseño del 6 de noviembre de 2026, maqueta Cu768ereKMYRaYhhaAyMb4 y
  planes/trabajo/rediseno/pildora-agente.md). Tranquilo, como Claude:
  - la bienvenida, sin saludo ni fecha: primero el fondo normal con la píldora, luego el brillo detrás de ella y
    luego sube, en grande, el renglón que escribe la IA (el de reserva, para que salga al instante; si no hay,
    el local, sin aviso), con la línea de colores y las chispas en su última palabra. Las 3 ideas ya guardan su
    lugar y salen en fila al abrir la caja: al pasar sobre una cambia el texto de la caja; al picarla, se
    escribe, y la caja no se cierra. Lo que se le manda al agente es su prompt largo, no lo que se ve. El
    candado va hasta abajo, a la misma altura que en la conversación;
  - la conversación, 20 px adentro de la caja por cada lado (planes/trabajo/rediseno/encuestas-carga.md): cada
    pregunta en su globo gris y cada respuesta en Markdown, renglón por renglón, con
    «Lo que leí» debajo de cada una, en palabras, como lo mandó cada herramienta de Postgres. La caja se
    queda fija abajo.
  Cada número de una respuesta sale de una herramienta de Postgres: aquí no se cuenta nada.

  Mientras piensa (maqueta AyS4xUfa5XmDaPJG1iqSgw): la pregunta vuela de la caja a su lugar, salen los
  puntos, los segundos y cada paso real que manda el Worker, y al llegar la respuesta se doblan en
  «Pensé 6 s ›». El botón de mandar es «Detener»: la pregunta se queda con «La detuviste» y vuelve a
  la caja; nunca se le manda al agente y, lo ya gastado, el Worker lo anota. Lo que decidí yo sobre
  todo esto, en planes/trabajo/estrella/vista.md.

  El «+» de la caja pide un «Reporte en PDF» (lib/reporte.ts): lo arma el sistema, sin IA y sin costo, y
  llega como respuesta del agente. Por eso sigue ahí aunque no haya tope.

  Historial guarda las conversaciones en este navegador, por sucursal (las últimas 30), y «Cerrar
  sesión» las borra. Sin tope (estado_ia), la caja dice el aviso y las ideas se apagan; el
  Historial y el resto del panel siguen igual. Si se acaba a media conversación, la caja de abajo
  dice lo mismo. Si una pregunta no se pudo contestar, vuelve a la caja para mandarla otra vez.
-->
<script lang="ts">
  import { onMount, tick } from 'svelte';
  import BarraArriba from '../../diseno/BarraArriba.svelte';
  import Boton from '../../diseno/Boton.svelte';
  import CajaError from '../../diseno/CajaError.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import Pensando from '../../diseno/Pensando.svelte';
  import {
    guardarConversacion,
    IDEAS,
    leerConversaciones,
    leerEstadoIa,
    leerZonaYCorte,
    prepararSaludo,
    preguntar,
    SALUDO_LOCAL,
    textoSinTope,
    tomarSaludo,
    type Conversacion,
    type EstadoIa,
    type PasoAgente,
    type Turno,
  } from '../../lib/agente';
  import { esDeRed, SIN_CONEXION } from '../../lib/errores';
  import { saludoPorHora } from '../../lib/formato';
  import type { Sucursal } from '../../lib/gerente';
  import { prepararReporte, tituloDelPedido, type PeriodoReporte } from '../../lib/reporte';
  import CajaSucursales from './CajaSucursales.svelte';
  import ArchivoReporte from './agente/ArchivoReporte.svelte';
  import CajaPregunta from './agente/CajaPregunta.svelte';
  import Historial from './agente/Historial.svelte';
  import Respuesta from './agente/Respuesta.svelte';

  let {
    sucursal,
    sucursales,
    alElegir,
  }: {
    sucursal: Sucursal;
    sucursales: Sucursal[];
    alElegir: (sucursal: Sucursal) => void;
  } = $props();

  const PH_BIENVENIDA = 'Pregunta lo que quieras de tu negocio…';
  const PH_CHAT = 'Sigue preguntando… por ejemplo, ¿y ayer?';

  type Pedido = { visible: string; pregunta: string; idea: number | null };

  // null mientras se lee; si no se pudo leer, se pregunta igual y el Worker revisa.
  let estado = $state<EstadoIa | null>(null);
  let listo = $state(false);
  let corte = $state<number | null>(null);
  let segundo = $state(SALUDO_LOCAL);
  // svelte-ignore state_referenced_locally
  let conversaciones = $state<Conversacion[]>(leerConversaciones(sucursal.id));
  // La conversación abierta; sin ella, la bienvenida.
  let actual = $state<Conversacion | null>(null);
  // La pregunta que está esperando su respuesta, y de qué conversación es.
  let pendiente = $state<(Pedido & { id: string }) | null>(null);
  // Sus pasos y sus segundos, y cómo cortar su llamada.
  let pasos = $state<PasoAgente[]>([]);
  let segundos = $state(0);
  let llamada: AbortController | null = null;
  // El reporte que se está pidiendo: es un momento, lo que tarda Postgres en dar las fechas.
  let reporteEnCamino = $state<{ id: string; visible: string } | null>(null);
  // La que no se pudo contestar: su burbuja se queda con el aviso y vuelve a la caja.
  let fallo = $state<(Pedido & { id: string; mensaje: string }) | null>(null);
  // La que se acaba de detener: qué turno es y si su pregunta volvió a la caja.
  let detenida = $state<(Pedido & { id: string; turno: number; volvio: boolean }) | null>(null);
  // La respuesta que acaba de llegar sale renglón por renglón; las demás, enteras.
  let nueva = $state<{ id: string; turno: number } | null>(null);
  let valor = $state('');
  let placeholder = $state(PH_BIENVENIDA);
  let vista = $state<HTMLElement | null>(null);
  let abajo = $state<HTMLDivElement | null>(null);
  let caja = $state<{ enfocar: () => void; medir: () => DOMRect | null } | null>(null);
  // La caja de la bienvenida: abierta, salen las ideas. En la conversación, la caja lleva la suya.
  let cajaAbierta = $state(false);
  let bienvenida = $state<HTMLDivElement | null>(null);

  const sinTope = $derived(estado && !estado.puede ? estado : null);
  const ocupado = $derived(pendiente !== null || reporteEnCamino !== null);
  const pensandoAqui = $derived(pendiente !== null && pendiente.id === actual?.id);

  // Siempre la última palabra, porque la frase la escribe la IA y cambia.
  const frase = $derived.by(() => {
    const i = segundo.lastIndexOf(' ');
    return { inicio: segundo.slice(0, i + 1), ultima: segundo.slice(i + 1) };
  });

  // Sin la hora de corte, la nota no dice de qué hora a qué hora va el día.
  const notaLeido = $derived(
    corte === null
      ? 'Siempre tengo a la mano tu menú, tus mesas y las cuentas abiertas ahora. Las sumas las hace el panel, no la IA.'
      : `Siempre tengo a la mano tu menú, tus mesas y las cuentas abiertas ahora. Tu día se cuenta de ${corte}:00 a ${corte}:00, y las sumas las hace el panel, no la IA.`,
  );

  // La pregunta queda hasta arriba: la respuesta se lee desde su principio (como en Flet).
  async function irALaPregunta() {
    await tick();
    const burbujas = vista?.querySelectorAll('.burbuja');
    const ultima = burbujas?.[burbujas.length - 1] as HTMLElement | undefined;
    if (!vista || !ultima) return;
    const top = vista.scrollTop + ultima.getBoundingClientRect().top - vista.getBoundingClientRect().top - 32;
    vista.scrollTo({ top, behavior: 'smooth' });
  }

  // Si los pasos ya no caben arriba de la caja, baja lo justo para verlos.
  $effect(() => {
    void pasos.length;
    tick().then(() => {
      const piensa = vista?.querySelector('.piensa');
      if (!vista || !piensa || !abajo) return;
      const falta = piensa.getBoundingClientRect().bottom - abajo.getBoundingClientRect().top + 16;
      if (falta > 0) vista.scrollBy({ top: falta, behavior: 'smooth' });
    });
  });

  // La burbuja de la pregunta vuela desde la caja hasta su lugar (la referencia de los pasos: 560 ms, su curva).
  async function volarDesde(desde: DOMRect | null) {
    await tick();
    const burbujas = vista?.querySelectorAll('.burbuja');
    const burbuja = burbujas?.[burbujas.length - 1] as HTMLElement | undefined;
    if (!desde || !burbuja || matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    const lugar = burbuja.getBoundingClientRect();
    if (!lugar.width || !lugar.height) return;
    burbuja.style.transformOrigin = '0 0';
    burbuja.animate(
      [
        {
          transform: `translate(${desde.left - lugar.left}px, ${desde.top - lugar.top}px) scale(${desde.width / lugar.width}, ${Math.min(desde.height, 60) / lugar.height})`,
        },
        { transform: 'translate(0px, 0px) scale(1, 1)' },
      ],
      { duration: 560, easing: 'cubic-bezier(0.22, 1, 0.36, 1)' },
    );
  }

  // Se queda en la conversación con lo que alcanzó a hacer. Solo se guarda en el Historial si la
  // conversación ya tiene alguna respuesta: la fecha y la hora del restaurante llegan con ellas.
  function quedoDetenida(p: Pedido, base: Conversacion, tardo: number) {
    const hechos = pasos.filter((x) => x.hecho);
    const turno: Turno = {
      visible: p.visible,
      pregunta: p.pregunta,
      respuesta: '',
      leido: hechos.filter((x) => x.dato).map((x) => ({ icono: x.icono, texto: x.texto })),
      idea: p.idea,
      segundos: tardo,
      pasos: hechos.map((x) => x.listo),
      detenida: true,
    };
    const antes = conversaciones.find((c) => c.id === base.id) ?? base;
    const conversacion: Conversacion = { ...antes, turnos: [...antes.turnos, turno] };
    if (conversacion.turnos.some((t) => !t.detenida)) conversaciones = guardarConversacion(sucursal.id, conversacion);
    actual = conversacion;
    // Si ya escribió otra cosa en la caja, no se le borra.
    const volvio = !valor.trim();
    if (volvio) valor = p.visible;
    detenida = { ...p, id: base.id, turno: conversacion.turnos.length - 1, volvio };
  }

  async function enviar(p: Pedido) {
    if (ocupado || sinTope) return;
    const desde = caja?.medir() ?? null;
    const base: Conversacion = actual ?? { id: crypto.randomUUID(), titulo: p.visible, fecha: '', hora: '', turnos: [] };
    actual = base;
    fallo = null;
    detenida = null;
    nueva = null;
    pendiente = { ...p, id: base.id };
    pasos = [];
    segundos = 0;
    const esta = new AbortController();
    llamada = esta;
    const inicio = performance.now();
    const tardo = () => Math.max(1, Math.round((performance.now() - inicio) / 1000));
    const reloj = setInterval(() => (segundos = Math.floor((performance.now() - inicio) / 1000)), 250);
    let alLlegar = 0;
    irALaPregunta();
    volarDesde(desde);

    try {
      const r = await preguntar(sucursal.id, p.pregunta, base.turnos, {
        senal: esta.signal,
        alPasos: (lista) => (pasos = lista),
        alLlegar: () => {
          clearInterval(reloj);
          alLlegar = tardo();
          segundos = alLlegar;
        },
      });
      if (r.tipo === 'sin_tope') {
        // Se acabó el tope antes de preguntar: la caja dice el aviso y la pregunta no se hizo.
        estado = r.estado;
        if (actual?.id === base.id && !base.turnos.length) actual = null;
        return;
      }
      // La conversación como está guardada (pudo cambiar de vista mientras tanto).
      const antes = conversaciones.find((c) => c.id === base.id) ?? base;
      const turno: Turno = {
        visible: p.visible,
        pregunta: p.pregunta,
        respuesta: r.respuesta,
        leido: r.leido,
        idea: p.idea,
        segundos: alLlegar,
        pasos: r.pasos,
      };
      const lista = [...antes.turnos, turno];
      const conversacion: Conversacion = {
        ...antes,
        fecha: antes.fecha || r.ahora?.fecha || sucursal.hoy,
        hora: antes.hora || r.ahora?.hora || '',
        turnos: lista,
      };
      conversaciones = guardarConversacion(sucursal.id, conversacion);
      if (actual?.id === base.id) {
        actual = conversacion;
        nueva = { id: base.id, turno: lista.length - 1 };
      }
      if (!r.puede) {
        try {
          estado = await leerEstadoIa(sucursal.id);
        } catch (error) {
          console.error('[agente] no se pudo leer el estado de la IA después del tope:', error);
        }
      }
    } catch (error) {
      if (esta.signal.aborted) {
        quedoDetenida(p, base, tardo());
        return;
      }
      console.error('[agente] la pregunta no se contestó:', error);
      const mensaje = error instanceof Error ? error.message : '';
      fallo = {
        ...p,
        id: base.id,
        mensaje:
          mensaje === SIN_CONEXION || !mensaje
            ? 'No se pudo contestar: se perdió la conexión con el servidor. Tu pregunta volvió a la caja para que la mandes otra vez.'
            : `${mensaje} Tu pregunta volvió a la caja para que la mandes otra vez.`,
      };
      if (actual?.id === base.id) valor = p.visible;
    } finally {
      clearInterval(reloj);
      llamada = null;
      pendiente = null;
      await tick();
      if (fallo || nueva) irALaPregunta();
      caja?.enfocar();
    }
  }

  function detener() {
    llamada?.abort();
  }

  // El «+»: entra a la plática como una pregunta, sin llamar a OpenAI. Si la conversación es nueva, se llama
  // como el reporte y lleva la fecha y la hora de ahora.
  async function pedirReporte(periodo: PeriodoReporte) {
    if (ocupado) return;
    const visible = tituloDelPedido(periodo);
    const base: Conversacion = actual ?? { id: crypto.randomUUID(), titulo: visible, fecha: '', hora: '', turnos: [] };
    actual = base;
    fallo = null;
    detenida = null;
    nueva = null;
    reporteEnCamino = { id: base.id, visible };
    irALaPregunta();
    try {
      const { reporte, ahora } = await prepararReporte(sucursal.id, periodo);
      const antes = conversaciones.find((c) => c.id === base.id) ?? base;
      const turno: Turno = { visible, pregunta: '', respuesta: '', leido: [], idea: null, reporte };
      const conversacion: Conversacion = {
        ...antes,
        fecha: antes.fecha || ahora.fecha,
        hora: antes.hora || ahora.hora,
        turnos: [...antes.turnos, turno],
      };
      conversaciones = guardarConversacion(sucursal.id, conversacion);
      if (actual?.id === base.id) actual = conversacion;
    } catch (error) {
      console.error('[agente] no se pudo pedir el reporte:', error);
      fallo = {
        visible,
        pregunta: '',
        idea: null,
        id: base.id,
        mensaje: `${esDeRed(error) ? SIN_CONEXION : 'No se pudo armar el reporte.'} Pídelo otra vez desde el «+».`,
      };
    } finally {
      reporteEnCamino = null;
      await tick();
      irALaPregunta();
      caja?.enfocar();
    }
  }

  // Lo escrito en la caja. Si es la que no se pudo contestar o la que se detuvo, se manda igual que
  // la primera vez; si es la frase de una idea, se manda su prompt.
  function enviarLoEscrito() {
    const texto = valor.trim();
    if (!texto) return;
    const otraVez = [fallo, detenida].find((x) => x && x.id === actual?.id && x.visible === texto);
    const idea = IDEAS.findIndex((x) => x.frase === texto);
    valor = '';
    if (otraVez) enviar(otraVez);
    else if (idea >= 0) enviar({ visible: texto, pregunta: IDEAS[idea].prompt, idea });
    else enviar({ visible: texto, pregunta: texto, idea: null });
  }

  function usarIdea(i: number) {
    valor = IDEAS[i].frase;
    caja?.enfocar();
  }

  function nuevaConversacion() {
    actual = null;
    fallo = null;
    detenida = null;
    nueva = null;
    valor = '';
    cajaAbierta = false;
    placeholder = PH_BIENVENIDA;
    vista?.scrollTo({ top: 0 });
  }

  async function abrirConversacion(c: Conversacion) {
    actual = c;
    fallo = null;
    detenida = null;
    nueva = null;
    valor = '';
    await tick();
    vista?.scrollTo({ top: vista.scrollHeight });
  }

  onMount(() => {
    const momento = saludoPorHora(sucursal.hora);
    Promise.allSettled([leerEstadoIa(sucursal.id), leerZonaYCorte(sucursal.id)]).then(([e, z]) => {
      if (e.status === 'fulfilled') estado = e.value;
      else console.error('[agente] no se pudo leer si hay tope; se pregunta igual y el Worker revisa:', e.reason);
      if (z.status === 'fulfilled') corte = z.value.corte;
      else console.error('[agente] no se pudo leer la hora de corte:', z.reason);
      // El renglón de la IA, solo si puede; luego se pide el de la próxima vez.
      if (!sinTope) {
        segundo = tomarSaludo(sucursal.id, sucursal.hoy, momento) ?? SALUDO_LOCAL;
        prepararSaludo(sucursal.id, sucursal.hoy, momento);
      }
      listo = true;
    });
  });
</script>

<BarraArriba titulo="Agente IA" estado={{ texto: 'Leyendo tus ventas en vivo', vivo: true }}>
  <Historial {conversaciones} actual={actual?.id ?? null} hoy={sucursal.hoy} alAbrir={abrirConversacion} />
  <Boton etiqueta="Nueva conversación" icono="r-mas" tono="tinta" onclick={nuevaConversacion} />
  <CajaSucursales {sucursales} actual={sucursal} {alElegir} />
</BarraArriba>

<main class="vista" bind:this={vista}>
  <section class="agente" aria-label="Agente IA">
    {#if !actual}
      {#if listo}
        <div class="bienvenida" class:abierta={cajaAbierta || !!sinTope} bind:this={bienvenida}>
          <h1>
            {frase.inicio}<span class="subrayada"
              >{frase.ultima}<span class="chispas" aria-hidden="true"
                ><span class="chispas-van"
                  ><i style="--d: 0s; --x: -5px; --y: -8px"></i><i style="--d: 0.08s; --x: -11px; --y: -4px"></i><i
                    style="--d: 0.16s; --x: -3px; --y: -11px"
                  ></i><i style="--d: 0.24s; --x: -13px; --y: 3px"></i><i style="--d: 0.32s; --x: -7px; --y: -6px"></i><i
                    style="--d: 0.4s; --x: -4px; --y: 5px"
                  ></i><i style="--d: 0.48s; --x: -15px; --y: -9px"></i></span
                ></span
              ></span
            >
          </h1>

          <div class="caja-zona">
            <div class="brillo" aria-hidden="true"></div>
            <CajaPregunta
              bind:this={caja}
              modo="bienvenida"
              bind:valor
              bind:abierta={cajaAbierta}
              zona={bienvenida}
              {placeholder}
              {ocupado}
              aviso={sinTope ? textoSinTope(sinTope) : null}
              alEnviar={enviarLoEscrito}
              alReporte={pedirReporte}
            />
          </div>

          <div class="ideas-zona">
            <div class="etiqueta ideas-titulo aparece" style="--i: 0">Ideas para ti</div>
            <div class="ideas">
              {#each IDEAS as idea, i (idea.titulo)}
                <button
                  type="button"
                  class="idea aparece"
                  style="--i: {i + 1}"
                  disabled={!!sinTope || ocupado}
                  onmousedown={(e) => e.preventDefault()}
                  onclick={() => usarIdea(i)}
                  onmouseenter={() => (placeholder = idea.frase)}
                  onmouseleave={() => (placeholder = PH_BIENVENIDA)}
                >
                  <span class="idea-cabeza">
                    <span class="cuadro-icono"><Icono nombre={idea.icono} tamano={18} /></span>
                    <Icono nombre="r-derecha" tamano={14} />
                  </span>
                  <span>
                    <b>{idea.titulo}</b>
                    <span class="idea-texto">{idea.texto}</span>
                  </span>
                </button>
              {/each}
            </div>
          </div>
        </div>
        <div class="candado candado-abajo">
          <Icono nombre="r-candado" tamano={14} />
          Solo responde sobre tu negocio. Las cifras salen de tus ventas cerradas.
        </div>
      {/if}
    {:else}
      <div class="chat" aria-label="Conversación">
        {#each actual.turnos as t, i (i)}
          <div class="burbuja">{t.visible}</div>
          {#if t.reporte}
            <ArchivoReporte reporte={t.reporte} restauranteId={sucursal.id} restaurante={sucursal.nombre} />
          {:else if t.detenida}
            <Respuesta
              texto=""
              aviso={detenida?.volvio && detenida.id === actual.id && detenida.turno === i
                ? 'La detuviste. Tu pregunta volvió a la caja por si quieres cambiarla.'
                : 'La detuviste.'}
              segundos={t.segundos}
              pasos={t.pasos}
              leido={t.leido}
              nota={notaLeido}
              alSeguir={() => {}}
            />
          {:else}
            <Respuesta
              texto={t.respuesta}
              nueva={nueva?.id === actual.id && nueva.turno === i}
              segundos={t.segundos}
              pasos={t.pasos}
              leido={t.leido}
              nota={notaLeido}
              seguimiento={t.idea !== null ? (IDEAS[t.idea]?.seguimiento ?? []) : []}
              apagado={ocupado || !!sinTope}
              alSeguir={(s) => enviar({ visible: s.etiqueta, pregunta: s.pregunta, idea: null })}
            />
          {/if}
        {/each}
        {#if pendiente && pendiente.id === actual.id}
          <div class="burbuja">{pendiente.visible}</div>
          <Pensando chicos texto="Pensando…" {pasos} {segundos} color="var(--punto-panel)" />
        {:else if reporteEnCamino && reporteEnCamino.id === actual.id}
          <div class="burbuja">{reporteEnCamino.visible}</div>
          <Pensando chicos texto="Armando tu reporte…" pasos={[]} color="var(--punto-panel)" />
        {:else if fallo && fallo.id === actual.id}
          <div class="burbuja">{fallo.visible}</div>
          <div class="error"><CajaError mensaje={fallo.mensaje} /></div>
        {/if}
      </div>
      <div class="abajo" bind:this={abajo}>
        <div class="ancho">
          <CajaPregunta
            bind:this={caja}
            modo="chat"
            bind:valor
            placeholder={PH_CHAT}
            {ocupado}
            aviso={sinTope ? textoSinTope(sinTope) : null}
            alEnviar={enviarLoEscrito}
            alDetener={pensandoAqui ? detener : null}
            alReporte={pedirReporte}
          />
          <div class="candado">
            <Icono nombre="r-candado" tamano={14} />
            Solo responde sobre tu negocio. Las cifras salen de tus ventas cerradas.
          </div>
        </div>
      </div>
    {/if}
  </section>
</main>

<style>
  .vista {
    position: absolute;
    left: 0;
    right: 0;
    top: 56px;
    bottom: 0;
    overflow-y: auto;
  }

  /* overflow: clip y no hidden, para que el brillo no la haga crecer sin romper el sticky de .abajo. */
  .agente {
    position: relative;
    min-height: 100%;
    display: flex;
    flex-direction: column;
    font-weight: 400;
    overflow: clip;
  }

  .bienvenida,
  .chat {
    position: relative;
    z-index: 1;
  }

  /* La frase y la píldora van al centro: lo de arriba y lo de abajo miden lo mismo. Las ideas ya ocupan
     su lugar aunque no se vean, para que nada brinque. */
  .bienvenida {
    flex: 1;
    width: 100%;
    max-width: 720px;
    margin: 0 auto;
    padding: 40px 32px 16px;
    display: flex;
    flex-direction: column;
    gap: 22px;
  }

  .bienvenida::before {
    content: '';
    flex: 1 1 0;
  }

  .ideas-zona {
    flex: 1 1 0;
    display: flex;
    flex-direction: column;
    gap: 22px;
  }

  /* Las ideas salen en fila cuando la caja ya es rectangular: el título y luego cada tarjeta. Se van juntas. */
  .aparece {
    opacity: 0;
    visibility: hidden;
    transform: translateY(10px) scale(0.97);
    transition:
      opacity 0.15s ease,
      transform 0.15s ease,
      visibility 0s linear 0.15s;
  }

  .bienvenida.abierta .aparece {
    --espera: calc(220ms + var(--i) * 80ms);
    opacity: 1;
    visibility: visible;
    transform: none;
    transition:
      opacity 0.35s ease var(--espera),
      transform 0.45s cubic-bezier(0.175, 0.885, 0.32, 1.275) var(--espera),
      visibility 0s linear var(--espera);
  }

  .bienvenida.abierta .idea.aparece:disabled {
    opacity: 0.45;
  }

  .caja-zona {
    position: relative;
    flex: none;
  }

  /* El brillo detrás de la caja, a partir de su centro. Sale primero y después sube la frase. Sus colores y
     su forma están en colores.css. */
  .brillo {
    position: absolute;
    left: 50%;
    top: 50%;
    z-index: -1;
    width: 1540px;
    height: 2400px;
    margin: -580px 0 0 -770px;
    pointer-events: none;
    opacity: var(--brillo-opacidad);
    transform-origin: 770px 580px;
    background: var(--brillo-capas);
    -webkit-mask-image: var(--brillo-mascara);
    mask-image: var(--brillo-mascara);
    animation: brillo-entra 0.9s cubic-bezier(0.4, 0, 0.2, 1) 0.45s both;
  }

  @keyframes brillo-entra {
    from {
      opacity: 0;
      transform: scale(0.8);
    }
  }

  h1 {
    margin: 0;
    text-align: center;
    text-wrap: balance;
    font-size: 34px;
    font-weight: 700;
    letter-spacing: -0.7px;
    line-height: 1.15;
    animation: frase-sube 0.55s cubic-bezier(0.22, 1, 0.36, 1) 1.05s both;
  }

  @keyframes frase-sube {
    from {
      opacity: 0;
      transform: translateY(18px);
    }
  }

  /* La última palabra: una raya gris por la que pasa dos veces la línea de colores, que acaba de golpe en su
     tono más claro; luego la raya se borra. */
  .subrayada {
    position: relative;
    display: inline-block;
  }

  .subrayada::after {
    content: '';
    position: absolute;
    left: 0;
    right: 0;
    bottom: -5px;
    height: 2.5px;
    border-radius: 2px;
    background:
      var(--raya) no-repeat,
      var(--linea-fuerte);
    background-size:
      45% 100%,
      100% 100%;
    background-position:
      -85% 0,
      0 0;
    animation:
      brillo 1.3s ease-in-out 1.6s 2,
      apagar 0.5s ease 4.2s forwards;
  }

  /* Las chispas: la punta de la línea las va soltando. El punto que las suelta avanza igual que la punta (mismo
     tiempo y misma curva) y, al pasar el final de la palabra, se recortan. */
  .chispas {
    position: absolute;
    left: 0;
    right: 0;
    bottom: -5px;
    height: 2.5px;
    pointer-events: none;
    clip-path: inset(-24px 0 -10px 0);
  }

  .chispas-van {
    position: absolute;
    inset: 0;
    animation: chispas-van 1.3s ease-in-out 1.6s 2 both;
  }

  @keyframes chispas-van {
    from {
      transform: translateX(-1.75%);
    }
    to {
      transform: translateX(146.75%);
    }
  }

  .chispas i {
    position: absolute;
    left: 0;
    top: 0;
    width: 2px;
    height: 2px;
    border-radius: 50%;
    background: var(--chispa);
    box-shadow: 0 0 3px var(--chispa);
    opacity: 0;
    animation: chispa 0.55s ease-out calc(1.6s + var(--d)) 5 both;
  }

  .chispas i:nth-child(even) {
    width: 1.5px;
    height: 1.5px;
    background: var(--chispa-2);
    box-shadow: 0 0 3px var(--chispa-2);
  }

  @keyframes chispa {
    0% {
      opacity: 0;
      transform: translate(0, 0) scale(1);
    }
    15% {
      opacity: 1;
    }
    100% {
      opacity: 0;
      transform: translate(var(--x), var(--y)) scale(0.4);
    }
  }

  @keyframes brillo {
    from {
      background-position:
        -85% 0,
        0 0;
    }
    to {
      background-position:
        185% 0,
        0 0;
    }
  }

  @keyframes apagar {
    to {
      opacity: 0;
    }
  }

  .ideas-titulo {
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  .ideas {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 10px;
  }

  .idea {
    display: flex;
    flex-direction: column;
    gap: 10px;
    padding: 14px;
    border: 1px solid var(--borde-tarjeta);
    border-radius: 14px;
    background: var(--solido);
    color: var(--texto);
    text-align: left;
  }

  .idea:hover:not(:disabled) {
    border-color: var(--linea-fuerte);
  }

  .idea:disabled {
    opacity: 0.45;
    cursor: default;
  }

  .idea-cabeza {
    display: flex;
    align-items: center;
    justify-content: space-between;
    color: var(--suave);
  }

  .cuadro-icono {
    width: 32px;
    height: 32px;
    display: grid;
    place-items: center;
    border-radius: 9px;
    background: var(--chip);
    color: var(--texto);
  }

  .idea b {
    display: block;
    font-size: 13.5px;
    font-weight: 700;
  }

  .idea-texto {
    font-size: 12.5px;
    line-height: 1.45;
    color: var(--suave);
  }

  .candado {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 7px;
    font-size: 12px;
    color: var(--tenue);
  }

  .candado-abajo {
    position: relative;
    z-index: 1;
    flex: none;
    padding: 0 32px 16px;
  }

  .chat {
    flex: 1;
    width: 100%;
    max-width: 720px;
    margin: 0 auto;
    padding: 40px 52px 24px;
    display: flex;
    flex-direction: column;
    gap: 22px;
  }

  .burbuja {
    flex: none;
    align-self: flex-end;
    max-width: 80%;
    padding: 10px 16px;
    border-radius: 10px;
    background: var(--burbuja);
    font-size: 14.5px;
    line-height: 1.5;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }

  .error {
    flex: none;
    min-width: 0;
  }

  .abajo {
    position: sticky;
    bottom: 0;
    z-index: 1;
    padding: 12px 32px 16px;
    background: var(--fondo);
  }

  .ancho {
    max-width: 656px;
    margin: 0 auto;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  @media (prefers-reduced-motion: reduce) {
    .subrayada::after {
      animation: none;
      opacity: 0;
    }

    .chispas {
      display: none;
    }

    .brillo,
    h1 {
      animation: none;
    }

    .aparece,
    .bienvenida.abierta .aparece {
      transform: none;
      transition: none;
    }
  }
</style>
