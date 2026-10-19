<!--
  El Agente IA del gerente (libreta 1; maqueta Agente IA KznKZdgQbLTZGs1EwVMvga, copiada de la
  vista de Flet del 28 de septiembre). Sobre su fondo de manchas, que es solo de esta vista:
  - la bienvenida: la fecha y la hora del restaurante (las da Postgres, nunca el reloj del
    aparato), el saludo por la hora con su nombre y, debajo, el renglón que escribe la IA (el de
    reserva, para que salga al instante; si no hay, el local, sin aviso), la caja, las 3 ideas y
    el selector Hoy · Semana · Mes;
  - la conversación: cada pregunta en su burbuja y cada respuesta en Markdown, renglón por
    renglón, con «Pensando…» mientras tanto; a la derecha, «Lo que leí para responder» de la
    última respuesta, en palabras, como lo mandó cada herramienta de Postgres.
  Cada número de una respuesta sale de una herramienta de Postgres: aquí no se cuenta nada.

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
  import FondoDithering from '../../diseno/FondoDithering.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import { ICONOS } from '../../diseno/iconos';
  import Integral from '../../diseno/Integral.svelte';
  import Vidrio from '../../diseno/Vidrio.svelte';
  import {
    guardarConversacion,
    IDEAS,
    leerConversaciones,
    leerEstadoIa,
    leerZonaYCorte,
    prepararSaludo,
    preguntar,
    SALUDO_LOCAL,
    tomarSaludo,
    type Conversacion,
    type EstadoIa,
    type Periodo,
    type SinTope,
    type Turno,
  } from '../../lib/agente';
  import { SIN_CONEXION } from '../../lib/errores';
  import { diaYMes, fechaLarga, saludoPorHora } from '../../lib/formato';
  import type { Sucursal } from '../../lib/gerente';
  import CajaSucursales from './CajaSucursales.svelte';
  import CajaPregunta from './agente/CajaPregunta.svelte';
  import Historial from './agente/Historial.svelte';
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
  // La que no se pudo contestar: su burbuja se queda con el aviso y vuelve a la caja.
  let fallo = $state<(Pedido & { id: string; mensaje: string }) | null>(null);
  // La respuesta que acaba de llegar sale renglón por renglón; las demás, enteras.
  let nueva = $state<{ id: string; turno: number } | null>(null);
  let valor = $state('');
  let periodo = $state<Periodo>('hoy');
  let placeholder = $state(PH_BIENVENIDA);
  let mensajes = $state<HTMLDivElement | null>(null);
  let caja = $state<{ enfocar: () => void } | null>(null);

  const sinTope = $derived(estado && !estado.puede ? estado : null);
  const ocupado = $derived(pendiente !== null);
  const enChat = $derived(actual !== null);
  const titulo = $derived(actual?.titulo ?? 'Agente IA');

  // El aviso de la libreta de Seguridad, según por qué no puede y quién le vende.
  function textoTope(e: SinTope): string {
    if (e.motivo === 'sin_ia') {
      return e.con_distribuidor
        ? 'La IA todavía no está activa en tu restaurante. Pídele a tu distribuidor que la active.'
        : 'La IA todavía no está activa en tu restaurante. Escríbele a Fragmentless para que la active.';
    }
    const vuelve = e.vuelve ? `Vuelve el ${diaYMes(e.vuelve)}` : 'Vuelve el próximo mes';
    return e.con_distribuidor
      ? `Llegaste al límite de IA de este mes. ${vuelve} o pídele a tu distribuidor que lo suba.`
      : `Llegaste al límite de IA de este mes. ${vuelve} o escríbele a Fragmentless para que lo suba.`;
  }

  // Lo que leyó para la última respuesta de la conversación abierta, si no hay otra esperando.
  const leido = $derived.by(() => {
    if (!actual || (pendiente && pendiente.id === actual.id) || (fallo && fallo.id === actual.id)) return null;
    return actual.turnos.at(-1)?.leido ?? null;
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
    const burbujas = mensajes?.querySelectorAll('.burbuja');
    const ultima = burbujas?.[burbujas.length - 1] as HTMLElement | undefined;
    if (mensajes && ultima) mensajes.scrollTo({ top: ultima.offsetTop - 32, behavior: 'smooth' });
  }

  async function enviar(p: Pedido) {
    if (pendiente || sinTope) return;
    const base: Conversacion = actual ?? { id: crypto.randomUUID(), titulo: p.visible, fecha: '', hora: '', turnos: [] };
    actual = base;
    fallo = null;
    nueva = null;
    pendiente = { ...p, id: base.id };
    irALaPregunta();

    try {
      const r = await preguntar(sucursal.id, p.pregunta, base.turnos, periodo);
      if (r.tipo === 'sin_tope') {
        // Se acabó el tope antes de preguntar: la caja dice el aviso y la pregunta no se hizo.
        estado = r.estado;
        if (actual?.id === base.id && !base.turnos.length) actual = null;
        return;
      }
      // La conversación como está guardada (pudo cambiar de vista mientras tanto).
      const antes = conversaciones.find((c) => c.id === base.id) ?? base;
      const turno: Turno = { visible: p.visible, pregunta: p.pregunta, respuesta: r.respuesta, leido: r.leido, idea: p.idea };
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
      pendiente = null;
      await tick();
      if (fallo || nueva) irALaPregunta();
      caja?.enfocar();
    }
  }

  // Lo escrito en la caja. Si es la que no se pudo contestar, se manda igual que la primera vez.
  function enviarLoEscrito() {
    const texto = valor.trim();
    if (!texto) return;
    const otraVez = fallo && fallo.id === actual?.id && fallo.visible === texto ? fallo : null;
    valor = '';
    enviar(otraVez ?? { visible: texto, pregunta: texto, idea: null });
  }

  function usarIdea(i: number) {
    const idea = IDEAS[i];
    enviar({ visible: idea.titulo, pregunta: idea.prompt, idea: i });
  }

  function nuevaConversacion() {
    actual = null;
    fallo = null;
    nueva = null;
    valor = '';
    placeholder = PH_BIENVENIDA;
  }

  async function abrirConversacion(c: Conversacion) {
    actual = c;
    fallo = null;
    nueva = null;
    valor = '';
    await tick();
    mensajes?.scrollTo({ top: mensajes.scrollHeight });
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

<FondoDithering />

<BarraArriba {titulo} estado={{ texto: 'Leyendo tus ventas en vivo', vivo: true }}>
  <Historial {conversaciones} actual={actual?.id ?? null} hoy={sucursal.hoy} alAbrir={abrirConversacion} />
  <Boton etiqueta="Nueva conversación" icono="mas" tono="tinta" onclick={nuevaConversacion} />
  <CajaSucursales {sucursales} actual={sucursal} {alElegir} />
</BarraArriba>

{#if !enChat}
  <main class="centro">
    {#if listo}
      <Vidrio como="section" class="bienvenida" radio={30} aria-label="Bienvenida">
        <div class="cabeza">
          <div class="fecha">
            <span class="logo"><Integral ancho={20} alto={22} /></span>
            <span class="etiqueta">{fechaLarga(sucursal.hoy)}</span>
          </div>
          <h1 class="saludo">{saludoPorHora(sucursal.hora)}, {nombre}.<span>{segundo}</span></h1>
        </div>

        <CajaPregunta
          bind:this={caja}
          modo="bienvenida"
          bind:valor
          bind:periodo
          {placeholder}
          {ocupado}
          aviso={sinTope ? textoTope(sinTope) : null}
          alEnviar={enviarLoEscrito}
        />

        <div class="ideas-caja">
          <span class="etiqueta">IDEAS PARA TI</span>
          <div class="ideas">
            {#each IDEAS as idea, i (idea.titulo)}
              <button
                type="button"
                class="idea"
                disabled={!!sinTope || ocupado}
                onclick={() => usarIdea(i)}
                onmouseenter={() => (placeholder = idea.prompt)}
                onmouseleave={() => (placeholder = PH_BIENVENIDA)}
              >
                <span class="idea-cabeza">
                  <span class="cuadro-icono"><Icono nombre={idea.icono} tamano={18} /></span>
                  <span class="flecha"><Icono nombre="derecha" tamano={16} /></span>
                </span>
                <span class="idea-textos">
                  <span class="idea-titulo">{idea.titulo}</span>
                  <span class="idea-texto">{idea.texto}</span>
                </span>
              </button>
            {/each}
          </div>
        </div>

        <div class="pie">
          <Icono nombre="candado" tamano={14} />
          Solo responde sobre tu negocio. Las cifras salen de tus ventas cerradas.
        </div>
      </Vidrio>
    {/if}
  </main>
{:else if actual}
  <Vidrio como="main" class="chat-agente" radio={26} aria-label="Conversación">
    <div class="mensajes" bind:this={mensajes}>
      {#each actual.turnos as t, i (i)}
        <div class="burbuja">{t.visible}</div>
        <Respuesta
          texto={t.respuesta}
          nueva={nueva?.id === actual.id && nueva.turno === i}
          seguimiento={t.idea !== null ? (IDEAS[t.idea]?.seguimiento ?? []) : []}
          apagado={ocupado || !!sinTope}
          alSeguir={(s) => enviar({ visible: s.etiqueta, pregunta: s.pregunta, idea: null })}
        />
      {/each}
      {#if pendiente && pendiente.id === actual.id}
        <div class="burbuja">{pendiente.visible}</div>
        <div class="pensando" role="status">
          <span class="logo"><Integral ancho={20} alto={22} pensando /></span>
          <span class="pensando-texto">Pensando…</span>
        </div>
      {:else if fallo && fallo.id === actual.id}
        <div class="burbuja">{fallo.visible}</div>
        <div class="resp-error">
          <span class="logo"><Integral ancho={20} alto={22} /></span>
          <div class="error"><CajaError mensaje={fallo.mensaje} /></div>
        </div>
      {/if}
    </div>
    <div class="chat-caja">
      <CajaPregunta
        bind:this={caja}
        modo="chat"
        bind:valor
        bind:periodo
        placeholder={PH_CHAT}
        {ocupado}
        aviso={sinTope ? textoTope(sinTope) : null}
        alEnviar={enviarLoEscrito}
      />
    </div>
  </Vidrio>

  <Vidrio como="section" class="leido-agente" radio={22} aria-label="Lo que leí para responder">
    <span class="etiqueta">LO QUE LEÍ PARA RESPONDER</span>
    {#if leido === null}
      <p class="leido-vacio">Aquí verás lo que calculé para responderte.</p>
    {:else if !leido.length}
      <p class="leido-vacio">Para esta respuesta no hice cálculos.</p>
    {:else}
      {#each leido as l (l.texto)}
        <div class="leido-fila">
          <span class="leido-icono"><Icono nombre={l.icono in ICONOS ? l.icono : 'datos'} tamano={16} /></span>
          <span>{l.texto}</span>
        </div>
      {/each}
    {/if}
    <div class="raya"></div>
    <p class="leido-nota">{notaLeido}</p>
  </Vidrio>
{/if}

<style>
  /* Debajo de la barra de arriba (16 + 60 + 16) y a la derecha de la lateral (16 + 244 + 16). */
  .centro {
    position: absolute;
    left: 276px;
    right: 16px;
    top: 92px;
    bottom: 16px;
    z-index: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    overflow-y: auto;
  }

  .centro > :global(.bienvenida) {
    width: 780px;
    flex: none;
    margin: auto 0;
    padding: 40px 40px 28px;
    display: flex;
    flex-direction: column;
    gap: 28px;
  }

  .cabeza {
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  .fecha {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .logo {
    width: 30px;
    height: 30px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--acento);
  }

  .fecha .etiqueta {
    font-size: 11.5px;
  }

  .saludo {
    margin: 0;
    font-size: 50px;
    font-weight: 800;
    line-height: 1.04;
    letter-spacing: -1.25px;
  }

  .saludo span {
    display: block;
    color: var(--tenue);
  }

  .ideas-caja {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .ideas {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 12px;
  }

  .idea {
    display: flex;
    flex-direction: column;
    gap: 14px;
    padding: 16px;
    border-radius: 18px;
    border: 1px solid var(--linea);
    background: var(--solido);
    color: var(--texto);
    text-align: left;
    transition: border-color 150ms;
  }

  .idea:hover:not(:disabled) {
    border-color: var(--tenue);
  }

  .idea:disabled {
    opacity: 0.45;
    cursor: default;
  }

  .idea-cabeza {
    width: 100%;
    display: flex;
    align-items: center;
    justify-content: space-between;
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

  .flecha {
    color: var(--tenue);
    opacity: 0;
    transition: opacity 150ms;
  }

  .idea:hover:not(:disabled) .flecha {
    opacity: 1;
  }

  .idea-textos {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .idea-titulo {
    font-size: 14.5px;
    font-weight: 700;
  }

  .idea-texto {
    font-size: 12.5px;
    line-height: 1.45;
    color: var(--suave);
  }

  .pie {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 12px;
    color: var(--tenue);
  }

  :global(.chat-agente) {
    position: absolute;
    left: 276px;
    top: 92px;
    bottom: 16px;
    z-index: 1;
    width: 812px;
    display: flex;
    flex-direction: column;
  }

  .mensajes {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    padding: 32px 40px 16px;
    display: flex;
    flex-direction: column;
    gap: 26px;
    scrollbar-width: thin;
  }

  .burbuja {
    flex: none;
    align-self: flex-end;
    max-width: 460px;
    padding: 12px 18px;
    border-radius: 18px 18px 6px 18px;
    background: var(--tinta);
    color: var(--sobre-tinta);
    font-size: 14.5px;
    line-height: 1.5;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }

  .pensando {
    flex: none;
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .pensando-texto {
    font-size: 14px;
    font-weight: 500;
    color: var(--suave);
  }

  .resp-error {
    flex: none;
    display: flex;
    gap: 12px;
  }

  .error {
    flex: 1;
    min-width: 0;
    padding-top: 2px;
  }

  .chat-caja {
    flex: none;
    padding: 0 24px 24px;
  }

  :global(.leido-agente) {
    position: absolute;
    left: 1104px;
    right: 16px;
    top: 92px;
    z-index: 1;
    padding: 20px;
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  .leido-fila {
    display: flex;
    align-items: flex-start;
    gap: 10px;
    font-size: 13px;
    line-height: 1.45;
  }

  .leido-icono {
    margin-top: 1px;
    color: var(--tenue);
  }

  .raya {
    height: 1px;
    flex: none;
    background: var(--linea);
  }

  .leido-nota {
    margin: 0;
    font-size: 12.5px;
    line-height: 1.5;
    color: var(--suave);
  }

  .leido-vacio {
    margin: 0;
    font-size: 13px;
    line-height: 1.45;
    color: var(--tenue);
  }

  @media (prefers-reduced-motion: reduce) {
    .idea,
    .flecha {
      transition: none;
    }
  }
</style>
