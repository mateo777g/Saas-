<!--
  El aviso de privacidad (los datos de los clientes, 21 nov 2026; maqueta Qvn42kQsyRX3m9vscikYfB, «Menú · Aviso»; encuesta
  del 20 nov 2026: «Ventana grande»). Casi del alto del celular, crece desde la liga que lo abrió (el aviso corto de Tu
  pedido o «Aviso de privacidad» de «Tus datos»); su cabeza se queda fija y el texto se desliza abajo, en el idioma del
  menú. Al cerrarlo sigues con tu pedido. abremenu.com/<slug>/privacidad abre el menú con este aviso ya abierto. El texto
  es el borrador aprobado (lib/aviso.ts), con los datos de Tu restaurante; lo revisa un abogado antes del primer cliente.
-->
<script lang="ts">
  import { avisoCompleto, pedazos, type DatosDelAviso, type Pedazo } from '../lib/aviso';
  import type { Lengua, Textos } from '../lib/textos';
  import VentanaCrece from './VentanaCrece.svelte';

  let {
    datos,
    lengua,
    t,
    desde,
    conTarjeta = false,
    alCerrar,
  }: {
    datos: DatosDelAviso;
    lengua: Lengua;
    t: Textos;
    desde: HTMLElement | null;
    // La sucursal tiene su tarjeta de lealtad (prendida o apagada): el aviso suma su parte.
    conTarjeta?: boolean;
    alCerrar: () => void;
  } = $props();

  const bloques = $derived(
    avisoCompleto(lengua, conTarjeta).map((b): { p: Pedazo[] } | { lista: Pedazo[][] } =>
      'p' in b ? { p: pedazos(b.p, datos, lengua) } : { lista: b.lista.map((x) => pedazos(x, datos, lengua)) },
    ),
  );
  // «Última actualización: …» va en chico y en gris, como en la maqueta.
  const esFecha = (p: Pedazo[]) => /^(Última actualización|Last updated)/.test(p[0]?.texto ?? '');
</script>

{#snippet texto(p: Pedazo[])}
  {#each p as x, i (i)}{#if x.como === 'negritas'}<b>{x.texto}</b>{:else if x.como === 'falta'}<span class="dc-falta">{x.texto}</span>{:else}{x.texto}{/if}{/each}
{/snippet}

<VentanaCrece etiqueta={t.avisoPrivacidad} {t} {desde} grande {alCerrar}>
  <div class="dc-aviso-cabeza" data-sube>
    <h2>{t.avisoPrivacidad}</h2>
    <p>{datos.nombre}</p>
  </div>
  <div class="dc-aviso-texto" data-sube>
    {#each bloques as b, i (i)}
      {#if 'p' in b}
        <p>{#if esFecha(b.p)}<span class="dc-fecha">{@render texto(b.p)}</span>{:else}{@render texto(b.p)}{/if}</p>
      {:else}
        <ul>
          {#each b.lista as x, j (j)}<li>{@render texto(x)}</li>{/each}
        </ul>
      {/if}
    {/each}
  </div>
</VentanaCrece>
