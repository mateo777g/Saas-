<!--
  Pedidos en el panel del gerente (parte 6b; maqueta Pedidos por WhatsApp G2nxGb3xBgiPEYrDb6CgcW):
  la misma lista de la caja, con la sesión de Don Chuy, así que lo que confirma queda a su nombre.
  Tiene el ancho del celular, al centro de la tarjeta, como la caja abierta desde Inicio. La vigía
  vive en PanelGerente, para que el tono suene en cualquier vista.

  Con la adaptabilidad (encuesta 15 «A, Tablero»; planes/trabajo/adaptabilidad/pedidos-ancho.md): cuando la vista mide
  unos 900 px o más, Pedidos va a lo ancho sobre el fondo de las vistas, sin el celular. Arriba, el chip dice lo que pasa
  («Recibiendo pedidos hasta las 22:00», «En pausa desde las 14:05» con su punto amarillo) y a la derecha van «Pausar
  pedidos» (o «Reanudar») y la cajita de sucursales.

  «Hago envíos» vive aquí desde el 14 nov 2026 (se fue de Tu restaurante; planes/trabajo/rediseno/pedidos-vista.md): en la
  barra de arriba, antes de «Pausar pedidos», a lo ancho y en la columna de celular. Solo el gerente lo cambia, así que el
  aparato no lo lleva. Lo guarda guardar_restaurante, que pide todos los datos del restaurante: se leen los de ahora y se
  mandan igual, con el nuevo «Hago envíos» (sin migraciones, no hay otra función que lo cambie).
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import BarraArriba from '../../diseno/BarraArriba.svelte';
  import Boton from '../../diseno/Boton.svelte';
  import Tarjeta from '../../diseno/Tarjeta.svelte';
  import { ALGO_SALIO_PANEL, esDeRed, Fallo, SIN_CONEXION } from '../../lib/errores';
  import { enZona } from '../../lib/formato';
  import type { Sucursal } from '../../lib/gerente';
  import type { VigiaPedidos } from '../../lib/pedidos.svelte';
  import { leerZona } from '../../lib/pos';
  import { guardarRestaurante, leerRestaurante } from '../../lib/restaurante';
  import { supabase } from '../../lib/supabase';
  import Pedidos from '../caja/Pedidos.svelte';
  import { franjaDe } from '../caja/pedidos/franja';
  import CajaSucursales from './CajaSucursales.svelte';
  import HagoEnvios from './pedidos/HagoEnvios.svelte';

  let {
    sucursal,
    sucursales,
    vigia,
    alElegir,
  }: { sucursal: Sucursal; sucursales: Sucursal[]; vigia: VigiaPedidos; alElegir: (s: Sucursal) => void } = $props();

  let zona = $state('America/Mexico_City');

  // Lo que mide la vista (de la barra lateral al borde, sin sus márgenes): desde 900, a lo ancho.
  let anchoVista = $state(0);
  const ancho = $derived(anchoVista >= 900);

  const estado = $derived.by(() => {
    const d = vigia.datos;
    if (ancho) {
      if (!d) return vigia.error ? { texto: 'No se pudo leer', vivo: false } : { texto: 'Cargando los pedidos…', vivo: true };
      const f = franjaDe(d, zona, true);
      return { texto: f.chip, vivo: f.tono === 'vivo', pausa: f.tono === 'pausa', hueco: f.tono === 'apagado' };
    }
    if (!d) return { texto: vigia.error ? 'No se pudo leer' : 'Leyendo…', vivo: false };
    if (d.pausado) return { texto: `En pausa desde las ${enZona(d.pausado_at ?? d.ahora, zona).hora}`, vivo: false, pausa: true };
    const n = d.por_confirmar.length;
    return { texto: n ? `${n} por confirmar` : 'Nada por confirmar', vivo: true };
  });

  // ─── «Hago envíos» ───
  // null = todavía no se sabe (se está leyendo, o no se pudo).
  let envios = $state<boolean | null>(null);
  let leyendoEnvios = $state(true);
  let guardandoEnvios = $state(false);
  let errorEnvios = $state<string | null>(null);

  async function leerEnvios() {
    try {
      const { data, error } = await supabase.from('restaurantes').select('hace_envios').eq('id', sucursal.id).single();
      if (error) throw error;
      if (!guardandoEnvios) envios = data.hace_envios as boolean;
      errorEnvios = null;
    } catch (falla) {
      console.error('[pedidos] no se pudo leer «Hago envíos»:', falla);
      // Si ya se sabía, se queda lo que había; si no, se dice (el riel apagado y sin picarse).
      if (envios === null) errorEnvios = esDeRed(falla) ? SIN_CONEXION : 'No se pudo leer si haces envíos. Intenta de nuevo en un momento.';
    } finally {
      leyendoEnvios = false;
    }
  }

  // Cambia en ese momento; si no se pudo guardar, regresa y se dice.
  async function cambiarEnvios(prendido: boolean) {
    if (envios === null || guardandoEnvios) return;
    const antes = envios;
    envios = prendido;
    guardandoEnvios = true;
    errorEnvios = null;
    try {
      // guardar_restaurante pide todo: lo de ahora, igual, con el nuevo «Hago envíos».
      const r = await leerRestaurante(sucursal.id);
      await guardarRestaurante(sucursal.id, {
        nombre: r.nombre,
        telefono: r.telefono ?? '',
        direccion: r.direccion ?? '',
        logo_ruta: r.logo_ruta,
        horario: r.horario,
        hace_envios: prendido,
      });
    } catch (falla) {
      envios = antes;
      if (!(falla instanceof Fallo)) console.error('[pedidos] no se pudo guardar «Hago envíos»:', falla);
      errorEnvios = falla instanceof Fallo ? falla.message : esDeRed(falla) ? SIN_CONEXION : ALGO_SALIO_PANEL;
    } finally {
      guardandoEnvios = false;
    }
  }

  onMount(() => {
    leerZona(supabase, sucursal.id)
      .then((z) => (zona = z))
      .catch((falla) => console.error('[gerente] no se pudo leer la zona de Pedidos; se usa la de México:', falla));
    leerEnvios();
    // Como los demás paneles, vuelve a leer al regresar a la pestaña.
    const alVolver = () => {
      if (document.visibilityState === 'visible') leerEnvios();
    };
    document.addEventListener('visibilitychange', alVolver);
    return () => document.removeEventListener('visibilitychange', alVolver);
  });
