<!--
  «Borrar los datos de un cliente» (datos de los clientes, 21 nov 2026; maqueta Qvn42kQsyRX3m9vscikYfB, «Ajustes ·
  Borrar un cliente»; planes/trabajo/datos-de-clientes/encuestas.md, encuesta 9). Una ventana del gerente con la cabeza al
  centro: el teléfono en su gris; al tener los 10 dígitos busca sola (buscar_datos_cliente) y dice cuántos pedidos
  encontró en esta sucursal. «Borrar sus datos», rojo lleno, se prende solo si hay; vacía el teléfono, la dirección y las
  referencias (borrar_datos_cliente) y el éxito sale en el mismo botón (~1.6 s), luego se cierra. «Cancelar» es el que se
  alarga. Los pedidos y lo que pagó se quedan en Cortes.
  Con la tarjeta de lealtad (encuesta del 23 nov 2026, planes/trabajo/tarjeta-lealtad/construir.md): al buscar también
  pregunta por su tarjeta (tarjeta_del_cliente) y, si tiene, un renglón más con su ícono dice de quién es, lo que lleva y
  que también se borra; con solo la tarjeta (sin pedidos), ese renglón solo, y el botón se prende igual.
-->
<script lang="ts">
  import { onDestroy } from 'svelte';
  import Boton from '../../../diseno/Boton.svelte';
  import CajaError from '../../../diseno/CajaError.svelte';
  import Campo from '../../../diseno/Campo.svelte';
  import GrupoCampos from '../../../diseno/GrupoCampos.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import Ventana from '../../../diseno/Ventana.svelte';
  import { borrarDatosCliente, buscarDatosCliente, tarjetaDelCliente, type TarjetaDelCliente } from '../../../lib/datosClientes';
  import { cuantos, juntado } from '../../../lib/lealtad';
  import { ALGO_SALIO_PANEL, Fallo } from '../../../lib/errores';
  import { quieto } from '../../../diseno/ventanaSeMueve';

  let {
    restauranteId,
    sucursal,
    alCerrar,
  }: {
    restauranteId: string;
    sucursal: string; // «La Fonda de Don Chuy»
    alCerrar: () => void;
  } = $props();

  const ESPERA_EXITO = 1600;

  let telefono = $state('');
  // Lo que encontró con los 10 dígitos de ahora (null: todavía no hay 10, o está buscando): cuántos pedidos y su tarjeta.
  let encontrados = $state<number | null>(null);
  let tarjeta = $state<TarjetaDelCliente | null>(null);
  const hay = $derived(!!encontrados || !!tarjeta);
  let error = $state<string | null>(null);
  let paso = $state<null | 'borrando' | 'listo'>(null);
  let temporizador: ReturnType<typeof setTimeout> | undefined;
  onDestroy(() => clearTimeout(temporizador));

  const digitos = $derived(telefono.replace(/\D/g, ''));
  // Cada búsqueda lleva su número: si llega tarde (ya cambió el teléfono), no cuenta.
  let vuelta = 0;

  $effect(() => {
    const d = digitos;
    const mia = ++vuelta;
    encontrados = null;
    tarjeta = null;
    error = null;
    if (d.length !== 10) return;
    Promise.all([buscarDatosCliente(restauranteId, d), tarjetaDelCliente(restauranteId, d)])
      .then(([n, t]) => {
        if (mia !== vuelta) return;
        tarjeta = t;
        encontrados = n;
      })
      .catch((falla) => {
        if (mia !== vuelta) return;
        error = falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL;
      });
  });

  // A medio borrar no se cierra.
  function cerrar() {
    if (!paso) alCerrar();
  }

  async function borrar() {
    if (paso || !hay) return;
    paso = 'borrando';
    error = null;
    try {
      const n = await borrarDatosCliente(restauranteId, digitos);
      // Regresa los pedidos; la tarjeta que se encontró se borra con ellos (Postgres la apunta en la bitácora).
      if (n === 0 && !tarjeta) {
        // Ya no había nada (otra pestaña o la noche se adelantaron): lo dice como al buscar.
        encontrados = 0;
        paso = null;
        return;
      }
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[ajustes] no se pudieron borrar los datos del cliente:', falla);
      error = falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL;
      paso = null;
      return;
    }
    paso = 'listo';
    temporizador = setTimeout(alCerrar, ESPERA_EXITO);
  }

  const pedidos = (n: number) => `${n} ${n === 1 ? 'pedido' : 'pedidos'}`;
  // «Rosa Ramírez, 8 de 10 sellos» (sin regla, «8 sellos»).
  const deTarjeta = (t: TarjetaDelCliente) => `${t.nombre}, ${t.meta ? `${juntado(t.forma, t.saldo, t.meta)} de ${cuantos(t.forma, t.meta)}` : cuantos(t.forma, t.saldo)}`;

  function aparece(_el: Element) {
    if (quieto()) return { duration: 0 };
    return { duration: 260, css: (x: number) => `opacity: ${x}; transform: translateY(${(1 - x) * -4}px)` };
  }
