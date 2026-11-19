<!--
  La receta de un platillo o de una opción (maqueta BBBNJST5w9qZfHWNdovGgb v3, «Receta de Taco al pastor»): arriba su
  foto y qué es; en su gris, lo que lleva para uno, renglón por renglón; y, en la de un platillo, una tarjeta por cada
  grupo que lleva («Sus opciones · Extras»), con lo que suma cada opción y su «Editar», que abre la receta de esa opción
  encima de esta. Una receta se guarda entera; sin renglones, se queda sin receta y no resta nada.
-->
<script lang="ts">
  import './tabla.css';
  import Boton from '../../../diseno/Boton.svelte';
  import Formulario from '../../../diseno/Formulario.svelte';
  import Ventana from '../../../diseno/Ventana.svelte';
  import { urlFoto } from '../../../lib/fotos';
  import { guardarReceta, loQueLleva, type Ingrediente, type Recetario } from '../../../lib/inventario';
  import type { Grupo, Menu, Opcion, Producto } from '../../../lib/menu';
  import { supabase } from '../../../lib/supabase';
  import Foto from '../menu/Foto.svelte';
  import Renglones, { lineasDe, lineaVacia, paraGuardar, type Linea } from './Renglones.svelte';

  let {
    restauranteId,
    de,
    menu,
    recetario,
    ingredientes,
    alCambiar,
    alEditarOpcion,
    alCerrar,
  }: {
    restauranteId: string;
    de: { producto: Producto } | { opcion: Opcion; grupo: Grupo };
    menu: Menu;
    recetario: Recetario;
    ingredientes: Ingrediente[];
    alCambiar: () => void;
    alEditarOpcion?: (opcion: Opcion, grupo: Grupo) => void;
    alCerrar: () => void;
  } = $props();

  // svelte-ignore state_referenced_locally
  const inicial = 'producto' in de ? recetario.recetas.filter((r) => r.producto_id === de.producto.id) : recetario.recetas.filter((r) => r.opcion_id === de.opcion.id);
  let lineas = $state<Linea[]>(inicial.length ? lineasDe(inicial) : [lineaVacia()]);
  let error = $state<string | null>(null);

  const nombres = $derived(
    new Map([
      ...ingredientes.map((i) => [`i:${i.id}`, i.nombre] as const),
      ...recetario.preparaciones.map((p) => [`p:${p.id}`, p.nombre] as const),
    ]),
  );
  // Los grupos del platillo, con lo que suma cada opción.
  const grupos = $derived('producto' in de ? menu.grupos.filter((g) => g.productos.includes(de.producto.id)) : []);
  function sumaDe(o: Opcion): string | null {
    const renglones = recetario.recetas.filter((r) => r.opcion_id === o.id);
    return renglones.length ? loQueLleva(renglones, ingredientes, recetario.preparaciones).join(' · ') : null;
  }

  async function guardar(): Promise<{ listo: string } | { error: string }> {
    const r = paraGuardar(lineas, nombres);
    if ('error' in r) return r;
    try {
      await guardarReceta(supabase, restauranteId, 'producto' in de ? { producto: de.producto.id } : { opcion: de.opcion.id }, r.renglones);
    } catch (falla) {
      return { error: (falla as Error).message };
    }
    alCambiar();
    return { listo: 'Receta guardada' };
  }
</script>

<Ventana
  etiqueta={'producto' in de ? 'RECETA · PARA UNO' : `OPCIÓN · ${de.grupo.nombre.toUpperCase()}`}
  titulo={'producto' in de ? de.producto.nombre : de.opcion.nombre}
  ancho={820}
  centrado
  {alCerrar}
>
  <Formulario verde boton={{ etiqueta: 'Guardar receta', icono: 'check' }} {guardar} alTerminar={alCerrar} bind:error espacio={16} antesDelBoton={28}>
      <div class="inv-campos">
    <div class="cabeza">
      {#if 'producto' in de}
        <Foto src={de.producto.imagen_ruta ? urlFoto(de.producto.imagen_ruta) : null} tamano={56} radio={14} />
        <span>
          <b>Qué lleva cada uno</b>
          <span>Se resta cuando la cuenta se cierra. Si piden tres, se resta tres veces.</span>
        </span>
      {:else}
        <span>
          <b>Qué suma esta opción</b>
          <span>Se resta junto con el platillo. Lleva lo mismo en todos los platillos que tienen su grupo.</span>
        </span>
      {/if}
    </div>

    <Renglones bind:lineas {ingredientes} preparaciones={recetario.preparaciones} agregar="Agregar ingrediente o preparación" />

    {#each grupos as g (g.id)}
      <div class="opciones">
        <div class="op-cabeza">
          <span class="etiqueta">SUS OPCIONES · {g.nombre.toUpperCase()}</span>
          <span class="op-pista">Una opción lleva lo mismo en todos los platillos que tienen su grupo.</span>
        </div>
        {#each g.opciones as o (o.id)}
          {@const suma = sumaDe(o)}
          <div class="op">
            <b>{o.nombre}</b>
            {#if suma}<span class="op-lleva">{suma}</span>{:else}<span class="op-nada">No resta nada</span>{/if}
            <button type="button" class="mini" onclick={() => alEditarOpcion?.(o, g)}>Editar</button>
          </div>
        {/each}
      </div>
    {/each}

      </div>

    {#snippet izquierda()}
      <Boton etiqueta="Cancelar" icono="cerrar" tono="alarga" onclick={alCerrar} />
    {/snippet}
  </Formulario>
</Ventana>

<style>
  .cabeza {
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 2px 4px;
  }

  .cabeza > span:last-child {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .cabeza b {
    font-size: 14px;
    font-weight: 700;
    color: var(--texto);
  }

  .cabeza span span {
    font-size: 12.5px;
    font-weight: 500;
    color: var(--tenue);
  }

  .opciones {
    border: 1px solid var(--borde-tarjeta);
    border-radius: 14px;
    overflow: hidden;
  }

  .op-cabeza {
    display: flex;
    flex-direction: column;
    gap: 4px;
    padding: 14px 16px 10px;
    border-bottom: 1px solid var(--linea);
  }

  .op-pista {
    font-size: 12px;
    font-weight: 500;
    color: var(--tenue);
  }

  .op {
    display: grid;
    grid-template-columns: 150px 1fr auto;
    gap: 12px;
    align-items: center;
    min-height: 50px;
    padding: 0 16px;
    border-bottom: 1px solid var(--linea);
    font-size: 13px;
    font-weight: 500;
    color: var(--texto);
  }

  .op:last-child {
    border-bottom: 0;
  }

  .op b {
    font-weight: 600;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .op-lleva {
    min-width: 0;
  }

  .op-nada {
    color: var(--tenue);
  }

  .mini {
    height: 30px;
    padding: 0 10px;
    border: 1px solid var(--borde-tarjeta);
    border-radius: 10px;
    background: transparent;
    color: var(--texto);
    font-size: 12px;
    font-weight: 600;
    transition: background 0.15s;
  }

  .mini:hover {
    background: var(--chip);
  }

  @media (prefers-reduced-motion: reduce) {
    .mini {
      transition: none;
    }
  }
</style>
