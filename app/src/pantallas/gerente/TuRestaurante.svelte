<!--
  «Tu restaurante», el primer renglón de GENERAL (maqueta de la 6a Qx4C5CbKJYpeAsJCfw4ghn, sección 2;
  libreta 6, decidido el 20 de octubre de 2026): el logo, el nombre, el teléfono (que también es su
  WhatsApp), la dirección y el horario de los 7 días de esta sucursal. De aquí los toman el menú en
  línea, los flyers y el mini agente. El slug no se cambia aquí: lo asigna Fragmentless.

  «Guardar» guarda todo junto (guardar_restaurante). El logo sigue el orden de las fotos: se sube
  antes de guardar; si el guardado falla, se borra el que se acababa de subir; el anterior se borra
  solo después de guardar.
-->
<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import BarraArriba from '../../diseno/BarraArriba.svelte';
  import Boton from '../../diseno/Boton.svelte';
  import BotonCuadro from '../../diseno/BotonCuadro.svelte';
  import CajaError from '../../diseno/CajaError.svelte';
  import Campo from '../../diseno/Campo.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import Vidrio from '../../diseno/Vidrio.svelte';
  import { ALGO_SALIO_PANEL, esDeRed, Fallo, SIN_CONEXION } from '../../lib/errores';
  import { borrarFoto, convertirLogo, revisarFoto, subirFoto, urlFoto } from '../../lib/fotos';
  import type { Sucursal } from '../../lib/gerente';
  import { guardarRestaurante, leerRestaurante, type Horario, type Restaurante } from '../../lib/restaurante';
  import CajaSucursales from './CajaSucursales.svelte';
  import Dias, { type Dia } from './restaurante/Dias.svelte';

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
  let error = $state<string | null>(null);
  let telefonoMal = $state(false);
  let paso = $state<null | 'logo' | 'guardando' | 'listo'>(null);
  let elegirArchivo = $state<HTMLInputElement>();

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
    quitarArchivo();
  }

  async function leer() {
    try {
      poner(await leerRestaurante(sucursal.id));
      errorLectura = null;
    } catch (falla) {
      console.error('[restaurante] no se pudieron leer sus datos:', falla);
      errorLectura = esDeRed(falla) ? SIN_CONEXION : 'No se pudieron leer los datos de tu restaurante. Intenta de nuevo en un momento.';
    }
  }

  onMount(leer);
  onDestroy(quitarArchivo);

  function quitarArchivo() {
    if (vistaPrevia) URL.revokeObjectURL(vistaPrevia);
    vistaPrevia = null;
    archivo = null;
  }

  const foto = $derived(vistaPrevia ?? (logo ? urlFoto(logo) : null));
  const cambio = $derived(
    !!guardado &&
      (nombre.trim() !== guardado.nombre ||
        soloDigitos(telefono) !== (guardado.telefono ?? '') ||
        direccion.trim() !== (guardado.direccion ?? '') ||
        logo !== guardado.logo_ruta ||
        !!archivo ||
        JSON.stringify(aHorario(dias)) !== JSON.stringify(guardado.horario)),
  );

  async function alElegirLogo(e: Event & { currentTarget: HTMLInputElement }) {
    const elegido = e.currentTarget.files?.[0];
    e.currentTarget.value = '';
    if (!elegido || paso) return;
    const problema = await revisarFoto(elegido);
    if (problema) {
      error = problema;
      return;
    }
    error = null;
    quitarArchivo();
    archivo = elegido;
    vistaPrevia = URL.createObjectURL(elegido);
  }

  function quitarLogo() {
    quitarArchivo();
    logo = null;
  }

  // Lo de antes de mandar nada, con las palabras de la maqueta. Postgres revisa lo mismo.
  function validar(): string | null {
    telefonoMal = false;
    if (!nombre.trim()) return 'El nombre de tu restaurante es obligatorio.';
    const digitos = soloDigitos(telefono);
    if (digitos && !/^\d{10}$/.test(digitos)) {
      telefonoMal = true;
      return TELEFONO_MAL;
    }
    const nombres = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
    const igual = dias.findIndex((d) => d && d.abre === d.cierra);
    if (igual >= 0) return `El ${nombres[igual]} abre y cierra a la misma hora.`;
    return null;
  }

  async function guardar() {
    if (!guardado || paso) return;
    const problema = validar();
    if (problema) {
      error = problema;
      return;
    }
    error = null;

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
      });
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[restaurante] no se pudo guardar:', falla);
      // El logo de algo que no se guardó no se queda en R2.
      if (rutaNueva) await borrarFoto(rutaNueva);
      const mensaje = falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL;
      telefonoMal = mensaje === TELEFONO_MAL;
      error = mensaje;
      paso = null;
      return;
    }

    // Ya guardado: el logo anterior ya no lo usa nadie.
    if (anterior) await borrarFoto(anterior);
    paso = 'listo';
    await leer();
    setTimeout(() => (paso = null), 1600);
  }

  // Lo que le falta para que su menú diga si está abierto.
  const falta = $derived(
    guardado && !guardado.horario.length
      ? guardado.telefono
        ? 'Tu menú ya se ve, pero sin horario no dice si estás abierto. Pon tu horario.'
        : 'Tu menú ya se ve, pero sin horario no dice si estás abierto. Pon tu teléfono y tu horario.'
      : null,
  );
