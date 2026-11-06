<!--
  El Agente IA del gerente (libreta 1; rediseño del 5 de noviembre de 2026, encuestas 17 a 22; maqueta
  V64Pv4gmANPRZuJW5hTe5D). Tranquilo, como Claude: la vista entra en blanco y al picarle a un espacio vacío
  del fondo sale la ondita.
  - la bienvenida, al centro de la pantalla: el saludo por la hora con su nombre y la fecha (las da Postgres,
    nunca el reloj del aparato), en grande el renglón que escribe la IA (el de reserva, para que salga al
    instante; si no hay, el local, sin aviso) con su última palabra subrayada, la caja, las 3 ideas y el
    candado. Al pasar sobre una idea cambia el texto de la caja; al picarla, se escribe. Lo que se le manda
    al agente es su prompt largo, no lo que se ve;
  - la conversación: cada pregunta en su globo gris y cada respuesta en Markdown, renglón por renglón, con
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
  import { diaConNombre, saludoPorHora } from '../../lib/formato';
  import type { Sucursal } from '../../lib/gerente';
  import { prepararReporte, tituloDelPedido, type PeriodoReporte } from '../../lib/reporte';
  import CajaSucursales from './CajaSucursales.svelte';
  import ArchivoReporte from './agente/ArchivoReporte.svelte';
  import CajaPregunta from './agente/CajaPregunta.svelte';
  import Historial from './agente/Historial.svelte';
  import Ondita from './agente/Ondita.svelte';
  import Respuesta from './agente/Respuesta.svelte';

  let {
    sucursal,
    sucursales,
    nombre,
    alElegir,
  }: {
    sucursal: Sucursal;
    sucursales: Sucursal[];
    nombre: string;
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
  let ondita = $state<{ picar: (e: MouseEvent) => void } | null>(null);

  const sinTope = $derived(estado && !estado.puede ? estado : null);
  const ocupado = $derived(pendiente !== null || reporteEnCamino !== null);
  const pensandoAqui = $derived(pendiente !== null && pendiente.id === actual?.id);

  // La fecha va en minúscula después del nombre: «Buenas tardes, Don Chuy · jueves 5 de noviembre».
  const linea1 = $derived.by(() => {
    const dia = diaConNombre(sucursal.hoy);
    return `${saludoPorHora(sucursal.hora)}, ${nombre} · ${dia.charAt(0).toLowerCase()}${dia.slice(1)}`;
  });

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

  // La ondita sale solo en lo vacío del fondo.
  function alPicar(e: MouseEvent) {
    if ((e.target as Element).closest('button, textarea, input, a, .caja-pregunta, .idea, .burbuja, .respuesta, .piensa, .error, .abajo')) return;
    ondita?.picar(e);
  }

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
  <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_noninteractive_element_interactions -->
  <section class="agente" aria-label="Agente IA" onclick={alPicar}>
    <Ondita bind:this={ondita} />

    {#if !actual}
      {#if listo}
        <div class="bienvenida">
          <div class="linea1">{linea1}</div>
          <h1>{frase.inicio}<span class="subrayada">{frase.ultima}</span></h1>

          <CajaPregunta
            bind:this={caja}
            modo="bienvenida"
            bind:valor
            {placeholder}
            {ocupado}
            aviso={sinTope ? textoSinTope(sinTope) : null}
            alEnviar={enviarLoEscrito}
            alReporte={pedirReporte}
          />

          <div class="etiqueta ideas-titulo">Ideas para ti</div>
          <div class="ideas">
            {#each IDEAS as idea, i (idea.titulo)}
              <button
                type="button"
                class="idea"
                disabled={!!sinTope || ocupado}
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

          <div class="candado">
            <Icono nombre="r-candado" tamano={14} />
            Solo responde sobre tu negocio. Las cifras salen de tus ventas cerradas.
          </div>
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
          <Pensando texto="Pensando…" {pasos} {segundos} color="var(--punto-panel)" />
        {:else if reporteEnCamino && reporteEnCamino.id === actual.id}
          <div class="burbuja">{reporteEnCamino.visible}</div>
          <Pensando texto="Armando tu reporte…" pasos={[]} color="var(--punto-panel)" />
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

  .agente {
    position: relative;
    min-height: 100%;
    display: flex;
    flex-direction: column;
    font-weight: 400;
  }

  .bienvenida,
  .chat {
    position: relative;
    z-index: 1;
  }

  .bienvenida {
    width: 100%;
    max-width: 720px;
    margin: auto;
    padding: 40px 32px 56px;
    display: flex;
    flex-direction: column;
    gap: 22px;
  }

  .linea1 {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 9px;
    font-size: 13px;
    color: var(--suave);
  }

  h1 {
    margin: -10px 0 0;
    text-align: center;
    text-wrap: balance;
    font-size: 34px;
    font-weight: 700;
    letter-spacing: -0.7px;
    line-height: 1.15;
  }

  /* La última palabra: una raya gris por la que pasa dos veces un brillo con la parte viva del degradado
     de la estrella; luego la raya se borra. */
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
      linear-gradient(90deg, transparent, var(--estrella-2) 18%, var(--estrella-3) 48%, var(--estrella-4) 76%, transparent) no-repeat,
      var(--linea-fuerte);
    background-size:
      45% 100%,
      100% 100%;
    background-position:
      -85% 0,
      0 0;
    animation:
      brillo 1.3s ease-in-out 0.35s 2,
      apagar 0.5s ease 2.95s forwards;
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

  .chat {
    flex: 1;
    width: 100%;
    max-width: 720px;
    margin: 0 auto;
    padding: 40px 32px 24px;
    display: flex;
    flex-direction: column;
    gap: 22px;
  }

  .burbuja {
    flex: none;
    align-self: flex-end;
    max-width: 80%;
    padding: 10px 16px;
    border-radius: 18px;
    background: var(--chip);
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
  }
</style>
