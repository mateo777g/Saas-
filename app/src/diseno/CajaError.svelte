<!--
  caja_error() de diseno.py: el error en línea, sin rojo. Chip con borde fino e icono de alerta;
  el aviso que no es error ("Cerraste sesión.") lleva el de info.
-->
<script lang="ts">
  import Icono from './Icono.svelte';

  let {
    mensaje,
    tipo = 'alerta',
    tamano = 12.5,
  }: { mensaje: string; tipo?: 'alerta' | 'info'; tamano?: number } = $props();
</script>

<div class="caja" role={tipo === 'alerta' ? 'alert' : 'status'} style:font-size="{tamano}px">
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

  .icono {
    color: var(--suave);
  }
</style>
