<!--
  Las preparaciones (maqueta BBBNJST5w9qZfHWNdovGgb v3, «Inventario · Preparaciones»): lo que se hace antes y va en
  varios platillos, como la salsa verde en olla. Cada una dice cuánto rinde su receta, lo que lleva y cuántos platillos
  u opciones la llevan. El lápiz abre su ventana; «Nueva preparación» va en la barra de arriba.
-->
<script lang="ts">
  import './tabla.css';
  import BotonCuadro from '../../../diseno/BotonCuadro.svelte';
  import Esqueleto from '../../../diseno/Esqueleto.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import NotaTabla from '../../../diseno/NotaTabla.svelte';
  import Tabla from '../../../diseno/Tabla.svelte';
  import { anchos } from '../../../lib/esqueletos';
  import { plural } from '../../../lib/formato';
  import { cantidad, loQueLleva, type Ingrediente, type Preparacion, type Recetario } from '../../../lib/inventario';
  import Herramientas from './Herramientas.svelte';

  let {
    recetario,
    ingredientes,
    cargando = false,
    error = null,
    esqueletos = 3,
    alEditar,
  }: {
    recetario: Recetario;
    ingredientes: Ingrediente[];
    cargando?: boolean;
    error?: { titulo: string; texto: string } | null;
    esqueletos?: number;
    alEditar: (p: Preparacion) => void;
  } = $props();

  let busqueda = $state('');

  const texto = $derived(busqueda.trim());
  const mostradas = $derived(recetario.preparaciones.filter((p) => !texto || p.nombre.toLowerCase().includes(texto.toLowerCase())));

  // «2 platillos», «1 platillo · 1 opción»: quién la lleva.
  function laLlevan(p: Preparacion): string {
    const usan = recetario.recetas.filter((r) => r.lleva_preparacion_id === p.id);
    const platillos = new Set(usan.map((r) => r.producto_id).filter((x) => x !== null)).size;
    const opciones = new Set(usan.map((r) => r.opcion_id).filter((x) => x !== null)).size;
    const partes = [
      ...(platillos ? [plural(platillos, 'platillo', 'platillos')] : []),
      ...(opciones ? [plural(opciones, 'opción', 'opciones')] : []),
    ];
    return partes.length ? partes.join(' · ') : 'Nadie todavía';
  }

  const ESQUELETO = ['96px', '120px', '84px'];
  const filas = $derived(anchos(ESQUELETO, esqueletos));
</script>

<Herramientas
  bind:busqueda
  placeholder="Busca una preparación…"
  cuenta={plural(mostradas.length, 'PREPARACIÓN', 'PREPARACIONES')}
  {cargando}
  filtro={{
    titulo: 'PREPARACIONES',
    todas: { boton: 'Todas', nombre: 'Todas', icono: 'olla' },
    opciones: [],
    total: recetario.preparaciones.length,
    elegida: null,
    alElegir: () => {},
  }}
/>

<Tabla
  columnas="2fr 0.8fr 3.4fr 1.2fr 80px"
  relleno="0 16px"
  altoFila={64}
  marco
  encabezados={[{ texto: 'Preparación' }, { texto: 'Rinde' }, { texto: 'Lleva' }, { texto: 'La llevan' }, { texto: '' }]}
>
  {#if cargando}
    <span class="solo-lector">Cargando tus preparaciones…</span>
    {#each filas as ancho, i (i)}
      <div class="fila quieta" aria-hidden="true">
        <span class="inv-producto"><Esqueleto ancho="44px" alto="44px" redondo="11px" /><Esqueleto {ancho} alto="11px" /></span>
        <span><Esqueleto ancho="40px" alto="11px" /></span>
        <span><Esqueleto ancho="220px" alto="10px" /></span>
        <span><Esqueleto ancho="70px" alto="10px" /></span>
        <span></span>
      </div>
    {/each}
  {:else if error}
    <NotaTabla relleno={48} angosta titulo={error.titulo} texto={error.texto} />
  {:else if !recetario.preparaciones.length}
    <NotaTabla
      relleno={48}
      angosta
      titulo="Todavía no hay preparaciones."
      texto="Lo que se hace antes y va en varios platillos, como la salsa verde en olla. Agrégala con Nueva preparación."
    />
  {:else if !mostradas.length}
    <NotaTabla relleno={48} angosta titulo={`No encontramos preparaciones para "${texto}".`} texto="Prueba con otro nombre." />
  {:else}
    {#each mostradas as p (p.id)}
      {@const cosas = loQueLleva(
        recetario.recetas.filter((r) => r.preparacion_id === p.id),
        ingredientes,
        recetario.preparaciones,
      )}
      <div class="fila">
        <span class="inv-producto">
          <span class="inv-olla"><Icono nombre="olla" tamano={20} /></span>
          <span class="inv-nombre">{p.nombre}</span>
        </span>
        <span class="inv-rinde">{cantidad(p.rinde, p.unidad)}</span>
        <span class="inv-lleva">
          {#each cosas as cosa, j (j)}{#if j > 0}{' · '}{/if}<span>{cosa}</span>{/each}
        </span>
        <span class="inv-tenue">{laLlevan(p)}</span>
        <span class="inv-acciones">
          <BotonCuadro icono="crear" ayuda="Editar preparación" onclick={() => alEditar(p)} />
        </span>
      </div>
    {/each}
  {/if}
</Tabla>
