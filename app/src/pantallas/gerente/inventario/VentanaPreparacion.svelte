<!--
  Una preparación (maqueta BBBNJST5w9qZfHWNdovGgb v3, «Salsa verde»): su nombre, cuánto rinde y en qué; en su gris, lo
  que lleva para eso (solo ingredientes, en una sola capa); y, si ya existe, quién la lleva. Se guarda entera, con su
  receta. Eliminarla la quita de los platillos y opciones que la llevan (antes lo dice). Nueva, lleva «Cancelar».
-->
<script lang="ts">
  import './tabla.css';
  import Boton from '../../../diseno/Boton.svelte';
  import Campo from '../../../diseno/Campo.svelte';
  import Confirmar from '../../../diseno/Confirmar.svelte';
  import Formulario from '../../../diseno/Formulario.svelte';
  import GrupoCampos from '../../../diseno/GrupoCampos.svelte';
  import Lista from '../../../diseno/Lista.svelte';
  import Ventana from '../../../diseno/Ventana.svelte';
  import { decimal } from '../../../lib/formato';
  import {
    cantidad,
    eliminarPreparacion,
    guardarPreparacion,
    NOMBRE_UNIDAD,
    UNIDADES,
    type Ingrediente,
    type Preparacion,
    type Recetario,
    type Unidad,
  } from '../../../lib/inventario';
  import type { Menu } from '../../../lib/menu';
  import { supabase } from '../../../lib/supabase';
  import Renglones, { lineasDe, lineaVacia, paraGuardar, type Linea } from './Renglones.svelte';

  let {
    restauranteId,
    preparacion,
    menu,
    recetario,
    ingredientes,
    alCambiar,
    alCerrar,
  }: {
    restauranteId: string;
    preparacion: Preparacion | null;
    menu: Menu;
    recetario: Recetario;
    ingredientes: Ingrediente[];
    alCambiar: () => void;
    alCerrar: () => void;
  } = $props();

  // svelte-ignore state_referenced_locally
  const p = preparacion;
  let nombre = $state(p?.nombre ?? '');
  let rinde = $state(p ? String(p.rinde) : '');
  let unidad = $state<Unidad | ''>(p?.unidad ?? '');
  // svelte-ignore state_referenced_locally
  const inicial = p ? recetario.recetas.filter((r) => r.preparacion_id === p.id) : [];
  let lineas = $state<Linea[]>(inicial.length ? lineasDe(inicial) : [lineaVacia()]);
  let error = $state<string | null>(null);
  let confirmando = $state(false);

  const nombres = $derived(new Map(ingredientes.map((i) => [`i:${i.id}`, i.nombre] as const)));

  // Quién la lleva: «Taco al pastor (30 ml) y Taco de suadero (30 ml)».
  const usan = $derived(p ? recetario.recetas.filter((r) => r.lleva_preparacion_id === p.id) : []);
  const laLlevan = $derived.by(() => {
    const opcionDe = new Map(menu.grupos.flatMap((g) => g.opciones.map((o) => [o.id, o.nombre] as const)));
    const productoDe = new Map(menu.productos.map((x) => [x.id, x.nombre]));
    const quienes = usan.map(
      (r) => `${(r.producto_id !== null ? productoDe.get(r.producto_id) : opcionDe.get(r.opcion_id ?? 0)) ?? '—'} (${cantidad(r.cantidad, r.unidad)})`,
    );
    if (!quienes.length) return 'Todavía no la lleva ningún platillo.';
    return `${quienes.length > 1 ? `${quienes.slice(0, -1).join(', ')} y ${quienes.at(-1)}` : quienes[0]}.`;
  });

  async function guardar(): Promise<{ listo: string } | { error: string }> {
    if (!nombre.trim()) return { error: 'Escribe el nombre de la preparación.' };
    const n = decimal(rinde);
    if (n === null || n <= 0) return { error: 'Escribe cuánto rinde su receta.' };
    if (!unidad) return { error: 'Elige en qué se mide lo que rinde.' };
    const r = paraGuardar(lineas, nombres);
    if ('error' in r) return r;
    try {
      await guardarPreparacion(supabase, restauranteId, { id: p?.id ?? null, nombre: nombre.trim(), rinde: n, unidad, renglones: r.renglones });
    } catch (falla) {
      return { error: (falla as Error).message };
    }
    alCambiar();
    return { listo: p ? 'Cambios guardados' : 'Preparación agregada' };
  }

  async function eliminar(): Promise<{ listo: string } | { error: string }> {
    if (!p) return { error: 'Esa preparación ya no está.' };
    try {
      await eliminarPreparacion(supabase, restauranteId, p.id);
    } catch (falla) {
      return { error: (falla as Error).message };
    }
    alCambiar();
    return { listo: 'Eliminada' };
  }
