<!--
  Mesas, portada de la maqueta aprobada el 13 de octubre de 2026 (4TKmJzMwyWMCAVU2MwEDwc), que
  es «Mesas» de Flet (mesas_view.py) con flechas. Las columnas Estado, Abierta y Cuenta volvieron con
  la pieza 5 (maqueta Cortes y reportes 7J6LvYWiktRnGxNugbuaoe): salen de mesas_ahora, igual que
  Mesas ahora en Inicio, con cuántas están ocupadas y lo que falta por cobrar (lo suma Postgres).
  Si las cuentas no se pudieron leer, van guiones: nunca un «Disponible» inventado. Arriba: el
  título, el chip con cuántas mesas hay y Nueva mesa. Abajo, la tarjeta de vidrio con la tabla:
  cada mesa con su lugar, su nombre, su estado, desde cuándo está abierta, su cuenta, las flechas,
  el lápiz y el bote. Encima, las ventanas.

  Lee las mesas de la sucursal al abrir y después de cada cambio, y las cuentas también cada vez
  que cambia una (tiempo real) y al regresar a la pestaña. Las flechas cambian la tabla
  en cuanto se pulsan y se guardan al instante; si Postgres no pudo, sale el aviso de abajo
  (aviso() de Flet) y se vuelve a leer lo que de verdad quedó.
