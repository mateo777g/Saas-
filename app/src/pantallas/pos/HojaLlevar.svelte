<!--
  La hoja de un pedido sin mesa (maqueta Mesero y cocina, estado «Para llevar»; adaptabilidad, «Lo que
  decidí yo» 1 y encuesta 3): comer aquí, para llevar o domicilio, y el nombre del cliente, que es
  opcional: sin nombre, la cuenta sale con su número del día («#23»). A domicilio pide teléfono y
  dirección. La hoja recuerda en este aparato el último tipo que se usó. La cuenta se abre hasta el
  primer envío; mientras tanto, lo anotado vive en este aparato.
-->
<script lang="ts">
  import Selector from '../../diseno/Selector.svelte';
  import { guardarTipoPedido, leerTipoPedido, type PedidoNuevo } from '../../lib/pos';
  import Hoja from './Hoja.svelte';

  let { alCerrar, alEmpezar }: { alCerrar: () => void; alEmpezar: (pedido: PedidoNuevo) => void } = $props();

  let tipo = $state<PedidoNuevo['tipo']>(leerTipoPedido());
  let nombre = $state('');
  let telefono = $state('');
  let direccion = $state('');

  const dom = $derived(tipo === 'domicilio');
  const listo = $derived(!dom || (!!telefono.trim() && !!direccion.trim()));

  function empezar() {
    guardarTipoPedido(tipo);
    alEmpezar({
      tipo,
      nombre: nombre.trim(),
      telefono: dom ? telefono.trim() : '',
      direccion: dom ? direccion.trim() : '',
    });
  }
</script>

<Hoja titulo="Pedido nuevo" {alCerrar}>
  <Selector
    etiqueta="Cómo se entrega"
    lleno
    alto={30}
    opciones={[
      { valor: 'comer_aqui', texto: 'Comer aquí' },
      { valor: 'para_llevar', texto: 'Para llevar' },
      { valor: 'domicilio', texto: 'Domicilio' },
    ]}
    elegida={tipo}
    alElegir={(t) => (tipo = t)}
  />
  <div class="campo">
    <label class="etq" for="hoja-nombre">Nombre del cliente · opcional</label>
    <input id="hoja-nombre" bind:value={nombre} placeholder="Ej. Rosa" autocomplete="off" maxlength="80" />
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
  {:else}
    <p class="cel-texto chico">Sin nombre, sale con su número del día.</p>
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