</script>

{#if confirmando && p}
  <Confirmar
    peligro
    icono="eliminar"
    titulo="¿Eliminar «{p.nombre}»?"
    texto={usan.length
      ? `Se va con su receta y sale de ${usan.length === 1 ? 'lo que la lleva' : `los ${usan.length} platillos u opciones que la llevan`}: ya no restarán su parte. Lo que ya se vendió no cambia.`
      : 'Se va con su receta. Ningún platillo la lleva todavía.'}
    boton={{ etiqueta: 'Sí, eliminar', icono: 'eliminar' }}
    textoCargando="Eliminando…"
    confirmar={eliminar}
    alCerrar={() => (confirmando = false)}
    alTerminar={alCerrar}
  />
{:else}
  <Ventana etiqueta={p ? 'PREPARACIÓN' : 'NUEVA PREPARACIÓN'} titulo={p ? p.nombre : 'Nueva preparación'} ancho={820} centrado {alCerrar}>
    <Formulario
      verde
      boton={p ? { etiqueta: 'Guardar cambios', icono: 'check' } : { etiqueta: 'Agregar preparación', icono: 'mas' }}
      {guardar}
      alTerminar={alCerrar}
      bind:error
      espacio={16}
      antesDelBoton={28}
    >
      <div class="inv-campos">
      <GrupoCampos>
        <div class="tres">
          <Campo id="prep-nombre" etiqueta="NOMBRE" bind:valor={nombre} placeholder="Ej. Salsa verde" largoMaximo={60} />
          <div class="rinde"><Campo id="prep-rinde" etiqueta="RINDE" bind:valor={rinde} placeholder="1" modoTeclado="decimal" /></div>
          <div class="en">
            <Lista
              id="prep-unidad"
              etiqueta="EN"
              placeholder="Elige"
              bind:valor={unidad}
              opciones={UNIDADES.map((u) => ({ valor: u, texto: NOMBRE_UNIDAD[u] }))}
            />
          </div>
        </div>
        <p class="pista">Lo que sale de esta receta. Un platillo que lleva una parte resta su parte de cada ingrediente.</p>
      </GrupoCampos>

      <Renglones bind:lineas {ingredientes} agregar="Agregar ingrediente" />

      {#if p}
        <GrupoCampos>
          <div class="nota">
            <span class="etiqueta">LA LLEVAN</span>
            <p class="pista">{laLlevan} No se anota cuándo se hace la olla: cada platillo resta su parte.</p>
          </div>
        </GrupoCampos>
      {/if}

      </div>

      {#snippet izquierda()}
        {#if p}
          <Boton
            etiqueta="Eliminar preparación"
            icono="eliminar"
            tono="peligro"
            onclick={() => {
              error = null;
              confirmando = true;
            }}
          />
        {:else}
          <Boton etiqueta="Cancelar" icono="cerrar" tono="alarga" onclick={alCerrar} />
        {/if}
      {/snippet}
    </Formulario>
  </Ventana>
{/if}

<style>
  .tres {
    display: flex;
    gap: 12px;
    align-items: flex-start;
  }

  .tres > :global(:first-child) {
    flex: 1;
    min-width: 0;
  }

  .rinde {
    width: 110px;
    flex: none;
  }

  .en {
    flex: 0.9;
    min-width: 0;
  }

  .pista {
    margin: 0;
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--tenue);
  }

  .nota {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
</style>
