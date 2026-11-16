<!--
  La barra de arriba de Vender, la Caja y Pedidos a lo ancho (adaptabilidad; maqueta GBWEGCsQFcwKkWm7Qe9FPA v4): la de
  las vistas del panel (diseno/BarraArriba.svelte) con el dock de Mi menú al centro (diseno/Dock.svelte). En el aparato,
  a la izquierda el logo del restaurante (sin logo, solo el nombre; lib/marcaAparato.ts), el restaurante y quién está
  («Lupita · Caja»), y el chip de lo que pasa; en el dock, sus
  pestañas, y la de la pantalla puede cambiarse por sus propias vistas (con mesas: Mesas · Para llevar). En el panel,
  «‹ Inicio» (o lo que pida la pantalla, como «‹ Mesas»), el título y el dock de sus vistas; a la derecha, los botones
  de la pantalla y la cajita de sucursales.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import BarraArriba from '../../../diseno/BarraArriba.svelte';
  import Boton from '../../../diseno/Boton.svelte';
  import Dock from '../../../diseno/Dock.svelte';
  import LogoRestaurante from '../../../diseno/LogoRestaurante.svelte';
  import { leerMarca } from '../../../lib/marcaAparato';
  import type { Anfitrion, OpcionDock } from './barra';

  let {
    anfitrion,
    titulo,
    chip = null,
    vistas = null,
    volver = null,
    children,
  }: {
    anfitrion: Anfitrion;
    titulo: string; // el del panel: «Punto de venta», «Caja»
    chip?: { texto: string; vivo: boolean; pausa?: boolean; hueco?: boolean } | null; // hueco: no se reciben (Pedidos)
    // Las vistas propias de la pantalla: en el panel son el dock; en el aparato toman el lugar de su pestaña.
    vistas?: { opciones: OpcionDock[]; elegida: string; alElegir: (valor: string) => void } | null;
    // Cambia «‹ Inicio» del panel; en el aparato sale antes del logo («‹ Mesas»).
    volver?: { texto: string; alVolver: () => void } | null;
    children?: Snippet;
  } = $props();

  const marca = leerMarca();

  const dock = $derived.by(() => {
    if (anfitrion.donde === 'panel') return vistas;
    const a = anfitrion;
    const propias = new Set(vistas?.opciones.map((o) => o.valor) ?? []);
    const opciones = a.pestanas.flatMap((p) => (vistas && p.valor === a.pestana ? vistas.opciones : [p]));
    return {
      opciones,
      elegida: vistas ? vistas.elegida : a.pestana,
      alElegir: (v: string) => (propias.has(v) ? vistas!.alElegir(v) : a.alPestana(v)),
    };
  });
</script>

<BarraArriba titulo={anfitrion.donde === 'panel' ? titulo : ''} estado={chip}>
  {#snippet antes()}
    {#if anfitrion.donde === 'panel'}
      <Boton etiqueta={volver?.texto ?? 'Inicio'} icono="anterior" onclick={volver?.alVolver ?? anfitrion.alInicio} />
    {:else}
      {#if volver}<Boton etiqueta={volver.texto} icono="anterior" onclick={volver.alVolver} />{/if}
      {#if marca?.logo}<span class="ap-logo"><LogoRestaurante ruta={marca.logo} /></span>{/if}
      <span class="ap-lugar"><b>{anfitrion.restaurante}</b><span>{anfitrion.linea}</span></span>
    {/if}
  {/snippet}
  {#snippet junto()}
    {#if dock && dock.opciones.length > 1}
      <Dock etiqueta="Pantalla" opciones={dock.opciones} elegida={dock.elegida} alElegir={dock.alElegir} />
    {/if}
  {/snippet}
  {@render children?.()}
  {#if anfitrion.donde === 'panel'}{@render anfitrion.sucursal?.()}{/if}
</BarraArriba>