-->
<script lang="ts">
  import { onMount, tick } from 'svelte';
  import AvisoFlotante from '../../diseno/AvisoFlotante.svelte';
  import BarraArriba from '../../diseno/BarraArriba.svelte';
  import Boton from '../../diseno/Boton.svelte';
  import BotonCuadro from '../../diseno/BotonCuadro.svelte';
  import Confirmar from '../../diseno/Confirmar.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import NotaTabla from '../../diseno/NotaTabla.svelte';
  import Tabla from '../../diseno/Tabla.svelte';
  import Vidrio from '../../diseno/Vidrio.svelte';
  import { ALGO_SALIO_PANEL, esDeRed, Fallo, SIN_CONEXION } from '../../lib/errores';
  import { dinero, plural } from '../../lib/formato';
  import type { Sucursal } from '../../lib/gerente';
  import { eliminarMesa, leerMesas, moverMesa, type Mesa } from '../../lib/mesas';
  import { escuchar } from '../../lib/pos';
  import { leerMesasAhora, type MesaAhora, type MesasAhora } from '../../lib/reportes';
  import { supabase } from '../../lib/supabase';
  import VentanaMesa from './mesas/VentanaMesa.svelte';

  let { sucursal }: { sucursal: Sucursal } = $props();

  type Lectura = { estado: 'leyendo' } | { estado: 'listo'; mesas: Mesa[] } | { estado: 'error'; deRed: boolean };

  let lectura = $state<Lectura>({ estado: 'leyendo' });
  let ventana = $state<{ tipo: 'mesa'; mesa: Mesa | null } | { tipo: 'eliminar'; mesa: Mesa } | null>(null);
  let aviso = $state<string | null>(null);
  let tarjeta = $state<HTMLElement>();

  const mesas = $derived(lectura.estado === 'listo' ? lectura.mesas : null);

  const estado = $derived.by(() => {
    if (lectura.estado === 'leyendo') return { texto: 'Cargando tus mesas…', vivo: true };
    if (lectura.estado === 'error') return { texto: lectura.deRed ? 'Sin conexión' : 'No se pudo leer', vivo: false };
    return { texto: plural(lectura.mesas.length, 'mesa', 'mesas'), vivo: true };
  });

  async function leer() {
    leerCuentas();
    try {
      lectura = { estado: 'listo', mesas: await leerMesas(sucursal.id) };
    } catch (error) {
      console.error('[mesas] no se pudieron leer las mesas:', error);
      lectura = { estado: 'error', deRed: esDeRed(error) };
    }
  }

  // ─── Las cuentas abiertas: Estado, Abierta y Cuenta ───
  let cuentas = $state<{ estado: 'leyendo' } | { estado: 'listo'; datos: MesasAhora } | { estado: 'error' }>({ estado: 'leyendo' });
  let vuelta = 0;

  async function leerCuentas() {
    const esta = ++vuelta;
    try {
      const datos = await leerMesasAhora(sucursal.id);
      if (esta === vuelta) cuentas = { estado: 'listo', datos };
    } catch (error) {
      console.error('[mesas] no se pudieron leer las cuentas abiertas:', error);
      if (esta === vuelta) cuentas = { estado: 'error' };
    }
  }

  const porMesa = $derived(
    cuentas.estado === 'listo' ? new Map<number, MesaAhora>(cuentas.datos.mesas.map((m) => [m.id, m])) : null,
  );

  const conteo = $derived.by(() => {
    if (cuentas.estado === 'error') return 'NO SE PUDIERON LEER LAS CUENTAS';
    if (cuentas.estado !== 'listo') return mesas ? plural(mesas.length, 'MESA', 'MESAS') : '';
    const { mesas: todas, ocupadas, por_cobrar } = cuentas.datos;
    return `${ocupadas} DE ${todas.length} OCUPADA${ocupadas === 1 ? '' : 'S'}` + (ocupadas ? ` · ${dinero(por_cobrar)} POR COBRAR` : '');
  });

  // «hace 12 min», como _hace() de Flet; el reloj avanza solo cada medio minuto.
  let ahora = $state(Date.now());
  function hace(desde: string): string {
    const minutos = Math.max(0, Math.floor((ahora - Date.parse(desde)) / 60000));
    if (minutos < 1) return 'hace un momento';
    if (minutos < 60) return `hace ${minutos} min`;
    const horas = Math.floor(minutos / 60);
    const resto = minutos % 60;
    return resto ? `hace ${horas} h ${resto} min` : `hace ${horas} h`;
  }

  let espera: ReturnType<typeof setTimeout> | undefined;
  onMount(() => {
    leer();
    const dejar = escuchar(supabase, sucursal.id, ['ventas'], () => {
      clearTimeout(espera);
      espera = setTimeout(leerCuentas, 400);
    });
    const reloj = setInterval(() => (ahora = Date.now()), 30000);
    const alVolver = () => {
      if (document.visibilityState === 'visible') leerCuentas();
    };
    document.addEventListener('visibilitychange', alVolver);
    return () => {
      clearTimeout(espera);
      clearInterval(reloj);
      dejar();
      document.removeEventListener('visibilitychange', alVolver);
    };
  });

  // Las flechas: la tabla cambia en cuanto se pulsa y se guarda al instante; si Postgres no
  // pudo, sale el aviso y se vuelve a leer lo que de verdad quedó.
  async function mover(m: Mesa, hacia: 'arriba' | 'abajo') {
    if (!mesas) return;
    const aqui = mesas.findIndex((x) => x.id === m.id);
    const alla = hacia === 'arriba' ? aqui - 1 : aqui + 1;
    if (aqui < 0 || alla < 0 || alla >= mesas.length) return;
    [mesas[aqui], mesas[alla]] = [mesas[alla], mesas[aqui]];
    await tick();
    const atributo = hacia === 'arriba' ? 'data-subir' : 'data-bajar';
    const boton = tarjeta?.querySelector<HTMLButtonElement>(`[${atributo}="${m.id}"]`);
    if (boton && !boton.disabled) boton.focus({ preventScroll: true });
    try {
      await moverMesa(m.id, hacia);
    } catch (falla) {
      aviso = (falla as Error).message;
      await leer();
    }
  }

  // Postgres la borra si nunca tuvo cuentas y la archiva si ya tuvo; para Don Chuy se ve igual.
  async function eliminar(m: Mesa): Promise<{ listo: string } | { error: string }> {
    try {
      await eliminarMesa(m.id);
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[mesas] no se pudo eliminar la mesa:', falla);
      return { error: falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL };
    }
    leer();
    return { listo: 'Eliminada' };
  }
</script>

<BarraArriba titulo="Mesas" {estado}>
  <Boton
    etiqueta="Nueva mesa"
    icono="mas"
    tono="tinta"
    apagado={!mesas}
    onclick={() => (ventana = { tipo: 'mesa', mesa: null })}
  />
</BarraArriba>