</script>

<BarraArriba titulo="Pedidos" {estado}>
  <HagoEnvios prendido={envios} leyendo={leyendoEnvios} guardando={guardandoEnvios} alCambiar={cambiarEnvios} />
  {#if ancho}
    {@const pausado = vigia.datos?.pausado ?? false}
    <Boton
      etiqueta={pausado ? 'Reanudar' : 'Pausar pedidos'}
      icono={pausado ? 'reanudar' : 'detener'}
      cargando={vigia.pausando}
      apagado={!vigia.datos}
      onclick={() => vigia.pausar()}
    />
  {/if}
  <CajaSucursales {sucursales} actual={sucursal} {alElegir} />
</BarraArriba>

<div class="medida" bind:clientWidth={anchoVista}></div>

{#if ancho}
  <main class="cuerpo">
    <Pedidos cliente={supabase} restauranteId={sucursal.id} restaurante={sucursal.nombre} {vigia} enPanel franjaAfuera errorArriba={errorEnvios} />
  </main>
{:else if anchoVista > 0}
  <Tarjeta como="main" class="tarjeta-pedidos">
    <div class="panel-cel">
      <Pedidos cliente={supabase} restauranteId={sucursal.id} restaurante={sucursal.nombre} {vigia} enPanel errorArriba={errorEnvios} />
    </div>
  </Tarjeta>
{/if}

<style>
  .medida {
    position: absolute;
    left: var(--vista-izquierda);
    right: var(--vista-derecha);
    top: var(--vista-arriba);
    height: 0;
    pointer-events: none;
  }

  /* A lo ancho: sobre el fondo de las vistas, en el lugar de una vista (como Mesas y Empleados). */
  .cuerpo {
    position: absolute;
    left: var(--vista-izquierda);
    right: var(--vista-derecha);
    top: var(--vista-arriba);
    bottom: var(--vista-abajo);
  }

  :global(.tarjeta-pedidos) {
    position: absolute;
    left: var(--vista-izquierda);
    right: var(--vista-derecha);
    top: var(--vista-arriba);
    bottom: var(--vista-abajo);
    overflow: hidden;
  }

  .panel-cel {
    position: absolute;
    top: 16px;
    bottom: 16px;
    left: 50%;
    width: 390px;
    max-width: calc(100% - 32px);
    transform: translateX(-50%);
    border-radius: 30px;
    border: 1px solid var(--linea);
    background: var(--suelo);
    overflow: hidden;
    display: flex;
    flex-direction: column;
  }

  .panel-cel > :global(.pos) {
    flex: 1;
    min-height: 0;
    padding: 18px 16px 30px;
  }
</style>
