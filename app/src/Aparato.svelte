<!--
  El portero del aparato del equipo (/equipo; libreta 3, «El personal: aparato y PIN»; maqueta de
  Empleados 36iXMMqXCfVv4NuVR7vNSc). No es el del panel: aquí nadie entra con correo, y la sesión
  de quien pone su PIN solo funciona desde este aparato.

    Sin ligar      pide el código de 6 letras (o lo trae el QR).
    Compartido     «¿Quién eres?» → PIN → adentro. Tras 2 minutos sin tocarla, su sesión se cierra
                   y vuelve a pedir el PIN de quien estaba, con «Cambiar de persona»; la pantalla
                   de cocina es la excepción y nunca lo vuelve a pedir (libreta 5). Al recargar la
                   página empieza desde la lista.
    De una persona va directo a su PIN, y una vez adentro se queda, hasta que el gerente desliga
                   el aparato o da de baja a esa persona.

  Adentro, cada quien ve lo de sus roles (Adentro.svelte): las mesas del punto de venta, la caja o
  la cocina. Cada vez que se vuelve a la pestaña, revisa con Postgres que el aparato siga ligado y
  que quien está adentro siga en el equipo.

  Afuera («¿Quién eres?» o el PIN), pregunta cada minuto cuántos pedidos del menú esperan y suena
  si hay alguno y la última persona adentro era de caja (parte 6b), para que la tableta de la
  cocina no suene.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import CajaError from './diseno/CajaError.svelte';
  import {
    FalloAparato,
    haySesion,
    leerLigado,
    nombres,
    olvidarLigado,
    salir,
    type Ligado,
    type Lista,
    type PersonaAparato,
  } from './lib/aparato';
  import { ALGO_SALIO_PANEL } from './lib/errores';
  import { avisarPedido, prepararSonido } from './lib/sonido';
  import Arriba from './pantallas/aparato/Arriba.svelte';
  import Adentro from './pantallas/aparato/Adentro.svelte';
  import Pin from './pantallas/aparato/Pin.svelte';
  import QuienEres from './pantallas/aparato/QuienEres.svelte';
  import SinLigar from './pantallas/aparato/SinLigar.svelte';

  const DOS_MINUTOS = 2 * 60 * 1000;
  const UN_MINUTO = 60 * 1000;

  type Pantalla =
    | { tipo: 'cargando' }
    | { tipo: 'sin-ligar'; aviso: string | null }
    | { tipo: 'problema'; mensaje: string }
    | { tipo: 'nombres' }
    | { tipo: 'pin'; persona: PersonaAparato; otraVez: boolean }
    | { tipo: 'adentro'; persona: PersonaAparato };

  // El código que trae el QR (…/equipo?codigo=KMRPTX). Sirve una sola vez: se quita de la
  // dirección para que recargar no lo vuelva a usar, y se olvida en cuanto se liga o se desliga.
  const parametros = new URLSearchParams(location.search);
  let codigoDelQr = $state((parametros.get('codigo') ?? '').toUpperCase().replace(/[^A-Z]/g, '').slice(0, 6));
  if (parametros.has('codigo')) history.replaceState(null, '', location.pathname);

  let ligado = $state<Ligado | null>(leerLigado());
  let lista = $state<Lista | null>(null);
  let pantalla = $state<Pantalla>({ tipo: 'cargando' });
  // El último toque, con el reloj que solo avanza (no el de la hora del aparato).
  let ultimoToque = performance.now();
  // La pantalla que se ve adentro: en la de cocina no corren los 2 minutos.
  let pestana = 'mesas';

  async function abrir() {
    if (!ligado) {
      pantalla = { tipo: 'sin-ligar', aviso: null };
      return;
    }
    let nueva: Lista;
    try {
      nueva = await nombres(ligado.token);
    } catch (falla) {
      await problema(falla);
      return;
    }
    lista = nueva;

    if (nueva.compartido) {
      // En la tableta compartida, abrir o recargar empieza desde la lista.
      if (ligado.adentro !== null || (await haySesion())) await cerrarSesion();
      pantalla = { tipo: 'nombres' };
      return;
    }
    const suya = nueva.personas[0];
    if (!suya) {
      pantalla = { tipo: 'problema', mensaje: 'La persona de este aparato todavía no tiene PIN. Avísale a tu gerente.' };
      return;
    }
    if (ligado.adentro === suya.id && (await haySesion())) {
      pantalla = { tipo: 'adentro', persona: suya };
      return;
    }
    if (ligado.adentro !== null || (await haySesion())) await cerrarSesion();
    pantalla = { tipo: 'pin', persona: suya, otraVez: false };
  }

  async function problema(falla: unknown) {
    if (falla instanceof FalloAparato && falla.desligado) {
      await desligado(falla.message);
      return;
    }
    if (!(falla instanceof FalloAparato)) console.error('[aparato] no se pudo abrir:', falla);
    pantalla = { tipo: 'problema', mensaje: falla instanceof FalloAparato ? falla.message : ALGO_SALIO_PANEL };
  }

  // El gerente lo desligó (o dio de baja a su persona): se olvida todo y pide un código nuevo.
  async function desligado(mensaje: string) {
    await salir(null);
    olvidarLigado();
    ligado = null;
    lista = null;
    codigoDelQr = '';
    pantalla = { tipo: 'sin-ligar', aviso: mensaje };
  }

  async function cerrarSesion() {
    await salir(ligado);
    ligado = leerLigado();
  }

  function alLigar(nuevo: Ligado) {
    ligado = nuevo;
    codigoDelQr = '';
    abrir();
  }

  function alEntrar(persona: PersonaAparato) {
    ligado = leerLigado();
    ultimoToque = performance.now();
    pantalla = { tipo: 'adentro', persona };
  }

  async function cambiarDePersona() {
    await cerrarSesion();
    await abrir();
  }

  // Tras 2 minutos sin tocar la tableta compartida, quien estaba sale y se le pide su PIN otra vez.
  // La cocina no: el taquero entra una vez y la pantalla queda abierta (libreta 5, «La cocina»).
  async function revisarDosMinutos() {
    if (pantalla.tipo !== 'adentro' || !lista?.compartido || pestana === 'cocina') return;
    if (performance.now() - ultimoToque < DOS_MINUTOS) return;
    const persona = pantalla.persona;
    pantalla = { tipo: 'pin', persona, otraVez: true };
    await cerrarSesion();
  }

  // Afuera, los pedidos que esperan: adentro ya los vigila Adentro.svelte.
  async function sonarSiEsperan() {
    if (!ligado?.ultimoDeCaja || (pantalla.tipo !== 'nombres' && pantalla.tipo !== 'pin')) return;
    let nueva: Lista;
    try {
      nueva = await nombres(ligado.token);
    } catch (falla) {
      if (falla instanceof FalloAparato && falla.desligado) await desligado(falla.message);
      else console.error('[aparato] no se pudo preguntar por los pedidos:', falla);
      return;
    }
    lista = nueva;
    if ((nueva.pedidosPorConfirmar ?? 0) > 0 && (pantalla.tipo === 'nombres' || pantalla.tipo === 'pin')) avisarPedido();
  }

  // Al volver a la pestaña: ¿sigue ligado?, ¿sigue en el equipo quien está adentro?
  async function revisar() {
    if (!ligado || pantalla.tipo === 'sin-ligar' || pantalla.tipo === 'cargando') return;
    await revisarDosMinutos();
    let nueva: Lista;
    try {
      nueva = await nombres(ligado.token);
    } catch (falla) {
      if (falla instanceof FalloAparato && falla.desligado) await desligado(falla.message);
      else console.error('[aparato] no se pudo revisar el aparato al volver:', falla);
      return;
    }
    lista = nueva;
    const actual = pantalla;
    if ((actual.tipo === 'adentro' || actual.tipo === 'pin') && !nueva.personas.some((p) => p.id === actual.persona.id)) {
      await cambiarDePersona();
    }
  }

  onMount(() => {
    document.title = 'Fragmentless · Equipo';
    abrir();
    const tocar = () => (ultimoToque = performance.now());
    const alVolver = () => {
      if (document.visibilityState === 'visible') revisar();
    };
    const reloj = setInterval(revisarDosMinutos, 5000);
    const pedidos = setInterval(sonarSiEsperan, UN_MINUTO);
    document.addEventListener('pointerdown', tocar, true);
    document.addEventListener('pointerdown', prepararSonido, true);
    document.addEventListener('keydown', tocar, true);
    document.addEventListener('visibilitychange', alVolver);
    return () => {
      clearInterval(reloj);
      clearInterval(pedidos);
      document.removeEventListener('pointerdown', tocar, true);
      document.removeEventListener('pointerdown', prepararSonido, true);
      document.removeEventListener('keydown', tocar, true);
      document.removeEventListener('visibilitychange', alVolver);
    };
  });
