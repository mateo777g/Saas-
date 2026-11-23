<!--
  La tarjeta de lealtad, la cuarta pestaña de abajo (parte B; maqueta v22 aprobada el 23 nov 2026, `vista_menu.py`). Como Tu
  pedido: la barra del restaurante, su cabeza, lo de adentro que se desliza y, cuando hay algo que hacer, el pie fijo con el
  botón en el color del restaurante. Sus pasos cambian dentro de la vista:
  · sin tarjeta, la presentación (la tarjeta vacía, el premio y «¿Cómo funciona?» en tres pasos) y luego sus datos (nombre,
    teléfono y «Tu privacidad» con el aviso corto y la casilla); si ese número ya tiene tarjeta, «Ya hay una tarjeta»;
  · recuperarla: su número y luego el código de 6 letras que confirma quien cobra, con lo que falta para que venza;
  · con tarjeta: la tarjeta que se voltea (su QR atrás), el aviso del premio listo, «Más de tu tarjeta» (Tu premio, Cómo
    funciona y Tu historial, cada uno en su ventanita que crece del círculo) y «Tu privacidad» (el aviso y «Borrar mi
    tarjeta», en dos tarjetas que se deslizan).
  Apagada, quien ya la tiene la sigue viendo y la puede borrar (migración tarjeta_lealtad, «Lo que decidí yo» 6). Todo pasa
  por el Worker (lib/tarjeta.svelte.ts); sacarla y pedir el código llevan la revisión de Cloudflare.
