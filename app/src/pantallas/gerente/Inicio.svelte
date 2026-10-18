<!--
  Inicio del gerente en el paso 1 (maqueta 5SVLK2avzLCq5TaW6mrqq6, estado "Paso 1"): la tarjeta
  de vidrio con la fecha y el saludo, lo no negociable de Inicio. La fecha y la hora son las del
  restaurante y las da Postgres (mis_sucursales), nunca el reloj del aparato (libreta 4,
  decidido el 11 de octubre de 2026). Debajo, «Accesos para tu equipo» (parte 4a del punto de
  venta). Las cifras, Mesas ahora y Tus meseros aparecen cuando exista su módulo (pieza 5).
-->
<script lang="ts">
  import Integral from '../../diseno/Integral.svelte';
  import Vidrio from '../../diseno/Vidrio.svelte';
  import { fechaLarga, saludoPorHora } from '../../lib/formato';
  import type { Sucursal } from '../../lib/gerente';
  import Accesos from './Accesos.svelte';

  let {
    sucursal,
    nombre,
    alAbrir,
  }: { sucursal: Sucursal; nombre: string; alAbrir: (que: 'pos' | 'caja' | 'cocina') => void } = $props();
</script>

<div class="inicio">
  <Vidrio como="section" class="saludo" radio={30} aria-label="Saludo">
    <div class="fecha">
      <span class="logo"><Integral ancho={20} alto={22} /></span>
      <span class="etiqueta">{fechaLarga(sucursal.hoy)}</span>
    </div>
    <p class="texto">
      {saludoPorHora(sucursal.hora)}, {nombre}.<span>Así va tu negocio hoy.</span>
    </p>
  </Vidrio>
  <Accesos {alAbrir} />
</div>

<style>
  .inicio > :global(.saludo) {
    padding: 34px 36px 28px;
  }

  .fecha {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .logo {
    width: 30px;
    height: 30px;
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--acento);
  }

  .fecha .etiqueta {
    font-size: 11.5px;
  }

  .texto {
    margin: 14px 0 0;
    font-size: 50px;
    font-weight: 800;
    line-height: 1.04;
    letter-spacing: -1.25px;
  }

  .texto span {
    display: block;
    color: var(--tenue);
  }
</style>