</script>

{#if lista && pantalla.tipo === 'adentro'}
  {#key pantalla.persona.id}
    <Adentro {lista} persona={pantalla.persona} alPestana={(p) => (pestana = p)} />
  {/key}
{:else}
  <div class="aparato">
    <div class="columna-aparato">
      {#if pantalla.tipo === 'cargando'}
        <Arriba />
      {:else if pantalla.tipo === 'sin-ligar'}
        <SinLigar codigoInicial={codigoDelQr} aviso={pantalla.aviso} {alLigar} />
      {:else if pantalla.tipo === 'problema'}
        <Arriba lugar={lista ? { restaurante: lista.restaurante, aparato: lista.aparato } : null} />
        <div class="cuerpo">
          <div class="centro">
            <h1 class="titulo">No pudimos abrir este aparato</h1>
            <CajaError mensaje={pantalla.mensaje} />
          </div>
          <button type="button" class="boton contorno" onclick={abrir}>Intentar de nuevo</button>
        </div>
      {:else if ligado && lista && pantalla.tipo === 'nombres'}
        <QuienEres {lista} alElegir={(persona) => (pantalla = { tipo: 'pin', persona, otraVez: false })} />
      {:else if ligado && lista && pantalla.tipo === 'pin'}
        {@const persona = pantalla.persona}
        {#key `${persona.id}-${pantalla.otraVez}`}
          <Pin
            {ligado}
            {lista}
            {persona}
            otraVez={pantalla.otraVez}
            alEntrar={() => alEntrar(persona)}
            alVolver={lista.compartido ? abrir : undefined}
            alDesligado={desligado}
          />
        {/key}
      {/if}
    </div>
  </div>
{/if}

<style>
  /* La pantalla del aparato: 390 de ancho como el celular de la maqueta; en una tableta, al
     centro. Arriba y abajo, el espacio de la maqueta o el del aparato, el que sea mayor. */
  .aparato {
    min-height: 100vh;
    min-height: 100dvh;
    display: flex;
    justify-content: center;
    background: var(--suelo);
  }

  .columna-aparato {
    width: 100%;
    max-width: 390px;
    min-height: 100vh;
    min-height: 100dvh;
    display: flex;
    flex-direction: column;
    padding: max(56px, env(safe-area-inset-top)) 20px max(34px, env(safe-area-inset-bottom));
    font-size: 14px;
    font-weight: 500;
  }

  /* Las piezas que comparten las pantallas del aparato, sin el sello de este componente: así
     cada pantalla les gana con sus propias reglas (el título de 32 de Hola, la inicial de 40). */
  :global(.columna-aparato .cuerpo) {
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;
  }

  :global(.columna-aparato .centro) {
    flex: 1;
    display: flex;
    flex-direction: column;
    justify-content: center;
    gap: 14px;
  }

  :global(.columna-aparato .titulo) {
    margin: 0;
    font-size: 26px;
    font-weight: 800;
    letter-spacing: -0.5px;
    line-height: 1.15;
  }

  :global(.columna-aparato .texto) {
    margin: 0;
    font-size: 14px;
    line-height: 1.5;
    color: var(--suave);
  }

  :global(.columna-aparato .boton) {
    width: 100%;
    height: 52px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    border: 0;
    border-radius: 14px;
    background: var(--tinta);
    color: var(--sobre-tinta);
    font-size: 15px;
    font-weight: 700;
  }

  :global(.columna-aparato .boton:disabled) {
    opacity: 0.4;
    cursor: default;
  }

  :global(.columna-aparato .boton.contorno) {
    border: 1px solid var(--linea);
    background: transparent;
    color: var(--texto);
  }

  :global(.columna-aparato .inicial) {
    width: 34px;
    height: 34px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 17px;
    border: 1px solid var(--linea);
    background: var(--chip);
    font-size: 13px;
    font-weight: 700;
  }
</style>
