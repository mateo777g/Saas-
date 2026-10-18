<!--
  La hoja de un pedido sin mesa (maqueta Mesero y cocina, estado «Para llevar»): para llevar con el
  nombre del cliente, o domicilio con su teléfono y su dirección. La cuenta se abre hasta el primer
  «Mandar a cocina»; mientras tanto, lo anotado vive en este aparato.
-->
<script lang="ts">
  import Selector from '../../diseno/Selector.svelte';
  import type { PedidoNuevo } from '../../lib/pos';
  import Hoja from './Hoja.svelte';

  let { alCerrar, alEmpezar }: { alCerrar: () => void; alEmpezar: (pedido: PedidoNuevo) => void } = $props();

  let tipo = $state<PedidoNuevo['tipo']>('para_llevar');
  let nombre = $state('');
  let telefono = $state('');
  let direccion = $state('');

  const dom = $derived(tipo === 'domicilio');
  const listo = $derived(!!nombre.trim() && (!dom || (!!telefono.trim() && !!direccion.trim())));

  function empezar() {
    alEmpezar({
      tipo,
      nombre: nombre.trim(),
      telefono: dom ? telefono.trim() : '',
      direccion: dom ? direccion.trim() : '',
    });
  }
</script>

<Hoja titulo={dom ? 'Domicilio' : 'Para llevar'} {alCerrar}>
  <Selector
    etiqueta="Cómo se entrega"
    lleno
    alto={30}
    opciones={[
      { valor: 'para_llevar', texto: 'Para llevar' },
      { valor: 'domicilio', texto: 'Domicilio' },
    ]}
    elegida={tipo}
    alElegir={(t) => (tipo = t)}
  />
  <div class="campo">
    <label class="etq" for="hoja-nombre">Nombre del cliente</label>
    <input id="hoja-nombre" bind:value={nombre} placeholder="Ej. «Sr. Ramírez»" autocomplete="off" maxlength="80" />
  </div>
  {#if dom}
    <div class="campo">
      <label class="etq" for="hoja-tel">Teléfono</label>
      <input id="hoja-tel" bind:value={telefono} inputmode="tel" placeholder="Ej. «55 1234 5678»" autocomplete="off" maxlength="30" />
    </div>
    <div class="campo">
      <label class="etq" for="hoja-dir">Dirección</label>
      <input id="hoja-dir" bind:value={direccion} placeholder="Calle, número, colonia y referencias" autocomplete="off" maxlength="200" />
    </div>
    <p class="cel-texto chico">El envío se cobra con el producto «Envío» de tu menú.</p>
  {/if}
  <button type="button" class="cel-boton empezar" disabled={!listo} onclick={empezar}>Empezar a anotar</button>
</Hoja>

<style>
  .cel-texto.chico {
    font-size: 12.5px;
  }

  .cel-boton.empezar {
    flex: none;
  }
</style>
