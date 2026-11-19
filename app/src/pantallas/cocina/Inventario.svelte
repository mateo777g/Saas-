<!--
  La pestaña Inventario de la tableta de cocina (maqueta BBBNJST5w9qZfHWNdovGgb v3, «Cocina · Inventario»; encuestas 9 y
  17): la tabla de los ingredientes del gerente, sin la caja ni el lápiz, con cuánto queda y qué se está acabando. Arriba,
  la barra del aparato con su dock, el chip («5 se están acabando»), «Merma» y «Llegó», que abren las mismas ventanas del
  gerente, y el reloj. Contar, las recetas y los ingredientes siguen siendo del gerente. Los ingredientes vienen de la
  vigía del aparato (lib/vigiaInventario.svelte.ts), en vivo.

  Usa la sesión del aparato que le pasan, nunca la del panel.
-->
<script lang="ts">
  import type { SupabaseClient } from '@supabase/supabase-js';
  import { onMount } from 'svelte';
  import Boton from '../../diseno/Boton.svelte';
  import { esDeRed, SIN_CONEXION } from '../../lib/errores';
  import { filasDeLaUltimaVez, recordarFilas } from '../../lib/esqueletos';
  import { enZona } from '../../lib/formato';
  import { leerZona } from '../../lib/pos';
  import type { VigiaInventario } from '../../lib/vigiaInventario.svelte';
  import Ingredientes from '../gerente/inventario/Ingredientes.svelte';
  import VentanaLlego from '../gerente/inventario/VentanaLlego.svelte';
  import VentanaMerma from '../gerente/inventario/VentanaMerma.svelte';
  import '../gerente/inventario/tabla.css';
  import Barra from '../pos/ancho/Barra.svelte';
  import type { Anfitrion } from '../pos/ancho/barra';
  import '../pos/ancho/ancho.css';

  let {
    cliente,
    restauranteId,
    vigia,
    anfitrion,
  }: { cliente: SupabaseClient; restauranteId: string; vigia: VigiaInventario; anfitrion: Anfitrion } = $props();

  let ventana = $state<'llego' | 'merma' | null>(null);
  const ingredientes = $derived(vigia.ingredientes ?? []);
  const cargando = $derived(vigia.ingredientes === null && !vigia.error);

  // svelte-ignore state_referenced_locally
  const llave = `inventario-cocina-${restauranteId}`;
  const esqueletos = filasDeLaUltimaVez(llave);
  $effect(() => {
    if (vigia.ingredientes) recordarFilas(llave, vigia.ingredientes.length);
  });

  const chip = $derived.by(() => {
    if (cargando) return { texto: 'Cargando el inventario…', vivo: true };
    if (!vigia.ingredientes) return { texto: esDeRed(vigia.error) ? 'Sin conexión' : 'No se pudo leer', vivo: false };
    if (!vigia.ingredientes.length) return { texto: 'Sin ingredientes', vivo: false };
    return vigia.acaban
      ? { texto: `${vigia.acaban} ${vigia.acaban === 1 ? 'se está acabando' : 'se están acabando'}`, vivo: false, pausa: true }
      : { texto: 'Nada se está acabando', vivo: true };
  });
  const error = $derived(
    vigia.ingredientes === null && vigia.error
      ? esDeRed(vigia.error)
        ? { titulo: 'Sin conexión.', texto: SIN_CONEXION }
        : { titulo: 'No se pudo cargar el inventario.', texto: 'Intenta de nuevo en un momento.' }
      : null,
  );

  // El reloj de la cocina, en la zona del restaurante.
  let zona = $state('America/Mexico_City');
  let ahora = $state(Date.now());
  const reloj = $derived(enZona(new Date(ahora).toISOString(), zona).hora);
  onMount(() => {
    leerZona(cliente, restauranteId)
      .then((z) => (zona = z))
      .catch((falla) => console.error('[inventario] no se pudo leer la zona; el reloj usa la de México:', falla));
    const tic = setInterval(() => (ahora = Date.now()), 15000);
    return () => clearInterval(tic);
  });
</script>

<div class="cocina-inventario">
  <div class="pos-ancho barra-c">
    <Barra {anfitrion} titulo="Inventario" {chip}>
      <Boton etiqueta="Merma" icono="eliminar" apagado={!ingredientes.length} onclick={() => (ventana = 'merma')} />
      <Boton etiqueta="Llegó" icono="llego" apagado={!ingredientes.length} onclick={() => (ventana = 'llego')} />
      <span class="reloj">{reloj}</span>
    </Barra>
  </div>

  <main class="cuerpo inv-desliza">
    <Ingredientes {ingredientes} {cargando} {error} {esqueletos} />
    <p class="inv-nota">
      Lo que anotes sale en el historial del gerente con tu nombre. Contar, las recetas y los ingredientes los lleva el gerente
      desde su panel; cada cuenta que se cierra resta sola su receta.
    </p>
  </main>
</div>

{#if ventana === 'llego'}
  <VentanaLlego {cliente} {restauranteId} {ingredientes} cocina alCambiar={() => void vigia.leer()} alCerrar={() => (ventana = null)} />
{:else if ventana === 'merma'}
  <VentanaMerma {cliente} {restauranteId} {ingredientes} alCambiar={() => void vigia.leer()} alCerrar={() => (ventana = null)} />
{/if}

<style>
  .cocina-inventario {
    position: absolute;
    inset: 0;
    background: var(--fondo);
    color: var(--texto);
    font-size: 13.5px;
    text-align: left;
    overflow: hidden;
  }

  :global(:root[data-estilo='cristal'] .lugar-vista) .cocina-inventario {
    background: transparent;
    overflow: visible;
  }

  /* Cristal en el aparato: lo de atrás es su degradado (aparato/cristal-aparato.css), como la Cocina. */
  :global(:root[data-puerta='equipo'][data-estilo='cristal']) .cocina-inventario {
    background: transparent;
  }

  .pos-ancho.barra-c {
    bottom: auto;
    height: 56px;
    z-index: 2;
    overflow: visible;
    background: transparent;
  }

  .reloj {
    font-family: var(--mono);
    font-size: 14px;
    font-weight: 500;
    font-variant-numeric: tabular-nums;
    white-space: nowrap;
  }

  /* Debajo de la barra, en el lugar de una vista: la tabla crece y lo de abajo se desliza. */
  .cuerpo {
    position: absolute;
    left: var(--vista-izquierda);
    right: var(--vista-derecha);
    top: var(--vista-arriba);
    bottom: 0;
    display: flex;
    flex-direction: column;
    gap: 16px;
    padding-bottom: 28px;
    overflow: auto;
  }

  .cuerpo > :global(.tabla) {
    flex: none;
  }

  @media (max-width: 860px) {
    .barra-c :global(.ap-lugar) {
      display: none;
    }
  }

  @media (max-width: 600px) {
    .barra-c :global(.chip),
    .reloj {
      display: none;
    }
  }
</style>
