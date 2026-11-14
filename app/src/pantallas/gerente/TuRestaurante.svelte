<!--
  «Tu restaurante» (maqueta de la 6a Qx4C5CbKJYpeAsJCfw4ghn, sección 2; libreta 6, decidido el 20 de octubre de 2026):
  el logo, el nombre, el teléfono (que también es su WhatsApp), la dirección y el horario de los 7 días de esta
  sucursal. De aquí los toman el menú en línea, los anuncios y el mini agente. El slug no se cambia aquí: lo asigna
  Fragmentless.

  Con el rediseño (13 nov 2026, planes/trabajo/rediseno/tu-restaurante.md): una columna al centro como Ajustes,
  «TU RESTAURANTE» con su nota sobre el gris y una tarjeta tras otra, cada una con su ícono, su título y su nota: Tu logo
  y tu nombre · Contacto · Envíos · Horario. Los campos van en su gris (diseno/GrupoCampos). Abajo, la barra de guardar
  de «Tu menú en línea» (diseno/BarraGuardar): «Descartar» en rojo y «Guardar» en verde; si se va con cambios, «Tienes
  cambios sin guardar» (lib/salida.ts).

  «Hago envíos» vive aquí desde el 12 nov 2026 (maqueta UDArhiEZceT7rmSKxqRA5r de «Tu menú en línea»): si sus clientes
  piden a domicilio además de para llevar. Se va a la vista de Pedidos cuando se rehaga (encuesta del 13 nov 2026).

  «Guardar» guarda todo junto (guardar_restaurante). El logo sigue el orden de las fotos: se sube antes de guardar; si el
  guardado falla, se borra el que se acababa de subir; el anterior se borra solo después de guardar.
