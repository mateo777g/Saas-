<!--
  La fila «Tema y colores» de «Tu menú en línea» (maqueta UDArhiEZceT7rmSKxqRA5r v59): el tema de su menú con el sol
  que se vuelve luna (diseno/BotonTema.svelte, el mismo de Ajustes), el color de su menú, el de la barra y el fondo.
  Cada color con su muestra, «Elegir color» o «Cambiar» (que abren la ventana del color) y, si hay uno, la X que lo
  quita. Sin color, la muestra dice qué sale. Un aviso amarillo si el color casi no se ve sobre su fondo, si la barra
  casi no se distingue del fondo o si con ese fondo las letras casi no se leen. Mientras la vista lee la primera vez, el
  botón del tema y cada color van en esqueleto.
-->
<script lang="ts">
  import Boton from '../../../diseno/Boton.svelte';
  import BotonCuadro from '../../../diseno/BotonCuadro.svelte';
  import BotonTema from '../../../diseno/BotonTema.svelte';
  import Esqueleto from '../../../diseno/Esqueleto.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import type { TemaMenu } from '../../../lib/color';
  import { avisoDeColor, type ClaveColor } from './colores';
  import Fila from './Fila.svelte';

  let {
    tema,
    color,
    colorBarra,
    fondo,
    cargando,
    alTema,
    alElegir,
    alQuitar,
  }: {
    tema: TemaMenu;
    color: string | null;
    colorBarra: string | null;
    fondo: string | null;
    cargando: boolean;
    alTema: () => void;
    alElegir: (clave: ClaveColor) => void;
    alQuitar: (clave: ClaveColor) => void;
  } = $props();

  const GRUPOS: { clave: ClaveColor; etiqueta: string; pista: string; quitar: string }[] = [
    {
      clave: 'color',
      etiqueta: 'COLOR DE TU MENÚ',
      pista: 'Pinta lo que está elegido, el «+», las rayas del cartel y los botones del pedido.',
      quitar: 'Quitar color',
    },
    {
      clave: 'colorBarra',
      etiqueta: 'COLOR DE LA BARRA',
      pista:
        'Pinta la barra de arriba y las cajas de tu menú: la búsqueda y las categorías. Si no lo eliges, la barra va del color de tu menú y las cajas no cambian.',
      quitar: 'Usar el color de tu menú',
    },
    { clave: 'fondo', etiqueta: 'FONDO', pista: 'El fondo de todo tu menú. Las letras siguen al tema.', quitar: 'Quitar fondo' },
  ];

  const valores = $derived({ color, colorBarra, fondo });
  const oscuro = $derived(tema === 'oscuro');

  // Sin color: lo elegido va en negro (en claro) o en blanco (en oscuro); la barra, del color de tu menú (o negra o
  // gris oscuro, como hoy); el fondo, blanco o negro.
  function sinGota(clave: ClaveColor) {
    if (clave === 'color') return oscuro ? '#f3f3f0' : '#121212';
    if (clave === 'colorBarra') return color || (oscuro ? '#1f1f1f' : '#121212');
    return oscuro ? '#0F0F0F' : '#FFFFFF';
  }

  function sinTexto(clave: ClaveColor) {
    if (clave === 'color') return `Sin color · ${oscuro ? 'blanco' : 'negro'}`;
    if (clave === 'colorBarra') return 'Del color de tu menú';
    return `Sin color · ${oscuro ? 'negro' : 'blanco'}`;
  }

</script>

<Fila clave="tema" icono="contraste" titulo="Tema y colores" nota="Escoge lo que vaya con tu logo.">
  <div class="grupo">
    <span class="etiqueta">TEMA DE TU MENÚ</span>
    <div class="control">
      {#if cargando}
        <Esqueleto ancho="64px" alto="40px" redondo="12px" /><Esqueleto ancho="120px" alto="12px" />
      {:else}
        <BotonTema {tema} ayuda={tema === 'claro' ? 'Cambiar tu menú a oscuro' : 'Cambiar tu menú a claro'} alCambiar={alTema} />
        <span class="tema-texto">Tu menú va en {tema}</span>
      {/if}
    </div>
    <p class="pista">Cambia el tema de tu menú, no el de este panel.</p>
  </div>

  {#each GRUPOS as g (g.clave)}
    {@const v = valores[g.clave]}
    {@const aviso = cargando ? null : avisoDeColor(g.clave, { tema, color, colorBarra, fondo })}
    <div class="grupo">
      <span class="etiqueta">{g.etiqueta}</span>
      <div class="control">
        {#if cargando}
          <span class="crece"><Esqueleto ancho="100%" alto="40px" redondo="12px" /></span>
          <Esqueleto ancho="96px" alto="40px" redondo="12px" />
        {:else}
          <div class="muestra">
            <span class="gota" style:background={v || sinGota(g.clave)}></span>
            {#if v}<span class="mono">{v}</span>{:else}<span class="sin">{sinTexto(g.clave)}</span>{/if}
          </div>
          <Boton etiqueta={v ? 'Cambiar' : 'Elegir color'} onclick={() => alElegir(g.clave)} />
          {#if v}
            <BotonCuadro icono="cerrar" ayuda={g.quitar} grande onclick={() => alQuitar(g.clave)} />
          {/if}
        {/if}
      </div>
      <p class="pista">{g.pista}</p>
      <!-- Su lugar se queda aunque no haya aviso, como en la maqueta. -->
      <div class="lugar-aviso">
        {#if aviso}
          <p class="aviso"><Icono nombre="alerta" tamano={16} /><span><b>{aviso.fuerte}</b> {aviso.texto}</span></p>
        {/if}
      </div>
    </div>
  {/each}
</Fila>

<style>
  .grupo {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .control {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .crece {
    flex: 1;
    min-width: 0;
    display: flex;
  }

  .tema-texto {
    font-size: 13px;
    font-weight: 600;
    color: var(--suave);
  }

  .pista {
    margin: 0;
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--tenue);
  }

  .muestra {
    flex: 1;
    min-width: 0;
    height: 40px;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 12px;
    border: 1px solid var(--linea);
    border-radius: 12px;
  }

  .gota {
    width: 20px;
    height: 20px;
    flex: none;
    border-radius: 6px;
    border: 1px solid var(--linea-fuerte);
  }

  .muestra .mono {
    font-size: 13px;
  }

  .sin {
    font-size: 13px;
    color: var(--suave);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .aviso {
    display: flex;
    align-items: flex-start;
    gap: 10px;
    margin: 0;
    padding: 11px 14px;
    border-radius: 12px;
    background: var(--amarillo-fondo);
    font-size: 12.5px;
    line-height: 1.5;
    color: var(--suave);
  }

  .aviso :global(svg) {
    flex: none;
    margin-top: 2px;
    color: var(--amarillo-texto);
  }

  .aviso b {
    color: var(--texto);
    font-weight: 600;
  }
</style>
