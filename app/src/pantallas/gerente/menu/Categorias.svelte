<!--
  La sección Categorías de Mi menú (maqueta del Menú CC2rrjbgxC2yykNa33a3sA): la lista en el orden
  del menú en línea (también el del filtro y el de la tabla de Productos), cada una con su número,
  su ícono, su nombre, cuántos productos tiene y cuántos están ocultos, las flechas de subir y
  bajar (se guarda al instante, como el ojito) y el lápiz.
-->
<script lang="ts">
  import BotonCuadro from '../../../diseno/BotonCuadro.svelte';
  import IconoCategoria from '../../../diseno/IconoCategoria.svelte';
  import NotaTabla from '../../../diseno/NotaTabla.svelte';
  import Tabla from '../../../diseno/Tabla.svelte';
  import { plural } from '../../../lib/formato';
  import type { Categoria, Menu } from '../../../lib/menu';

  let {
    menu,
    alMover,
    alEditar,
  }: {
    menu: Menu;
    alMover: (c: Categoria, hacia: 'arriba' | 'abajo') => void;
    alEditar: (c: Categoria) => void;
  } = $props();

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
  <span class="etiqueta">{plural(menu.categorias.length, 'CATEGORÍA', 'CATEGORÍAS')}</span>
</div>

<Tabla
  columnas="3fr 2fr 128px"
  relleno="0 16px"
  altoFila={64}
  encabezados={[{ texto: 'CATEGORÍA' }, { texto: 'PRODUCTOS' }, { texto: '' }]}
>
  {#if !menu.categorias.length}
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
  .herramientas {
    flex: none;
    min-height: 40px;
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

  .acciones {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
  }
</style>
