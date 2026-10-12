<!--
  «Dar de baja» y «Reactivar» (fila de Distribuidores): la ventana de confirmar, que llama a
  fijar_distribuidor_activo(distribuidor, activo). Con clientes no se da de baja: Postgres los
  cuenta y lo dice («Juanito Pérez todavía tiene 3 clientes; quítaselos primero»).
-->
<script lang="ts">
  import Confirmar from '../../diseno/Confirmar.svelte';
  import { fijarDistribuidorActivo, type Distribuidor } from '../../lib/panel';

  let {
    distribuidor,
    baja,
    alCerrar,
    alGuardar,
  }: { distribuidor: Distribuidor; baja: boolean; alCerrar: () => void; alGuardar: () => void } = $props();

  async function confirmar() {
    const r = await fijarDistribuidorActivo(distribuidor.id, !baja);
    if (!r.ok) return { error: r.mensaje };
    alGuardar();
    return { listo: baja ? 'Baja guardada' : 'Reactivación guardada' };
  }
</script>

{#if baja}
  <Confirmar
    icono="alerta"
    titulo="Dar de baja a {distribuidor.nombre}"
    texto="Ya no se le pueden asignar clientes. Sus cobros pasados siguen siendo suyos, y se puede reactivar cuando quieras."
    boton={{ etiqueta: 'Dar de baja', icono: 'usuario-menos' }}
    {confirmar}
    {alCerrar}
  />
{:else}
  <Confirmar
    icono="usuario-check"
    titulo="Reactivar a {distribuidor.nombre}"
    texto="Su estado vuelve a Activo y se le pueden asignar clientes otra vez."
    boton={{ etiqueta: 'Reactivar', icono: 'usuario-check' }}
    {confirmar}
    {alCerrar}
  />
{/if}
