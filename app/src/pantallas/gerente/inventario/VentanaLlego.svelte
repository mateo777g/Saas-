<!--
  «¿Qué llegó?» (maqueta BBBNJST5w9qZfHWNdovGgb v3, «Llegó»): en su gris, un renglón por ingrediente con cuánto y en qué
  (en su unidad o, si dice cuánto trae su caja, en cajas, con «= 48 piezas» al lado), y «+ Otro ingrediente». Se suma a
  lo que queda. La abren el gerente y la cocina (encuesta 17): a la cocina le dice que un error lo deshace el gerente.
  Con la misma clave no se anota dos veces.
-->
<script lang="ts">
  import './tabla.css';
  import type { SupabaseClient } from '@supabase/supabase-js';
  import Boton from '../../../diseno/Boton.svelte';
  import BotonCuadro from '../../../diseno/BotonCuadro.svelte';
  import Campo from '../../../diseno/Campo.svelte';
  import Formulario from '../../../diseno/Formulario.svelte';
  import GrupoCampos from '../../../diseno/GrupoCampos.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import Lista from '../../../diseno/Lista.svelte';
  import Ventana from '../../../diseno/Ventana.svelte';
  import { decimal, entero } from '../../../lib/formato';
  import { anotarLlegada, cantidad, NOMBRE_UNIDAD, type Ingrediente } from '../../../lib/inventario';

  let {
    cliente,
    restauranteId,
    ingredientes,
    cocina = false,
    alCambiar,
    alCerrar,
  }: {
    cliente: SupabaseClient;
    restauranteId: string;
    ingredientes: Ingrediente[];
    cocina?: boolean;
    alCambiar: () => void;
    alCerrar: () => void;
  } = $props();

  type Linea = { clave: string; ingrediente: string; cuanto: string; en: 'cajas' | 'unidad' | '' };
  const vacia = (): Linea => ({ clave: crypto.randomUUID(), ingrediente: '', cuanto: '', en: '' });
  let lineas = $state<Linea[]>([vacia()]);
  let error = $state<string | null>(null);
  const clave = crypto.randomUUID();

  const porNombre = $derived([...ingredientes].sort((a, b) => a.nombre.localeCompare(b.nombre, 'es')));
  const deId = (texto: string) => ingredientes.find((i) => String(i.id) === texto) ?? null;

  // «Cajas de 24» (piezas) o «Cajas de 10 kg».
  const cajasDe = (i: Ingrediente) => `Cajas de ${i.unidad === 'pieza' ? i.por_caja : cantidad(i.por_caja ?? 0, i.unidad)}`;

  // Al elegir un ingrediente: en cajas si dice cuánto trae una; si no, en su unidad.
  $effect(() => {
    for (const l of lineas) {
      const i = deId(l.ingrediente);
      if (i && (!l.en || (l.en === 'cajas' && i.por_caja === null))) l.en = i.por_caja !== null ? 'cajas' : 'unidad';
    }
  });

  function igual(l: Linea): string {
    const i = deId(l.ingrediente);
    const n = entero(l.cuanto);
    return i && l.en === 'cajas' && i.por_caja !== null && n ? `= ${cantidad(n * i.por_caja, i.unidad)}` : '';
  }

  async function guardar(): Promise<{ listo: string } | { error: string }> {
    const renglones: ({ ingrediente_id: number; cantidad: number } | { ingrediente_id: number; cajas: number })[] = [];
    for (const l of lineas) {
      if (!l.ingrediente && !l.cuanto.trim()) continue;
      const i = deId(l.ingrediente);
      if (!i) return { error: 'Elige qué llegó en cada renglón, o quítalo con la ✕.' };
      if (l.en === 'cajas') {
        const n = entero(l.cuanto);
        if (!n) return { error: `De «${i.nombre}», escribe cuántas cajas llegaron.` };
        renglones.push({ ingrediente_id: i.id, cajas: n });
      } else {
        const n = decimal(l.cuanto);
        if (n === null || n <= 0) return { error: `De «${i.nombre}», escribe cuánto llegó.` };
        renglones.push({ ingrediente_id: i.id, cantidad: n });
      }
    }
    if (!renglones.length) return { error: 'Anota al menos un ingrediente.' };
    try {
      await anotarLlegada(cliente, restauranteId, clave, renglones);
    } catch (falla) {
      return { error: (falla as Error).message };
    }
    alCambiar();
    return { listo: 'Anotado' };
  }
