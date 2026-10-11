<!--
  «Dar de alta» (botón de arriba): llama a alta_restaurante(nombre, slug, inicio, meses). El
  restaurante nace con la licencia prendida y Postgres calcula su fin. La fecha de inicio viene
  puesta con el día de hoy que da panel_hoy(), en hora de México (decidido el 11 de octubre de
  2026): la app no la saca del reloj del aparato.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import Campo from '../../diseno/Campo.svelte';
  import Formulario from '../../diseno/Formulario.svelte';
  import Ventana from '../../diseno/Ventana.svelte';
  import { entero } from '../../lib/formato';
  import { altaRestaurante, leerHoy } from '../../lib/panel';

  let { alCerrar, alGuardar }: { alCerrar: () => void; alGuardar: () => void } = $props();

  let nombre = $state('');
  let slug = $state('');
  let inicio = $state('');
  let meses = $state('1');

  onMount(async () => {
    const hoy = await leerHoy();
    // Si ya eligió una fecha mientras llegaba, se queda la suya.
    if (hoy && !inicio) inicio = hoy;
  });

  async function guardar() {
    const r = await altaRestaurante(nombre.trim(), slug.trim(), inicio || null, entero(meses));
    if (!r.ok) return { error: r.mensaje };
    alGuardar();
    return { listo: 'Restaurante dado de alta' };
  }
</script>

<Ventana etiqueta="NUEVO CLIENTE" titulo="Dar de alta un restaurante" {alCerrar}>
  <Formulario boton={{ etiqueta: 'Dar de alta', icono: 'mas' }} {guardar} alTerminar={alCerrar}>
    <Campo id="alta-nombre" etiqueta="NOMBRE" bind:valor={nombre} placeholder="Ej. La fonda de Don Chuy" />
    <Campo
      id="alta-slug"
      etiqueta="SLUG"
      bind:valor={slug}
      placeholder="Ej. fonda-don-chuy"
      corrector={false}
      pista="La dirección de su menú en línea. Solo minúsculas, números y guiones."
    />
    <div class="par">
      <Campo id="alta-inicio" etiqueta="INICIO" tipo="date" bind:valor={inicio} />
      <Campo id="alta-meses" etiqueta="MESES" tipo="number" bind:valor={meses} min={1} step={1} />
    </div>
    <p class="pista">
      Nace con la licencia prendida y termina el mismo día, tantos meses después: 8 oct con 1 mes
      termina el 8 nov.
    </p>
  </Formulario>
</Ventana>
