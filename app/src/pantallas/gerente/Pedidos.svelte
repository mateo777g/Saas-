<!--
  Pedidos en el panel del gerente (parte 6b; maqueta Pedidos por WhatsApp G2nxGb3xBgiPEYrDb6CgcW):
  la misma lista de la caja, con la sesión de Don Chuy, así que lo que confirma queda a su nombre.
  Tiene el ancho del celular, al centro de la tarjeta, como la caja abierta desde Inicio. La vigía
  vive en PanelGerente, para que el tono suene en cualquier vista.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import BarraArriba from '../../diseno/BarraArriba.svelte';
  import Vidrio from '../../diseno/Vidrio.svelte';
  import { enZona } from '../../lib/formato';
  import type { Sucursal } from '../../lib/gerente';
  import type { VigiaPedidos } from '../../lib/pedidos.svelte';
  import { leerZona } from '../../lib/pos';
  import { supabase } from '../../lib/supabase';
  import Pedidos from '../caja/Pedidos.svelte';
  import CajaSucursales from './CajaSucursales.svelte';

  let {
    sucursal,
    sucursales,
    vigia,
    alElegir,
  }: { sucursal: Sucursal; sucursales: Sucursal[]; vigia: VigiaPedidos; alElegir: (s: Sucursal) => void } = $props();

  let zona = $state('America/Mexico_City');

  const estado = $derived.by(() => {
    const d = vigia.datos;
    if (!d) return { texto: vigia.error ? 'No se pudo leer' : 'Leyendo…', vivo: false };
    if (d.pausado) return { texto: `En pausa desde las ${enZona(d.pausado_at ?? d.ahora, zona).hora}`, vivo: false, pausa: true };
    const n = d.por_confirmar.length;
    return { texto: n ? `${n} por confirmar` : 'Nada por confirmar', vivo: true };
  });

  onMount(() => {
    leerZona(supabase, sucursal.id)
      .then((z) => (zona = z))
      .catch((falla) => console.error('[gerente] no se pudo leer la zona de Pedidos; se usa la de México:', falla));
  });
</script>

<BarraArriba titulo="Pedidos" {estado}>
  <CajaSucursales {sucursales} actual={sucursal} {alElegir} />
</BarraArriba>

<Vidrio como="main" class="tarjeta-pedidos" radio={26}>
  <div class="panel-cel">
    <Pedidos cliente={supabase} restauranteId={sucursal.id} restaurante={sucursal.nombre} {vigia} enPanel />
  </div>
</Vidrio>

<style>
  :global(.tarjeta-pedidos) {
    position: absolute;
    left: 276px;
    right: 16px;
    top: 92px;
    bottom: 16px;
    overflow: hidden;
  }

  .panel-cel {
    position: absolute;
    top: 16px;
    bottom: 16px;
    left: 50%;
    width: 390px;
    max-width: calc(100% - 32px);
    transform: translateX(-50%);
    border-radius: 30px;
    border: 1px solid var(--linea);
    background: var(--suelo);
    overflow: hidden;
    display: flex;
    flex-direction: column;
  }

  .panel-cel > :global(.pos) {
    flex: 1;
    min-height: 0;
    padding: 18px 16px 30px;
  }
</style>
