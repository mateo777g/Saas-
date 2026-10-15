<!--
  La sección Opciones de Mi menú (maqueta de Opciones y áreas GhrEVWPmevfBZtWzi4exKi): los grupos en
  el orden en que se eligen al agregar un producto, el mismo en todos los productos. Cada uno con su
  número, su nombre y debajo sus opciones (con el precio extra y las agotadas en gris), cómo se
  elige, en cuántos productos está, las flechas (se guardan al instante, como en Categorías) y el
  lápiz.
-->
<script lang="ts">
  import BotonCuadro from '../../../diseno/BotonCuadro.svelte';
  import NotaTabla from '../../../diseno/NotaTabla.svelte';
  import Tabla from '../../../diseno/Tabla.svelte';
  import { dinero, plural } from '../../../lib/formato';
  import type { Grupo, Menu } from '../../../lib/menu';
  import { regla } from '../../../lib/opciones';

  let {
    menu,
    alMover,
    alEditar,
  }: {
    menu: Menu;
    alMover: (g: Grupo, hacia: 'arriba' | 'abajo') => void;
    alEditar: (g: Grupo) => void;
  } = $props();
</script>

<div class="herramientas">
  <p class="nota">Al agregar un producto, se elige en este orden, de arriba abajo. Muévelos con las flechas.</p>
  <span class="crece"></span>
  <span class="etiqueta">{plural(menu.grupos.length, 'GRUPO', 'GRUPOS')}</span>
</div>

<Tabla
  columnas="3fr 1.3fr 1.1fr 128px"
  relleno="0 16px"
  altoFila={64}
  encabezados={[{ texto: 'GRUPO' }, { texto: 'CÓMO SE ELIGE' }, { texto: 'PRODUCTOS' }, { texto: '' }]}
>
  {#if !menu.grupos.length}
    <NotaTabla
      relleno={48} angosta
      titulo="Todavía no tienes grupos de opciones."
      texto="Crea el primero con Nuevo grupo, como Salsa: Verde, Roja y Sin salsa. Después lo pones en los productos que lo llevan."
    />
  {:else}
    {#each menu.grupos as g, i (g.id)}
      <div class="fila">
        <span class="grupo">
          <span class="numero">{String(i + 1).padStart(2, '0')}</span>
          <span class="textos">
            <span class="nombre">{g.nombre}</span>
            <span class="opciones">
              {#each g.opciones as o, j (o.id)}
                {#if j > 0}{' · '}{/if}
                {#if o.visible}
                  {o.nombre}{#if o.precio_extra > 0}{' '}<span class="extra">+{dinero(o.precio_extra)}</span>{/if}
                {:else}
                  <span class="agotada">{o.nombre} (agotada)</span>
                {/if}
              {/each}
            </span>
          </span>
        </span>
        <span class="cuenta">{regla(g.minimo, g.maximo)}</span>
        <span class="cuenta">{g.productos.length ? `En ${plural(g.productos.length, 'producto', 'productos')}` : 'En ningún producto'}</span>
        <span class="acciones">
          <BotonCuadro
            icono="arriba"
            ayuda="Subir"
            etiqueta="Subir {g.nombre}"
            apagado={i === 0}
            data-subir={g.id}
            onclick={() => alMover(g, 'arriba')}
          />
          <BotonCuadro
            icono="abajo"
            ayuda="Bajar"
            etiqueta="Bajar {g.nombre}"
            apagado={i === menu.grupos.length - 1}
            data-bajar={g.id}
            onclick={() => alMover(g, 'abajo')}
          />
          <BotonCuadro icono="crear" ayuda="Editar grupo" onclick={() => alEditar(g)} />
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

  .grupo {
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

  .textos {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .nombre {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 13.5px;
    font-weight: 700;
  }

  .opciones {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .extra {
    font-family: var(--mono);
    font-size: 11px;
    color: var(--tenue);
  }

  .agotada {
    color: var(--tenue);
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
