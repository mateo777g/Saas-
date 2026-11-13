<!--
  La ventana de la «i» («Tu menú en línea», maqueta v55 del 12 de noviembre de 2026, encuesta 36): flota al
  centro, separada de arriba y de abajo, sobre su velo. Arriba solo el logo (sin logo, el nombre) y si está
  abierto; abajo tres pestañas como las de las categorías, Dirección · Contacto · Horario, y solo se ve la
  elegida. Lo de antes (HojaInfo) se queda: la dirección, el WhatsApp con «Escribir por WhatsApp» y el horario
  de los 7 días con hoy marcado (el día del restaurante, nunca el del celular). Lo que Don Chuy no puso en
  «Tu restaurante» no sale, ni su pestaña.
  Crece desde la «i» que la abrió (su vidrio se vuelve la ventana) y al cerrar regresa ahí; si esa «i» ya no
  se ve, sale del centro como las ventanas del panel. El CSS es el de la maqueta, en formas.css.
-->
<script lang="ts">
  import { onDestroy, onMount, tick } from 'svelte';
  import { urlImagen, type MenuPublico } from '../lib/datos';
  import { textoEstado, type Lengua, type Textos } from '../lib/textos';
  import { quieto, RESORTE_VENTANA } from '../lib/movimiento';
  import Icono from './Icono.svelte';

  let {
    menu,
    t,
    lengua,
    desde,
    alCerrar,
  }: { menu: MenuPublico; t: Textos; lengua: Lengua; desde: HTMLElement | null; alCerrar: () => void } = $props();

  type Pestana = 'direccion' | 'contacto' | 'horario';
  const ICONO: Record<Pestana, string> = { direccion: 'ubicacion', contacto: 'mensaje', horario: 'reloj' };

  const r = $derived(menu.restaurante);
  const [estadoUno, estadoDos] = $derived((textoEstado(menu.estado, lengua) ?? '').split(' · '));
  const pestanas = $derived(
    ([r.direccion ? 'direccion' : null, r.telefono ? 'contacto' : null, menu.horario.length ? 'horario' : null] as const).filter(
      (p): p is Pestana => p !== null,
    ),
  );
  const nombres = $derived({ direccion: t.direccion, contacto: t.contacto, horario: t.horario });
  // svelte-ignore state_referenced_locally
  let elegida = $state<Pestana | null>(pestanas[0] ?? null);
  const telefono = $derived(r.telefono?.replace(/(\d{3})(\d{3})(\d{4})/, '$1 $2 $3') ?? null);
  const dias = $derived(
    t.dias.map((nombre, i) => {
      const h = menu.horario.find((d) => d.dia === i + 1);
      return { nombre, hoy: i + 1 === menu.ahora.dia, horas: h ? `${h.abre} ${t.a} ${h.cierra}` : null };
    }),
  );
  const mapa = $derived(r.direccion ? `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(r.direccion)}` : null);

  // Un logo largo (más ancho que alto) va más bajito y más ancho, como en la maqueta.
  let largo = $state(false);

  let caja = $state<HTMLDivElement>();
  let fondo = $state<HTMLDivElement>();
  let dentro = $state<HTMLDivElement>();
  let cabeza = $state<HTMLDivElement>();
  let nav = $state<HTMLDivElement>();
  let cuerpo = $state<HTMLDivElement>();
  let raya = $state<HTMLElement>();
  const botones: Record<string, HTMLButtonElement> = {};

  // Solo crece desde la «i» si esa «i» se ve en la pantalla.
  function seVe(el: HTMLElement | null): el is HTMLElement {
    if (!el?.isConnected) return false;
    const b = el.getBoundingClientRect();
    return b.width > 0 && b.bottom > 0 && b.top < innerHeight;
  }
  // svelte-ignore state_referenced_locally
  const origen = seVe(desde) ? desde : null;

  // La raya de la pestaña elegida, debajo de su ícono y su nombre; al cambiar se desliza con el resorte de las listas.
  function ponerRaya(mover: boolean) {
    const b = elegida ? botones[elegida] : null;
    if (!b || !raya) return;
    if (!mover) raya.style.transition = 'none';
    raya.style.width = b.offsetWidth + 'px';
    raya.style.transform = `translateX(${b.offsetLeft}px)`;
    if (!mover) {
      void raya.offsetWidth;
      raya.style.transition = '';
    }
  }

  // Otra pestaña: lo de adentro entra del lado al que vas y la ventana cambia de alto con suavidad (se queda al centro).
  async function irA(p: Pestana) {
    if (p === elegida || !cuerpo) return;
    const dir = pestanas.indexOf(p) > pestanas.indexOf(elegida!) ? 1 : -1;
    const antes = cuerpo.offsetHeight;
    elegida = p;
    await tick();
    ponerRaya(true);
    if (quieto() || !cuerpo) return;
    const despues = cuerpo.offsetHeight;
    const curva = 'cubic-bezier(0.22, 1, 0.36, 1)';
    cuerpo.animate([{ height: antes + 'px' }, { height: despues + 'px' }], { duration: 440, easing: curva });
    cuerpo.firstElementChild?.animate([{ opacity: 0, transform: `translateX(${dir * 28}px)` }, { opacity: 1, transform: 'none' }], {
      duration: 340,
      easing: curva,
    });
  }

  // El vidrio de la «i» crece hasta la ventana: su caja va de la «i» a la ventana, con sus esquinas y su color.
  function morph(abre: boolean): Animation {
    const f = fondo!, rb = origen!.getBoundingClientRect(), rv = f.getBoundingClientRect();
    const sx = rb.width / rv.width, sy = rb.height / rv.height, dx = rb.left - rv.left, dy = rb.top - rv.top;
    const radio = rb.height / 2 > 15 ? 17 : 14;
    const fin = getComputedStyle(f).backgroundColor;
    const color = getComputedStyle(origen!).backgroundColor;
    const de = {
      transform: `translate(${dx}px, ${dy}px) scale(${sx}, ${sy})`,
      borderRadius: `${radio / sx}px / ${radio / sy}px`,
      backgroundColor: color === 'rgba(0, 0, 0, 0)' ? fin : color,
      boxShadow: '0 0 0 rgba(0, 0, 0, 0)',
    };
    const a = { transform: 'none', borderRadius: '24px', backgroundColor: fin, boxShadow: '0 20px 50px rgba(0, 0, 0, 0.25)' };
    return f.animate(
      abre ? [de, a] : [a, de],
      abre
        ? { duration: 480, easing: 'cubic-bezier(0.32, 0.72, 0, 1)' }
        : { duration: 320, easing: 'cubic-bezier(0.4, 0, 0.2, 1)', fill: 'forwards' },
    );
  }

  onMount(() => {
    ponerRaya(false);
    caja?.focus({ preventScroll: true });
    // Mientras está abierta, la «i» se vuelve la ventana: no se ve en el cartel.
    origen?.classList.add('f-ci-fuera');
    if (quieto()) return;
    if (origen) morph(true);
    else caja!.animate([{ opacity: 0, transform: 'scale(0.97)' }, { opacity: 1, transform: 'none' }], { duration: 350, easing: RESORTE_VENTANA });
    const espera = origen ? 200 : 60;
    dentro!.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 260, delay: espera, easing: 'ease-out', fill: 'backwards' });
    [cabeza, nav, cuerpo].forEach((x, i) =>
      x?.animate([{ opacity: 0, transform: 'translateY(14px)' }, { opacity: 1, transform: 'none' }], {
        duration: 460,
        delay: espera + 40 + i * 50,
        easing: 'cubic-bezier(0.22, 1, 0.36, 1)',
        fill: 'backwards',
      }),
    );
  });

  onDestroy(() => origen?.classList.remove('f-ci-fuera'));

  // Al cerrar (la X, el velo, Escape o «atrás» del celular) regresa a su «i», más rápido; si ya no se ve, se va al centro.
  function salir(_el: Element) {
    if (quieto()) return { duration: 0 };
    if (seVe(origen)) {
      dentro?.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 120, easing: 'ease-in', fill: 'forwards' });
      morph(false);
      return { duration: 320 };
    }
    caja?.animate([{ opacity: 1, transform: 'none' }, { opacity: 0, transform: 'scale(0.97)' }], { duration: 200, easing: 'ease-in', fill: 'forwards' });
    return { duration: 200 };
  }

  function velo(_el: Element, { intro }: { intro: boolean }) {
    if (quieto()) return { duration: 0 };
    return intro
      ? { duration: 300, easing: (x: number) => 1 - (1 - x) * (1 - x), css: (x: number) => `opacity: ${x}` }
      : { duration: 260, css: (x: number) => `opacity: ${x}` };
  }

  function alCargarLogo(e: Event) {
    const img = e.currentTarget as HTMLImageElement;
    largo = img.naturalWidth > img.naturalHeight * 1.4;
  }