</script>

<BarraArriba titulo="Tu restaurante" estado={{ texto: 'Lo ven tus clientes en tu menú', vivo: true }}>
  <CajaSucursales {sucursales} actual={sucursal} {alElegir} />
</BarraArriba>

<main class="cuerpo">
  <Vidrio como="section" class="tu-restaurante" radio={26} aria-label="Tu restaurante">
    <div class="cabeza">
      <span class="etiqueta">TU RESTAURANTE</span>
      <p class="nota">Tu logo, tus datos y tu horario. Los ven tus clientes en tu menú en línea, y van en tus flyers.</p>
    </div>

    {#if errorLectura}
      <CajaError mensaje={errorLectura} />
    {:else}
      <div class="fila">
        <div class="tarjeta datos">
          <div class="encabezado">
            <span class="cuadro-icono"><Icono nombre="tienda" tamano={18} /></span>
            <span class="titulos">
              <span class="titulo">Datos</span>
              <span class="nota">Lo que sale en la barra de tu menú y en la «i».</span>
            </span>
          </div>
          <div class="raya"></div>
          <div class="campos">
            <div class="fila-logo">
              <span class="logo-cuadro" class:vacio={!foto}>
                {#if foto}<img src={foto} alt="Tu logo" />{:else}<Icono nombre="biblio" tamano={24} />{/if}
              </span>
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
            <Campo id="restaurante-nombre" etiqueta="NOMBRE DEL RESTAURANTE" bind:valor={nombre} largoMaximo={60} />
            <Campo
              id="restaurante-telefono"
              etiqueta="TELÉFONO Y WHATSAPP"
              bind:valor={telefono}
              tipo="tel"
              modoTeclado="tel"
              placeholder="Ej. 222 123 4567"
              pista="10 dígitos. Sale en tu menú y en tus flyers, y ahí te escriben tus clientes."
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
          </div>
        </div>

        <div class="tarjeta horario">
          <div class="encabezado">
            <span class="cuadro-icono"><Icono nombre="reloj" tamano={18} /></span>
            <span class="titulos">
              <span class="titulo">Horario</span>
              <span class="nota">Tus clientes ven si estás abierto, con la hora de tu restaurante.</span>
            </span>
          </div>
          <div class="raya" style:margin-bottom="4px"></div>
          <Dias bind:dias {hoy} apagado={!guardado || paso !== null} />
          <p class="pie">
            Si cierras después de medianoche, pon la hora del día siguiente: de 18:00 a 2:00. Esas horas cuentan como
            del día en que abriste.
          </p>
        </div>
      </div>

      {#if error}
        <CajaError mensaje={error} />
      {:else if falta}
        <CajaError mensaje={falta} tipo="info" />
      {/if}

      <div class="pie-seccion">
        <p class="pista crece">Es de esta sucursal. Tu menú en línea cambia en cuanto guardas.</p>
        <Boton
          etiqueta={paso === 'logo' ? 'Subiendo logo…' : paso === 'guardando' ? 'Guardando…' : paso === 'listo' ? 'Guardado' : 'Guardar'}
          icono="guardar"
          tono="tinta"
          apagado={!cambio && paso === null}
          cargando={paso === 'logo' || paso === 'guardando'}
          exito={paso === 'listo'}
          onclick={guardar}
        />
      </div>
    {/if}
  </Vidrio>
</main>

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

  :global(.tu-restaurante) {
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

  .tarjeta {
    min-width: 0;
    padding: 20px;
    display: flex;
    flex-direction: column;
    background: var(--solido);
    border: 1px solid var(--linea);
    border-radius: 18px;
  }

  .datos {
    flex: 1;
  }

  .horario {
    flex: 1.15;
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

  .campos {
    display: flex;
    flex-direction: column;
    gap: 14px;
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

  .pista {
    margin: 0;
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--tenue);
  }

  .pie {
    margin: 18px 0 0;
    font-size: 12px;
    font-weight: 500;
    line-height: 1.5;
    color: var(--tenue);
  }

  .pie-seccion {
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 0 4px;
  }

  .crece {
    flex-grow: 1;
  }
</style>
