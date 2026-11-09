<!--
  La sección Categorías de Mi menú (maqueta del Menú CC2rrjbgxC2yykNa33a3sA): la lista en el orden
  del menú en línea (también el del filtro y el de la tabla de Productos), cada una con su número,
  su ícono, su nombre, cuántos productos tiene y cuántos están ocultos, su área (maqueta de Opciones
  y áreas GhrEVWPmevfBZtWzi4exKi), las flechas de subir y bajar (se guarda al instante, como el
  ojito) y el lápiz.

  Desde la tabla nueva (8 nov 2026, maqueta Ltm74p3fb7tiAqYcj5nqbX): la nota va suelta sobre el fondo y la
  tabla, en su marco. Mientras se lee el menú la primera vez (`cargando`), esqueletos con la forma de cada
  fila y del conteo.
-->
<script lang="ts">
  import BotonCuadro from '../../../diseno/BotonCuadro.svelte';
  import Esqueleto from '../../../diseno/Esqueleto.svelte';
  import IconoCategoria from '../../../diseno/IconoCategoria.svelte';
  import NotaTabla from '../../../diseno/NotaTabla.svelte';
  import Tabla from '../../../diseno/Tabla.svelte';
  import { plural } from '../../../lib/formato';
  import type { Categoria, Menu } from '../../../lib/menu';

  let {
    menu,
    cargando = false,
    esqueletos = 3,
    alMover,
    alEditar,
  }: {
    menu: Menu;
    cargando?: boolean;
    esqueletos?: number;
    alMover: (c: Categoria, hacia: 'arriba' | 'abajo') => void;
    alEditar: (c: Categoria) => void;
  } = $props();

  const ESQUELETO = [
    { nombre: '60px', cuenta: '128px', area: '60px' },
    { nombre: '86px', cuenta: '96px', area: '52px' },
    { nombre: '72px', cuenta: '112px', area: '60px' },
  ];
  const filasEsqueleto = $derived(Array.from({ length: esqueletos }, (_, i) => ESQUELETO[i % ESQUELETO.length]));

  const nombreArea = $derived(new Map(menu.areas.map((a) => [a.id, a.nombre])));

  // «6 productos · 1 oculto», o «Sin productos».
  function cuenta(id: number) {
    const suyos = menu.productos.filter((p) => p.categoria_id === id);
    if (!suyos.length) return 'Sin productos';
    const ocultos = suyos.filter((p) => !p.visible).length;
    return plural(suyos.length, 'producto', 'productos') + (ocultos ? ` · ${plural(ocultos, 'oculto', 'ocultos')}` : '');
  }
</script>

<div class="herramientas">
  <p class="nota">Así salen en tu menú en línea, de arriba abajo. Muévelas con las flechas.</p>
  <span class="crece"></span>
  <span class="etiqueta">
    {#if cargando}<Esqueleto ancho="92px" alto="10px" />{:else}{plural(menu.categorias.length, 'CATEGORÍA', 'CATEGORÍAS')}{/if}
  </span>
</div>

<Tabla
  columnas="3fr 1.6fr 1.5fr 128px"
  relleno="0 16px"
  altoFila={64}
  marco
  encabezados={[{ texto: 'Categoría' }, { texto: 'Productos' }, { texto: 'Área' }, { texto: '' }]}
>
  {#if cargando}
    <!-- El esqueleto: tantas filas como categorías había la última vez, con su forma y sin sus botones. -->
    <span class="solo-lector">Cargando tus categorías…</span>
    {#each filasEsqueleto as e, i (i)}
      <div class="fila quieta" aria-hidden="true">
        <span class="categoria">
          <span class="numero"><Esqueleto ancho="16px" alto="9px" /></span>
          <Esqueleto ancho="36px" alto="36px" redondo="11px" />
          <Esqueleto ancho={e.nombre} alto="11px" />
        </span>
        <span><Esqueleto ancho={e.cuenta} alto="10px" /></span>
        <span><Esqueleto ancho={e.area} alto="26px" redondo="8px" /></span>
        <span></span>
      </div>
    {/each}
  {:else if !menu.categorias.length}
    <NotaTabla
      relleno={48} angosta
      titulo="Todavía no tienes categorías."
      texto="Crea la primera con Nueva categoría: por ejemplo Tacos, Bebidas o Postres. Cada producto va en una."
    />
  {:else}
    {#each menu.categorias as c, i (c.id)}
      <div class="fila">
        <span class="categoria">
          <span class="numero">{String(i + 1).padStart(2, '0')}</span>
          <span class="cuadro-icono"><IconoCategoria id={c.icono} tamano={18} /></span>
          <span class="nombre">{c.nombre}</span>
        </span>
        <span class="cuenta">{cuenta(c.id)}</span>
        <span>
          {#if c.area_preparacion_id !== null}
            <span class="area">{nombreArea.get(c.area_preparacion_id) ?? '—'}</span>
          {:else}
            <span class="area mesero">Lo sirve el mesero</span>
          {/if}
        </span>
        <span class="acciones">
          <BotonCuadro
            icono="arriba"
            ayuda="Subir"
            etiqueta="Subir {c.nombre}"
            apagado={i === 0}
            data-subir={c.id}
            onclick={() => alMover(c, 'arriba')}
          />
          <BotonCuadro
            icono="abajo"
            ayuda="Bajar"
            etiqueta="Bajar {c.nombre}"
            apagado={i === menu.categorias.length - 1}
            data-bajar={c.id}
            onclick={() => alMover(c, 'abajo')}
          />
          <BotonCuadro icono="crear" ayuda="Editar categoría" onclick={() => alEditar(c)} />
        </span>
      </div>
    {/each}
  {/if}
</Tabla>

<style>
  /* 48, como la de Productos con su búsqueda: la tabla no brinca al cambiar de sección. */
  .herramientas {
    flex: none;
    min-height: 48px;
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .nota {
    margin: 0;
    font-size: 12.5px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .crece {
    flex-grow: 1;
  }

  .categoria {
    min-width: 0;
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .numero {
    width: 22px;
    flex: none;
    font-family: var(--mono);
    font-size: 11px;
    color: var(--tenue);
  }

  .cuadro-icono {
    width: 36px;
    height: 36px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 11px;
    background: var(--chip);
  }

  .nombre {
    min-width: 0;
    overflow: hidden;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    font-size: 13.5px;
    font-weight: 700;
  }

  .cuenta {
    font-size: 12.5px;
    font-weight: 500;
    color: var(--suave);
  }

  .area {
    max-width: 100%;
    height: 26px;
    display: inline-flex;
    align-items: center;
    padding: 0 10px;
    border-radius: 8px;
    background: var(--chip);
    font-size: 12px;
    font-weight: 600;
    color: var(--suave);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .area.mesero {
    border: 1px dashed var(--linea-fuerte);
    background: transparent;
    font-weight: 500;
    color: var(--tenue);
  }

  .acciones {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
  }
</style>
