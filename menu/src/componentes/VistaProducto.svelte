<!--
  El producto como vista completa («Tu menú en línea», maqueta v44; encuestas 41, 45 y 46). Crece desde lo que lo abrió (la
  fila, la tarjeta, el cartel, la tarjeta del asistente o el renglón de Tu pedido) y regresa ahí al cerrar; tapa la barra
  de abajo. Sus tres formas, como las eligió el restaurante:
  - Pantalla completa: la foto de orilla a orilla con «‹» de vidrio encima; al subir, la foto va más lenta y arriba sale
    una barra con su nombre. O la Ventana (la de Krispis): sube desde abajo sobre un velo y deja ver el menú arriba, con
    su cabeza, la X redonda y la foto adentro con sus márgenes.
  - El título abajo de la foto (sube a la barra al pasarlo) o arriba, en la barra, siempre.
  - Las opciones todas juntas, cada grupo en su tarjeta gris con «Obligatorio» → «✓ Listo»; o por pasos, una píldora por
    grupo con su puntito, el avance «1 de 2 listos» y el grupo del paso con sus flechas ‹ ›.
  Mientras recibe pedidos lleva la nota y, abajo fijos, el − n + y «Agregar al pedido · $25» (el precio solo va ahí); si
  falta algo, el botón dice qué y al tocarlo baja hasta ahí. Desde Tu pedido abre con lo que ya llevaba ese renglón y dice
  «Guardar cambios». Las reglas de lo que se elige son las del celular de Pepe. El CSS es el de la maqueta, en formas.css.
