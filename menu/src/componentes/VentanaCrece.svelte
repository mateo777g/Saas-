<!--
  Una ventana que crece desde lo que la abrió, como la de la «i» (VentanaInfo.svelte, maqueta v55): flota al centro sobre
  su velo, su fondo va de lo que la abrió a la ventana (480 ms) y al cerrar regresa ahí, más rápido (320 ms); lo de adentro
  aparece a los 200 ms y cada pieza marcada con `data-sube` sube 14 px, una tras otra. Si lo que la abrió ya no se ve (o
  no hay, como al llegar por abremenu.com/<slug>/privacidad), sale del centro como las ventanas del panel. La usan «Tus
  datos» y el aviso de privacidad (los datos de los clientes, 21 nov 2026; maqueta Qvn42kQsyRX3m9vscikYfB). `grande`: casi
  del alto del celular, y encima de otra ventana (el aviso se abre también desde «Tus datos»). `esconder`: mientras está
  abierta, lo que la abrió no se ve (el ícono de persona se vuelve la ventana). El CSS es el de la maqueta, en formas.css.
-->
<script lang="ts">
  import { onDestroy, onMount, type Snippet } from 'svelte';
  import { quieto, RESORTE_VENTANA } from '../lib/movimiento';
  import type { Textos } from '../lib/textos';
  import Icono from './Icono.svelte';

  let {
    etiqueta,
    t,
    desde,
    grande = false,
    esconder = false,
    caja = $bindable(),
    alCerrar,
    children,
  }: {
    etiqueta: string;
    t: Textos;
    desde: HTMLElement | null;
    grande?: boolean;
    esconder?: boolean;
    caja?: HTMLDivElement;
    alCerrar: () => void;
    children: Snippet;
  } = $props();

  let fondo = $state<HTMLDivElement>();
  let dentro = $state<HTMLDivElement>();

  function seVe(el: HTMLElement | null): el is HTMLElement {
    if (!el?.isConnected) return false;
    const b = el.getBoundingClientRect();
    return b.width > 0 && b.bottom > 0 && b.top < innerHeight;
  }
  // svelte-ignore state_referenced_locally
  const origen = seVe(desde) ? desde : null;

  // El fondo va de lo que la abrió a la ventana, con sus esquinas y su color (el morph de VentanaInfo).
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
    caja?.focus({ preventScroll: true });
    if (esconder) origen?.classList.add('dc-fuera');
    if (quieto()) return;
    if (origen) morph(true);
    else caja!.animate([{ opacity: 0, transform: 'scale(0.97)' }, { opacity: 1, transform: 'none' }], { duration: 350, easing: RESORTE_VENTANA });
    const espera = origen ? 200 : 60;
    dentro!.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 260, delay: espera, easing: 'ease-out', fill: 'backwards' });
    dentro!.querySelectorAll<HTMLElement>('[data-sube]').forEach((x, i) =>
      x.animate([{ opacity: 0, transform: 'translateY(14px)' }, { opacity: 1, transform: 'none' }], {
        duration: 460,
        delay: espera + 40 + i * 50,
        easing: 'cubic-bezier(0.22, 1, 0.36, 1)',
        fill: 'backwards',
      }),
    );
  });

  onDestroy(() => origen?.classList.remove('dc-fuera'));

  // Al cerrar (la X, el velo, Escape o «atrás» del celular) regresa a lo que la abrió, más rápido.
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
</script>

<!-- El velo es un atajo del dedo; con el teclado se cierra con Escape (lo lleva Menu.svelte). -->
<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
<div class="f-info-velo" class:dc-velo-grande={grande} onclick={alCerrar} in:velo={{ intro: true }} out:velo={{ intro: false }}></div>
<div class="f-info" class:dc-grande={grande} role="dialog" aria-modal="true" aria-label={etiqueta} out:salir>
  <div class="f-info-caja" tabindex="-1" bind:this={caja}>
    <div class="f-info-fondo" bind:this={fondo}></div>
    <div class="f-info-dentro" bind:this={dentro}>
      <button type="button" class="f-info-cerrar" aria-label={t.cerrar} onclick={alCerrar}><Icono nombre="cerrar" tamano={18} grosor={2.2} /></button>
      {@render children()}
    </div>
  </div>
</div>

<style>
  .f-info-caja:focus {
    outline: none;
  }
</style>
