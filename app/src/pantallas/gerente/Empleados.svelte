<!--
  Empleados, portada de la maqueta aprobada el 14 de octubre de 2026 (36iXMMqXCfVv4NuVR7vNSc).
  Arriba: el título, Personas | Aparatos, el chip con cuántos hay y el botón de la sección (Nuevo
  empleado o Vincular aparato). Abajo, la tarjeta de vidrio con la tabla de la sección.

  Personas: los gerentes arriba, sin editar (en su propia fila, Don Chuy solo pone su PIN; a otro
  gerente lo liga Fragmentless), y después el equipo con el lápiz, el candado del PIN y Dar de
  baja. La columna PIN dice si ya tiene PIN o si está bloqueado, con Desbloquear.
  Aparatos: cada uno con de quién es y cuándo entró alguien por última vez, y Desligar.

  Lee todo al abrir, después de cada cambio y cada vez que Don Chuy regresa a la pestaña (un
  aparato que se ligó, alguien que se bloqueó). Si esa lectura falla, se queda lo que se veía.
-->
<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import AvisoFlotante from '../../diseno/AvisoFlotante.svelte';
  import BarraArriba from '../../diseno/BarraArriba.svelte';
  import Boton from '../../diseno/Boton.svelte';
  import BotonCuadro from '../../diseno/BotonCuadro.svelte';
  import Confirmar from '../../diseno/Confirmar.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import NotaTabla from '../../diseno/NotaTabla.svelte';
  import Selector from '../../diseno/Selector.svelte';
  import Tabla from '../../diseno/Tabla.svelte';
  import Vidrio from '../../diseno/Vidrio.svelte';
  import {
    darDeBaja,
    desbloquear,
    desligar,
    leerEquipo,
    type Aparato,
    type Equipo,
    type Persona,
  } from '../../lib/equipo';
  import { ALGO_SALIO_PANEL, esDeRed, Fallo, SIN_CONEXION } from '../../lib/errores';
  import { plural } from '../../lib/formato';
  import { NOMBRE_ROL } from '../../lib/roles';
  import type { Sucursal } from '../../lib/gerente';
  import VentanaEmpleado from './empleados/VentanaEmpleado.svelte';
  import VentanaPin from './empleados/VentanaPin.svelte';
  import VentanaVincular from './empleados/VentanaVincular.svelte';

  let { sucursal, usuarioId }: { sucursal: Sucursal; usuarioId: string } = $props();

  const ESPERA_EXITO = 1600;
  const COLUMNAS_PERSONAS = 'minmax(0, 2fr) minmax(0, 1.6fr) minmax(0, 2fr) 132px';
  const COLUMNAS_APARATOS = 'minmax(0, 2fr) minmax(0, 2fr) minmax(0, 1.2fr) 84px';

  type Lectura = { estado: 'leyendo' } | { estado: 'listo'; equipo: Equipo } | { estado: 'error'; deRed: boolean };

  let lectura = $state<Lectura>({ estado: 'leyendo' });
  let seccion = $state<'personas' | 'aparatos'>('personas');
  let ventana = $state<
    | { tipo: 'empleado'; persona: Persona | null }
    | { tipo: 'pin'; persona: Persona }
    | { tipo: 'baja'; persona: Persona }
    | { tipo: 'vincular' }
    | { tipo: 'desligar'; aparato: Aparato }
    | null
  >(null);
  // Desbloquear se ve en el mismo botón: apagado mientras trabaja y con la palomita al terminar.
  let desbloqueo = $state<{ id: number; listo: boolean } | null>(null);
  let aviso = $state<string | null>(null);
  let temporizador: ReturnType<typeof setTimeout> | undefined;

  const equipo = $derived(lectura.estado === 'listo' ? lectura.equipo : null);
  const personas = $derived(equipo?.personas ?? []);
  const aparatos = $derived(equipo?.aparatos ?? []);
  // Quienes no son gerentes: los que se editan y los que pueden tener su propio aparato.
  const delEquipo = $derived(personas.filter((p) => !p.gerente));

  const estado = $derived.by(() => {
    if (lectura.estado === 'leyendo') return { texto: 'Cargando tu equipo…', vivo: true };
    if (lectura.estado === 'error') return { texto: lectura.deRed ? 'Sin conexión' : 'No se pudo leer', vivo: false };
    return seccion === 'personas'
      ? { texto: plural(personas.length, 'persona activa', 'personas activas'), vivo: true }
      : { texto: plural(aparatos.length, 'aparato ligado', 'aparatos ligados'), vivo: true };
  });

  async function leer() {
    try {
      lectura = { estado: 'listo', equipo: await leerEquipo(sucursal, usuarioId) };
    } catch (error) {
      console.error('[equipo] no se pudo leer el equipo:', error);
      // Si ya se veía la lista, se queda; si no, la nota del error.
      if (lectura.estado !== 'listo') lectura = { estado: 'error', deRed: esDeRed(error) };
    }
  }

  onMount(() => {
    leer();
    const alVolver = () => {
      if (document.visibilityState === 'visible') leer();
    };
    document.addEventListener('visibilitychange', alVolver);
    return () => document.removeEventListener('visibilitychange', alVolver);
  });
  onDestroy(() => clearTimeout(temporizador));

  async function quitarBloqueo(p: Persona) {
    desbloqueo = { id: p.id, listo: false };
    try {
      await desbloquear(p.id);
    } catch (falla) {
      desbloqueo = null;
      aviso = falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL;
      return;
    }
    desbloqueo = { id: p.id, listo: true };
    leer();
    temporizador = setTimeout(() => (desbloqueo = null), ESPERA_EXITO);
  }

  // Dar de baja y Desligar: la ventana de confirmar enseña el error o la palomita.
  async function confirmar(trabajo: () => Promise<void>, listo: string): Promise<{ listo: string } | { error: string }> {
    try {
      await trabajo();
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[equipo] no se pudo:', falla);
      return { error: falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL };
    }
    leer();
    return { listo };
  }

  const inicial = (nombre: string) => nombre.trim().charAt(0).toUpperCase();
  const dueno = (a: Aparato) => (a.miembroId === null ? null : personas.find((p) => p.id === a.miembroId) ?? null);