-->
<script lang="ts">
  import TarjetaLealtad from '@app/diseno/TarjetaLealtad.svelte';
  import { onDestroy, tick, untrack, type Snippet } from 'svelte';
  import { AVISO_CORTO_TARJETA, LO_JUNTADO } from '../lib/aviso';
  import type { Formas } from '../lib/formas';
  import { quieto } from '../lib/movimiento';
  import { enlaceWhatsApp } from '../lib/pedido';
  import type { MiTarjeta } from '../lib/tarjeta.svelte';
  import { NoSalio } from '../lib/tarjeta.svelte';
  import type { Lengua, Textos } from '../lib/textos';
  import { diaCorto, type Regla, type TextosDeTarjeta } from '../lib/textosTarjeta';
  import { pedirToken, quitarRevision } from '../lib/turnstile';
  import Icono from './Icono.svelte';
  import VentanaCrece from './VentanaCrece.svelte';
  import '../tarjeta.css';

  let {
    mi,
    regla,
    tt,
    t,
    lengua,
    formas,
    restaurante,
    logo,
    telefono,
    barra,
    deMuestra = false,
    alAviso,
    alUsarPremio,
  }: {
    mi: MiTarjeta;
    // null = apagada (su dueña la sigue viendo y la puede borrar).
    regla: Regla | null;
    tt: TextosDeTarjeta | null;
    t: Textos;
    lengua: Lengua;
    formas: Formas;
    restaurante: string;
    logo: string | null;
    // El WhatsApp del restaurante (para mandar el código).
    telefono: string | null;
    barra: Snippet;
    deMuestra?: boolean;
    alAviso: (desde: HTMLElement) => void;
    // «Usarlo en mi pedido»: va a Tu pedido con el premio puesto.
    alUsarPremio: () => void;
  } = $props();

  type Paso = 'sacar' | 'datos' | 'existe' | 'recuperar' | 'codigo' | 'tarjeta';
  let paso = $state<Paso>(untrack(() => (mi.estado === 'con' ? 'tarjeta' : mi.estado === 'esperando' ? 'codigo' : 'sacar')));
  // Lo que leyó el Worker manda: con tarjeta, la tarjeta; esperando, el código.
  $effect(() => {
    if (mi.estado === 'con') paso = 'tarjeta';
    else if (mi.estado === 'esperando') paso = 'codigo';
    else if (mi.estado === 'sin' && (paso === 'tarjeta' || paso === 'codigo')) paso = 'sacar';
  });

  let nombre = $state('');
  let tel = $state('');
  let acepta = $state(false);
  let telRecuperar = $state('');
  let ocupado = $state(false);
  let aviso = $state<string | null>(null);
  let volteada = $state(false);
  let hueco = $state<HTMLDivElement>();
  let dentro = $state<HTMLDivElement>();

  const premioListo = $derived(!!mi.tarjeta?.premio_listo);
  const soloDigitos = (x: string) => x.replace(/\D/g, '');
  const telOk = (x: string) => soloDigitos(x).length === 10;
  const escrito = (x: string) => soloDigitos(x).replace(/(\d{3})(\d{3})(\d{4})/, '$1 $2 $3');

  async function irA(p: Paso) {
    aviso = null;
    paso = p;
    await tick();
    dentro?.parentElement?.scrollTo({ top: 0 });
    subir();
  }

  // Lo de adentro sube, uno tras otro, al cambiar de paso (como al abrir la vista).
  function subir() {
    if (quieto() || !dentro) return;
    [...dentro.querySelectorAll<HTMLElement>(':scope > .tl-estado > *, :scope > .f-ped-cabeza')].forEach((el, i) =>
      el.animate([{ opacity: 0, transform: 'translateY(14px)' }, { opacity: 1, transform: 'none' }], {
        duration: 320,
        delay: 40 * i,
        easing: 'cubic-bezier(0.22, 1, 0.36, 1)',
        fill: 'backwards',
      }),
    );
  }

  function noSalio(e: unknown) {
    aviso = e instanceof NoSalio ? e.message : (tt?.sinRed ?? '');
  }

  async function sacar() {
    if (!tt || ocupado) return;
    if (deMuestra) return;
    ocupado = true;
    aviso = null;
    try {
      const token = await pedirToken(hueco!, lengua);
      const r = await mi.sacar(nombre.trim(), soloDigitos(tel), acepta, token, tt.sinRed);
      if (r.ok) {
        volteada = false;
        await irA('tarjeta');
      } else if (r.motivo === 'ya_existe') {
        telRecuperar = tel;
        await irA('existe');
      } else if (r.motivo === 'no_hay') aviso = tt.apagada;
      else aviso = tt.limite;
    } catch (e) {
      noSalio(e);
    } finally {
      ocupado = false;
    }
  }

  async function pedirCodigo() {
    if (!tt || ocupado || deMuestra) return;
    ocupado = true;
    aviso = null;
    try {
      const token = await pedirToken(hueco!, lengua);
      const r = await mi.pedirCodigo(soloDigitos(telRecuperar), token, tt.sinRed);
      if (r.ok) await irA('codigo');
      else if (r.motivo === 'sin_tarjeta') aviso = tt.sinTarjeta;
      else if (r.motivo === 'no_hay') aviso = tt.apagada;
      else aviso = tt.limite;
    } catch (e) {
      noSalio(e);
    } finally {
      ocupado = false;
    }
  }

  // ─── Esperando que confirmen el código: el reloj y, cada 4 segundos, si ya llegó ───
  let ahora = $state(Date.now());
  const vence = $derived(mi.guardada?.esperando ? Date.parse(mi.guardada.esperando.vence) : 0);
  const quedan = $derived(Math.max(0, Math.floor((vence - ahora) / 1000)));
  const reloj = $derived(`${Math.floor(quedan / 60)}:${String(quedan % 60).padStart(2, '0')}`);
  $effect(() => {
    if (paso !== 'codigo' || mi.estado !== 'esperando' || !tt) return;
    const sinRed = tt.sinRed;
    let vueltas = 0;
    const id = setInterval(() => {
      ahora = Date.now();
      if (++vueltas % 4 === 0) void mi.leer(sinRed);
    }, 1000);
    return () => clearInterval(id);
  });
  // Venció sin que lo confirmaran: se olvida y se pide otro.
  $effect(() => {
    if (paso === 'codigo' && mi.estado === 'esperando' && vence && quedan === 0 && tt) {
      mi.olvidar();
      aviso = tt.vencio;
      paso = 'recuperar';
    }
  });
  const codigoEspera = $derived(mi.guardada?.esperando?.codigo ?? '');

  // ─── Las ventanitas: Tu premio, Cómo funciona, Tu historial y «¿Borrar tu tarjeta?» ───
  type Ventana = 'premio' | 'como' | 'historial' | 'borrar';
  let abierta = $state<{ cual: Ventana; desde: HTMLElement } | null>(null);
  let pasoBorrar = $state<'pregunta' | 'borrada'>('pregunta');
  let historialLeido = $state(false);
  let historialMal = $state(false);

  async function abrir(cual: Ventana, desde: HTMLElement) {
    pasoBorrar = 'pregunta';
    abierta = { cual, desde };
    // El historial se lee de nuevo al abrirlo (por el Worker): lleva su esqueleto mientras llega.
    if (cual === 'historial' && tt) {
      historialLeido = false;
      historialMal = false;
      if (!deMuestra) await mi.leer(tt.sinRed);
      historialMal = mi.estado !== 'con';
      historialLeido = true;
    }
  }
  function cerrar() {
    abierta = null;
  }

  async function borrar() {
    if (!tt || ocupado) return;
    if (deMuestra) return void (pasoBorrar = 'borrada');
    ocupado = true;
    try {
      if (await mi.borrar(tt.sinRed)) pasoBorrar = 'borrada';
    } catch (e) {
      noSalio(e);
      cerrar();
    } finally {
      ocupado = false;
    }
  }

  // ─── «Tu privacidad»: las dos tarjetas que se deslizan, con su puntito ───
  let carril = $state<HTMLDivElement>();
  let hoja = $state(0);
  function alDeslizar() {
    if (!carril) return;
    hoja = carril.scrollLeft > carril.scrollWidth / 4 ? 1 : 0;
  }
  function aHoja(i: number) {
    const h = carril?.children[i] as HTMLElement | undefined;
    if (h && carril) carril.scrollTo({ left: i ? carril.scrollWidth : 0, behavior: quieto() ? 'auto' : 'smooth' });
  }

  const avisoCorto = $derived(
    regla ? AVISO_CORTO_TARJETA[lengua].replace('{nombre}', restaurante).replace('{lo_juntado}', LO_JUNTADO[lengua][regla.forma]) : '',
  );
  const atras = $derived(
    mi.tarjeta && mi.guardada
      ? { restaurante, logo, titular: mi.tarjeta.nombre, telefono: mi.tarjeta.telefono, codigo: mi.guardada.codigo, llave: mi.guardada.llave }
      : null,
  );

  onDestroy(() => {
    if (!deMuestra) quitarRevision();
  });

  function aparece(_el: Element) {
    if (quieto()) return { duration: 0 };
    return { duration: 180, css: (x: number) => `opacity: ${x}` };
  }
