<!--
  La «i» de la barra (maqueta de la 6a, estado «Información»): el logo y el nombre, la dirección, el
  WhatsApp con «Escribir por WhatsApp» y el horario de los 7 días, con hoy en negritas (el día del
  restaurante, nunca el del celular). Lo que Don Chuy no puso en «Tu restaurante» no sale.
-->
<script lang="ts">
  import { urlImagen, type MenuPublico } from '../lib/datos';
  import type { Textos } from '../lib/textos';
  import Hoja from './Hoja.svelte';
  import Icono from './Icono.svelte';

  let { menu, t, alCerrar }: { menu: MenuPublico; t: Textos; alCerrar: () => void } = $props();

  const r = $derived(menu.restaurante);
  const telefono = $derived(r.telefono?.replace(/(\d{3})(\d{3})(\d{4})/, '$1 $2 $3') ?? null);
  const dias = $derived(
    t.dias.map((nombre, i) => {
      const h = menu.horario.find((d) => d.dia === i + 1);
      return { nombre, hoy: i + 1 === menu.ahora.dia, horas: h ? `${h.abre} ${t.a} ${h.cierra}` : null };
    }),
  );
</script>

<Hoja etiqueta={t.info} {alCerrar}>
  <div class="cabeza">
    <div class="marca">
      {#if r.logo_ruta}<span class="logo"><img src={urlImagen(r.logo_ruta)} alt="" /></span>{/if}
      <b>{r.nombre}</b>
    </div>
    <button type="button" class="cerrar" aria-label={t.cerrar} onclick={alCerrar}><Icono nombre="cerrar" tamano={18} /></button>
  </div>
  <div class="filas">
    {#if r.direccion}
      <div class="fila">
        <Icono nombre="ubicacion" tamano={19} />
        <div class="t"><span class="k">{t.direccion}</span><span class="v">{r.direccion}</span></div>
      </div>
    {/if}
    {#if r.telefono}
      <div class="fila">
        <Icono nombre="mensaje" tamano={19} />
        <div class="t">
          <span class="k">{t.whatsapp}</span><span class="v mono">{telefono}</span>
          <a class="boton-wa" href="https://wa.me/52{r.telefono}" target="_blank" rel="noopener"><Icono nombre="afuera" tamano={15} />{t.escribir}</a>
        </div>
      </div>
    {/if}
    {#if menu.horario.length}
      <div class="fila">
        <Icono nombre="reloj" tamano={19} />
        <div class="t">
          <span class="k">{t.horario}</span>
          <div class="horario">
            {#each dias as d (d.nombre)}
              <span class:hoy={d.hoy}>{d.nombre}{d.hoy ? ` · ${t.hoy}` : ''}</span>
              <span class:hoy={d.hoy && d.horas} class:cerr={!d.horas}>{d.horas ?? t.cerrado}</span>
            {/each}
          </div>
        </div>
      </div>
    {/if}
  </div>
</Hoja>

<style>
  .cabeza {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
  }

  .marca {
    display: flex;
    align-items: center;
    gap: 12px;
    flex: 1;
    min-width: 0;
  }

  .logo {
    height: 48px;
    width: 48px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  /* Como en la barra: solo el logo, con sus esquinas suaves. */
  .logo img {
    max-width: 100%;
    max-height: 100%;
    border-radius: 14px;
  }

  .marca b {
    font-size: 17px;
    font-weight: 800;
  }

  .cerrar {
    width: 40px;
    height: 40px;
    flex: none;
    border-radius: 20px;
    border: 1px solid var(--m-linea);
    background: transparent;
    color: var(--m-texto);
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0;
  }

  .filas {
    margin-top: 8px;
  }

  .fila {
    display: flex;
    gap: 12px;
    padding: 14px 0;
    border-bottom: 1px solid var(--m-linea);
  }

  .fila:last-child {
    border-bottom: 0;
  }

  .fila > :global(svg) {
    margin-top: 1px;
    color: var(--m-suave);
  }

  .t {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .k {
    font-family: var(--mono);
    font-size: 10.5px;
    letter-spacing: 0.13em;
    text-transform: uppercase;
    color: var(--m-tenue);
  }

  .v {
    font-size: 14.5px;
    font-weight: 600;
    line-height: 1.4;
  }

  .v.mono {
    font-family: var(--mono);
    font-weight: 500;
  }

  .boton-wa {
    margin-top: 8px;
    align-self: flex-start;
    text-decoration: none;
    display: inline-flex;
    align-items: center;
    gap: 8px;
    height: 36px;
    padding: 0 14px;
    border-radius: 18px;
    border: 1px solid var(--m-linea);
    background: transparent;
    color: var(--m-texto);
    font-size: 13px;
    font-weight: 600;
  }

  .horario {
    display: grid;
    grid-template-columns: 1fr auto;
    row-gap: 7px;
    margin-top: 4px;
    font-size: 14px;
  }

  .horario span:nth-child(even) {
    text-align: right;
    font-variant-numeric: tabular-nums;
    font-family: var(--mono);
    font-size: 13px;
  }

  .horario .hoy {
    font-weight: 800;
  }

  .horario .cerr {
    color: var(--m-tenue);
  }
</style>
