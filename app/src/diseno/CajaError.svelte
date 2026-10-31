<!--
  caja_error() de diseno.py: el error en línea, sin rojo. Chip con borde fino e icono de alerta;
  el aviso que no es error ("Cerraste sesión.") lleva el de info, y el de sin internet del punto
  de venta, el de sin red (maqueta Mesero y cocina).
-->
<script lang="ts">
  import Icono from './Icono.svelte';

  let {
    mensaje,
    tipo = 'alerta',
    tamano = 12.5,
    compacta = false,
  }: {
    mensaje: string;
    tipo?: 'alerta' | 'info' | 'sinred';
    tamano?: number;
    // Más baja (9 px arriba y abajo): la de Crear contenido, junto a Generar anuncio y en Resultado.
    compacta?: boolean;
  } = $props();
</script>

<div class="caja" class:compacta role={tipo === 'info' ? 'status' : 'alert'} style:font-size="{tamano}px">
  <span class="icono"><Icono nombre={tipo} tamano={16} /></span>
  <span>{mensaje}</span>
</div>

<style>
  .caja {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 11px 14px;
    border-radius: 12px;
    border: 1px solid var(--linea);
    background: var(--chip);
    font-weight: 500;
    line-height: 1.45;
    color: var(--texto);
  }

  .caja.compacta {
    padding: 9px 14px;
    line-height: 1.4;
  }

  .icono {
    color: var(--suave);
  }
</style>
