<!--
  Un ingrediente (maqueta BBBNJST5w9qZfHWNdovGgb v3): «Nuevo ingrediente» (su nombre, en qué se cuenta, cuánto hay hoy,
  que es su primer conteo, y su mínimo y su caja, opcionales) o el lápiz de uno (sus datos a la izquierda, con la
  unidad apagada porque no cambia, y su historial a la derecha). Archivar va abajo en rojo y antes dice de cuántas
  recetas sale.
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
    archivarIngrediente,
    enCaja,
    guardarIngrediente,
    NOMBRE_UNIDAD,
    SUFIJO_UNIDAD,
    UNIDADES,
    type Ingrediente,
    type Recetario,
    type Unidad,
  } from '../../../lib/inventario';
  import type { Menu } from '../../../lib/menu';
  import { supabase } from '../../../lib/supabase';
  import Historial from './Historial.svelte';

  let {
    restauranteId,
    ingrediente,
    menu,
    recetario,
    zona,
    hoy,
    alCambiar,
    alCerrar,
  }: {
    restauranteId: string;
    ingrediente: Ingrediente | null; // el de ahora (la vigía lo trae al día); null, uno nuevo
    menu: Menu | null;
    recetario: Recetario | null;
    zona: string;
    hoy: string;
    alCambiar: () => void;
    alCerrar: () => void;
  } = $props();

  // svelte-ignore state_referenced_locally
  const inicial = ingrediente;
  let nombre = $state(inicial?.nombre ?? '');
  let unidad = $state<Unidad | ''>(inicial?.unidad ?? 'kg');
  let hay = $state('');
  let minimo = $state(enCaja(inicial?.minimo ?? null));
  let porCaja = $state(enCaja(inicial?.por_caja ?? null));
  let error = $state<string | null>(null);
  let confirmando = $state(false);
  // Un doble toque en «Agregar ingrediente» no lo crea dos veces (la clave de su primer conteo).
  const clave = crypto.randomUUID();

  const sufijo = $derived(unidad ? SUFIJO_UNIDAD[unidad] : '');

  // Las recetas que lo llevan, para decirlo antes de archivarlo: «Taco al pastor y Gringa».
  const recetasQueLoLlevan = $derived.by(() => {
    if (!inicial || !recetario) return [];
    const opcionDe = new Map((menu?.grupos ?? []).flatMap((g) => g.opciones.map((o) => [o.id, o.nombre] as const)));
    const productoDe = new Map((menu?.productos ?? []).map((p) => [p.id, p.nombre]));
    const prepDe = new Map(recetario.preparaciones.map((p) => [p.id, p.nombre]));
    return recetario.recetas
      .filter((r) => r.ingrediente_id === inicial.id)
      .map((r) =>
        r.producto_id !== null ? productoDe.get(r.producto_id) : r.opcion_id !== null ? opcionDe.get(r.opcion_id) : prepDe.get(r.preparacion_id ?? 0),
      )
      .filter((x): x is string => !!x);
  });

  // Lo opcional: vacío es nada; si se escribió, un número de más de 0.
  function opcional(texto: string, que: string): number | null | { error: string } {
    if (!texto.trim()) return null;
    const n = decimal(texto);
    return n === null || n <= 0 ? { error: `${que} va con un número de más de 0, o déjalo vacío.` } : n;
  }

  async function guardar(): Promise<{ listo: string } | { error: string }> {
    if (!nombre.trim()) return { error: 'Escribe el nombre del ingrediente.' };
    if (!unidad) return { error: 'Elige en qué se cuenta.' };
    const m = opcional(minimo, 'El mínimo');
    if (m !== null && typeof m === 'object') return m;
    const c = opcional(porCaja, 'Lo que trae una caja');
    if (c !== null && typeof c === 'object') return c;
    let h: number | null = null;
    if (!inicial) {
      h = decimal(hay);
      if (h === null) return { error: 'Escribe cuánto hay hoy (puede ser 0).' };
    }
    try {
      await guardarIngrediente(supabase, restauranteId, {
        id: inicial?.id ?? null,
        nombre: nombre.trim(),
        unidad,
        por_caja: c,
        minimo: m,
        hay: h,
        clave: inicial ? null : clave,
      });
    } catch (falla) {
      return { error: (falla as Error).message };
    }
    alCambiar();
    return { listo: inicial ? 'Cambios guardados' : 'Ingrediente agregado' };
  }

  async function archivar(): Promise<{ listo: string } | { error: string }> {
    if (!inicial) return { error: 'Ese ingrediente ya no está.' };
    try {
      await archivarIngrediente(supabase, restauranteId, inicial.id);
    } catch (falla) {
      return { error: (falla as Error).message };
    }
    alCambiar();
    return { listo: 'Archivado' };
  }

  const textoArchivar = $derived.by(() => {
    const n = recetasQueLoLlevan.length;
    const fin = 'Su historial se queda. Si solo se acabó, no lo archives: anota lo que llegue.';
    if (!n) return `No está en ninguna receta. Deja de salir en tu inventario. ${fin}`;
    const cuales = n > 1 ? `${recetasQueLoLlevan.slice(0, -1).join(', ')} y ${recetasQueLoLlevan.at(-1)}` : recetasQueLoLlevan[0];
    return `Sale de ${n === 1 ? 'la receta que lo lleva' : `las ${n} recetas que lo llevan`} (${cuales}) y deja de restarse. ${fin}`;
  });
