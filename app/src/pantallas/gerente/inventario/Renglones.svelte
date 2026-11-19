<!--
  Los renglones de una receta (maqueta BBBNJST5w9qZfHWNdovGgb v3: la de Taco al pastor y la de Salsa verde), en su gris:
  qué lleva (un ingrediente o, en la de un platillo o una opción, una preparación), cuánto y en qué, con la ✕ para
  quitarlo; abajo, «+ Agregar ingrediente o preparación». Solo el primer renglón lleva las etiquetas. «En qué» ofrece las
  unidades de la familia de lo elegido (kilos o gramos, litros o mililitros, piezas) y, al elegirlo, toma la suya.
-->
<script lang="ts" module>
  import { decimal } from '../../../lib/formato';
  import { enCaja, type RenglonNuevo, type RenglonReceta, type Unidad } from '../../../lib/inventario';

  // Lo que se escribe en un renglón: `cosa` es «i:12» (un ingrediente) o «p:3» (una preparación).
  export type Linea = { clave: string; cosa: string; cuanto: string; unidad: Unidad | '' };

  export function lineaVacia(): Linea {
    return { clave: crypto.randomUUID(), cosa: '', cuanto: '', unidad: '' };
  }

  // Los renglones para guardar, o lo que falta. Los que se dejaron en blanco no cuentan.
  export function paraGuardar(lineas: Linea[], nombres: Map<string, string>): { renglones: RenglonNuevo[] } | { error: string } {
    const renglones: RenglonNuevo[] = [];
    for (const l of lineas) {
      if (!l.cosa && !l.cuanto.trim()) continue;
      if (!l.cosa) return { error: 'Elige qué lleva cada renglón, o quítalo con la ✕.' };
      const n = decimal(l.cuanto);
      const nombre = nombres.get(l.cosa) ?? 'ese renglón';
      if (n === null || n <= 0) return { error: `De «${nombre}», escribe cuánto lleva.` };
      if (!l.unidad) return { error: `De «${nombre}», elige en qué va.` };
      const id = Number(l.cosa.slice(2));
      renglones.push(l.cosa.startsWith('i:') ? { ingrediente_id: id, cantidad: n, unidad: l.unidad } : { preparacion_id: id, cantidad: n, unidad: l.unidad });
    }
    return { renglones };
  }

  // Los renglones de una receta guardada, para escribirlos.
  export function lineasDe(renglones: RenglonReceta[]): Linea[] {
    return renglones.map((r) => ({
      clave: crypto.randomUUID(),
      cosa: r.ingrediente_id !== null ? `i:${r.ingrediente_id}` : `p:${r.lleva_preparacion_id}`,
      cuanto: enCaja(r.cantidad),
      unidad: r.unidad,
    }));
  }
</script>

<script lang="ts">
  import BotonCuadro from '../../../diseno/BotonCuadro.svelte';
  import Campo from '../../../diseno/Campo.svelte';
  import GrupoCampos from '../../../diseno/GrupoCampos.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import Lista from '../../../diseno/Lista.svelte';
  import { deSuFamilia, NOMBRE_UNIDAD, type Ingrediente, type Preparacion } from '../../../lib/inventario';

  let {
    lineas = $bindable(),
    ingredientes,
    preparaciones = [],
    agregar,
    apagado = false,
  }: {
    lineas: Linea[];
    ingredientes: Ingrediente[];
    preparaciones?: Preparacion[]; // vacía en la receta de una preparación: una preparación lleva solo ingredientes
    agregar: string; // «Agregar ingrediente o preparación»
    apagado?: boolean;
  } = $props();

  const conPreparaciones = $derived(preparaciones.length > 0);
  const opciones = $derived([
    ...ingredientes.map((i) => ({ valor: `i:${i.id}`, texto: i.nombre, icono: conPreparaciones ? 'inventario' : null })),
    ...preparaciones.map((p) => ({ valor: `p:${p.id}`, texto: p.nombre, icono: 'olla' })),
  ]);

  // La unidad en que se cuenta lo elegido (la de lo que rinde, si es una preparación).
  function suUnidad(cosa: string): Unidad | null {
    const [tipo, id] = [cosa.slice(0, 1), Number(cosa.slice(2))];
    if (tipo === 'i') return ingredientes.find((i) => i.id === id)?.unidad ?? null;
    if (tipo === 'p') return preparaciones.find((p) => p.id === id)?.unidad ?? null;
    return null;
  }

  // Al elegir algo de otra familia, el renglón toma su unidad.
  $effect(() => {
    for (const l of lineas) {
      const u = suUnidad(l.cosa);
      if (u && (!l.unidad || !deSuFamilia(u).includes(l.unidad))) l.unidad = u;
    }
  });
</script>

<GrupoCampos>
  <div class="renglones" class:con-preparaciones={conPreparaciones}>
    {#each lineas as l, i (l.clave)}
      {@const u = suUnidad(l.cosa)}
      <div class="renglon">
        <Lista
          id="renglon-{l.clave}"
          etiqueta={i === 0 ? (conPreparaciones ? 'INGREDIENTE O PREPARACIÓN' : 'INGREDIENTE') : undefined}
          aria-label={conPreparaciones ? 'Ingrediente o preparación' : 'Ingrediente'}
          placeholder="Elige uno"
          bind:valor={l.cosa}
          {opciones}
          {apagado}
        />
        <Campo id="cuanto-{l.clave}" etiqueta={i === 0 ? 'CUÁNTO' : ''} bind:valor={l.cuanto} placeholder="0" modoTeclado="decimal" />
        <Lista
          id="unidad-{l.clave}"
          etiqueta={i === 0 ? 'EN' : undefined}
          aria-label="En qué"
          placeholder="—"
          bind:valor={l.unidad}
          opciones={(u ? deSuFamilia(u) : []).map((x) => ({ valor: x, texto: NOMBRE_UNIDAD[x] }))}
          apagado={apagado || !u}
        />
        <span class="quitar">
          <BotonCuadro
            icono="cerrar"
            ayuda="Quitar"
            apagado={apagado}
            onclick={() => (lineas = lineas.filter((x) => x.clave !== l.clave))}
          />
        </span>
      </div>
    {/each}
    <button type="button" class="agregar" disabled={apagado} onclick={() => (lineas = [...lineas, lineaVacia()])}>
      <Icono nombre="mas" tamano={16} />
      {agregar}
    </button>
  </div>
</GrupoCampos>

<style>
  .renglones {
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  .renglon {
    display: grid;
    grid-template-columns: 1.8fr 110px 1fr 36px;
    gap: 10px;
    align-items: end;
  }

  .renglon > :global(*) {
    min-width: 0;
  }

  /* La ✕ a la altura de la caja de texto. */
  .quitar {
    display: flex;
    justify-content: center;
    margin-bottom: 4px;
  }

  /* «+ Otro ingrediente»: de contorno punteado, como algo que todavía no está. */
  .agregar {
    align-self: flex-start;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 36px;
    margin-top: 2px;
    padding: 0 12px;
    border: 1px dashed var(--borde-tarjeta);
    border-radius: 12px;
    background: transparent;
    color: var(--texto);
    font-size: 13px;
    font-weight: 600;
    transition: background 0.15s;
  }

  .agregar:hover:not(:disabled) {
    background: var(--chip);
  }

  .agregar:disabled {
    opacity: 0.4;
  }

  @media (prefers-reduced-motion: reduce) {
    .agregar {
      transition: none;
    }
  }
</style>