</script>

<!-- El velo es un atajo del dedo; con el teclado se cierra con Escape (lo lleva Menu.svelte). -->
<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
<div class="f-info-velo" onclick={alCerrar} in:velo={{ intro: true }} out:velo={{ intro: false }}></div>
<div class="f-info" role="dialog" aria-modal="true" aria-label={t.info} out:salir>
  <div class="f-info-caja" tabindex="-1" bind:this={caja}>
    <div class="f-info-fondo" bind:this={fondo}></div>
    <div class="f-info-dentro" bind:this={dentro}>
      <button type="button" class="f-info-cerrar" aria-label={t.cerrar} onclick={alCerrar}><Icono nombre="cerrar" tamano={18} grosor={2.2} /></button>
      <div class="f-info-cabeza" bind:this={cabeza}>
        <!-- Solo el logo (el developer: «nada más que salga el logo»); sin logo, su nombre, para que diga de quién es. -->
        {#if r.logo_ruta}
          <span class="f-info-logo" class:largo><img src={urlImagen(r.logo_ruta)} alt={r.nombre} onload={alCargarLogo} /></span>
        {:else}
          <h2>{r.nombre}</h2>
        {/if}
        {#if estadoUno}
          <span class="f-info-estado" class:cerrado={!menu.estado?.abierto}>
            <i></i><b>{estadoUno}</b>{#if estadoDos}<span>· {estadoDos}</span>{/if}
          </span>
        {/if}
      </div>
      {#if pestanas.length}
        <div class="f-info-pestanas" role="tablist" bind:this={nav}>
          {#each pestanas as p (p)}
            <button
              type="button"
              class="f-info-pestana"
              role="tab"
              aria-selected={p === elegida}
              bind:this={botones[p]}
              onclick={() => irA(p)}
            >
              <Icono nombre={ICONO[p]} tamano={17} />{nombres[p]}
            </button>
          {/each}
          <i class="f-info-raya" aria-hidden="true" bind:this={raya}></i>
        </div>
        <div class="f-info-cuerpo" bind:this={cuerpo}>
          {#key elegida}
            {#if elegida === 'direccion'}
              <div class="f-info-panel" role="tabpanel">
                <div class="f-info-tarjeta"><span class="f-info-v">{r.direccion}</span></div>
                <a class="f-info-ir" href={mapa} target="_blank" rel="noopener"><Icono nombre="ubicacion" tamano={17} grosor={1.9} />{t.llegar}</a>
              </div>
            {:else if elegida === 'contacto'}
              <div class="f-info-panel" role="tabpanel">
                <div class="f-info-tarjeta"><span class="f-info-k">{t.whatsapp}</span><span class="f-info-v mono">{telefono}</span></div>
                <a class="f-info-ir" href="https://wa.me/52{r.telefono}" target="_blank" rel="noopener">
                  <Icono nombre="mensaje" tamano={17} grosor={1.9} />{t.escribir}
                </a>
              </div>
            {:else}
              <div class="f-info-panel" role="tabpanel">
                <div class="f-info-tarjeta horario">
                  <div class="f-info-dias">
                    {#each dias as d (d.nombre)}
                      <div class="f-info-dia" class:hoy={d.hoy} class:cerr={!d.horas}>
                        <span>{d.nombre}{d.hoy ? ` · ${t.hoy}` : ''}</span><span>{d.horas ?? t.cerrado}</span>
                      </div>
                    {/each}
                  </div>
                </div>
              </div>
            {/if}
          {/key}
        </div>
      {/if}
    </div>
  </div>
</div>

<style>
  /* Sin el aro del navegador al recibir el foco (lo recibe al abrir, para el lector de pantalla). */
  .f-info-caja:focus {
    outline: none;
  }

  /* Los botones son enlaces aquí (abren Google Maps y WhatsApp): sin su raya. */
  a.f-info-ir {
    text-decoration: none;
  }
</style>