</script>

{#snippet minimoYCaja(pista: string, placeholder: string)}
  <GrupoCampos>
    <div class="dos">
      <Campo id="ing-minimo" etiqueta="AVÍSAME AL LLEGAR A" bind:valor={minimo} {placeholder} modoTeclado="decimal" {sufijo} />
      <Campo id="ing-caja" etiqueta="UNA CAJA TRAE" bind:valor={porCaja} {placeholder} modoTeclado="decimal" {sufijo} />
    </div>
    {#if pista}<p class="pista">{pista}</p>{/if}
  </GrupoCampos>
{/snippet}

{#if confirmando && inicial}
  <Confirmar
    peligro
    icono="eliminar"
    titulo="¿Archivar «{inicial.nombre}»?"
    texto={textoArchivar}
    boton={{ etiqueta: 'Sí, archivar', icono: 'eliminar' }}
    textoCargando="Archivando…"
    confirmar={archivar}
    alCerrar={() => (confirmando = false)}
    alTerminar={alCerrar}
  />
{:else if inicial}
  <Ventana etiqueta="INGREDIENTE" titulo={inicial.nombre} ancho={984} centrado {alCerrar}>
    <Formulario verde boton={{ etiqueta: 'Guardar cambios', icono: 'check' }} {guardar} alTerminar={alCerrar} bind:error espacio={16} antesDelBoton={28}>
      <div class="inv-campos">
      <div class="dos-columnas">
        <div class="col">
          <GrupoCampos>
            <Campo id="ing-nombre" etiqueta="NOMBRE" bind:valor={nombre} largoMaximo={60} />
            <Lista
              id="ing-unidad"
              etiqueta="SE CUENTA EN"
              bind:valor={unidad}
              opciones={UNIDADES.map((u) => ({ valor: u, texto: NOMBRE_UNIDAD[u] }))}
              apagado
              pista="No cambia después de crearlo. Si te equivocaste, archívalo y crea otro."
            />
          </GrupoCampos>
          {@render minimoYCaja('Opcionales. Con el mínimo sale en amarillo cuando se está acabando; con la caja, lo que llega se anota en cajas.', '')}
        </div>
        <Historial {restauranteId} ingrediente={ingrediente ?? inicial} {zona} {hoy} {alCambiar} />
      </div>

      </div>

      {#snippet izquierda()}
        <Boton
          etiqueta="Archivar ingrediente"
          icono="eliminar"
          tono="peligro"
          onclick={() => {
            error = null;
            confirmando = true;
          }}
        />
      {/snippet}
    </Formulario>
  </Ventana>
{:else}
  <Ventana etiqueta="NUEVO INGREDIENTE" titulo="Nuevo ingrediente" ancho={640} centrado {alCerrar}>
    <Formulario verde boton={{ etiqueta: 'Agregar ingrediente', icono: 'mas' }} {guardar} alTerminar={alCerrar} bind:error espacio={16} antesDelBoton={28}>
      <div class="inv-campos">
      <GrupoCampos>
        <Campo id="ing-nombre" etiqueta="NOMBRE" bind:valor={nombre} placeholder="Ej. Pastor, Tortilla, Coca-Cola" largoMaximo={60} />
        <Lista
          id="ing-unidad"
          etiqueta="SE CUENTA EN"
          bind:valor={unidad}
          opciones={UNIDADES.map((u) => ({ valor: u, texto: NOMBRE_UNIDAD[u] }))}
          pista="La receta puede decir gramos aunque se cuente en kilos: el sistema convierte."
        />
      </GrupoCampos>
      <GrupoCampos>
        <Campo id="ing-hay" etiqueta="¿CUÁNTO HAY HOY?" bind:valor={hay} placeholder="0" modoTeclado="decimal" {sufijo} pista="Es su primer conteo." />
      </GrupoCampos>
      {@render minimoYCaja('', 'Opcional')}

      </div>

      {#snippet izquierda()}
        <Boton etiqueta="Cancelar" icono="cerrar" tono="alarga" onclick={alCerrar} />
      {/snippet}
    </Formulario>
  </Ventana>
{/if}

<style>
  .dos-columnas {
    display: grid;
    grid-template-columns: minmax(0, 420px) minmax(0, 1fr);
    gap: 28px;
    align-items: stretch;
  }

  .col {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 16px;
  }

  .dos {
    display: flex;
    gap: 12px;
    align-items: flex-start;
  }

  .dos > :global(*) {
    flex: 1;
    min-width: 0;
  }

  .pista {
    margin: 0;
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--tenue);
  }
</style>