-->
<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import BarraArriba from '../../diseno/BarraArriba.svelte';
  import BarraGuardar from '../../diseno/BarraGuardar.svelte';
  import Boton from '../../diseno/Boton.svelte';
  import BotonCuadro from '../../diseno/BotonCuadro.svelte';
  import CajaError from '../../diseno/CajaError.svelte';
  import Campo from '../../diseno/Campo.svelte';
  import Esqueleto from '../../diseno/Esqueleto.svelte';
  import GrupoCampos from '../../diseno/GrupoCampos.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import Interruptor from '../../diseno/Interruptor.svelte';
  import Tarjeta from '../../diseno/Tarjeta.svelte';
  import { quieto } from '../../diseno/ventanaSeMueve';
  import { ALGO_SALIO_PANEL, esDeRed, Fallo, SIN_CONEXION } from '../../lib/errores';
  import { borrarFoto, convertirLogo, revisarFoto, subirFoto, urlFoto } from '../../lib/fotos';
  import type { Sucursal } from '../../lib/gerente';
  import { leerEnvios, type Envio } from '../../lib/pedidos.svelte';
  import { ponerGuardia } from '../../lib/salida';
  import { supabase } from '../../lib/supabase';
  import { guardarRestaurante, leerRestaurante, type Horario, type Restaurante } from '../../lib/restaurante';
  import CajaSucursales from './CajaSucursales.svelte';
  import Dias, { type Dia } from './restaurante/Dias.svelte';
  import VentanaSalir from './restaurante/VentanaSalir.svelte';

  let {
    sucursal,
    sucursales,
    alElegir,
  }: { sucursal: Sucursal; sucursales: Sucursal[]; alElegir: (s: Sucursal) => void } = $props();

  const TELEFONO_MAL = 'El teléfono lleva 10 dígitos, como 222 123 4567.';

  let guardado = $state<Restaurante | null>(null);
  let errorLectura = $state<string | null>(null);

  let nombre = $state('');
  let telefono = $state('');
  let direccion = $state('');
  let logo = $state<string | null>(null);
  let archivo = $state<File | null>(null);
  let vistaPrevia = $state<string | null>(null);
  let dias = $state<Dia[]>(Array(7).fill(null));
  // Un logo más ancho que alto (más de 1.4 veces, como el «largo» del menú): su cuadrito deja de ser cuadro.
  let largo = $state(false);
  let envios = $state(false);
  // Los productos de envío de Mi menú, para decir cuál elige quien confirma un pedido a domicilio.
  let productosEnvio = $state<Envio[]>([]);
  let errorGuardar = $state<string | null>(null);
  let telefonoMal = $state(false);
  let paso = $state<null | 'logo' | 'guardando' | 'listo'>(null);
  let elegirArchivo = $state<HTMLInputElement>();
  // Si quiso irse con cambios: a dónde iba (la ventana «Tienes cambios sin guardar» está abierta).
  let salida = $state<(() => void) | null>(null);

  // Qué día es hoy en el restaurante (0 = lunes), con su fecha, nunca con la del aparato.
  // svelte-ignore state_referenced_locally
  const hoy = (new Date(`${sucursal.hoy}T12:00:00Z`).getUTCDay() + 6) % 7;

  // El teléfono guardado se enseña como se dicta: 222 123 4567.
  function conEspacios(t: string | null) {
    return t && /^\d{10}$/.test(t) ? `${t.slice(0, 3)} ${t.slice(3, 6)} ${t.slice(6)}` : (t ?? '');
  }

  function soloDigitos(t: string) {
    return t.replace(/[\s().-]/g, '');
  }

  function aDias(horario: Horario[]): Dia[] {
    return Array.from({ length: 7 }, (_, i) => {
      const h = horario.find((x) => x.dia === i + 1);
      return h ? { abre: h.abre, cierra: h.cierra } : null;
    });
  }

  function aHorario(lista: Dia[]): Horario[] {
    return lista.flatMap((d, i) => (d ? [{ dia: i + 1, abre: d.abre, cierra: d.cierra }] : []));
  }

  function poner(r: Restaurante) {
    guardado = r;
    nombre = r.nombre;
    telefono = conEspacios(r.telefono);
    direccion = r.direccion ?? '';
    logo = r.logo_ruta;
    dias = aDias(r.horario);
    envios = r.hace_envios;
    quitarArchivo();
  }

  async function leer() {
    try {
      const [r, pe] = await Promise.all([leerRestaurante(sucursal.id), leerEnvios(supabase, sucursal.id)]);
      productosEnvio = pe;
      poner(r);
      errorLectura = null;
    } catch (falla) {
      console.error('[restaurante] no se pudieron leer sus datos:', falla);
      errorLectura = esDeRed(falla) ? SIN_CONEXION : 'No se pudieron leer los datos de tu restaurante. Intenta de nuevo en un momento.';
    }
  }

  onMount(() => {
    leer();
    // Si se va con cambios (la barra lateral, la búsqueda, otra sucursal, cerrar sesión), primero lo pregunta.
    const quitarGuardia = ponerGuardia((seguir) => {
      if (!cambios || paso) return false;
      salida = seguir;
      return true;
    });
    // Y si cierra o recarga la pestaña, el navegador también pregunta.
    const alIrse = (e: BeforeUnloadEvent) => {
      if (cambios) e.preventDefault();
    };
    window.addEventListener('beforeunload', alIrse);
    return () => {
      quitarGuardia();
      window.removeEventListener('beforeunload', alIrse);
    };
  });
  onDestroy(quitarArchivo);

  function quitarArchivo() {
    if (vistaPrevia) URL.revokeObjectURL(vistaPrevia);
    vistaPrevia = null;
    archivo = null;
  }

  // Sin datos todavía (la primera lectura): esqueletos en su lugar (regla «Los esqueletos»).
  const cargando = $derived(!guardado && !errorLectura);
  const foto = $derived(vistaPrevia ?? (logo ? urlFoto(logo) : null));

  // Cuántas cosas cambió, para la barra de guardar: cada dato y cada día del horario cuenta como uno.
  const cambios = $derived.by(() => {
    if (!guardado) return 0;
    const antes = aDias(guardado.horario);
    return (
      [
        nombre.trim() !== guardado.nombre,
        soloDigitos(telefono) !== (guardado.telefono ?? ''),
        direccion.trim() !== (guardado.direccion ?? ''),
        logo !== guardado.logo_ruta || !!archivo,
        envios !== guardado.hace_envios,
      ].filter(Boolean).length + dias.filter((d, i) => JSON.stringify(d) !== JSON.stringify(antes[i])).length
    );
  });

  // Un cambio nuevo quita el error del guardado anterior (como en «Tu menú en línea»).
  $effect(() => {
    void [nombre, telefono, direccion, logo, archivo, envios, JSON.stringify(dias)];
    errorGuardar = null;
    telefonoMal = false;
  });

  async function alElegirLogo(e: Event & { currentTarget: HTMLInputElement }) {
    const elegido = e.currentTarget.files?.[0];
    e.currentTarget.value = '';
    if (!elegido || paso) return;
    const problema = await revisarFoto(elegido);
    if (problema) {
      errorGuardar = problema;
      return;
    }
    quitarArchivo();
    archivo = elegido;
    vistaPrevia = URL.createObjectURL(elegido);
  }

  function quitarLogo() {
    quitarArchivo();
    logo = null;
  }

  function descartar() {
    if (!guardado || paso) return;
    poner(guardado);
  }

  // Lo de antes de mandar nada, con las palabras de la maqueta. Postgres revisa lo mismo.
  function validar(): string | null {
    if (!nombre.trim()) return 'El nombre de tu restaurante es obligatorio.';
    const digitos = soloDigitos(telefono);
    if (digitos && !/^\d{10}$/.test(digitos)) return TELEFONO_MAL;
    const nombres = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
    const igual = dias.findIndex((d) => d && d.abre === d.cierra);
    if (igual >= 0) return `El ${nombres[igual]} abre y cierra a la misma hora.`;
    return null;
  }

  // Guarda todo; regresa el error si no se pudo (para «Guardar y salir»), o null.
  async function guardar(): Promise<string | null> {
    if (!guardado || paso) return null;
    const problema = validar();
    if (problema) {
      errorGuardar = problema;
      telefonoMal = problema === TELEFONO_MAL;
      return problema;
    }
    errorGuardar = null;

    let rutaNueva: string | null = null;
    let anterior: string | null;
    try {
      if (archivo) {
        paso = 'logo';
        rutaNueva = await subirFoto(sucursal.id, await convertirLogo(archivo), 'logo');
      }
      paso = 'guardando';
      anterior = await guardarRestaurante(sucursal.id, {
        nombre: nombre.trim(),
        telefono: soloDigitos(telefono),
        direccion: direccion.trim(),
        logo_ruta: rutaNueva ?? logo,
        horario: aHorario(dias),
        hace_envios: envios,
      });
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[restaurante] no se pudo guardar:', falla);
      // El logo de algo que no se guardó no se queda en R2.
      if (rutaNueva) await borrarFoto(rutaNueva);
      const mensaje = falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL;
      errorGuardar = mensaje;
      telefonoMal = mensaje === TELEFONO_MAL;
      paso = null;
      return mensaje;
    }

    // Ya guardado: el logo anterior ya no lo usa nadie.
    if (anterior) await borrarFoto(anterior);
    paso = 'listo';
    await leer();
    setTimeout(() => (paso = null), 1600);
    return null;
  }

  // Los envíos de Mi menú como los elige quien confirma: «Envío $30 o Envío lejos $50».
  const precioCorto = (n: number) => `$${Number.isInteger(n) ? n : n.toFixed(2)}`;
  const listaEnvios = $derived(productosEnvio.map((e) => `${e.nombre} ${precioCorto(e.precio)}`));
  // Qué dice la pista de «Hago envíos» (cambia con un desvanecido corto).
  const pistaEnvios = $derived(!envios ? 'solo' : listaEnvios.length ? 'con' : 'sin');

  // Lo que le falta para que su menú diga si está abierto.
  const falta = $derived(
    guardado && !guardado.horario.length
      ? guardado.telefono
        ? 'Tu menú ya se ve, pero sin horario no dice si estás abierto. Pon tu horario.'
        : 'Tu menú ya se ve, pero sin horario no dice si estás abierto. Pon tu teléfono y tu horario.'
      : null,
  );

  // Lo que cambia (el logo, la pista de los envíos) aparece con el desvanecido corto de «Tu menú en línea».
  function aparece(_el: Element) {
    if (quieto()) return { duration: 0 };
    return { duration: 220, css: (x: number) => `opacity: ${x}` };
  }
