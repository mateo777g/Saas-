<!--
  «Tarjeta de lealtad» en Tu negocio (parte B, paso 5c; maqueta v22 aprobada el 23 nov 2026, `planes/maquetas/tarjeta-lealtad/`,
  pantalla «Tarjeta de lealtad»). Dos secciones con el dock de Mi menú en la barra de arriba:
  · Tarjetas (lealtad/Tarjetas.svelte): la tarjeta de la regla (la muestra que se voltea, la regla en tres renglones,
    «Editar tu regla» y el interruptor) y la tabla de tarjetas como la de Mi menú; sin regla, por qué sirve y «Poner tu
    regla». Arriba, «Confirmar un código» (pasar una tarjeta a otro celular).
  · Tu tarjeta (lealtad/TuTarjeta.svelte): cómo se ve, como «Tu menú en línea»: sellos o puntos, el estilo y el color, con
    el teléfono a la derecha (?muestra=tarjeta) y la barra de guardar.
  Al cambiar de sección, lo de la sección entra en cascada, como las filas de Mi menú. Lo que no se ha guardado de Tu
  tarjeta se queda al ir a Tarjetas; al salir de la vista con cambios, «Tienes cambios sin guardar».
-->
<script lang="ts">
  import { onMount, tick } from 'svelte';
  import BarraArriba from '../../diseno/BarraArriba.svelte';
  import Boton from '../../diseno/Boton.svelte';
  import { cascada } from '../../diseno/cascada';
  import Dock from '../../diseno/Dock.svelte';
  import Esqueleto from '../../diseno/Esqueleto.svelte';
  import { esDeRed, SIN_CONEXION } from '../../lib/errores';
  import type { Sucursal } from '../../lib/gerente';
  import { urlFoto } from '../../lib/fotos';
  import { conRegla, leerLealtad, leerMarca, leerTarjetas, type Lealtad, type Tarjetas as DatosTarjetas } from '../../lib/lealtad';
  import { leerMenu, type Menu } from '../../lib/menu';
  import { supabase } from '../../lib/supabase';
  import CajaSucursales from './CajaSucursales.svelte';
  import Tarjetas from './lealtad/Tarjetas.svelte';
  import TuTarjeta from './lealtad/TuTarjeta.svelte';
  import VentanaPasar from '../lealtad/VentanaPasar.svelte';

  let { sucursal, sucursales, alElegir }: { sucursal: Sucursal; sucursales: Sucursal[]; alElegir: (s: Sucursal) => void } =
    $props();

  // Lo que entra en cascada (como la maqueta): la tarjeta de la regla, la búsqueda, las filas de la tabla, las filas de
  // Tu tarjeta y el teléfono.
  const CASCADA = '.tl-seccion > :not(.tabla), .tl-seccion .tabla .cuerpo > .fila, .col > *, .lado';

  type Seccion = 'tarjetas' | 'diseno';
  let seccion = $state<Seccion>('tarjetas');
  let lealtad = $state<Lealtad | null>(null);
  let tarjetas = $state<DatosTarjetas | null>(null);
  let menu = $state<Menu | null>(null);
  let colorMenu = $state<string | null>(null);
  let logo = $state<string | null>(null);
  let errorLectura = $state<string | null>(null);
  let errorTarjetas = $state<string | null>(null);
  let pasando = $state(false);
  let cuerpo = $state<HTMLElement>();

  async function leer() {
    try {
      const [l, m, d] = await Promise.all([leerLealtad(supabase, sucursal.id), leerMenu(sucursal.id), leerMarca(supabase, sucursal.id)]);
      lealtad = l;
      menu = m;
      colorMenu = d.colorMenu;
      logo = d.logo ? urlFoto(d.logo) : null;
      errorLectura = null;
    } catch (falla) {
      console.error('[lealtad] no se pudo leer:', falla);
      errorLectura = esDeRed(falla) ? SIN_CONEXION : 'No se pudo leer tu tarjeta de lealtad. Intenta de nuevo en un momento.';
    }
  }

  async function leerLasTarjetas() {
    try {
      tarjetas = await leerTarjetas(supabase, sucursal.id);
      errorTarjetas = null;
    } catch (falla) {
      errorTarjetas = falla instanceof Error ? falla.message : 'No se pudieron leer tus tarjetas.';
    }
  }

  // Después de guardar la regla, prenderla o guardar Tu tarjeta: la regla y las tarjetas otra vez (lo juntado puede
  // volver a 0 y el aviso del premio cambiar).
  async function alCambiar() {
    await Promise.all([leer(), leerLasTarjetas()]);
  }

  onMount(() => {
    void (async () => {
      await Promise.all([leer(), leerLasTarjetas()]);
      await tick();
      cascada(cuerpo, CASCADA);
    })();
    // Al volver a la pestaña, se releen quietas (sin esqueleto ni cascada).
    const alVolver = () => {
      if (!document.hidden) void Promise.all([leer(), leerLasTarjetas()]);
    };
    document.addEventListener('visibilitychange', alVolver);
    return () => document.removeEventListener('visibilitychange', alVolver);
  });

  async function cambiarSeccion(valor: Seccion) {
    if (valor === seccion) return;
    seccion = valor;
    await tick();
    cascada(cuerpo, CASCADA);
  }

  const regla = $derived(!!lealtad && conRegla(lealtad));
  const chip = $derived.by(() => {
    if (errorLectura) return { texto: 'No se pudo leer', vivo: false };
    if (!lealtad || !regla) return null;
    return lealtad.prendida ? { texto: 'Prendida · tu menú la ofrece', vivo: true } : { texto: 'Apagada · tu menú no la ofrece', vivo: false, apagado: true };
  });
</script>

<BarraArriba titulo="Tarjeta de lealtad" estado={chip} chipAntes>
  {#snippet junto()}
    {#if !lealtad && !errorLectura}<span class="chip-esqueleto"><Esqueleto ancho="200px" alto="26px" redondo="13px" /></span>{/if}
    <Dock
      etiqueta="Qué ves"
      opciones={[
        { valor: 'tarjetas', texto: 'Tarjetas', icono: 'usuarios' },
        { valor: 'diseno', texto: 'Tu tarjeta', icono: 'r-lealtad' },
      ]}
      elegida={seccion}
      alElegir={cambiarSeccion}
    />
  {/snippet}
  {#if seccion === 'tarjetas' && regla}
    <Boton etiqueta="Confirmar un código" icono="celular" onclick={() => (pasando = true)} />
  {/if}
  <CajaSucursales {sucursales} actual={sucursal} {alElegir} />
</BarraArriba>

<div class="lugar" bind:this={cuerpo}>
  {#if seccion === 'tarjetas'}
    <Tarjetas
      restauranteId={sucursal.id}
      restaurante={sucursal.nombre}
      {lealtad}
      {tarjetas}
      {menu}
      {colorMenu}
      {logo}
      {errorLectura}
      {errorTarjetas}
      {alCambiar}
      alPasar={() => (pasando = true)}
    />
  {:else}
    <TuTarjeta {sucursal} {lealtad} {menu} {colorMenu} cuantasTarjetas={tarjetas?.tarjetas.length ?? 0} {errorLectura} {alCambiar} />
  {/if}
</div>

{#if pasando}
  <VentanaPasar cliente={supabase} restauranteId={sucursal.id} alPasar={leerLasTarjetas} alCerrar={() => (pasando = false)} />
{/if}

<style>
  .lugar {
    display: contents;
  }

  .chip-esqueleto {
    display: flex;
  }
</style>
