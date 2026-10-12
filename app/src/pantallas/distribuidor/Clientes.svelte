<!--
  Clientes del distribuidor, portada de la maqueta aprobada el 12 de octubre de 2026
  (YXYVVNdLRXwgWCNErFSeyK): la lista de Clientes de Fragmentless solo para leer, sin la columna
  Distribuidor ni botones. Sus restaurantes (distribuidor_clientes), ordenados por fecha de fin,
  con su licencia, sus fechas y su vigencia.
-->
<script lang="ts">
  import EstadoPunto from '../../diseno/EstadoPunto.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import NotaTabla from '../../diseno/NotaTabla.svelte';
  import Tabla from '../../diseno/Tabla.svelte';
  import Vidrio from '../../diseno/Vidrio.svelte';
  import type { ClienteDistribuidor } from '../../lib/distribuidor';
  import { fecha, vigencia } from '../../lib/formato';
  import { urgente, type Lectura } from '../../lib/panel';

  let { clientes }: { clientes: Lectura<ClienteDistribuidor[]> | null } = $props();
</script>

<div class="clientes">
  <Vidrio como="section" class="tarjeta" radio={26} aria-label="Tus clientes">
    <div class="cabeza">
      <span class="etiqueta">TUS CLIENTES</span>
      <p class="descripcion">
        Los restaurantes que te asignó Fragmentless y su licencia.
        Un restaurante funciona mientras su licencia esté prendida y su fecha de fin no haya pasado.
      </p>
    </div>
    <Tabla
      columnas="24fr 10fr 10fr 10fr 14fr"
      encabezados={[
        { texto: 'RESTAURANTE' },
        { texto: 'LICENCIA' },
        { texto: 'INICIO' },
        { texto: 'FIN' },
        { texto: 'VIGENCIA' },
      ]}
    >
      {#if !clientes}
        <!-- leyendo la primera vez -->
      {:else if !clientes.ok}
        <NotaTabla titulo="No se pudo leer la lista de clientes." texto={clientes.mensaje} />
      {:else if clientes.datos.length === 0}
        <NotaTabla
          titulo="Todavía no tienes clientes."
          texto="Cuando cierres un trato, Fragmentless te asigna el restaurante."
        />
      {:else}
        {#each clientes.datos as c (c.id)}
          <div class="fila">
            <div class="restaurante">
              <span class="cuadro-icono"><Icono nombre="tienda" tamano={18} /></span>
              <div class="nombres">
                <span class="nombre">{c.nombre}</span>
                <span class="slug">{c.slug}</span>
              </div>
            </div>
            <EstadoPunto prendido={c.licencia_activa} texto={c.licencia_activa ? 'Prendida' : 'Pausada'} />
            <span class="celda">{fecha(c.licencia_inicio)}</span>
            <span class="celda">{fecha(c.licencia_fin)}</span>
            <span class="celda" class:fuerte={urgente(c)} class:tenue={c.dias_restantes === null}>
              {vigencia(c.dias_restantes)}
            </span>
          </div>
        {/each}
      {/if}
    </Tabla>
  </Vidrio>
</div>

<style>
  .clientes {
    height: 100%;
  }

  .clientes > :global(.tarjeta) {
    height: 100%;
    padding: 20px;
    display: flex;
    flex-direction: column;
    gap: 16px;
  }

  .cabeza {
    padding: 4px 4px 0;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .descripcion {
    margin: 0;
    font-size: 12.5px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .restaurante {
    min-width: 0;
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .cuadro-icono {
    width: 36px;
    height: 36px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 11px;
    background: var(--chip);
  }

  .nombres {
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

  .slug {
    font-family: var(--mono);
    font-size: 11px;
    color: var(--tenue);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
</style>