</script>

<Ventana
  centrado
  etiqueta="DATOS DE TUS CLIENTES"
  titulo="Borrar los datos de un cliente"
  nota="Escribe el teléfono con el que pidió. Se borran su teléfono y su dirección; sus pedidos y lo que pagó se quedan en tus cortes."
  ancho={600}
  alCerrar={cerrar}
>
  <div class="campos">
    <GrupoCampos>
      <Campo
        id="dc-telefono"
        etiqueta="TELÉFONO DEL CLIENTE"
        placeholder="Ej. 222 987 6543"
        modoTeclado="tel"
        autocomplete="off"
        corrector={false}
        mono
        bind:valor={telefono}
      />
    </GrupoCampos>
    {#if encontrados !== null && !error}
      {#key `${encontrados > 0}-${!!tarjeta}`}
        <div class="resultados" role="status" in:aparece>
          {#if encontrados > 0}
            <p class="resultado si">
              <Icono nombre="check" tamano={16} />
              <span>Encontramos <b>{pedidos(encontrados)}</b> con este teléfono en {sucursal}.</span>
            </p>
          {/if}
          {#if tarjeta}
            <p class="resultado de-tarjeta">
              <Icono nombre="r-lealtad" tamano={16} />
              {#if encontrados > 0}
                <span>Y su tarjeta de lealtad (<b>{deTarjeta(tarjeta)}</b>): también se borra.</span>
              {:else}
                <span>Encontramos su tarjeta de lealtad (<b>{deTarjeta(tarjeta)}</b>) en {sucursal}: se borra.</span>
              {/if}
            </p>
          {/if}
          {#if !encontrados && !tarjeta}
            <p class="resultado">
              <Icono nombre="info" tamano={16} />
              <span>No hay pedidos con este teléfono en esta sucursal, o sus datos ya se borraron.</span>
            </p>
          {/if}
        </div>
      {/key}
    {/if}
    {#if error}<CajaError mensaje={error} />{/if}
  </div>

  <div class="pie">
    <Boton tono="alarga" etiqueta="Cancelar" icono="cerrar" apagado={!!paso} onclick={cerrar} />
    <Boton
      tono="peligro-lleno"
      icono="eliminar"
      etiqueta={paso === 'borrando' ? 'Borrando…' : paso === 'listo' ? 'Datos borrados' : 'Borrar sus datos'}
      apagado={!hay && !paso}
      cargando={paso === 'borrando'}
      exito={paso === 'listo'}
      onclick={borrar}
    />
  </div>
</Ventana>

<style>
  .campos {
    display: flex;
    flex-direction: column;
    gap: 12px;
    margin-top: 22px;
  }

  .resultados {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .resultado {
    display: flex;
    align-items: flex-start;
    gap: 8px;
    margin: 0;
    padding: 0 4px;
    font: 500 13px/1.45 var(--jakarta);
    color: var(--suave);
  }

  .resultado :global(svg) {
    flex: none;
    margin-top: 1px;
    color: var(--tenue);
  }

  .resultado.si :global(svg) {
    color: var(--verde);
  }

  .resultado.de-tarjeta :global(svg) {
    color: var(--texto);
  }

  .resultado b {
    font-weight: 700;
  }

  .pie {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    margin-top: 28px;
  }
</style>
