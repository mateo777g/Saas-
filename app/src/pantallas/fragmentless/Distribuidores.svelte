<!--
  Distribuidores (paso 2 de la libreta 8), portada de la maqueta aprobada el 10 de octubre de 2026
  (Tbt7H3G1QRXykzNKe1GXHh, v3): la lista de panel_distribuidores en el orden de Inicio (más
  clientes arriba, los de baja al final), con su estado, su contacto, si ya tiene cuenta y cuántos
  clientes tiene. Cada fila abre sus ventanas: Ligar cuenta (solo en quien no la tiene; quien ya
  la tiene deja el hueco), Sus clientes, Corregir datos y Dar de baja o Reactivar.
-->
<script lang="ts" module>
  export type AccionDistribuidor = 'ligar' | 'clientes' | 'corregir' | 'baja' | 'reactivar';
</script>

<script lang="ts">
  import BotonCuadro from '../../diseno/BotonCuadro.svelte';
  import EstadoPunto from '../../diseno/EstadoPunto.svelte';
  import NotaTabla from '../../diseno/NotaTabla.svelte';
  import Tabla from '../../diseno/Tabla.svelte';
  import Vidrio from '../../diseno/Vidrio.svelte';
  import type { Distribuidor, Lectura } from '../../lib/panel';

  let {
    distribuidores,
    alElegir,
  }: {
    distribuidores: Lectura<Distribuidor[]> | null;
    alElegir: (accion: AccionDistribuidor, distribuidor: Distribuidor) => void;
  } = $props();
</script>

<div class="distribuidores">
  <Vidrio como="section" class="tarjeta" radio={26} aria-label="Tus distribuidores">
    <div class="cabeza">
      <span class="etiqueta">TUS DISTRIBUIDORES</span>
      <p class="descripcion">
        Quienes venden Fragmentless en persona. Sus clientes se asignan y se quitan en su ventana;
        un restaurante sin distribuidor es cliente directo de Fragmentless.
      </p>
    </div>
    <Tabla
      columnas="22fr 9fr 20fr 12fr 9fr 7fr 168px"
      encabezados={[
        { texto: 'DISTRIBUIDOR' },
        { texto: 'ESTADO' },
        { texto: 'CORREO' },
        { texto: 'TELÉFONO' },
        { texto: 'CUENTA' },
        { texto: 'CLIENTES', derecha: true },
        { texto: '' },
      ]}
    >
      {#if !distribuidores}
        <!-- leyendo la primera vez -->
      {:else if !distribuidores.ok}
        <NotaTabla titulo="No se pudo leer la lista de distribuidores." texto={distribuidores.mensaje} />
      {:else if distribuidores.datos.length === 0}
        <NotaTabla titulo="Todavía no hay distribuidores." texto="Da de alta el primero con el botón de arriba." />
      {:else}
        {#each distribuidores.datos as d (d.id)}
          <div class="fila">
            <div class="persona">
              <span class="inicial">{d.nombre.charAt(0)}</span>
              <span class="nombre">{d.nombre}</span>
            </div>
            <EstadoPunto prendido={d.activo} texto={d.activo ? 'Activo' : 'De baja'} />
            <span class="celda" class:tenue={!d.correo}>{d.correo ?? '—'}</span>
            <span class="celda" class:tenue={!d.telefono}>{d.telefono ?? '—'}</span>
            <span class="celda" class:tenue={!d.cuenta_ligada}>{d.cuenta_ligada ? 'Ligada' : 'Sin ligar'}</span>
            <span class="celda numero">{d.clientes}</span>
            <div class="acciones">
              {#if d.cuenta_ligada}
                <span class="hueco"></span>
              {:else}
                <BotonCuadro
                  icono="usuario-mas"
                  ayuda="Ligar cuenta"
                  etiqueta="Ligar la cuenta de {d.nombre}"
                  onclick={() => alElegir('ligar', d)}
                />
              {/if}
              <BotonCuadro
                icono="tienda"
                ayuda="Sus clientes"
                etiqueta="Clientes de {d.nombre}"
                onclick={() => alElegir('clientes', d)}
              />
              <BotonCuadro
                icono="crear"
                ayuda="Corregir datos"
                etiqueta="Corregir los datos de {d.nombre}"
                onclick={() => alElegir('corregir', d)}
              />
              {#if d.activo}
                <BotonCuadro
                  icono="usuario-menos"
                  ayuda="Dar de baja"
                  etiqueta="Dar de baja a {d.nombre}"
                  onclick={() => alElegir('baja', d)}
                />
              {:else}
                <BotonCuadro
                  icono="usuario-check"
                  ayuda="Reactivar"
                  etiqueta="Reactivar a {d.nombre}"
                  onclick={() => alElegir('reactivar', d)}
                />
              {/if}
            </div>
          </div>
        {/each}
      {/if}
    </Tabla>
  </Vidrio>
</div>

<style>
  .distribuidores {
    height: 100%;
  }

  .distribuidores > :global(.tarjeta) {
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

  .persona {
    min-width: 0;
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .inicial {
    width: 34px;
    height: 34px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 17px;
    background: var(--chip);
    border: 1px solid var(--linea);
    font-size: 13px;
    font-weight: 700;
  }

  .nombre {
    font-size: 13.5px;
    font-weight: 700;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .acciones {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
  }

  .hueco {
    width: 36px;
    height: 36px;
    flex: none;
  }
</style>
