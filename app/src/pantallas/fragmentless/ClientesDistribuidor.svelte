<!--
  «Sus clientes» (fila de Distribuidores): los restaurantes asignados a Juanito, con su vigencia,
  y abajo la lista para asignarle otro. Es el único lugar donde se asignan y se quitan clientes
  (decidido el 10 de octubre de 2026). Asignar y Quitar llaman a asignar_distribuidor(restaurante,
  distribuidor); Quitar lo llama con el distribuidor vacío y el restaurante pasa a directo.

  Como en la maqueta: Asignar y Quitar no cierran la ventana; después de su palomita (1.6 s) el
  panel se vuelve a leer y la ventana sigue con lo nuevo. En la lista salen primero los directos
  y luego los de otro distribuidor; si eliges uno de otro, un aviso dice a quién se le quita, y
  pasa en un solo paso. A quien está de baja no se le asigna nada: sale su aviso, sin la lista ni
  el botón.
-->
<script lang="ts">
  import { onDestroy } from 'svelte';
  import Aviso from '../../diseno/Aviso.svelte';
  import Boton from '../../diseno/Boton.svelte';
  import CajaError from '../../diseno/CajaError.svelte';
  import CampoLista from '../../diseno/CampoLista.svelte';
  import Formulario from '../../diseno/Formulario.svelte';
  import Ventana from '../../diseno/Ventana.svelte';
  import { fecha, vigencia } from '../../lib/formato';
  import { asignarDistribuidor, urgente, type Cliente, type DatosPanel, type Distribuidor } from '../../lib/panel';

  const ESPERA_EXITO = 1600;

  let {
    distribuidor,
    datos,
    alCerrar,
    alCambiar,
  }: {
    distribuidor: Distribuidor;
    datos: DatosPanel | null;
    alCerrar: () => void;
    alCambiar: () => Promise<void>;
  } = $props();

  // Lo de la última lectura del panel; si esa lectura falló, lo que tenía al abrir.
  const actual = $derived(
    (datos?.distribuidores.ok && datos.distribuidores.datos.find((d) => d.id === distribuidor.id)) || distribuidor,
  );
  const clientes = $derived(datos?.clientes.ok ? datos.clientes.datos : null);
  const suyos = $derived(clientes?.filter((c) => c.distribuidor_id === actual.id) ?? []);
  const directos = $derived(clientes?.filter((c) => c.distribuidor_id === null) ?? []);
  const deOtro = $derived(
    clientes?.filter((c) => c.distribuidor_id !== null && c.distribuidor_id !== actual.id) ?? [],
  );

  let elegido = $state('');
  let error = $state<string | null>(null);
  // Cada asignación vuelve a montar el formulario, para que su botón regrese a «Asignar».
  let ronda = $state(0);
  // Las filas que se están quitando: «Quitando…» y luego «Quitado».
  let quitando = $state<Record<string, 'quitando' | 'quitado'>>({});
  const temporizadores: ReturnType<typeof setTimeout>[] = [];

  const deQuien = $derived(deOtro.find((c) => c.id === elegido)?.distribuidor_nombre ?? null);

  async function asignar() {
    if (!elegido) return { error: 'Elige un cliente de la lista.' };
    const r = await asignarDistribuidor(elegido, actual.id);
    if (!r.ok) return { error: r.mensaje };
    return { listo: 'Asignado' };
  }

  function siguiente() {
    elegido = '';
    ronda += 1;
    alCambiar();
  }

  async function quitar(c: Cliente) {
    if (quitando[c.id]) return;
    error = null;
    quitando[c.id] = 'quitando';
    const r = await asignarDistribuidor(c.id, null);
    if (!r.ok) {
      delete quitando[c.id];
      error = r.mensaje;
      return;
    }
    quitando[c.id] = 'quitado';
    temporizadores.push(
      setTimeout(async () => {
        await alCambiar();
        delete quitando[c.id];
      }, ESPERA_EXITO),
    );
  }

  onDestroy(() => temporizadores.forEach(clearTimeout));
</script>

{#snippet lista()}
  <div class="campo">
    <span class="etiqueta">SUS CLIENTES · {actual.clientes}</span>
    <div class="lista">
      {#if !clientes}
        <div class="vacia">No se pudo cargar.</div>
      {:else if suyos.length === 0}
        <div class="vacia">Todavía no tiene clientes.</div>
      {:else}
        {#each suyos as c (c.id)}
          <div class="item">
            <div class="item-texto">
              <span class="nombre">{c.nombre}</span>
              <span class="linea">
                {#if urgente(c)}<b>{vigencia(c.dias_restantes)}</b>{:else}{vigencia(c.dias_restantes)}{/if}
                · {fecha(c.licencia_fin)}
              </span>
            </div>
            <Boton
              tamano="chico"
              etiqueta={quitando[c.id] === 'quitando' ? 'Quitando…' : quitando[c.id] === 'quitado' ? 'Quitado' : 'Quitar'}
              cargando={quitando[c.id] === 'quitando'}
              exito={quitando[c.id] === 'quitado'}
              onclick={() => quitar(c)}
            />
          </div>
        {/each}
      {/if}
    </div>
  </div>
{/snippet}

<Ventana etiqueta="DISTRIBUIDOR" titulo={distribuidor.nombre} {alCerrar}>
  {#if actual.activo}
    {#key ronda}
      <Formulario boton={{ etiqueta: 'Asignar', icono: 'mas' }} guardar={asignar} alTerminar={siguiente} bind:error>
        {@render lista()}
        <CampoLista
          id="asignar-cliente"
          etiqueta="ASIGNAR UN CLIENTE"
          bind:valor={elegido}
          placeholder="Elige un cliente"
          grupos={[
            { etiqueta: 'Directos', opciones: directos.map((c) => ({ valor: c.id, texto: c.nombre })) },
            {
              etiqueta: 'De otro distribuidor',
              opciones: deOtro.map((c) => ({ valor: c.id, texto: `${c.nombre} · ${c.distribuidor_nombre}` })),
            },
          ]}
          pista="Primero salen los directos, que no tienen distribuidor."
        />
        {#if deQuien}
          <Aviso>
            Hoy es cliente de {deQuien}. Al asignarlo pasa a {actual.nombre}; lo que ya pagó le sigue
            contando a {deQuien}.
          </Aviso>
        {/if}
      </Formulario>
    {/key}
  {:else}
    <div class="campos">
      <Aviso>{actual.nombre} está de baja. Para asignarle clientes, primero usa Reactivar.</Aviso>
      {@render lista()}
    </div>
    {#if error}
      <div class="error"><CajaError mensaje={error} /></div>
    {/if}
  {/if}
</Ventana>

<style>
  /* Lo mismo que Formulario pone entre campos, para quien está de baja (sin formulario). */
  .campos {
    margin-top: 22px;
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  .error {
    margin-top: 14px;
  }

  .campo {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  /* Las filas de Vencen pronto, en una lista que se desplaza si son muchas. */
  .lista {
    max-height: 252px;
    overflow: auto;
  }

  .item {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 11px 0;
    border-bottom: 1px solid var(--linea);
  }

  .item:first-child {
    border-top: 1px solid var(--linea);
  }

  .item-texto {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .nombre {
    font-size: 13.5px;
    font-weight: 700;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .linea {
    font-size: 12px;
    font-weight: 500;
    color: var(--suave);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .linea b {
    font-weight: 600;
    color: var(--texto);
  }

  .vacia {
    padding: 24px 0;
    font-size: 12.5px;
    font-weight: 500;
    color: var(--suave);
  }
</style>
