<!--
  «Sumar meses» (fila de Clientes y Vencen pronto): llama a extender_licencia(restaurante,
  meses). Postgres cuenta desde la fecha mayor entre su fin y hoy, y no prende una licencia
  pausada. El botón muestra el fin nuevo que devuelve.
-->
<script lang="ts">
  import Campo from '../../diseno/Campo.svelte';
  import Formulario from '../../diseno/Formulario.svelte';
  import Ventana from '../../diseno/Ventana.svelte';
  import { entero, fecha, vigencia } from '../../lib/formato';
  import { extenderLicencia, type Cliente } from '../../lib/panel';

  let {
    cliente,
    alCerrar,
    alGuardar,
  }: { cliente: Cliente; alCerrar: () => void; alGuardar: () => void } = $props();

  let meses = $state('1');

  async function guardar() {
    const r = await extenderLicencia(cliente.id, entero(meses));
    if (!r.ok) return { error: r.mensaje };
    alGuardar();
    return { listo: `Ahora termina el ${fecha(r.valor)}` };
  }
</script>

<Ventana etiqueta="SUMAR MESES" titulo={cliente.nombre} {alCerrar}>
  <Formulario boton={{ etiqueta: 'Sumar meses', icono: 'calendario-mas' }} {guardar} alTerminar={alCerrar}>
    <div class="aviso">
      {#if cliente.licencia_fin}
        Su licencia termina el {fecha(cliente.licencia_fin)}. {vigencia(cliente.dias_restantes)}.
      {:else}
        Su licencia no tiene fecha de fin.
      {/if}
    </div>
    <Campo id="sumar-meses" etiqueta="MESES" tipo="number" bind:valor={meses} min={1} step={1} />
    <p class="pista">
      Si todavía no vence, se suman a su fecha de fin. Si ya venció, cuentan desde hoy. No prende
      una licencia pausada.
    </p>
  </Formulario>
</Ventana>

<style>
  .aviso {
    padding: 11px 14px;
    border: 1px solid var(--linea);
    border-radius: 12px;
    background: var(--chip);
    font-size: 12.5px;
    font-weight: 500;
    line-height: 1.45;
  }
</style>
