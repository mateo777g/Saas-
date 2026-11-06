<!--
  Las columnas del Inicio del gerente: Abrir, con los accesos del equipo; Atajos, y Recientes, por sucursal.
-->
<script lang="ts">
  import ColumnasBase, { type ItemColumna } from '../../../diseno/Columnas.svelte';
  import { VISTAS, type Destino, type VistaGerente } from '../../../lib/vistas';

  let {
    recientes,
    alAbrir,
    alIr,
  }: {
    recientes: VistaGerente[];
    alAbrir: (que: 'pos' | 'caja' | 'cocina') => void;
    alIr: (destino: Destino) => void;
  } = $props();

  const ABRIR: { texto: string; icono: string; abre: 'pos' | 'caja' | 'cocina' }[] = [
    { texto: 'Punto de venta', icono: 'r-mesas', abre: 'pos' },
    { texto: 'Caja', icono: 'r-billete', abre: 'caja' },
    { texto: 'Cocina', icono: 'r-cocina', abre: 'cocina' },
  ];

  const ATAJOS: { texto: string; icono: string; destino: Destino }[] = [
    { texto: 'Agregar producto', icono: 'r-producto', destino: { vista: 'menu', nuevo: 'producto' } },
    { texto: 'Crear anuncio', icono: 'r-crear', destino: { vista: 'crear' } },
    { texto: 'Ver el corte de hoy', icono: 'r-corte', destino: { vista: 'cortes' } },
  ];

  const abrir: ItemColumna[] = ABRIR.map((a) => ({
    clave: a.abre,
    texto: a.texto,
    icono: a.icono,
    flecha: 'r-afuera',
    alPicar: () => alAbrir(a.abre),
  }));

  const atajos: ItemColumna[] = ATAJOS.map((a) => ({
    clave: a.texto,
    texto: a.texto,
    icono: a.icono,
    alPicar: () => alIr(a.destino),
  }));

  const deRecientes = $derived<ItemColumna[]>(
    recientes.map((v) => ({
      clave: v,
      texto: VISTAS[v].texto,
      de: VISTAS[v].grupo,
      icono: 'r-reloj',
      alPicar: () => alIr({ vista: v }),
    })),
  );
</script>

<ColumnasBase {abrir} {atajos} recientes={deRecientes} />