-->
<script lang="ts">
  import { onMount, tick, untrack } from 'svelte';
  import { SvelteSet } from 'svelte/reactivity';
  import { dinero } from '@app/lib/formato';
  import { urlImagen, type Grupo, type Producto } from '../lib/datos';
  import type { Formas } from '../lib/formas';
  import { bezier, quieto, rueda } from '../lib/movimiento';
  import { centavos, precioUnitario, type Renglon } from '../lib/pedido';
  import { monto } from '../lib/precio';
  import type { Moneda } from '../lib/preferencias';
  import { enSuLengua, textoRegla, type Lengua, type Textos } from '../lib/textos';
  import Icono from './Icono.svelte';

  let {
    producto,
    formas,
    lengua,
    moneda,
    t,
    recibe,
    inicial,
    desde,
    alAgregar,
    alCerrar,
  }: {
    producto: Producto;
    formas: Formas;
    lengua: Lengua;
    moneda: Moneda;
    t: Textos;
    recibe: boolean;
    // Desde Tu pedido: lo que ya llevaba ese renglón.
    inicial: Renglon | null;
    // Lo que lo abrió: de ahí crece y ahí regresa (si todavía se ve).
    desde: HTMLElement | null;
    alAgregar: (r: Renglon) => void;
    alCerrar: () => void;
  } = $props();

  // Las formas y el producto se leen una vez, al abrir: la vista no cambia de forma con ella abierta.
  const { ventana, arriba, grupos, pasos, foto, inicio, origen } = untrack(() => ({
    ventana: formas.producto_ventana === 'ventana',
    arriba: formas.producto_titulo === 'arriba',
    grupos: producto.grupos,
    pasos: formas.producto_opciones === 'pasos' && producto.grupos.length > 0,
    foto: producto.imagen_ruta,
    inicio: inicial,
    origen: desde,
  }));

  const nombre = $derived(enSuLengua(producto.nombre, producto.nombre_en, lengua));
  const descripcion = $derived(enSuLengua(producto.descripcion, producto.descripcion_en, lengua));
  const nombreDe = (x: { nombre: string; nombre_en: string | null }) => enSuLengua(x.nombre, x.nombre_en, lengua);

  // ─── Lo elegido ───
  // Las reglas del celular de Pepe (HojaOpciones del punto de venta): en un grupo de una, tocar otra la cambia y tocar la
  // elegida la quita solo si es opcional; en uno de varias, se prenden y apagan hasta su máximo.
  const ya = inicio?.opciones ?? [];
  let elegidas = $state<Record<number, number[]>>(
    Object.fromEntries(grupos.map((g) => [g.id, g.opciones.filter((o) => ya.includes(o.id)).map((o) => o.id)])),
  );
  let nota = $state(inicio?.nota ?? '');
  let cantidad = $state(inicio?.cantidad ?? 1);
  // Por pasos: en cuál va y cuáles ya vio (uno opcional está listo en cuanto lo ves).
  let paso = $state(0);
  const vistos = new SvelteSet<number>(grupos.length ? [grupos[0].id] : []);

  const cuantasEn = (g: Grupo) => elegidas[g.id]?.length ?? 0;
  const cumple = (g: Grupo) => cuantasEn(g) >= g.minimo;
  const listoPaso = (g: Grupo) => cumple(g) && (g.minimo > 0 || vistos.has(g.id));

  const opciones = $derived(grupos.flatMap((g) => elegidas[g.id] ?? []));
  // Solo la vista, como en el celular de Pepe: el precio que vale lo pone Postgres. El pedido va siempre en pesos: con
  // dólares, «MX$».
  const importe = $derived(centavos(precioUnitario(producto, opciones) * cantidad));
  const precio = $derived(`${moneda === 'usd' ? 'MX' : ''}${dinero(importe)}`);
  const falta = $derived(pasos ? null : (grupos.find((g) => !cumple(g)) ?? null));
  const nListos = $derived(pasos ? grupos.filter(listoPaso).length : 0);
  const faltan = $derived(pasos ? grupos.length - nListos : 0);
  const texto = $derived(
    faltan ? t.faltan(faltan) : falta ? `${t.elige} ${nombreDe(falta)}` : inicial ? t.guardarCambios : t.agregar,
  );

  let raiz = $state<HTMLElement>();
  let desliza = $state<HTMLDivElement>();
  let imagen = $state<HTMLImageElement>();
  let titulo = $state<HTMLHeadingElement>();
  let cabeza = $state<HTMLElement>();
  let seccionPasos = $state<HTMLElement>();
  let chips = $state<HTMLDivElement>();
  let marco = $state<HTMLDivElement>();
  // Sin foto, o con el título arriba, la barra (o la cabeza) siempre lleva el nombre.
  let conBarra = $state(!foto || arriba);
  // El grupo cuya etiqueta avisa que falta (tiembla y se queda en el color del menú hasta que se elige).
  let avisa = $state<number | null>(null);

  function tocar(g: Grupo, id: number) {
    const lista = elegidas[g.id] ?? [];
    if (g.maximo === 1) elegidas[g.id] = lista.includes(id) && g.minimo === 0 ? [] : [id];
    else if (lista.includes(id)) elegidas[g.id] = lista.filter((x) => x !== id);
    else if (lista.length < g.maximo) elegidas[g.id] = [...lista, id];
    if (avisa === g.id) avisa = null;
    // Por pasos, al elegir en un grupo de una sola, pasa solo al siguiente.
    const i = paso;
    if (pasos && g.maximo === 1 && elegidas[g.id].length && i < grupos.length - 1) {
      setTimeout(() => {
        if (raiz?.isConnected && paso === i) irAPaso(i + 1);
      }, quieto() ? 0 : 340);
    }
  }

  // Ir a un paso: su grupo entra del lado al que vas y su píldora se centra en la fila.
  async function irAPaso(i: number) {
    if (i < 0 || i >= grupos.length || i === paso) return;
    const dir = i > paso ? 1 : -1;
    paso = i;
    vistos.add(grupos[i].id);
    await tick();
    const c = chips?.children[i] as HTMLElement | undefined;
    if (!quieto()) {
      marco?.firstElementChild?.animate([{ opacity: 0, transform: `translateX(${dir * 28}px)` }, { opacity: 1, transform: 'none' }], {
        duration: 340,
        easing: 'cubic-bezier(0.22, 1, 0.36, 1)',
      });
    }
    if (chips && c) chips.scrollTo({ left: c.offsetLeft - (chips.clientWidth - c.offsetWidth) / 2, behavior: quieto() ? 'auto' : 'smooth' });
  }

  // Tiembla otra vez aunque ya estuviera temblando.
  function sacudir(el: Element | null | undefined) {
    if (!el) return;
    el.classList.remove('avisa');
    void (el as HTMLElement).offsetWidth;
    el.classList.add('avisa');
  }

  const arribaEn = (el: Element) => el.getBoundingClientRect().top - desliza!.getBoundingClientRect().top + desliza!.scrollTop;
  const bajarA = (y: number) => desliza?.scrollTo({ top: Math.max(0, y), behavior: quieto() ? 'auto' : 'smooth' });

  function agregar() {
    if (pasos) {
      const pendiente = grupos.findIndex((g) => !listoPaso(g));
      if (pendiente >= 0) {
        if (seccionPasos) bajarA(arribaEn(seccionPasos) - (ventana ? 76 : 110));
        if (pendiente !== paso) irAPaso(pendiente);
        else sacudir(chips?.children[pendiente]);
        return;
      }
    } else if (falta) {
      const sec = raiz?.querySelector(`[data-grupo="${falta.id}"]`);
      if (sec) bajarA(arribaEn(sec) - 110);
      if (avisa === falta.id) sacudir(sec?.querySelector('.f-prod-etiqueta'));
      avisa = falta.id;
      return;
    }
    alAgregar({ producto_id: producto.id, cantidad, opciones, nota: nota.trim() });
  }

  // ─── Al subir ───
  // Con el nombre abajo, sube a la barra (o a la cabeza) en cuanto pasa debajo de ella: a media letra en pantalla
  // completa y con su orilla de arriba en la Ventana (lo que hace la maqueta). La foto de orilla a orilla va más lenta.
  function alDeslizar() {
    const d = desliza;
    if (!d) return;
    const y = d.scrollTop;
    if (imagen && !ventana && !quieto()) imagen.style.transform = `translateY(${Math.max(0, y) * 0.35}px)`;
    if (!foto || arriba || !titulo) return;
    const barra = ventana ? cabeza : raiz?.querySelector<HTMLElement>('.f-prod-barra');
    const umbral = arribaEn(titulo) - (barra?.offsetHeight ?? 0) + (ventana ? -4 : 18);
    conBarra = y > umbral;
  }

  // ─── Cómo entra y cómo se va ───
  const ENTRA = 'cubic-bezier(0.32, 0.72, 0, 1)';
  const SALE = bezier(0.4, 0, 1, 1);
  const REGRESA = bezier(0.4, 0, 0.2, 1);

  function seVe(el: HTMLElement | null, en: HTMLElement): el is HTMLElement {
    if (!el?.isConnected) return false;
    const r = el.getBoundingClientRect();
    const b = en.getBoundingClientRect();
    return r.width > 0 && r.bottom > b.top && r.top < b.bottom;
  }

  // Lo que deja ver solo lo que tapa lo que la abrió, con sus esquinas de 16.
  function recorte(el: HTMLElement, en: HTMLElement): [number, number, number, number] {
    const r = el.getBoundingClientRect();
    const b = en.getBoundingClientRect();
    return [r.top - b.top, b.right - r.right, b.bottom - r.bottom, r.left - b.left].map((x) => Math.max(0, x)) as [number, number, number, number];
  }
  const inset = (v: number[], k: number) => `inset(${v.map((x) => (x * k).toFixed(1) + 'px').join(' ')} round ${(16 * k).toFixed(1)}px)`;

  onMount(() => {
    raiz?.focus({ preventScroll: true });
    if (quieto() || !raiz) return;
    const velo = raiz.previousElementSibling;
    if (ventana) {
      velo?.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 300, easing: 'ease-out' });
      raiz.animate([{ transform: 'translateY(100%)' }, { transform: 'none' }], { duration: 420, easing: ENTRA });
    } else if (seVe(origen, raiz)) {
      raiz.animate([{ clipPath: inset(recorte(origen, raiz), 1) }, { clipPath: 'inset(0px 0px 0px 0px round 0px)' }], { duration: 460, easing: ENTRA });
    } else {
      raiz.animate([{ transform: 'translateY(100%)' }, { transform: 'none' }], { duration: 400, easing: ENTRA });
    }
    raiz.querySelector('.f-prod-cuerpo')?.animate([{ opacity: 0, transform: 'translateY(18px)' }, { opacity: 1, transform: 'none' }], {
      duration: 420,
      delay: 140,
      easing: 'cubic-bezier(0.22, 1, 0.36, 1)',
      fill: 'backwards',
    });
    if (!ventana) {
      raiz.querySelector('.f-prod-pie')?.animate([{ transform: 'translateY(100%)' }, { transform: 'none' }], {
        duration: 420,
        delay: 180,
        easing: 'cubic-bezier(0.22, 1, 0.36, 1)',
        fill: 'backwards',
      });
    }
  });

  // Al cerrar: la Ventana baja y su velo se va; la pantalla completa regresa a lo que la abrió si todavía se ve (si no,
  // baja). Svelte corre la de salida de 1 a 0: la curva se voltea para que salga con la suya.
  function sale(nodo: HTMLElement) {
    if (quieto()) return { duration: 0 };
    if (!ventana && seVe(origen, nodo)) {
      const v = recorte(origen, nodo);
      return { duration: 300, easing: (x: number) => 1 - REGRESA(1 - x), css: (_x: number, u: number) => `clip-path: ${inset(v, u)}` };
    }
    return { duration: 260, easing: (x: number) => 1 - SALE(1 - x), css: (x: number) => `transform: translateY(${(1 - x) * 100}%)` };
  }

  function veloSale(_el: Element) {
    if (quieto()) return { duration: 0 };
    return { duration: 240, css: (x: number) => `opacity: ${x}` };
  }

  // El puntito de un paso, al quedar listo, salta con el rebote de lo que se abre.
  function punto(el: HTMLElement, estado: string) {
    let antes = estado;
    return {
      update(nuevo: string) {
        if (nuevo !== antes && nuevo === 'listo' && !quieto()) {
          el.animate([{ transform: 'scale(0.3)' }, { transform: 'scale(1)' }], { duration: 420, easing: 'cubic-bezier(0.175, 0.885, 0.32, 1.275)' });
        }
        antes = nuevo;
      },
    };
  }
