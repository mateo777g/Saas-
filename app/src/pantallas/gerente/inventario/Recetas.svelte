<!--
  Las recetas (maqueta BBBNJST5w9qZfHWNdovGgb v3, «Inventario · Recetas»): los platillos de Mi menú, sin envíos, cada uno
  con su foto, su categoría, lo que lleva y las opciones de sus grupos que tienen receta. Sin botón de crear: los
  platillos salen de Mi menú. Los que no tienen receta dicen «Sin receta · no resta nada» en amarillo, y el filtro
  también los junta. El lápiz abre su receta.
-->
<script lang="ts">
  import './tabla.css';
  import BotonCuadro from '../../../diseno/BotonCuadro.svelte';
  import Esqueleto from '../../../diseno/Esqueleto.svelte';
  import IconoCategoria from '../../../diseno/IconoCategoria.svelte';
  import NotaTabla from '../../../diseno/NotaTabla.svelte';
  import Tabla from '../../../diseno/Tabla.svelte';
  import { anchos } from '../../../lib/esqueletos';
  import { urlFoto } from '../../../lib/fotos';
  import { plural } from '../../../lib/formato';
  import { loQueLleva, type Ingrediente, type Recetario } from '../../../lib/inventario';
  import type { Menu, Producto } from '../../../lib/menu';
  import Foto from '../menu/Foto.svelte';
  import Herramientas from './Herramientas.svelte';

  let {
    menu,
    recetario,
    ingredientes,
    cargando = false,
    error = null,
    esqueletos = 3,
    alEditar,
  }: {
    menu: Menu;
    recetario: Recetario;
    ingredientes: Ingrediente[];
    cargando?: boolean;
    error?: { titulo: string; texto: string } | null;
    esqueletos?: number;
    alEditar: (p: Producto) => void;
  } = $props();

  let busqueda = $state('');
  let filtro = $state<string | null>(null);

  const platillos = $derived(menu.productos.filter((p) => !p.es_envio));
  const categoriaDe = $derived(new Map(menu.categorias.map((c) => [c.id, c])));
  const lleva = $derived.by(() => {
    const m = new Map<number, string[]>();
    for (const p of platillos) {
      const renglones = recetario.recetas.filter((r) => r.producto_id === p.id);
      if (renglones.length) m.set(p.id, loQueLleva(renglones, ingredientes, recetario.preparaciones));
    }
    return m;
  });
  // Las opciones de sus grupos que llevan receta: «Extra de queso · Extra de piña».
  const conReceta = $derived(new Set(recetario.recetas.map((r) => r.opcion_id).filter((x) => x !== null)));
  function opcionesConReceta(p: Producto): string {
    const nombres = menu.grupos
      .filter((g) => g.productos.includes(p.id))
      .flatMap((g) => g.opciones.filter((o) => conReceta.has(o.id)).map((o) => o.nombre));
    return nombres.length ? nombres.join(' · ') : '—';
  }

  const texto = $derived(busqueda.trim());
  const mostrados = $derived.by(() => {
    const q = texto.toLowerCase();
    return platillos.filter((p) => {
      if (filtro === 'sin' && lleva.has(p.id)) return false;
      if (filtro !== null && filtro !== 'sin' && String(p.categoria_id) !== filtro) return false;
      return !q || p.nombre.toLowerCase().includes(q);
    });
  });
  const sinReceta = $derived(platillos.filter((p) => !lleva.has(p.id)).length);

  const ESQUELETO = [
    { nombre: '96px', lleva: '220px' },
    { nombre: '120px', lleva: '180px' },
    { nombre: '70px', lleva: '240px' },
    { nombre: '104px', lleva: '150px' },
  ];
  const filas = $derived(anchos(ESQUELETO, esqueletos));
</script>

<Herramientas
  bind:busqueda
  placeholder="Busca un platillo…"
  cuenta={plural(mostrados.length, 'PLATILLO', 'PLATILLOS')}
  {cargando}
  filtro={{
    titulo: 'CATEGORÍAS',
    todas: { boton: 'Todas las categorías', nombre: 'Todas', icono: 'menu' },
    opciones: [
      ...menu.categorias.map((c) => ({
        valor: String(c.id),
        nombre: c.nombre,
        cuenta: platillos.filter((p) => p.categoria_id === c.id).length,
        categoria: c.icono,
      })),
      { valor: 'sin', nombre: 'Sin receta', cuenta: sinReceta, color: 'amarillo' },
    ],
    total: platillos.length,
    elegida: filtro,
    alElegir: (v) => (filtro = v),
  }}
/>

<Tabla
  columnas="2fr 1fr 3.2fr 1.4fr 80px"
  relleno="0 16px"
  altoFila={64}
  marco
  encabezados={[{ texto: 'Platillo' }, { texto: 'Categoría' }, { texto: 'Lleva' }, { texto: 'Opciones con receta' }, { texto: '' }]}
>
  {#if cargando}
    <span class="solo-lector">Cargando tus recetas…</span>
    {#each filas as e, i (i)}
      <div class="fila quieta" aria-hidden="true">
        <span class="inv-producto"><Esqueleto ancho="44px" alto="44px" redondo="11px" /><Esqueleto ancho={e.nombre} alto="11px" /></span>
        <span><Esqueleto ancho="72px" alto="24px" redondo="8px" /></span>
        <span><Esqueleto ancho={e.lleva} alto="10px" /></span>
        <span><Esqueleto ancho="90px" alto="10px" /></span>
        <span></span>
      </div>
    {/each}
  {:else if error}
    <NotaTabla relleno={48} angosta titulo={error.titulo} texto={error.texto} />
  {:else if !platillos.length}
    <NotaTabla
      relleno={48}
      angosta
      titulo="Todavía no hay platillos en tu menú."
      texto="Agrégalos en Mi menú; aquí les pones lo que lleva cada uno."
    />
  {:else if !mostrados.length}
    <NotaTabla
      relleno={48}
      angosta
      titulo={texto ? `No encontramos platillos para "${texto}".` : filtro === 'sin' ? 'Todos tus platillos tienen receta.' : 'No hay platillos en esta categoría.'}
      texto="Prueba con otro nombre o con Todas las categorías."
    />
  {:else}
    {#each mostrados as p (p.id)}
      {@const c = categoriaDe.get(p.categoria_id)}
      {@const cosas = lleva.get(p.id)}
      <div class="fila">
        <span class="inv-producto">
          <Foto src={p.imagen_ruta ? urlFoto(p.imagen_ruta) : null} />
          <span class="inv-nombre">{p.nombre}</span>
        </span>
        <span>
          {#if c}<span class="inv-chip"><IconoCategoria id={c.icono} tamano={13} /><span>{c.nombre}</span></span>{/if}
        </span>
        {#if cosas}
          <span class="inv-lleva">
            {#each cosas as cosa, j (j)}{#if j > 0}{' · '}{/if}<span>{cosa}</span>{/each}
          </span>
        {:else}
          <span><span class="inv-estado amarillo"><span class="inv-punto"></span>Sin receta · no resta nada</span></span>
        {/if}
        <span class="inv-tenue">{opcionesConReceta(p)}</span>
        <span class="inv-acciones">
          <BotonCuadro icono="crear" ayuda="Editar receta" onclick={() => alEditar(p)} />
        </span>
      </div>
    {/each}
  {/if}
</Tabla>
