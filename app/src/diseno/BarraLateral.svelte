<!--
  La barra lateral de barra_lateral.py: una tarjeta de vidrio que flota a 16 del borde, de 244
  de ancho. Arriba la marca (la ∫∫ en su cuadro del acento y "fragmentless" en Outfit 200);
  luego las opciones, con la activa en una píldora de tinta y las demás en gris, que se
  encienden con el cursor encima; abajo las acciones (Cerrar sesión) y el pie: el círculo con
  la inicial, el nombre y una línea en mono, sobre una raya fina. Si el pie trae alPulsar, es un
  botón (el gerente abre ahí su Perfil). Entre las opciones puede ir un título de grupo en mono
  ({ grupo: 'GENERAL' }), como en Flet.
-->
<script lang="ts">
  import Icono from './Icono.svelte';
  import Integral from './Integral.svelte';
  import Vidrio from './Vidrio.svelte';

  type Opcion = { valor: string; texto: string; icono: string };
  type Grupo = { grupo: string };

  let {
    subtitulo,
    opciones,
    acciones = [],
    activa,
    alElegir,
    pie,
  }: {
    subtitulo: string;
    opciones: (Opcion | Grupo)[];
    acciones?: Opcion[];
    activa: string;
    alElegir: (valor: string) => void;
    pie: { inicial: string; nombre: string; linea: string; alPulsar?: () => void };
  } = $props();
</script>

{#snippet opcion(o: Opcion)}
  <button
    type="button"
    class="opcion"
    class:activa={o.valor === activa}
    aria-current={o.valor === activa ? 'page' : undefined}
    onclick={() => alElegir(o.valor)}
  >
    <Icono nombre={o.icono} tamano={18} />
    {o.texto}
  </button>
{/snippet}

{#snippet filaPie()}
  <span class="inicial">{pie.inicial}</span>
  <span class="pie-texto">
    <span class="pie-nombre">{pie.nombre}</span>
    <span class="pie-linea">{pie.linea}</span>
  </span>
{/snippet}

<Vidrio como="nav" class="barra-lateral" aria-label="Menú del panel">
  <div class="marca">
    <span class="logo"><Integral ancho={25} alto={27} /></span>
    <span class="marca-texto">
      <span class="marca-nombre">fragmentless</span>
      <span class="mono marca-sub">{subtitulo}</span>
    </span>
  </div>

  <div class="opciones">
    {#each opciones as o ('grupo' in o ? `grupo-${o.grupo}` : o.valor)}
      {#if 'grupo' in o}
        <span class="etiqueta titulo-grupo">{o.grupo}</span>
      {:else}
        {@render opcion(o)}
      {/if}
    {/each}
  </div>

  <div class="crece"></div>

  {#if acciones.length}
    <div class="opciones">
      {#each acciones as o (o.valor)}
        {@render opcion(o)}
      {/each}
    </div>
  {/if}

  <div class="pie">
    {#if pie.alPulsar}
      <button type="button" class="pie-fila boton-pie" onclick={pie.alPulsar}>
        {@render filaPie()}
      </button>
    {:else}
      <div class="pie-fila">{@render filaPie()}</div>
    {/if}
  </div>
</Vidrio>

<style>
  :global(.barra-lateral) {
    position: absolute;
    left: 16px;
    top: 16px;
    bottom: 16px;
    width: 244px;
    z-index: 2;
    padding: 18px 12px 14px;
    display: flex;
    flex-direction: column;
  }

  .marca {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 0 6px 18px;
  }

  .logo {
    width: 40px;
    height: 40px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 12px;
    background: var(--acento);
    color: var(--sobre-acento);
  }

  .marca-texto {
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .marca-nombre {
    font-family: var(--outfit);
    font-size: 19px;
    font-weight: 200;
    line-height: 1.1;
    letter-spacing: 0.005em;
  }

  .marca-sub {
    font-size: 10.5px;
    color: var(--tenue);
  }

  .opciones {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .titulo-grupo {
    padding: 14px 14px 6px;
  }

  .opcion {
    width: 100%;
    height: 42px;
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 0 14px;
    border: 0;
    border-radius: 12px;
    background: transparent;
    color: var(--suave);
    font-size: 14px;
    font-weight: 500;
    text-align: left;
    transition: background-color 150ms ease-out;
  }

  .opcion:hover {
    background: var(--chip);
  }

  .opcion.activa {
    background: var(--tinta);
    color: var(--sobre-tinta);
    font-weight: 600;
  }

  .crece {
    flex-grow: 1;
  }

  .pie {
    margin-top: 12px;
    padding-top: 4px;
    border-top: 1px solid var(--linea);
  }

  .pie-fila {
    width: 100%;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 8px;
    text-align: left;
  }

  .boton-pie {
    border: 0;
    border-radius: 12px;
    background: transparent;
  }

  .boton-pie:hover {
    background: var(--chip);
  }

  .inicial {
    width: 34px;
    height: 34px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 17px;
    background: var(--chip);
    border: 1px solid var(--linea);
    font-size: 13px;
    font-weight: 700;
  }

  .pie-texto {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 1px;
  }

  .pie-nombre {
    font-size: 13px;
    font-weight: 700;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .pie-linea {
    font-family: var(--mono);
    font-size: 10.5px;
    color: var(--tenue);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
</style>