</script>

<BarraArriba titulo="Empleados" {estado}>
  {#snippet junto()}
    <Selector
      etiqueta="Sección de Empleados"
      opciones={[
        { valor: 'personas', texto: 'Personas' },
        { valor: 'aparatos', texto: 'Aparatos' },
      ]}
      elegida={seccion}
      alElegir={(valor) => (seccion = valor)}
    />
  {/snippet}
  {#if seccion === 'personas'}
    <Boton
      etiqueta="Nuevo empleado"
      icono="mas"
      tono="tinta"
      apagado={!equipo}
      onclick={() => (ventana = { tipo: 'empleado', persona: null })}
    />
  {:else}
    <Boton
      etiqueta="Vincular aparato"
      icono="mas"
      tono="tinta"
      apagado={!equipo}
      onclick={() => (ventana = { tipo: 'vincular' })}
    />
  {/if}
</BarraArriba>

<main class="cuerpo">
  <Vidrio como="section" class="tarjeta-equipo" radio={26} aria-label="Empleados">
    <div class="herramientas">
      <p class="nota">
        {seccion === 'personas'
          ? 'Tu equipo entra con su nombre y su PIN en un aparato ligado. Nadie puede ver un PIN, ni tú.'
          : 'Los celulares y tabletas desde donde entra tu equipo. Uno compartido muestra a todo el equipo; el de una persona, solo a ella.'}
      </p>
      <span class="crece"></span>
      {#if equipo}
        <span class="etiqueta">
          {seccion === 'personas'
            ? plural(personas.length, 'PERSONA', 'PERSONAS')
            : plural(aparatos.length, 'APARATO', 'APARATOS')}
        </span>
      {/if}
    </div>

    {#if seccion === 'personas'}
      <Tabla
        columnas={COLUMNAS_PERSONAS}
        relleno="0 16px"
        altoFila={64}
        encabezados={[{ texto: 'PERSONA' }, { texto: 'ROLES' }, { texto: 'PIN' }, { texto: '' }]}
      >
        {#if lectura.estado === 'leyendo'}
          <NotaTabla relleno={48} angosta titulo="Cargando tu equipo…" />
        {:else if lectura.estado === 'error' && lectura.deRed}
          <NotaTabla relleno={48} angosta titulo="Sin conexión." texto={SIN_CONEXION} />
        {:else if lectura.estado === 'error'}
          <NotaTabla relleno={48} angosta titulo="No se pudo cargar tu equipo." texto="Intenta de nuevo en un momento." />
        {:else}
          {#each personas as p (p.id)}
            <div class="fila">
              <span class="persona">
                <span class="inicial">{inicial(p.nombre)}</span>
                <span class="nombre">{p.nombre}</span>
                {#if p.yo}<span class="tu">TÚ</span>{/if}
              </span>
              <span class="roles">
                {#each p.roles as r (r)}
                  <span class="rol" class:gerente={r === 'gerente'}>{NOMBRE_ROL[r] ?? r}</span>
                {/each}
              </span>
              <span class="estado-pin">
                {#if (!p.gerente || p.yo) && desbloqueo?.id === p.id}
                  <button type="button" class="chico" disabled>
                    {#if desbloqueo.listo}<span class="verde"><Icono nombre="check" tamano={14} /></span>Desbloqueado{:else}Desbloquear{/if}
                  </button>
                {:else if (!p.gerente || p.yo) && p.bloqueo}
                  <span class="vis alto">
                    <Icono nombre="candado" tamano={14} />
                    {p.bloqueo.hasta ? `Bloqueado hasta las ${p.bloqueo.hasta}` : 'Bloqueado'}
                  </span>
                  <button type="button" class="chico" onclick={() => quitarBloqueo(p)}>Desbloquear</button>
                {:else if p.tienePin}
                  <span class="vis"><span class="p"></span>Puesto</span>
                {:else}
                  <span class="vis no"><span class="p"></span>Sin PIN</span>
                {/if}
              </span>
              {#if p.yo}
                <span class="acciones">
                  <BotonCuadro
                    icono="candado"
                    ayuda={p.tienePin ? 'Cambiar mi PIN' : 'Poner mi PIN'}
                    onclick={() => (ventana = { tipo: 'pin', persona: p })}
                  />
                </span>
              {:else if p.gerente}
                <span class="sin-acciones">Su cuenta la liga Fragmentless</span>
              {:else}
                <span class="acciones">
                  <BotonCuadro
                    icono="crear"
                    ayuda="Editar nombre y roles"
                    etiqueta="Editar {p.nombre}"
                    onclick={() => (ventana = { tipo: 'empleado', persona: p })}
                  />
                  <BotonCuadro
                    icono="candado"
                    ayuda="PIN nuevo"
                    etiqueta="PIN nuevo para {p.nombre}"
                    onclick={() => (ventana = { tipo: 'pin', persona: p })}
                  />
                  <BotonCuadro
                    icono="baja"
                    ayuda="Dar de baja"
                    etiqueta="Dar de baja a {p.nombre}"
                    onclick={() => (ventana = { tipo: 'baja', persona: p })}
                  />
                </span>
              {/if}
            </div>
          {/each}
          {#if !delEquipo.length}
            <NotaTabla
              relleno={48}
              angosta
              largoLinea={56}
              titulo="Todavía no tienes equipo."
              texto="Agrega a la primera persona de tu equipo con Nuevo empleado. Después vincula su celular o la tableta de la caja en Aparatos."
            />
          {/if}
        {/if}
      </Tabla>
    {:else}
      <Tabla
        columnas={COLUMNAS_APARATOS}
        relleno="0 16px"
        altoFila={64}
        encabezados={[{ texto: 'APARATO' }, { texto: 'DE QUIÉN ES' }, { texto: 'ÚLTIMO USO' }, { texto: '' }]}
      >
        {#if lectura.estado === 'leyendo'}
          <NotaTabla relleno={48} angosta titulo="Cargando tu equipo…" />
        {:else if lectura.estado === 'error' && lectura.deRed}
          <NotaTabla relleno={48} angosta titulo="Sin conexión." texto={SIN_CONEXION} />
        {:else if lectura.estado === 'error'}
          <NotaTabla relleno={48} angosta titulo="No se pudieron cargar tus aparatos." texto="Intenta de nuevo en un momento." />
        {:else if !aparatos.length}
          <NotaTabla
            relleno={48}
            angosta
            largoLinea={56}
            titulo="Todavía no hay aparatos ligados."
            texto="Vincula la tableta de la caja, la de la cocina o el celular de alguien de tu equipo con Vincular aparato."
          />
        {:else}
          {#each aparatos as a (a.id)}
            {@const de = dueno(a)}
            <div class="fila">
              <span class="aparato">
                <span class="cuadro-icono"><Icono nombre={a.miembroId === null ? 'tableta' : 'celular'} tamano={18} /></span>
                <span class="nombre">{a.nombre}</span>
              </span>
              {#if a.miembroId === null}
                <span class="de-quien compartido">Compartido · sale todo el equipo</span>
              {:else}
                <span class="de-quien">{de?.nombre ?? '—'}</span>
              {/if}
              <span class="uso" class:nunca={!a.ultimoUso}>{a.ultimoUso ?? 'Nadie ha entrado'}</span>
              <span class="acciones">
                <BotonCuadro
                  icono="desligar"
                  ayuda="Desligar"
                  etiqueta="Desligar {a.nombre}"
                  onclick={() => (ventana = { tipo: 'desligar', aparato: a })}
                />
              </span>
            </div>
          {/each}
        {/if}
      </Tabla>
    {/if}
  </Vidrio>
</main>

{#if equipo && ventana?.tipo === 'empleado'}
  <VentanaEmpleado
    restauranteId={sucursal.id}
    persona={ventana.persona}
    {personas}
    alCambiar={leer}
    alCerrar={() => (ventana = null)}
  />
{:else if ventana?.tipo === 'pin'}
  <VentanaPin persona={ventana.persona} alCambiar={leer} alCerrar={() => (ventana = null)} />
{:else if equipo && ventana?.tipo === 'vincular'}
  <VentanaVincular
    restauranteId={sucursal.id}
    equipo={delEquipo}
    {aparatos}
    alCambiar={leer}
    alCerrar={() => (ventana = null)}
  />
{:else if ventana?.tipo === 'baja'}
  {@const p = ventana.persona}
  <Confirmar
    icono="baja"
    titulo="¿Dar de baja a {p.nombre}?"
    texto="Ya no podrá entrar, y su celular se desliga. Sus ventas siguen a su nombre en tus reportes. Si regresa, se da de alta otra vez."
    boton={{ etiqueta: 'Sí, dar de baja', icono: 'baja' }}
    textoCargando="Dando de baja…"
    confirmar={() => confirmar(() => darDeBaja(p.id), 'Baja lista')}
    alCerrar={() => (ventana = null)}
  />
{:else if ventana?.tipo === 'desligar'}
  {@const a = ventana.aparato}
  <Confirmar
    icono="desligar"
    titulo="¿Desligar «{a.nombre}»?"
    texto="Ese aparato ya no entra, y quien esté adentro sale al instante. Para volver a usarlo, vincúlalo otra vez."
    boton={{ etiqueta: 'Sí, desligar', icono: 'desligar' }}
    textoCargando="Desligando…"
    confirmar={() => confirmar(() => desligar(a.id), 'Desligado')}
    alCerrar={() => (ventana = null)}
  />
{/if}

{#if aviso}
  {#key aviso}
    <AvisoFlotante mensaje={aviso} alTerminar={() => (aviso = null)} />
  {/key}
{/if}

<style>
  /* Debajo de la barra de arriba (16 + 60 + 16) y a la derecha de la lateral (16 + 244 + 16). */
  .cuerpo {
    position: absolute;
    left: 276px;
    right: 16px;
    top: 92px;
    bottom: 16px;
  }

  .cuerpo > :global(.tarjeta-equipo) {
    height: 100%;
    padding: 20px;
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  .herramientas {
    flex: none;
    min-height: 40px;
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .nota {
    margin: 0;
    font-size: 12.5px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .crece {
    flex-grow: 1;
  }

  .persona,
  .aparato {
    min-width: 0;
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .inicial {
    width: 36px;
    height: 36px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 18px;
    border: 1px solid var(--linea);
    background: var(--chip);
    font-size: 13px;
    font-weight: 700;
  }

  .nombre {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 13.5px;
    font-weight: 700;
  }

  .tu {
    flex: none;
    padding: 2px 7px;
    border-radius: 6px;
    background: var(--chip);
    font-family: var(--mono);
    font-size: 10px;
    letter-spacing: 0.08em;
    color: var(--suave);
  }

  .roles {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }

  .rol {
    display: inline-flex;
    align-items: center;
    padding: 4px 10px;
    border-radius: 8px;
    background: var(--chip);
    font-size: 12px;
    font-weight: 600;
    color: var(--suave);
    white-space: nowrap;
  }

  .rol.gerente {
    background: transparent;
    border: 1px solid var(--linea-fuerte);
    color: var(--texto);
  }

  /* Si la columna se angosta (una ventana chica), Desbloquear y el texto bajan de renglón: nunca
     se enciman con los botones de la fila. */
  .estado-pin {
    min-width: 0;
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 6px 10px;
    padding-block: 8px;
  }

  .vis {
    min-width: 0;
    display: inline-flex;
    align-items: center;
    gap: 8px;
    font-size: 12.5px;
    font-weight: 600;
  }

  .vis .p {
    width: 8px;
    height: 8px;
    flex: none;
    border-radius: 4px;
    background: var(--tinta);
  }

  .vis.no {
    font-weight: 500;
    color: var(--tenue);
  }

  .vis.no .p {
    background: transparent;
    border: 1.5px solid var(--tenue);
  }

  .vis.alto {
    color: var(--texto);
  }

  .vis.alto :global(svg) {
    color: var(--suave);
  }

  /* El botón chico de Desbloquear (boton-chico de la maqueta): 30 de alto, sin icono. */
  .chico {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 30px;
    padding: 0 10px;
    border: 1px solid var(--linea);
    border-radius: 10px;
    background: transparent;
    color: var(--texto);
    font-size: 12px;
    font-weight: 600;
    white-space: nowrap;
    transition: opacity 150ms;
  }

  .chico:hover:not(:disabled) {
    opacity: 0.86;
  }

  .chico:disabled {
    cursor: default;
  }

  .verde {
    color: var(--verde);
  }

  .acciones {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
  }

  .sin-acciones {
    font-size: 12px;
    line-height: 1.35;
    color: var(--tenue);
    text-align: right;
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

  .de-quien {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 13px;
    font-weight: 600;
  }

  .de-quien.compartido {
    font-weight: 500;
    color: var(--suave);
  }

  .uso {
    font-family: var(--mono);
    font-size: 12px;
    color: var(--suave);
    font-variant-numeric: tabular-nums;
    white-space: nowrap;
  }

  .uso.nunca {
    color: var(--tenue);
  }
</style>
