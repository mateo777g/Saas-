<!--
  La búsqueda del gerente: sus vistas y sus acciones (lib/vistas.ts). Sin `alCerrar` es la grande de Inicio; con
  `alCerrar`, la que se abre en cualquier otra vista (diseno/BuscarAqui.svelte, 9 nov 2026).
-->
<script lang="ts">
  import BuscadorBase, { type RenglonBusqueda } from '../../../diseno/Buscador.svelte';
  import BuscarAqui from '../../../diseno/BuscarAqui.svelte';
  import { ACCIONES, VISTAS, type Destino, type VistaGerente } from '../../../lib/vistas';

  let {
    recientes,
    alIr,
    alCerrar,
  }: { recientes: VistaGerente[]; alIr: (destino: Destino) => void; alCerrar?: () => void } = $props();

  let base = $state<{ enfocar: () => void } | null>(null);

  const deVista = (v: VistaGerente): RenglonBusqueda => ({
    clave: v,
    texto: VISTAS[v].texto,
    de: VISTAS[v].grupo,
    icono: VISTAS[v].icono,
    alPicar: () => alIr({ vista: v }),
  });

  const vistas = (Object.keys(VISTAS) as VistaGerente[]).map(deVista);
  const acciones: RenglonBusqueda[] = ACCIONES.map((a) => ({
    clave: a.texto,
    texto: a.texto,
    de: a.de,
    icono: a.icono,
    alPicar: () => alIr(a.destino),
  }));
  const deRecientes = $derived(recientes.map(deVista));

  export function enfocar() {
    base?.enfocar();
  }
</script>

{#if alCerrar}
  <BuscarAqui {vistas} {acciones} recientes={deRecientes} {alCerrar} />
{:else}
  <BuscadorBase bind:this={base} {vistas} {acciones} recientes={deRecientes} />
{/if}
