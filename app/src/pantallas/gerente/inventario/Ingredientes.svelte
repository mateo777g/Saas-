<!--
  Los ingredientes (maqueta BBBNJST5w9qZfHWNdovGgb v3, «Inventario · Ingredientes»): la búsqueda con su filtro por cómo
  van y la tabla en el marco de Mi menú. Los que se acabaron primero, luego los que se acaban y luego los demás, por
  nombre (lib/inventario.ts). Cada uno dice cuánto queda, su mínimo, su caja y cómo va. Buscar y filtrar es en memoria.

  La usan el gerente (con la caja y el lápiz, que abre su ventana) y la tableta de cocina, que solo la ve (sin la caja
  ni el lápiz: anota con «Merma» y «Llegó» de su barra). Mientras se lee la primera vez, esqueletos.
-->
<script lang="ts">
  import './tabla.css';
  import BotonCuadro from '../../../diseno/BotonCuadro.svelte';
  import Esqueleto from '../../../diseno/Esqueleto.svelte';
  import NotaTabla from '../../../diseno/NotaTabla.svelte';
  import Tabla from '../../../diseno/Tabla.svelte';
  import { anchos } from '../../../lib/esqueletos';
  import { plural } from '../../../lib/formato';
  import { cantidad, comoVa, TEXTO_COMO_VA, type ComoVa, type Ingrediente } from '../../../lib/inventario';
  import Herramientas from './Herramientas.svelte';

  let {
    ingredientes,
    cargando = false,
    error = null,
    esqueletos = 3,
    gerente = false,
    alEditar,
  }: {
    ingredientes: Ingrediente[];
    cargando?: boolean;
    error?: { titulo: string; texto: string } | null; // si no se pudo leer y no hay nada que enseñar
    esqueletos?: number;
    gerente?: boolean;
    alEditar?: (i: Ingrediente) => void;
  } = $props();

  let busqueda = $state('');
  let filtro = $state<ComoVa | null>(null);

  const COLUMNAS = $derived(gerente ? '2fr 1.1fr 1fr 1fr 1.1fr 80px' : '2fr 1.2fr 1fr 1.2fr');
  const texto = $derived(busqueda.trim());
  const mostrados = $derived.by(() => {
    const q = texto.toLowerCase();
    return ingredientes.filter((i) => (filtro === null || comoVa(i) === filtro) && (!q || i.nombre.toLowerCase().includes(q)));
  });
  const cuantos = (c: ComoVa) => ingredientes.filter((i) => comoVa(i) === c).length;

  const ESQUELETO = ['120px', '96px', '140px', '80px', '110px'];
  const filas = $derived(anchos(ESQUELETO, esqueletos));
</script>

<Herramientas
  bind:busqueda
  placeholder="Busca un ingrediente…"
  cuenta={plural(mostrados.length, 'INGREDIENTE', 'INGREDIENTES')}
  {cargando}
  filtro={{
    titulo: 'CÓMO VAN',
    todas: { boton: 'Todos los ingredientes', nombre: 'Todos', icono: 'inventario' },
    opciones: [
      { valor: 'rojo', nombre: 'Se acabaron', cuenta: cuantos('rojo'), color: 'rojo' },
      { valor: 'amarillo', nombre: 'Se acaban', cuenta: cuantos('amarillo'), color: 'amarillo' },
      { valor: 'verde', nombre: 'Bien', cuenta: cuantos('verde'), color: 'verde' },
    ],
    total: ingredientes.length,
    elegida: filtro,
    alElegir: (v) => (filtro = v as ComoVa | null),
  }}
/>

<Tabla
  columnas={COLUMNAS}
  relleno="0 16px"
  altoFila={64}
  marco
  encabezados={[
    { texto: 'Ingrediente' },
    { texto: 'Queda' },
    { texto: 'Mínimo' },
    ...(gerente ? [{ texto: 'Caja' }] : []),
    { texto: 'Cómo va' },
    ...(gerente ? [{ texto: '' }] : []),
  ]}
>
  {#if cargando}
    <span class="solo-lector">Cargando tu inventario…</span>
    {#each filas as ancho, i (i)}
      <div class="fila quieta" aria-hidden="true">
        <span><Esqueleto {ancho} alto="11px" /></span>
        <span><Esqueleto ancho="60px" alto="11px" /></span>
        <span><Esqueleto ancho="44px" alto="11px" /></span>
        {#if gerente}<span><Esqueleto ancho="52px" alto="11px" /></span>{/if}
        <span><Esqueleto ancho="70px" alto="11px" /></span>
        {#if gerente}<span></span>{/if}
      </div>
    {/each}
  {:else if error}
    <NotaTabla relleno={48} angosta titulo={error.titulo} texto={error.texto} />
  {:else if !ingredientes.length}
    <NotaTabla
      relleno={48}
      angosta
      titulo="Todavía no hay ingredientes."
      texto={gerente
        ? 'Agrega el primero con Nuevo ingrediente: el pastor, la tortilla, la Coca-Cola… con cuánto hay hoy.'
        : 'El gerente los agrega desde su panel.'}
    />
  {:else if !mostrados.length}
    <NotaTabla
      relleno={48}
      angosta
      titulo={texto ? `No encontramos ingredientes para "${texto}".` : 'No hay ingredientes así.'}
      texto="Prueba con otro nombre o con Todos los ingredientes."
    />
  {:else}
    {#each mostrados as i (i.id)}
      {@const va = comoVa(i)}
      <div class="fila">
        <span class="inv-producto"><span class="inv-nombre">{i.nombre}</span></span>
        <span class="inv-queda {va}">{cantidad(i.existencia, i.unidad)}</span>
        <span class="inv-tenue">{i.minimo !== null ? cantidad(i.minimo, i.unidad) : '—'}</span>
        {#if gerente}<span class="inv-tenue">{i.por_caja !== null ? cantidad(i.por_caja, i.unidad) : '—'}</span>{/if}
        <span><span class="inv-estado {va}"><span class="inv-punto"></span>{TEXTO_COMO_VA[va]}</span></span>
        {#if gerente}
          <span class="inv-acciones">
            <BotonCuadro icono="crear" ayuda="Ver y editar ingrediente" onclick={() => alEditar?.(i)} />
          </span>
        {/if}
      </div>
    {/each}
  {/if}
</Tabla>
