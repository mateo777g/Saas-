<!--
  «¿Cuánto hay?» (maqueta BBBNJST5w9qZfHWNdovGgb v3, «Contar»): todos los ingredientes por nombre, cada uno con su caja
  de texto; no dice lo que dice el sistema hasta que escribes lo que hay (como el corte de caja). Entonces sale la
  diferencia: «Faltan 0.6 kg» en rojo, «Sobran 2 piezas» en verde o «Igual». Lo contado reemplaza lo que decía el
  sistema y la diferencia queda en su historial. Solo el gerente cuenta. Un conteo de varios comparte su clave.
-->
<script lang="ts">
  import Boton from '../../../diseno/Boton.svelte';
  import Campo from '../../../diseno/Campo.svelte';
  import Formulario from '../../../diseno/Formulario.svelte';
  import GrupoCampos from '../../../diseno/GrupoCampos.svelte';
  import Ventana from '../../../diseno/Ventana.svelte';
  import { decimal, plural } from '../../../lib/formato';
  import { anotarConteo, cantidad, SUFIJO_UNIDAD, type Ingrediente } from '../../../lib/inventario';
  import { supabase } from '../../../lib/supabase';
  import './tabla.css';

  let {
    restauranteId,
    ingredientes,
    alCambiar,
    alCerrar,
  }: {
    restauranteId: string;
    ingredientes: Ingrediente[];
    alCambiar: () => void;
    alCerrar: () => void;
  } = $props();

  // svelte-ignore state_referenced_locally
  const lista = [...ingredientes].sort((a, b) => a.nombre.localeCompare(b.nombre, 'es'));
  let contado = $state<Record<number, string>>({});
  let error = $state<string | null>(null);
  const clave = crypto.randomUUID();

  // Lo que dice el sistema ahora (la vigía lo trae al día), para la diferencia.
  const ahora = $derived(new Map(ingredientes.map((i) => [i.id, i.existencia])));
  const contados = $derived(lista.filter((i) => (contado[i.id] ?? '').trim() !== ''));

  function diferencia(i: Ingrediente): { texto: string; tono: string } | null {
    const texto = (contado[i.id] ?? '').trim();
    if (!texto) return null;
    const n = decimal(texto);
    if (n === null) return null;
    const d = Math.round((n - (ahora.get(i.id) ?? i.existencia)) * 1000) / 1000;
    if (d === 0) return { texto: 'Igual', tono: 'igual' };
    return d < 0 ? { texto: `Faltan ${cantidad(-d, i.unidad)}`, tono: 'baja' } : { texto: `Sobran ${cantidad(d, i.unidad)}`, tono: 'sube' };
  }

  async function guardar(): Promise<{ listo: string } | { error: string }> {
    const conteos: { ingrediente_id: number; contado: number }[] = [];
    for (const i of contados) {
      const n = decimal(contado[i.id]);
      if (n === null) return { error: `De «${i.nombre}», escribe cuánto hay (un número, puede ser 0).` };
      conteos.push({ ingrediente_id: i.id, contado: n });
    }
    if (!conteos.length) return { error: 'Escribe cuánto hay de al menos un ingrediente.' };
    try {
      await anotarConteo(supabase, restauranteId, clave, conteos);
    } catch (falla) {
      return { error: (falla as Error).message };
    }
    alCambiar();
    return { listo: 'Conteo guardado' };
  }
</script>

<Ventana etiqueta="CONTAR" titulo="¿Cuánto hay?" ancho={640} centrado {alCerrar}>
  <Formulario
    verde
    boton={{ etiqueta: contados.length ? `Guardar conteo · ${plural(contados.length, 'contado', 'contados')}` : 'Guardar conteo', icono: 'check' }}
    {guardar}
    alTerminar={alCerrar}
    bind:error
    espacio={16}
    antesDelBoton={28}
  >
      <div class="inv-campos">
    <p class="arriba">
      Cuenta lo que hay y escríbelo. Lo que cuentes reemplaza lo que decía el sistema; la diferencia sale al escribir y queda en su
      historial.
    </p>
    <GrupoCampos>
      <div class="cuenta inv-desliza">
        {#each lista as i (i.id)}
          {@const d = diferencia(i)}
          <div class="fila-cuenta">
            <label class="nombre" for="contar-{i.id}">{i.nombre}</label>
            <span class="caja">
              <Campo
                id="contar-{i.id}"
                etiqueta=""
                bind:valor={() => contado[i.id] ?? '', (v) => (contado[i.id] = v)}
                placeholder="¿Cuánto hay?"
                modoTeclado="decimal"
                sufijo={SUFIJO_UNIDAD[i.unidad]}
              />
            </span>
            <span class="dif {d?.tono ?? ''}">{d?.texto ?? ''}</span>
          </div>
        {/each}
      </div>
    </GrupoCampos>

      </div>

    {#snippet izquierda()}
      <Boton etiqueta="Cancelar" icono="cerrar" tono="alarga" onclick={alCerrar} />
    {/snippet}
  </Formulario>
</Ventana>

<style>
  .arriba {
    margin: 0 24px;
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--tenue);
    text-align: center;
  }

  /* La lista se desliza adentro, con su desvanecido abajo, para que la ventana quepa entera. */
  .cuenta {
    max-height: 380px;
    overflow: auto;
    padding-bottom: 24px;
    display: flex;
    flex-direction: column;
    -webkit-mask-image: linear-gradient(to bottom, #000 calc(100% - 40px), transparent);
    mask-image: linear-gradient(to bottom, #000 calc(100% - 40px), transparent);
  }

  .fila-cuenta {
    display: grid;
    grid-template-columns: 1fr 170px 130px;
    gap: 12px;
    align-items: center;
    min-height: 54px;
    border-bottom: 1px solid var(--linea);
  }

  .fila-cuenta:last-child {
    border-bottom: 0;
  }

  /* El campo sin su etiqueta (la dice el nombre de la izquierda). */
  .caja :global(.etiqueta) {
    display: none;
  }

  .nombre {
    font-size: 13.5px;
    font-weight: 600;
    color: var(--texto);
  }

  .dif {
    font-family: var(--mono);
    font-size: 12px;
    font-weight: 600;
    text-align: right;
  }

  .dif.baja {
    color: var(--rojo);
  }

  .dif.sube {
    color: var(--verde);
  }

  .dif.igual {
    color: var(--tenue);
  }
</style>
