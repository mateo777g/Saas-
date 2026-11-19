<!--
  «¿Qué se tiró?» (maqueta BBBNJST5w9qZfHWNdovGgb v3, «Merma»): primero si es un ingrediente (cuánto, en su unidad) o un
  platillo entero (cuántos; abajo dice lo que se va a restar, como está escrita su receta, encuesta 15). Luego por qué,
  de la lista corta, y una nota, que con «Otro» es obligatoria. La abren el gerente y la cocina (encuesta 17). Solo se
  ofrecen los platillos con receta. Con la misma clave no se anota dos veces.
-->
<script lang="ts">
  import './tabla.css';
  import type { SupabaseClient } from '@supabase/supabase-js';
  import Boton from '../../../diseno/Boton.svelte';
  import Campo from '../../../diseno/Campo.svelte';
  import Formulario from '../../../diseno/Formulario.svelte';
  import GrupoCampos from '../../../diseno/GrupoCampos.svelte';
  import Lista from '../../../diseno/Lista.svelte';
  import Ventana from '../../../diseno/Ventana.svelte';
  import { decimal, entero } from '../../../lib/formato';
  import {
    anotarMerma,
    loQueResta,
    MOTIVOS,
    platillosParaMerma,
    SUFIJO_UNIDAD,
    type Ingrediente,
    type Motivo,
  } from '../../../lib/inventario';

  let {
    cliente,
    restauranteId,
    ingredientes,
    alCambiar,
    alCerrar,
  }: {
    cliente: SupabaseClient;
    restauranteId: string;
    ingredientes: Ingrediente[];
    alCambiar: () => void;
    alCerrar: () => void;
  } = $props();

  let es = $state<'ingrediente' | 'platillo'>('ingrediente');
  let ingrediente = $state('');
  let platillo = $state('');
  let cuanto = $state('');
  let motivo = $state<Motivo | ''>('');
  let nota = $state('');
  let error = $state<string | null>(null);
  const clave = crypto.randomUUID();

  const porNombre = $derived([...ingredientes].sort((a, b) => a.nombre.localeCompare(b.nombre, 'es')));
  const elegido = $derived(ingredientes.find((i) => String(i.id) === ingrediente) ?? null);

  // Los platillos con receta, al abrir.
  let platillos = $state<{ id: number; nombre: string }[] | null>(null);
  $effect(() => {
    platillosParaMerma(cliente, restauranteId)
      .then((p) => (platillos = p))
      .catch(() => (platillos = []));
  });

  // Lo que se va a restar, al elegir el platillo y cuántos (medio segundo después de escribir).
  let resta = $state('');
  $effect(() => {
    const p = Number(platillo);
    const n = entero(cuanto);
    resta = '';
    if (es !== 'platillo' || !p || !n) return;
    let fuera = false;
    const reloj = setTimeout(() => {
      loQueResta(cliente, restauranteId, p, n)
        .then((texto) => {
          if (!fuera) resta = texto;
        })
        .catch(() => {});
    }, 200);
    return () => {
      fuera = true;
      clearTimeout(reloj);
    };
  });

  async function guardar(): Promise<{ listo: string } | { error: string }> {
    if (!motivo) return { error: 'Elige por qué se tiró.' };
    if (motivo === 'otro' && !nota.trim()) return { error: 'Con «Otro», cuenta qué pasó en la nota.' };
    try {
      if (es === 'platillo') {
        const p = Number(platillo);
        const n = entero(cuanto);
        if (!p) return { error: 'Elige qué platillo se tiró.' };
        if (!n) return { error: 'Escribe cuántos se tiraron.' };
        await anotarMerma(cliente, restauranteId, { clave, motivo, nota, producto: p, platillos: n });
      } else {
        if (!elegido) return { error: 'Elige qué ingrediente se tiró.' };
        const n = decimal(cuanto);
        if (n === null || n <= 0) return { error: `De «${elegido.nombre}», escribe cuánto se tiró.` };
        await anotarMerma(cliente, restauranteId, { clave, motivo, nota, ingrediente: elegido.id, cantidad: n });
      }
    } catch (falla) {
      return { error: (falla as Error).message };
    }
    alCambiar();
    return { listo: 'Anotada' };
  }
</script>

<Ventana etiqueta="ANOTAR UNA MERMA" titulo="¿Qué se tiró?" ancho={720} centrado {alCerrar}>
  <Formulario verde boton={{ etiqueta: 'Anotar merma', icono: 'check' }} {guardar} alTerminar={alCerrar} bind:error espacio={16} antesDelBoton={28}>
      <div class="inv-campos">
    <GrupoCampos>
      <div class="tres">
        <div class="es">
          <Lista
            id="merma-es"
            etiqueta="ES"
            bind:valor={es}
            opciones={[
              { valor: 'ingrediente', texto: 'Un ingrediente', icono: 'inventario' },
              { valor: 'platillo', texto: 'Un platillo', icono: 'receta' },
            ]}
          />
        </div>
        <div class="cual">
          {#if es === 'platillo'}
            <Lista
              id="merma-platillo"
              etiqueta="PLATILLO"
              placeholder={platillos && !platillos.length ? 'Ningún platillo tiene receta' : 'Elige uno'}
              bind:valor={platillo}
              opciones={(platillos ?? []).map((p) => ({ valor: String(p.id), texto: p.nombre }))}
              apagado={!platillos?.length}
            />
          {:else}
            <Lista
              id="merma-ingrediente"
              etiqueta="INGREDIENTE"
              placeholder="Elige uno"
              bind:valor={ingrediente}
              opciones={porNombre.map((i) => ({ valor: String(i.id), texto: i.nombre }))}
            />
          {/if}
        </div>
        <div class="cuanto">
          <Campo
            id="merma-cuanto"
            etiqueta={es === 'platillo' ? 'CUÁNTOS' : 'CUÁNTO'}
            bind:valor={cuanto}
            placeholder="0"
            modoTeclado={es === 'platillo' ? 'numeric' : 'decimal'}
            sufijo={es === 'ingrediente' && elegido ? SUFIJO_UNIDAD[elegido.unidad] : undefined}
          />
        </div>
      </div>
      {#if es === 'platillo' && resta}
        <div class="resta"><span class="etiqueta">SE RESTA</span>{resta}</div>
      {/if}
    </GrupoCampos>
    <GrupoCampos>
      <Lista id="merma-motivo" etiqueta="POR QUÉ" placeholder="Elige por qué" bind:valor={motivo} opciones={MOTIVOS} />
      <Campo id="merma-nota" etiqueta="NOTA" bind:valor={nota} placeholder="Opcional; con «Otro», cuéntanos qué pasó" multilinea largoMaximo={200} />
    </GrupoCampos>

      </div>

    {#snippet izquierda()}
      <Boton etiqueta="Cancelar" icono="cerrar" tono="alarga" onclick={alCerrar} />
    {/snippet}
  </Formulario>
</Ventana>

<style>
  .tres {
    display: flex;
    gap: 12px;
    align-items: flex-start;
  }

  .es {
    flex: 0.8;
    min-width: 0;
  }

  .cual {
    flex: 1;
    min-width: 0;
  }

  .cuanto {
    width: 130px;
    flex: none;
  }

  .resta {
    margin-top: 14px;
    padding-top: 12px;
    border-top: 1px solid var(--linea);
    font-size: 13px;
    font-weight: 500;
    line-height: 1.5;
    color: var(--texto);
  }

  .resta .etiqueta {
    display: block;
    margin-bottom: 4px;
    font: 500 10px var(--mono);
    letter-spacing: 0.14em;
  }
</style>