</script>

<!-- Un grupo de opciones: su nombre y su regla; todas juntas, con su etiqueta «Obligatorio»; por pasos, con las flechas. -->
{#snippet grupo(g: Grupo, i: number)}
  {@const ok = cumple(g)}
  <section class="f-prod-grupo" data-grupo={g.id}>
    <div class="f-prod-gcabeza">
      <div><b>{nombreDe(g)}</b><span>{textoRegla(g.minimo, g.maximo, lengua)}</span></div>
      {#if pasos}
        <span class="f-pasos-flechas">
          <button type="button" aria-label={t.pasoAnterior} disabled={i === 0} onclick={() => irAPaso(paso - 1)}>
            <Icono nombre="anterior" tamano={20} grosor={2.2} />
          </button>
          <button type="button" aria-label={t.pasoSiguiente} disabled={i === grupos.length - 1} onclick={() => irAPaso(paso + 1)}>
            <Icono nombre="siguiente" tamano={20} grosor={2.2} />
          </button>
        </span>
      {:else if g.minimo && recibe}
        <span class="f-prod-etiqueta" class:listo={ok} class:avisa={avisa === g.id && !ok}>
          {#if ok}<Icono nombre="check" tamano={12} grosor={2.8} />{t.listo}{:else}{t.obligatorio}{/if}
        </span>
      {/if}
    </div>
    <div class="f-prod-ops">
      {#each g.opciones as o (o.id)}
        {@const extra = o.precio_extra ? `+${monto(o.precio_extra, o.precio_extra_usd, moneda)}` : t.incluido}
        {#if recibe}
          {@const si = elegidas[g.id]?.includes(o.id) ?? false}
          <button type="button" class="f-prod-op" role={g.maximo === 1 ? 'radio' : 'checkbox'} aria-checked={si} onclick={() => tocar(g, o.id)}>
            <span class="f-prod-marca" class:redonda={g.maximo === 1}>
              {#if g.maximo === 1}<i></i>{:else}<Icono nombre="check" tamano={13} grosor={2.8} />{/if}
            </span>
            <span class="n">{nombreDe(o)}</span>
            <span class="x">{extra}</span>
          </button>
        {:else}
          <div class="f-prod-op solo"><span class="n">{nombreDe(o)}</span><span class="x">{extra}</span></div>
        {/if}
      {/each}
    </div>
  </section>
{/snippet}

{#if ventana}
  <div class="f-prod-velo" aria-hidden="true" onclick={alCerrar} out:veloSale|global></div>
{/if}
<div
  class="f-prod"
  class:ventana
  class:tit-arriba={arriba}
  class:juntas={!pasos}
  class:sin-foto={!foto}
  class:sin-pie={!recibe}
  class:con-barra={conBarra}
  role="dialog"
  aria-modal="true"
  aria-label={nombre}
  tabindex="-1"
  bind:this={raiz}
  out:sale
>
  <div class="f-prod-desliza" bind:this={desliza} onscroll={alDeslizar}>
    {#if foto}
      <div class="f-prod-foto"><img src={urlImagen(foto)} alt="" bind:this={imagen} /></div>
    {/if}
    <div class="f-prod-cuerpo">
      <div class="f-prod-intro">
        {#if !arriba}<h2 bind:this={titulo}>{nombre}</h2>{/if}
        <!-- El precio va solo en el botón de abajo; sin pedidos no hay botón y se queda aquí, para que se vea. -->
        {#if !recibe}
          <div class="f-prod-precio">
            {#if producto.desde}{t.desde} {/if}{monto(producto.precio, producto.precio_usd, moneda)}{#if moneda === 'usd' && producto.precio_usd !== null}
              <small>{t.aprox}</small>{/if}
          </div>
        {/if}
        {#if descripcion}<p class="f-prod-desc">{descripcion}</p>{/if}
      </div>

      {#if pasos}
        <!-- Por pasos (como Krispis): una píldora por grupo con su puntito (ámbar mientras falta, gris si es opcional y no lo
             has visto, la palomita verde al estar listo), el avance y el grupo del paso. -->
        <section class="f-pasos" class:solo={!recibe} bind:this={seccionPasos}>
          <div class="f-pasos-chips" role="tablist" aria-label={t.pasosEt} bind:this={chips}>
            {#each grupos as g, i (g.id)}
              {@const estado = listoPaso(g) ? 'listo' : g.minimo ? 'falta' : 'opcional'}
              <button type="button" class="f-pasos-chip" role="tab" aria-selected={i === paso} onclick={() => irAPaso(i)}>
                <span class="f-pasos-punto" data-estado={estado} aria-hidden="true" use:punto={estado}>
                  {#if estado === 'listo'}<Icono nombre="check" tamano={10} grosor={3.2} />{/if}
                </span>
                <span class="t">{nombreDe(g)}</span>
              </button>
            {/each}
          </div>
          {#if recibe}
            <div class="f-pasos-avance">
              <span class="f-pasos-barra"><i style:width="{(nListos / grupos.length) * 100}%"></i></span>
              <span class="f-pasos-cuenta">{t.listos(nListos, grupos.length)}</span>
            </div>
          {/if}
          <div class="f-pasos-marco" bind:this={marco}>
            {#key paso}{@render grupo(grupos[paso], paso)}{/key}
          </div>
        </section>
      {:else}
        {#each grupos as g, i (g.id)}{@render grupo(g, i)}{/each}
      {/if}

      {#if recibe}
        <div class="f-campo">
          <label for="f-prod-nota">{t.nota}</label>
          <input id="f-prod-nota" class="f-prod-nota" bind:value={nota} maxlength="140" placeholder={t.notaEjemplo} autocomplete="off" />
        </div>
      {/if}
    </div>
  </div>

  {#if ventana}
    <div class="f-prod-cabeza" bind:this={cabeza}>
      <b>{nombre}</b>
      <button type="button" class="f-prod-cerrar" aria-label={t.cerrar} onclick={alCerrar}><Icono nombre="cerrar" tamano={18} grosor={2.2} /></button>
    </div>
  {:else}
    <div class="f-prod-barra" aria-hidden={!arriba}><b>{nombre}</b></div>
    <button type="button" class="f-prod-atras" aria-label={t.regresar} onclick={alCerrar}><Icono nombre="anterior" tamano={20} grosor={2.2} /></button>
  {/if}

  {#if recibe}
    <div class="f-prod-pie">
      <span class="f-paso" role="group" aria-label={t.cantidad}>
        <button type="button" aria-label={t.unoMenos} disabled={cantidad <= 1} onclick={() => (cantidad = Math.max(1, cantidad - 1))}>
          <Icono nombre="menos" tamano={17} grosor={2.2} />
        </button>
        <span class="n" use:rueda={cantidad}>{cantidad}</span>
        <button type="button" aria-label={t.unoMas} disabled={cantidad >= 99} onclick={() => (cantidad = Math.min(99, cantidad + 1))}>
          <Icono nombre="mas" tamano={17} grosor={2.2} />
        </button>
      </span>
      <!-- En la Ventana, el precio va a la derecha (Krispis). Por pasos, «Faltan 2 pasos» no va clarito: te lleva al que
           falta. -->
      <button type="button" class="f-prod-agregar" class:dos={ventana} aria-disabled={!!falta} onclick={agregar}>
        {#if ventana}<span>{texto}</span><span>{precio}</span>{:else}{texto} · {precio}{/if}
      </button>
    </div>
  {/if}
</div>
