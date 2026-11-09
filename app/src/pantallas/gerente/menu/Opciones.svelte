<!--
  La sección Opciones de Mi menú (maqueta de Opciones y áreas GhrEVWPmevfBZtWzi4exKi): los grupos en
  el orden en que se eligen al agregar un producto, el mismo en todos los productos. Cada uno con su
  número, su nombre y debajo sus opciones (con el precio extra y las agotadas en gris), cómo se
  elige, en cuántos productos está, las flechas (se guardan al instante, como en Categorías) y el
  lápiz.

  Desde la tabla nueva (8 nov 2026, maqueta Ltm74p3fb7tiAqYcj5nqbX): la nota va suelta sobre el fondo y la
  tabla, en su marco. Mientras se lee el menú la primera vez (`cargando`), esqueletos con la forma de cada
  fila y del conteo.
-->
<script lang="ts">
  import BotonCuadro from '../../../diseno/BotonCuadro.svelte';
  import Esqueleto from '../../../diseno/Esqueleto.svelte';
  import NotaTabla from '../../../diseno/NotaTabla.svelte';
  import Tabla from '../../../diseno/Tabla.svelte';
  import { dinero, plural } from '../../../lib/formato';
  import type { Grupo, Menu } from '../../../lib/menu';
  import { regla } from '../../../lib/opciones';

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
    alMover: (g: Grupo, hacia: 'arriba' | 'abajo') => void;
    alEditar: (g: Grupo) => void;
  } = $props();

  const ESQUELETO = [
    { nombre: '48px', opciones: '156px', regla: '96px', productos: '92px' },
    { nombre: '64px', opciones: '120px', regla: '112px', productos: '80px' },
    { nombre: '56px', opciones: '184px', regla: '96px', productos: '100px' },
  ];
  const filasEsqueleto = $derived(Array.from({ length: esqueletos }, (_, i) => ESQUELETO[i % ESQUELETO.length]));
</script>

<div class="herramientas">
  <p class="nota">Al agregar un producto, se elige en este orden, de arriba abajo. Muévelos con las flechas.</p>
  <span class="crece"></span>
  <span class="etiqueta">
    {#if cargando}<Esqueleto ancho="64px" alto="10px" />{:else}{plural(menu.grupos.length, 'GRUPO', 'GRUPOS')}{/if}
  </span>
</div>

<Tabla
  columnas="3fr 1.3fr 1.1fr 128px"
  relleno="0 16px"
  altoFila={64}
  marco
  encabezados={[{ texto: 'Grupo' }, { texto: 'Cómo se elige' }, { texto: 'Productos' }, { texto: '' }]}
>
  {#if cargando}
    <!-- El esqueleto: tantas filas como grupos había la última vez, con su forma (su nombre y sus opciones) y sin sus botones. -->
    <span class="solo-lector">Cargando tus opciones…</span>
    {#each filasEsqueleto as e, i (i)}
      <div class="fila quieta" aria-hidden="true">
        <span class="grupo">
          <span class="numero"><Esqueleto ancho="16px" alto="9px" /></span>
          <span class="textos esqueletos"><Esqueleto ancho={e.nombre} alto="11px" /><Esqueleto ancho={e.opciones} alto="10px" /></span>
        </span>
        <span><Esqueleto ancho={e.regla} alto="10px" /></span>
        <span><Esqueleto ancho={e.productos} alto="10px" /></span>
        <span></span>
      </div>
    {/each}
  {:else if !menu.grupos.length}
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

  .textos.esqueletos {
    gap: 6px;
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
    color: var(--amarillo-texto);
    font-weight: 600;
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