<main class="cuerpo" bind:this={tarjeta}>
  <Vidrio como="section" class="tarjeta-mesas" radio={26} aria-label="Mesas">
    <div class="herramientas">
      <p class="nota">Las mesas que tu equipo elige al tomar un pedido, en este orden. Muévelas con las flechas.</p>
      <span class="crece"></span>
      {#if mesas}<span class="etiqueta">{conteo}</span>{/if}
    </div>

    <Tabla
      columnas="minmax(0, 1fr) 150px 150px 120px 168px"
      relleno="0 16px"
      altoFila={64}
      encabezados={[{ texto: 'MESA' }, { texto: 'ESTADO' }, { texto: 'ABIERTA' }, { texto: 'CUENTA' }, { texto: '' }]}
    >
      {#if lectura.estado === 'leyendo'}
        <NotaTabla relleno={48} angosta titulo="Cargando tus mesas…" />
      {:else if lectura.estado === 'error' && lectura.deRed}
        <NotaTabla relleno={48} angosta titulo="Sin conexión." texto={SIN_CONEXION} />
      {:else if lectura.estado === 'error'}
        <NotaTabla relleno={48} angosta titulo="No se pudieron cargar tus mesas." texto="Intenta de nuevo en un momento." />
      {:else if !lectura.mesas.length}
        <NotaTabla
          relleno={48} angosta
          titulo="Todavía no tienes mesas."
          texto="Agrega la primera con Nueva mesa, por ejemplo «Mesa 1» o «Barra»."
        />
      {:else}
        {#each lectura.mesas as m, i (m.id)}
          <div class="fila">
            <span class="mesa">
              <span class="numero">{String(i + 1).padStart(2, '0')}</span>
              <span class="cuadro-icono"><Icono nombre="mesas" tamano={18} /></span>
              <span class="nombre">{m.nombre}</span>
            </span>
            {#if !porMesa}
              <span class="estado libre">—</span>
              <span class="desde libre">—</span>
              <span class="cuenta libre">—</span>
            {:else if porMesa.get(m.id)?.venta_id}
              {@const c = porMesa.get(m.id)}
              <span class="estado"><span class="marca"></span>Ocupada</span>
              <span class="desde">{c?.abierta_at ? hace(c.abierta_at) : '—'}</span>
              <span class="cuenta">{c?.total === null || c?.total === undefined ? '—' : dinero(c.total)}</span>
            {:else}
              <span class="estado libre"><span class="marca libre"></span>Disponible</span>
              <span class="desde libre">—</span>
              <span class="cuenta libre">—</span>
            {/if}
            <span class="acciones">
              <BotonCuadro
                icono="arriba"
                ayuda="Subir"
                etiqueta="Subir {m.nombre}"
                apagado={i === 0}
                data-subir={m.id}
                onclick={() => mover(m, 'arriba')}
              />
              <BotonCuadro
                icono="abajo"
                ayuda="Bajar"
                etiqueta="Bajar {m.nombre}"
                apagado={i === lectura.mesas.length - 1}
                data-bajar={m.id}
                onclick={() => mover(m, 'abajo')}
              />
              <BotonCuadro
                icono="crear"
                ayuda="Renombrar mesa"
                etiqueta="Renombrar {m.nombre}"
                onclick={() => (ventana = { tipo: 'mesa', mesa: m })}
              />
              <BotonCuadro
                icono="eliminar"
                ayuda="Eliminar mesa"
                etiqueta="Eliminar {m.nombre}"
                onclick={() => (ventana = { tipo: 'eliminar', mesa: m })}
              />
            </span>
          </div>
        {/each}
      {/if}
    </Tabla>
  </Vidrio>
</main>

{#if mesas && ventana?.tipo === 'mesa'}
  <VentanaMesa
    restauranteId={sucursal.id}
    mesa={ventana.mesa}
    {mesas}
    alCambiar={leer}
    alCerrar={() => (ventana = null)}
  />
{:else if ventana?.tipo === 'eliminar'}
  {@const m = ventana.mesa}
  <Confirmar
    icono="eliminar"
    titulo="¿Eliminar esta mesa?"
    texto="«{m.nombre}» se quita de tus mesas. Si ya tuvo cuentas, tus reportes las siguen contando."
    boton={{ etiqueta: 'Sí, eliminar', icono: 'eliminar' }}
    textoCargando="Eliminando…"
    confirmar={() => eliminar(m)}
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

  .cuerpo > :global(.tarjeta-mesas) {
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

  .mesa {
    min-width: 0;
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .numero {
    width: 22px;
    flex: none;
    font-family: var(--mono);
    font-size: 11px;
    color: var(--tenue);
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

  .nombre {
    min-width: 0;
    overflow: hidden;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    font-size: 13.5px;
    font-weight: 700;
  }

  .acciones {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
  }

  .estado {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 12.5px;
    font-weight: 600;
  }

  .estado.libre {
    font-weight: 500;
  }

  .marca {
    width: 8px;
    height: 8px;
    flex: none;
    border-radius: 4px;
    background: var(--tinta);
  }

  .marca.libre {
    background: transparent;
    border: 1.5px solid var(--tenue);
  }

  .desde {
    font-size: 12.5px;
    color: var(--suave);
  }

  .cuenta {
    font-family: var(--mono);
    font-size: 13px;
    font-variant-numeric: tabular-nums;
  }

  .estado.libre,
  .desde.libre,
  .cuenta.libre {
    color: var(--tenue);
  }
</style>