</script>

<Ventana etiqueta="ANOTAR LO QUE LLEGÓ" titulo="¿Qué llegó?" ancho={760} centrado {alCerrar}>
  <Formulario verde boton={{ etiqueta: 'Anotar lo que llegó', icono: 'check' }} {guardar} alTerminar={alCerrar} bind:error espacio={16} antesDelBoton={28}>
      <div class="inv-campos">
    <GrupoCampos>
      <div class="renglones">
        {#each lineas as l, j (l.clave)}
          {@const i = deId(l.ingrediente)}
          <div class="renglon">
            <Lista
              id="llego-{l.clave}"
              etiqueta={j === 0 ? 'INGREDIENTE' : undefined}
              aria-label="Ingrediente"
              placeholder="Elige uno"
              bind:valor={l.ingrediente}
              opciones={porNombre.map((x) => ({ valor: String(x.id), texto: x.nombre }))}
            />
            <Campo id="llego-cuanto-{l.clave}" etiqueta={j === 0 ? 'CUÁNTO' : ''} bind:valor={l.cuanto} placeholder="0" modoTeclado="decimal" />
            <Lista
              id="llego-en-{l.clave}"
              etiqueta={j === 0 ? 'EN' : undefined}
              aria-label="En qué"
              placeholder="—"
              bind:valor={l.en}
              opciones={i
                ? [
                    ...(i.por_caja !== null ? [{ valor: 'cajas' as const, texto: cajasDe(i) }] : []),
                    { valor: 'unidad' as const, texto: NOMBRE_UNIDAD[i.unidad] },
                  ]
                : []}
              apagado={!i}
            />
            <span class="igual">{igual(l)}</span>
            <span class="quitar">
              <BotonCuadro icono="cerrar" ayuda="Quitar" onclick={() => (lineas = lineas.filter((x) => x.clave !== l.clave))} />
            </span>
          </div>
        {/each}
        <button type="button" class="agregar" onclick={() => (lineas = [...lineas, vacia()])}>
          <Icono nombre="mas" tamano={16} />
          Otro ingrediente
        </button>
      </div>
    </GrupoCampos>
    <p class="afuera">
      Se suma a lo que queda de cada uno. {cocina ? 'Si te equivocas, avísale al gerente: lo deshace desde su panel.' : 'Si te equivocas, lo deshaces en su historial.'}
    </p>

      </div>

    {#snippet izquierda()}
      <Boton etiqueta="Cancelar" icono="cerrar" tono="alarga" onclick={alCerrar} />
    {/snippet}
  </Formulario>
</Ventana>

<style>
  .renglones {
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  .renglon {
    display: grid;
    grid-template-columns: 1.6fr 110px 1fr 92px 36px;
    gap: 10px;
    align-items: end;
  }

  .renglon > :global(*) {
    min-width: 0;
  }

  /* «= 48 piezas»: a media altura de la caja de texto. */
  .igual {
    height: 44px;
    display: flex;
    align-items: center;
    font-family: var(--mono);
    font-size: 12px;
    font-weight: 600;
    color: var(--tenue);
    white-space: nowrap;
  }

  .quitar {
    display: flex;
    justify-content: center;
    margin-bottom: 4px;
  }

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

  .agregar:hover {
    background: var(--chip);
  }

  .afuera {
    margin: -4px 4px 0;
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--tenue);
  }

  @media (prefers-reduced-motion: reduce) {
    .agregar {
      transition: none;
    }
  }
</style>