</script>

{#snippet seccion(titulo: string, clase: string, cuerpo: Snippet)}
  <section class="f-ped-seccion {clase}"><h3>{titulo}</h3>{@render cuerpo()}</section>
{/snippet}

{#snippet privacidad()}
  {#if tt}
    <section class="f-ped-seccion tl-otros">
      <h3>{tt.privH}</h3>
      <div class="tl-deslizan" role="group" aria-label={tt.privH}>
        <div class="tl-carril" bind:this={carril} onscroll={alDeslizar}>
          <div class="tl-hoja">
            <div class="tl-hoja-cab"><span class="tl-hoja-i"><Icono nombre="candado" tamano={19} grosor={1.9} /></span><b>{tt.privB}</b></div>
            <p>{tt.privS}</p>
            <button type="button" class="f-info-ir" onclick={(e) => alAviso(e.currentTarget)}>{tt.privIr}<Icono nombre="flechita" tamano={18} grosor={2} /></button>
          </div>
          <div class="tl-hoja">
            <div class="tl-hoja-cab"><span class="tl-hoja-i"><Icono nombre="bote" tamano={19} grosor={1.9} /></span><b>{tt.borraB}</b></div>
            <p>{tt.borraS}</p>
            <button type="button" class="f-info-ir tl-rojo-lleno" onclick={(e) => abrir('borrar', e.currentTarget)}>{tt.borraB}</button>
          </div>
        </div>
        <div class="tl-puntitos">
          {#each [0, 1] as i (i)}
            <button type="button" aria-label={tt.aLaTarjeta(i + 1)} aria-current={hoja === i} onclick={() => aHoja(i)}></button>
          {/each}
        </div>
      </div>
    </section>
  {/if}
{/snippet}

<section
  class="f-ped tl-vista"
  class:f-asis-pildora={formas.abajo === 'pildora'}
  class:f-asis-chica={!formas.abajo_con_nombres}
  data-tl={paso}
  aria-label={tt?.vistaT ?? ''}
  in:aparece
>
  {@render barra()}

  <div class="f-asis-cuerpo f-ped-cuerpo">
    <div class="f-ped-dentro" bind:this={dentro}>
      {#if mi.estado === 'leyendo'}
        <!-- La primera vez que lee su tarjeta: su lugar y el de los atajos, del mismo tamaño. -->
        <div class="tl-estado" aria-busy="true">
          <span class="tl-esq tl-esq-titulo"></span>
          <span class="tl-esq tl-esq-tarjeta"></span>
          <span class="tl-esq tl-esq-renglon"></span>
          <span class="visually-hidden">{tt?.vistaT}</span>
        </div>
      {:else if mi.estado === 'error'}
        <div class="f-ped-vacio nada">
          <h2>{tt?.vistaT}</h2>
          <p>{tt?.noSeLeyo}</p>
          <button type="button" class="f-ped-ir suave corto" onclick={() => tt && mi.leer(tt.sinRed)}>{tt?.otraVezB}</button>
        </div>
      {:else if !regla || !tt}
        <!-- Apagada: su tarjeta se queda; solo se ve que está en pausa y se puede borrar. -->
        <div class="f-ped-cabeza"><h2>{tt?.vistaT ?? ''}</h2></div>
        <div class="tl-estado">
          <p class="tl-datos-p">{tt?.apagada}</p>
          {@render privacidad()}
        </div>
      {:else}
        <div class="f-ped-cabeza">
          {#if paso !== 'sacar' && paso !== 'tarjeta'}
            <button
              type="button"
              class="tl-volver"
              aria-label={tt.atras}
              onclick={() => irA(paso === 'datos' ? 'sacar' : paso === 'existe' ? 'datos' : paso === 'recuperar' ? 'sacar' : 'recuperar')}
              ><Icono nombre="anterior" tamano={20} grosor={2.2} /></button
            >
          {/if}
          <h2>
            {paso === 'tarjeta' ? tt.vistaT : paso === 'datos' ? tt.datosT : paso === 'existe' ? tt.existeT : paso === 'recuperar' ? tt.recuperarT : paso === 'codigo' ? tt.codigoT : tt.sinT}
          </h2>
          {#if paso === 'tarjeta' && mi.tarjeta}
            {#if premioListo}<span class="tl-verde">{tt.cuentaListo}</span>{:else}<span>{tt.cuenta(mi.tarjeta.saldo)}</span>{/if}
          {/if}
        </div>

        {#if paso === 'sacar'}
          <div class="tl-estado">
            <div class="tl-lugar-tarjeta tl-muestra-menu">
              <TarjetaLealtad estilo={regla.estilo} color={regla.color} forma={regla.forma} meta={regla.meta} saldo={0} premioListo={false} t={tt.tarjeta} />
            </div>
            <p class="tl-lead">{tt.leadCorto}</p>
            {#snippet pasos()}
              <div class="tl-como tl-pasos">
                {#each tt!.pasos as [b, x], i (i)}
                  <div class="tl-como-fila"><span class="tl-como-i tl-num">{i + 1}</span><span class="t"><b>{b}</b><span>{x}</span></span></div>
                {/each}
              </div>
            {/snippet}
            {@render seccion(tt.comoQ, '', pasos)}
          </div>
        {:else if paso === 'datos'}
          <div class="tl-estado">
            <p class="tl-datos-p">{tt.datosP}</p>
            <div class="f-ped-campos">
              <div class="f-campo">
                <label for="tl-nombre">{tt.tuNombre}</label>
                <input id="tl-nombre" bind:value={nombre} maxlength="60" autocomplete="name" />
              </div>
              <div class="f-campo">
                <label for="tl-tel">{tt.telefono}</label>
                <input id="tl-tel" bind:value={tel} inputmode="tel" autocomplete="tel-national" placeholder={t.telefonoEjemplo} />
              </div>
            </div>
            {#snippet priv()}
              <div class="tl-priv">
                <div class="tl-hoja-cab"><span class="tl-hoja-i"><Icono nombre="candado" tamano={19} grosor={1.9} /></span><b>{tt!.privB}</b></div>
                <p>{avisoCorto}</p>
                <label class="tl-casilla"
                  ><input type="checkbox" bind:checked={acepta} />
                  <span>{tt!.acepto[0]}<button type="button" class="tl-liga" onclick={(e) => alAviso(e.currentTarget)}>{tt!.acepto[1]}</button></span></label
                >
              </div>
            {/snippet}
            {@render seccion(tt.privH, '', priv)}
          </div>
        {:else if paso === 'existe'}
          <div class="tl-estado"><p class="tl-datos-p">{tt.existeP}</p></div>
        {:else if paso === 'recuperar'}
          <div class="tl-estado">
            <p class="tl-datos-p">{tt.recuperarP}</p>
            <div class="f-ped-campos">
              <div class="f-campo">
                <label for="tl-tel-r">{tt.telefono}</label>
                <input id="tl-tel-r" bind:value={telRecuperar} inputmode="tel" autocomplete="tel-national" placeholder={t.telefonoEjemplo} />
              </div>
            </div>
          </div>
        {:else if paso === 'codigo'}
          {@const p = tt.codigoP(escrito(telRecuperar || mi.tarjeta?.telefono || ''))}
          <div class="tl-estado">
            <p class="tl-datos-p">{p[0]}<b>{p[1]}</b>{p[2]}</p>
            <div class="tl-codigo-caja">
              <div class="tl-codigo-grande" aria-label={codigoEspera.split('').join(' ')}>
                {#each codigoEspera.split('') as c, i (i)}<span>{c}</span>{/each}
              </div>
              <p class="tl-espera"><i><b></b><b></b><b></b></i>{tt.esperando} · {tt.vence} <span class="tl-vence">{reloj}</span></p>
            </div>
          </div>
        {:else if mi.tarjeta}
          <div class="tl-estado">
            {#if mi.llegada === 'nueva' || mi.llegada === 'pasada'}
              <div class="tl-llegada">
                <Icono nombre="check" tamano={18} grosor={2.2} /><span
                  ><b>{mi.llegada === 'nueva' ? tt.nuevaB : tt.pasadaB}</b>{mi.llegada === 'nueva' ? tt.nuevaS : tt.pasadaS}</span
                >
              </div>
            {/if}
            <div class="tl-lugar-tarjeta">
              <TarjetaLealtad
                estilo={regla.estilo}
                color={regla.color}
                forma={regla.forma}
                meta={regla.meta}
                saldo={mi.tarjeta.saldo}
                {premioListo}
                t={tt.tarjeta}
                {atras}
                llega={mi.llegada !== 'normal'}
                bind:volteada
              />
            </div>
            <p class="tl-pista"><Icono nombre="girar" tamano={15} grosor={2} />{tt.pista}</p>
            {#if premioListo}
              <div class="tl-listo-aviso">
                <span class="tl-listo-i"><Icono nombre="regalo" tamano={20} grosor={1.9} /></span>
                <span class="t"><b>{tt.listoB}</b><span>{tt.listoS}</span></span>
                {#if telefono && regla?.premio.disponible}
                  <button type="button" class="tl-listo-boton" onclick={alUsarPremio}>{tt.usarlo}<Icono nombre="flechita" tamano={16} grosor={2} /></button>
                {/if}
              </div>
            {/if}
            <section class="f-ped-seccion tl-mas">
              <h3>{tt.masH}</h3>
              <div class="tl-atajos">
                <button type="button" class="tl-atajo" aria-haspopup="dialog" onclick={(e) => abrir('premio', e.currentTarget.querySelector('.tl-atajo-i')!)}>
                  <span class="tl-atajo-i"><Icono nombre="regalo" tamano={24} grosor={1.8} />{#if premioListo}<span class="tl-app-punto"></span>{/if}</span>
                  <span class="tl-atajo-t">{tt.premioA}</span>
                </button>
                <button type="button" class="tl-atajo" aria-haspopup="dialog" onclick={(e) => abrir('como', e.currentTarget.querySelector('.tl-atajo-i')!)}>
                  <span class="tl-atajo-i"><Icono nombre="info" tamano={24} grosor={1.8} /></span><span class="tl-atajo-t">{tt.comoH}</span>
                </button>
                <button type="button" class="tl-atajo" aria-haspopup="dialog" onclick={(e) => abrir('historial', e.currentTarget.querySelector('.tl-atajo-i')!)}>
                  <span class="tl-atajo-i"><Icono nombre="historial" tamano={24} grosor={1.8} /></span><span class="tl-atajo-t">{tt.histA}</span>
                </button>
              </div>
            </section>
            {@render privacidad()}
          </div>
        {/if}
      {/if}
      {#if aviso}
        <div class="m-aviso" role="alert"><Icono nombre="alerta" tamano={17} /><span>{aviso}</span></div>
      {/if}
      <!-- La revisión de Cloudflare vive aquí; invisible mientras no duda. -->
      <div class="f-ped-hueco" bind:this={hueco}></div>
    </div>
  </div>

  {#if regla && tt && mi.estado !== 'leyendo' && mi.estado !== 'error'}
    {#if paso === 'sacar'}
      <div class="f-ped-pie tl-pie-m">
        <button type="button" class="f-ped-boton" onclick={() => irA('datos')}>{tt.sacar}</button>
        <button type="button" class="tl-otra" onclick={() => irA('recuperar')}>{tt.yaTienes[0]}<b>{tt.yaTienes[1]}</b></button>
      </div>
    {:else if paso === 'datos'}
      <div class="f-ped-pie tl-pie-m">
        <button type="button" class="f-ped-boton" disabled={!acepta || !nombre.trim() || !telOk(tel) || ocupado} aria-busy={ocupado} onclick={sacar}>{tt.sacar}</button>
      </div>
    {:else if paso === 'existe'}
      <div class="f-ped-pie tl-pie-m">
        <button type="button" class="f-ped-boton" disabled={ocupado} aria-busy={ocupado} onclick={pedirCodigo}>{tt.pasarla}</button>
        <button type="button" class="tl-otra" onclick={() => irA('datos')}>{tt.otraVez}</button>
      </div>
    {:else if paso === 'recuperar'}
      <div class="f-ped-pie tl-pie-m">
        <button type="button" class="f-ped-boton" disabled={!telOk(telRecuperar) || ocupado} aria-busy={ocupado} onclick={pedirCodigo}>{tt.pedir}</button>
      </div>
    {:else if paso === 'codigo' && telefono}
      <div class="f-ped-pie tl-pie-m">
        <a class="f-ped-boton" href={enlaceWhatsApp(telefono, tt.mensajeCodigo(codigoEspera))} target="_blank" rel="noopener"
          ><Icono nombre="mensaje" tamano={18} grosor={1.9} /><span>{tt.mandar}</span></a
        >
      </div>
    {/if}
  {/if}
</section>

{#if abierta && tt}
  {@const a = abierta}
  {#key a}
    <VentanaCrece etiqueta={a.cual === 'borrar' ? tt.borraB : a.cual === 'premio' ? tt.premioA : a.cual === 'como' ? tt.comoH : tt.histA} {t} desde={a.desde} alCerrar={cerrar}>
      {#if a.cual === 'borrar'}
        {#if pasoBorrar === 'pregunta'}
          <div class="dc-cabeza tl-v-cabeza">
            <span class="dc-icono rojo"><Icono nombre="bote" tamano={22} grosor={1.9} /></span>
            <h2>{tt.borrarT}</h2>
            <p>{tt.borrarP(mi.tarjeta?.saldo ?? 0)}</p>
          </div>
          <div class="dc-cuerpo dc-dos">
            <button type="button" class="f-info-ir" onclick={cerrar}>{tt.cancelar}</button>
            <button type="button" class="dc-si" disabled={ocupado} onclick={borrar}>{tt.si}</button>
          </div>
        {:else}
          <div class="dc-cabeza tl-v-cabeza listo" role="status">
            <svg class="dc-palomita" viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <circle class="aro" cx="24" cy="24" r="19"></circle><path class="pal" d="M16 24.5l5.5 5.5L32.5 19"></path>
            </svg>
            <h2>{tt.listoT}</h2>
            <p>{tt.borradaP}</p>
          </div>
        {/if}
      {:else if a.cual === 'premio' && regla}
        {@const saldo = mi.tarjeta?.saldo ?? 0}
        <div class="dc-cabeza tl-v-cabeza" data-sube>
          <span class="dc-icono tl-icono-acento"><Icono nombre="regalo" tamano={22} grosor={1.8} /></span>
          <h2>{tt.premioB}</h2>
          <p>{tt.premioS}</p>
        </div>
        <div class="dc-cuerpo tl-v-cuerpo" data-sube>
          <div class="tl-avance">
            {#if premioListo}
              <span class="tl-avance-fila"><b class="tl-verde">{tt.tarjeta.yaJuntaste}</b><span>{tt.juntaste(saldo)}</span></span>
              <span class="tl-avance-barra llena"><i style:width="100%"></i></span>
            {:else}
              <span class="tl-avance-fila"><b>{tt.llevas(saldo)}</b><span>{tt.falta(Math.max(0, regla.meta - saldo))}</span></span>
              <span class="tl-avance-barra"><i style:width="{Math.min(100, (saldo / regla.meta) * 100)}%"></i></span>
            {/if}
          </div>
          {#if premioListo && telefono && regla?.premio.disponible}
            <button type="button" class="tl-listo-boton" onclick={() => (cerrar(), alUsarPremio())}>{tt.usarlo}</button>
          {/if}
        </div>
      {:else if a.cual === 'como'}
        <div class="dc-cabeza tl-v-cabeza" data-sube>
          <span class="dc-icono tl-icono-acento"><Icono nombre="info" tamano={22} grosor={1.8} /></span>
          <h2>{tt.comoH}</h2>
        </div>
        <div class="dc-cuerpo tl-v-cuerpo" data-sube>
          <div class="tl-como">
            {#each tt.como as [icono, b, s], i (i)}
              <div class="tl-como-fila"><span class="tl-como-i"><Icono nombre={icono} tamano={19} grosor={1.8} /></span><span class="t"><b>{b}</b><span>{s}</span></span></div>
            {/each}
          </div>
        </div>
      {:else}
        <div class="dc-cabeza tl-v-cabeza" data-sube>
          <span class="dc-icono tl-icono-acento"><Icono nombre="historial" tamano={22} grosor={1.8} /></span>
          <h2>{tt.histH}</h2>
        </div>
        <div class="dc-cuerpo tl-v-cuerpo" data-sube>
          {#if !historialLeido}
            <div class="tl-hist" aria-busy="true">
              {#each { length: Math.min(5, Math.max(1, mi.tarjeta?.movimientos.length ?? 3)) } as _, i (i)}
                <div class="tl-hist-fila"><span class="t"><span class="tl-esq tl-esq-linea"></span><span class="tl-esq tl-esq-chica"></span></span></div>
              {/each}
            </div>
          {:else if historialMal}
            <p class="tl-hist-vacio">{tt.histNoSe}</p>
          {:else if mi.tarjeta?.movimientos.length}
            <div class="tl-hist">
              {#each mi.tarjeta.movimientos as m, i (i)}
                <div class="tl-hist-fila" class:canje={m.cantidad < 0}>
                  <span class="t"><b>{tt.movimiento(m.tipo, m.origen)}</b><span>{diaCorto(m.dia, mi.hoy, lengua)}</span></span>
                  <span class="tl-hist-n">{m.cantidad > 0 ? '+' : '−'}{Math.abs(m.cantidad).toLocaleString('en-US')}</span>
                </div>
              {/each}
            </div>
          {:else}
            <p class="tl-hist-vacio">{tt.histVacio}</p>
          {/if}
        </div>
      {/if}
    </VentanaCrece>
  {/key}
{/if}

<style>
  /* Los esqueletos: su tarjeta y sus renglones, en el gris del menú, latiendo como los del menú. */
  .tl-esq {
    display: block;
    border-radius: 8px;
    background: var(--m-chip);
    animation: tl-late 2s ease-in-out infinite;
  }
  .tl-esq-titulo {
    width: 46%;
    height: 26px;
  }
  .tl-esq-tarjeta {
    width: 100%;
    aspect-ratio: 1.586;
    border-radius: 18px;
  }
  .tl-esq-renglon {
    width: 70%;
    height: 14px;
    margin: 0 auto;
  }
  .tl-esq-linea {
    width: 60%;
    height: 14px;
    background: var(--m-linea-fuerte);
  }
  .tl-esq-chica {
    width: 30%;
    height: 11px;
    background: var(--m-linea-fuerte);
  }
  @keyframes tl-late {
    50% {
      opacity: 0.5;
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .tl-esq {
      animation: none;
    }
  }
  .visually-hidden {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip-path: inset(50%);
  }

  /* La revisión de Cloudflare no ocupa lugar mientras no duda (como en Tu pedido); si duda, va al centro. */
  .f-ped-hueco {
    display: contents;
  }

  .f-ped-hueco > :global(*) {
    align-self: center;
  }
</style>