</script>

{#snippet cabecera(icono: string, titulo: string, nota: string)}
  <div class="encabezado">
    <span class="cuadro-icono"><Icono nombre={icono} tamano={18} /></span>
    <span class="titulos">
      <span class="titulo">{titulo}</span>
      <span class="sub">{nota}</span>
    </span>
  </div>
{/snippet}

{#snippet campoEsqueleto(etiqueta: string, pista?: string)}
  <div class="campo-esqueleto" aria-hidden="true">
    <span class="etiqueta">{etiqueta}</span>
    <Esqueleto alto="44px" redondo="12px" />
    {#if pista}<span class="pista">{pista}</span>{/if}
  </div>
{/snippet}

<BarraArriba titulo="Tu restaurante" estado={{ texto: 'Lo ven tus clientes en tu menú', vivo: true }}>
  <CajaSucursales {sucursales} actual={sucursal} {alElegir} />
</BarraArriba>

<main class="cuerpo" aria-label="Tu restaurante">
  <div class="col">
    <div class="cabeza">
      <span class="etiqueta">TU RESTAURANTE</span>
      <p class="nota">
        Tu logo, tus datos y tu horario. Los ven tus clientes en tu menú en línea, y van en tus anuncios. Son de esta
        sucursal, y tu menú cambia en cuanto guardas.
      </p>
    </div>

    {#if falta}
      <p class="aviso"><Icono nombre="info" tamano={16} /><span>{falta}</span></p>
    {/if}

    {#if errorLectura}
      <CajaError mensaje={errorLectura} />
    {:else}
      {#if cargando}<span class="solo-lector">Cargando tu restaurante…</span>{/if}

      <Tarjeta como="section" class="tr-tarjeta" aria-label="Tu logo y tu nombre">
        {@render cabecera('tienda', 'Tu logo y tu nombre', 'Lo que sale en la barra de tu menú y en la «i».')}
        <div class="fila-logo">
          {#if cargando}
            <Esqueleto ancho="72px" alto="72px" redondo="14px" />
          {:else}
            <span class="logo-cuadro" class:vacio={!foto} class:largo={foto && largo}>
              {#key foto}
                {#if foto}<img
                    src={foto}
                    alt="Tu logo"
                    in:aparece
                    onload={(e) => {
                      const img = e.currentTarget as HTMLImageElement;
                      largo = img.naturalWidth > img.naturalHeight * 1.4;
                    }}
                  />{:else}<Icono nombre="biblio" tamano={24} />{/if}
              {/key}
            </span>
          {/if}
          <div class="logo-texto">
            <div class="logo-botones">
              <Boton
                etiqueta={foto ? 'Cambiar logo' : 'Agregar logo'}
                icono="biblio"
                apagado={!guardado || paso !== null}
                onclick={() => elegirArchivo?.click()}
              />
              {#if foto}
                <BotonCuadro icono="eliminar" ayuda="Quitar logo" grande apagado={paso !== null} onclick={quitarLogo} />
              {/if}
            </div>
            <span class="pista">PNG con fondo transparente · se optimiza automáticamente</span>
          </div>
          <input bind:this={elegirArchivo} type="file" accept="image/*" hidden onchange={alElegirLogo} />
        </div>
        <GrupoCampos>
          {#if cargando}
            {@render campoEsqueleto('NOMBRE DEL RESTAURANTE')}
          {:else}
            <Campo id="restaurante-nombre" etiqueta="NOMBRE DEL RESTAURANTE" bind:valor={nombre} largoMaximo={60} />
          {/if}
        </GrupoCampos>
      </Tarjeta>

      <Tarjeta como="section" class="tr-tarjeta" aria-label="Contacto">
        {@render cabecera('celular', 'Contacto', 'Por dónde te escriben y cómo te encuentran tus clientes.')}
        <GrupoCampos>
          {#if cargando}
            {@render campoEsqueleto('TELÉFONO Y WHATSAPP', '10 dígitos. Sale en tu menú y en tus anuncios, y ahí te escriben tus clientes.')}
            {@render campoEsqueleto('DIRECCIÓN')}
          {:else}
            <Campo
              id="restaurante-telefono"
              etiqueta="TELÉFONO Y WHATSAPP"
              bind:valor={telefono}
              tipo="tel"
              modoTeclado="tel"
              placeholder="Ej. 222 123 4567"
              pista="10 dígitos. Sale en tu menú y en tus anuncios, y ahí te escriben tus clientes."
              mal={telefonoMal}
              mono
            />
            <Campo
              id="restaurante-direccion"
              etiqueta="DIRECCIÓN"
              bind:valor={direccion}
              placeholder="Ej. Av. Juárez 123, Centro"
              largoMaximo={200}
            />
          {/if}
        </GrupoCampos>
      </Tarjeta>

      <Tarjeta como="section" class="tr-tarjeta" aria-label="Envíos">
        {@render cabecera('moto', 'Envíos', 'Si tus clientes también piden a domicilio desde tu menú.')}
        <GrupoCampos>
          <div class="envios-fila">
            {#if cargando}
              <span class="envios-esqueleto" aria-hidden="true"><Esqueleto ancho="34px" alto="20px" redondo="10px" /><Esqueleto ancho="84px" alto="10px" /></span>
              <span class="pista crece"><Esqueleto ancho="70%" alto="10px" /></span>
            {:else}
              <Interruptor prendido={envios} texto="Hago envíos" alCambiar={(v) => (envios = v)} />
              {#key pistaEnvios}
                <span class="pista crece" in:aparece>
                  {#if pistaEnvios === 'solo'}
                    Tus clientes solo piden para llevar.
                  {:else if pistaEnvios === 'sin'}
                    Tus clientes también piden a domicilio. Para cobrar el envío, crea un producto en Mi menú y prende <b
                      >«Es un costo de envío»</b
                    >.
                  {:else}
                    Tus clientes también piden a domicilio. Al confirmar, eliges el envío:
                    {#each listaEnvios as e, i (i)}{i === 0 ? '' : i === listaEnvios.length - 1 ? ' o ' : ', '}<b>{e}</b>{/each}, de Mi menú.
                  {/if}
                </span>
              {/key}
            {/if}
          </div>
        </GrupoCampos>
      </Tarjeta>

      <Tarjeta como="section" class="tr-tarjeta" aria-label="Horario">
        {@render cabecera('reloj', 'Horario', 'Tus clientes ven si estás abierto, con la hora de tu restaurante.')}
        <GrupoCampos>
          <Dias bind:dias {hoy} apagado={!guardado || paso !== null} {cargando} />
        </GrupoCampos>
        <p class="pie">
          Si cierras después de medianoche, pon la hora del día siguiente: de 18:00 a 2:00. Esas horas cuentan como del
          día en que abriste.
        </p>
      </Tarjeta>
    {/if}
  </div>
</main>

<BarraGuardar
  {cambios}
  paso={paso === 'logo' ? 'guardando' : paso}
  cargando={cargando || !!errorLectura}
  error={errorGuardar}
  alGuardar={() => void guardar()}
  alDescartar={descartar}
/>

{#if salida}
  <VentanaSalir
    {cambios}
    alSalir={() => {
      const ir = salida;
      salida = null;
      descartar();
      ir?.();
    }}
    alGuardar={guardar}
    alCerrar={() => (salida = null)}
  />
{/if}

<style>
  /* Entre la barra de arriba (56) y la de guardar (64), una columna al centro como Ajustes, más angosta (760): aquí todo
     es campos, y a 940 una caja de texto quedaba de 860 de ancho. */
  .cuerpo {
    position: absolute;
    left: 0;
    right: 0;
    top: 56px;
    bottom: 64px;
    overflow-y: auto;
    scrollbar-gutter: stable;
  }

  .col {
    max-width: 760px;
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
    text-wrap: pretty;
  }

  .aviso {
    display: flex;
    align-items: flex-start;
    gap: 10px;
    margin: 0;
    padding: 11px 14px;
    border-radius: 12px;
    background: var(--chip);
    font-size: 12.5px;
    line-height: 1.5;
    color: var(--suave);
  }

  .aviso :global(svg) {
    flex: none;
    margin-top: 2px;
  }

  /* Cada tarjeta, como las filas de «Tu menú en línea»: su encabezado y debajo lo suyo. */
  :global(.tr-tarjeta) {
    flex: none;
    padding: 20px;
    display: flex;
    flex-direction: column;
    gap: 18px;
  }

  /* En Cristal la tarjeta es material, y lo de adentro un relleno transparente, como dentro de las ventanas (libreta 4,
     «El estilo Cristal»; Ajustes): el gris de los campos (--fondo) pasa al relleno de Cristal, nunca negro. */
  :global(:root[data-estilo='cristal'][data-tema='oscuro'] .tr-tarjeta) {
    --fondo: var(--cristal-relleno);
  }

  :global(:root[data-estilo='cristal'][data-tema='claro'] .tr-tarjeta) {
    --fondo: var(--cl-relleno);
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
    color: var(--texto);
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

  .sub {
    font-size: 12.5px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .fila-logo {
    display: flex;
    align-items: center;
    gap: 16px;
  }

  .logo-cuadro {
    width: 72px;
    height: 72px;
    border-radius: 14px;
    background: var(--chip);
    border: 1px solid var(--linea);
    display: flex;
    align-items: center;
    justify-content: center;
    flex: none;
    overflow: hidden;
  }

  .logo-cuadro.vacio {
    color: var(--tenue);
  }

  .logo-cuadro img {
    width: 58px;
    height: 58px;
    display: block;
    object-fit: contain;
  }

  /* Con un logo largo (maqueta UDArhiEZceT7rmSKxqRA5r, 11 nov 2026): 72 de alto y lo ancho que pida. */
  .logo-cuadro.largo {
    width: auto;
    min-width: 72px;
    padding: 0 12px;
  }

  .logo-cuadro.largo img {
    width: auto;
    height: auto;
    max-width: 220px;
    max-height: 58px;
  }

  .logo-texto {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 8px;
  }

  .logo-botones {
    display: flex;
    gap: 8px;
  }

  .campo-esqueleto {
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

  .pie {
    margin: 0 4px;
    font-size: 12px;
    font-weight: 500;
    line-height: 1.5;
    color: var(--tenue);
  }

  .crece {
    flex-grow: 1;
  }

  .envios-fila {
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

  .envios-esqueleto {
    display: inline-flex;
    align-items: center;
    gap: 9px;
    min-height: 20px;
  }
</style>
