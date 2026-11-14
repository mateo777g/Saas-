<!--
  El asistente como vista completa («Tu menú en línea», maqueta v31 del 11 de noviembre de 2026, encuestas 34 a
  40). Se llega por la barra de abajo, que se queda a la vista como pestañas. Arriba la barra de tu menú; al centro
  la frase con la raya y las chispas del Agente IA, del color de tu menú, y las 3 ideas, que salen en fila al
  entrar; abajo la caja en píldora, que al picarla se abre con el rebote del Agente IA (las ideas se van) y, con el
  teclado del celular, queda justo encima de él (13 nov 2026). La plática es la del Agente IA: la burbuja del
  cliente del color de tu menú, «Pensando…» con los puntitos chicos y sus pasos, y la respuesta que sale renglón
  por renglón con los puntitos bajando, que luego se dobla en «Pensé 3 s ›».
  Lo que hacía la hoja de la 6c se queda (lib/asistente.svelte.ts, el Worker, la revisión de Cloudflare en su
  hueco, los avisos sin IA y de los límites, las tarjetas de los productos que nombró, que abren su producto). El
  CSS es el de la maqueta, en formas.css.
-->
<script lang="ts">
  import { onMount, tick, type Snippet } from 'svelte';
  import { SvelteSet } from 'svelte/reactivity';
  import { contraste, FONDO_MENU } from '@app/lib/color';
  import type { ClavePaso, Mensaje, Motivo, PasoMenu, Platica } from '../lib/asistente.svelte';
  import { urlImagen, type MenuPublico, type Producto } from '../lib/datos';
  import type { Formas } from '../lib/formas';
  import { quieto } from '../lib/movimiento';
  import type { Moneda } from '../lib/preferencias';
  import { enSuLengua, type Lengua, type Textos } from '../lib/textos';
  import { quitarRevision } from '../lib/turnstile';
  import Icono from './Icono.svelte';
  import Precio from './Precio.svelte';

  let {
    platica,
    menu,
    productos,
    lengua,
    moneda,
    tema,
    color,
    fondo,
    formas,
    t,
    barra,
    alPreguntar,
    alAbrirProducto,
  }: {
    platica: Platica;
    menu: MenuPublico;
    productos: Map<number, Producto>;
    lengua: Lengua;
    moneda: Moneda;
    tema: 'claro' | 'oscuro';
    color: string | null;
    fondo: string | null;
    formas: Formas;
    t: Textos;
    barra: Snippet;
    alPreguntar: (pregunta: string, hueco: HTMLElement) => void;
    alAbrirProducto: (p: Producto, desde: HTMLElement) => void;
  } = $props();

  const ICONO_PASO: Record<ClavePaso, string> = { buscar: 'lupa', recomendar: 'ia', escribir: 'crear' };
  const ICONO_IDEA = ['estrella', 'reloj', 'moto'];
  // Las 7 chispas que suelta la punta de la raya (las mismas del Agente IA).
  const CHISPAS = [[0, -5, -8], [0.08, -11, -4], [0.16, -3, -11], [0.24, -13, 3], [0.32, -7, -6], [0.4, -4, 5], [0.48, -15, -9]];
  const LETRA = { claro: '#121212', oscuro: '#F3F3F0' };

  let cuerpo = $state<HTMLDivElement>();
  let caja = $state<HTMLDivElement>();
  let campo = $state<HTMLTextAreaElement>();
  let hueco = $state<HTMLDivElement>();
  // La caja en píldora (cerrada) o abierta; con algo escrito (la pregunta que no se contestó) llega abierta.
  // svelte-ignore state_referenced_locally
  let abierta = $state(!!platica.borrador.trim());
  let escribiendo = $state(false);
  const pensesAbiertos = new SvelteSet<number>();

  const nombre = $derived(menu.restaurante.nombre);
  const telefono = $derived(menu.restaurante.telefono);
  const contesta = $derived(menu.asistente_contesta);
  const ocupado = $derived(platica.pendiente !== null);
  const hayPlatica = $derived(platica.mensajes.length > 0 || platica.pendiente !== null);
  const ultimo = $derived(platica.mensajes.at(-1));
  const avisoAlFinal = $derived(!contesta && platica.mensajes.length > 0 && !(ultimo?.rol === 'aviso' && ultimo.motivo === 'sin_ia'));

  // El color del asistente (los puntitos, el ícono del paso, el cursor y la raya de la frase): el de tu menú; si casi
  // no se ve sobre tu fondo, se acerca a la letra lo justo, como el azul claro del Agente IA en oscuro.
  function mezclar(a: string, b: string, k: number): string {
    const x = parseInt(a.slice(1), 16), y = parseInt(b.slice(1), 16);
    return '#' + [16, 8, 0].map((s) => Math.round(((x >> s) & 255) * (1 - k) + ((y >> s) & 255) * k).toString(16).padStart(2, '0')).join('');
  }
  const estiloAsis = $derived.by(() => {
    if (!color) return '';
    const atras = fondo ?? FONDO_MENU[tema];
    let c = color;
    for (let k = 1; k <= 10 && contraste(c, atras) < 3; k++) c = mezclar(color, LETRA[tema], k / 10);
    return `--m-asis:${c};`;
  });

  function textoAviso(motivo: Motivo): string {
    if (motivo === 'sin_ia') return t.sinIa + (telefono ? t.sinIaWa : '');
    return (motivo === 'limite_celular' ? t.limiteCelular : t.limiteConexion) + (telefono ? t.limiteWa : t.limiteTarde);
  }
  const parrafos = (texto: string) => texto.split(/\n+/).filter((p) => p.trim());
  const tarjetas = (m: Mensaje) =>
    m.rol === 'asistente' ? m.productos.map((id) => productos.get(id)).filter((p): p is Producto => !!p) : [];

  // ─── La caja: píldora de 48 que al picarla se hace rectángulo (116, y crece con el texto) ───
  function medir() {
    if (!campo || !caja) return;
    campo.style.height = 'auto';
    const alto = Math.min(Math.max(campo.scrollHeight, 68), 140);
    campo.style.height = alto + 'px';
    caja.style.height = alto + 48 + 'px';
  }

  async function abrirCaja() {
    if (!contesta || abierta) return;
    abierta = true;
    await tick();
    medir();
    campo?.focus({ preventScroll: true });
  }

  function cerrarCaja() {
    abierta = false;
    escribiendo = false;
    if (caja) caja.style.height = '';
    if (campo) campo.style.height = '';
  }

  function preguntar(pregunta: string) {
    if (!pregunta || ocupado || !contesta || !hueco) return;
    platica.borrador = '';
    cerrarCaja();
    campo?.blur();
    alPreguntar(pregunta, hueco);
  }

  function alTeclear(e: KeyboardEvent) {
    if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
      e.preventDefault();
      preguntar(platica.borrador.trim());
    } else if (e.key === 'Escape') {
      // Escape aquí no cierra la vista: vacía, la caja vuelve a píldora.
      e.stopPropagation();
      if (!platica.borrador.trim()) {
        cerrarCaja();
        campo?.blur();
      }
    }
  }

  function alEscribir() {
    escribiendo = true;
    medir();
  }

  // Al salir de la caja vacía (no hacia sus ideas), vuelve a píldora.
  function alSalir(e: FocusEvent) {
    if (!abierta) return;
    const a = e.relatedTarget as HTMLElement | null;
    queueMicrotask(() => {
      if (!abierta || document.activeElement === campo || a?.closest('.f-asis-caja, .f-asis-ideas')) return;
      if (!platica.borrador.trim()) cerrarCaja();
    });
  }

  // Las ideas y mandar no le quitan el foco a la caja.
  const sinQuitarFoco = (e: MouseEvent) => e.preventDefault();

  // ─── El teclado del celular (el developer, 13 nov 2026, en su prueba): tapaba la caja, porque lo fijo a la pantalla
  // se queda detrás de él (y la caja se enfoca sin mover la página). Con el teclado abierto, la vista toma lo que queda
  // visible de la pantalla (visualViewport) y la caja queda justo encima de él; la barra de abajo se queda detrás. ───
  let visible = $state<{ arriba: number; alto: number } | null>(null);
  function medirTeclado() {
    const vv = window.visualViewport;
    if (!vv) return;
    const tapado = document.documentElement.clientHeight - vv.height;
    const antes = visible;
    // Más de 120 px tapados con la caja enfocada es el teclado; acercar la página con los dedos no cuenta.
    visible = tapado > 120 && vv.scale < 1.05 && document.activeElement === campo ? { arriba: vv.offsetTop, alto: vv.height } : null;
    if (visible && !antes) tick().then(() => alFondo(false));
  }
  const conTeclado = $derived(visible ? `top:${visible.arriba}px;height:${visible.alto}px;bottom:auto;padding-bottom:0;` : '');

  // ─── La plática ───
  function alFondo(suave: boolean) {
    if (cuerpo && hayPlatica) cuerpo.scrollTo({ top: cuerpo.scrollHeight, behavior: suave && !quieto() ? 'smooth' : 'auto' });
  }

  // Cada vez que llega algo, baja hasta lo último.
  $effect(() => {
    void platica.mensajes.length;
    void platica.pendiente;
    void platica.pasos.length;
    void platica.noContesto;
    tick().then(() => alFondo(true));
  });

  // La pregunta que no se contestó vuelve a la caja: se abre con ella.
  $effect(() => {
    if (platica.noContesto && platica.borrador.trim() && !abierta) {
      abierta = true;
      tick().then(medir);
    }
  });

  // La respuesta nueva sale renglón por renglón con el cursor, y los puntitos bajan debajo del último renglón; al
  // terminar se van. Los puntitos los pone y los quita esta acción (no Svelte), igual que el cursor.
  function revelar(r: HTMLElement) {
    if (quieto()) return;
    const piezas = [...r.querySelectorAll<HTMLElement>(':scope > .f-asis-md > p'), ...r.querySelectorAll<HTMLElement>(':scope > .f-asis-tarjetas')];
    const bajan = document.createElement('span');
    bajan.className = 'f-asis-bajan';
    bajan.innerHTML = '<span class="f-puntos" aria-hidden="true"><span class="f-giro"><i></i><i></i><i></i></span></span>';
    r.prepend(bajan);
    const cursor = document.createElement('span');
    cursor.className = 'f-asis-cursor';
    const relojes: ReturnType<typeof setTimeout>[] = [];
    piezas.forEach((p, n) => {
      p.style.animationDelay = `${n * 110}ms`;
      p.classList.add('f-asis-sale');
      relojes.push(
        setTimeout(() => {
          if (p.tagName === 'P') p.append(cursor);
          void bajan.offsetWidth;
          bajan.style.top = `${p.offsetTop + p.offsetHeight + 8}px`;
          alFondo(true);
        }, n * 110),
      );
    });
    const fin = piezas.length * 110 + 260;
    relojes.push(setTimeout(() => (cursor.remove(), bajan.classList.add('se-van')), fin));
    relojes.push(setTimeout(() => bajan.remove(), fin + 150));
    return {
      destroy() {
        relojes.forEach(clearTimeout);
        cursor.remove();
        bajan.remove();
      },
    };
  }

  function aparece(_el: Element) {
    if (quieto()) return { duration: 0 };
    return { duration: 180, css: (x: number) => `opacity: ${x}` };
  }
  function seVa(_el: Element) {
    if (quieto()) return { duration: 0 };
    return { duration: 150, css: (x: number) => `opacity: ${x}` };
  }

  onMount(() => {
    alFondo(false);
    if (abierta) medir();
    const vv = window.visualViewport;
    vv?.addEventListener('resize', medirTeclado);
    vv?.addEventListener('scroll', medirTeclado);
    return () => {
      vv?.removeEventListener('resize', medirTeclado);
      vv?.removeEventListener('scroll', medirTeclado);
      quitarRevision();
      // Al volver, ya es una respuesta guardada: sale quieta.
      platica.nuevo = null;
    };
  });
</script>

{#snippet pasosLista(lista: PasoMenu[], entran: boolean)}
  <ol class="f-asis-pasos">
    {#each lista as p (p.clave)}
      <li class:en-curso={!p.hecho} class:entra={entran}>
        <span class="f-asis-paso">
          {#if p.hecho}<Icono nombre="check" tamano={12} grosor={2} />{:else}<Icono nombre={ICONO_PASO[p.clave]} tamano={15} />{/if}
        </span>
        <span>{p.hecho ? t.pasos[p.clave].listo : t.pasos[p.clave].corre}</span>
      </li>
    {/each}
  </ol>
{/snippet}

{#snippet botonWa()}
  <a class="f-asis-wa" href="https://wa.me/52{telefono}" target="_blank" rel="noopener"><Icono nombre="mensaje" tamano={15} />{t.escribir}</a>
{/snippet}

{#snippet aviso(motivo: Motivo, entra: boolean)}
  <div class="f-asis-resp" class:f-asis-sale={entra}>
    <div class="f-asis-md"><p>{textoAviso(motivo)}</p></div>
    {#if telefono}{@render botonWa()}{/if}
  </div>
{/snippet}

<!-- Los puntitos se juntan como gotas (su «goo»), como los del Agente IA. -->
<svg width="0" height="0" style="position: absolute" aria-hidden="true" focusable="false">
  <filter id="f-goo">
    <feGaussianBlur in="SourceGraphic" stdDeviation="1.6" result="blur"></feGaussianBlur>
    <feColorMatrix in="blur" mode="matrix" values="1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 18 -7"></feColorMatrix>
  </filter>
</svg>

<section
  class="f-asis"
  class:f-asis-pildora={formas.abajo === 'pildora'}
  class:f-asis-chica={!formas.abajo_con_nombres}
  class:con-teclado={!!visible}
  aria-label={t.asistente(nombre)}
  style={estiloAsis + conTeclado}
  in:aparece
  out:seVa
  onfocusout={alSalir}
>
  {@render barra()}

  <div class="f-asis-cuerpo" bind:this={cuerpo}>
    {#if !hayPlatica && !contesta}
      <!-- Sin IA: el aviso en lugar de la frase, con su WhatsApp; la caja apagada. -->
      <div class="f-asis-bienvenida f-asis-sin">
        <p>{t.sinIa + (telefono ? t.sinIaWa : '')}</p>
        {#if telefono}{@render botonWa()}{/if}
      </div>
    {:else if !hayPlatica}
      <!-- La frase al centro de lo que queda arriba de las ideas, que se ven al entrar y se van al abrir la caja. -->
      <div class="f-asis-bienvenida" class:abierta>
        <h2 class="f-asis-frase">
          {t.frase[0]}<span class="f-asis-sub"
            >{t.frase[1]}<span class="f-chispas" aria-hidden="true"
              ><span class="f-chispas-van">
                {#each CHISPAS as [d, x, y] (d)}<i style="--d:{d}s;--x:{x}px;--y:{y}px"></i>{/each}
              </span></span
            ></span
          >
        </h2>
        <div class="f-asis-ideas">
          <div class="f-asis-ideas-titulo f-asis-aparece" style="--i:3">{t.ideas}</div>
          {#each t.sugeridas as s, i (i)}
            <button
              type="button"
              class="f-asis-idea f-asis-aparece"
              style="--i:{2 - i}"
              tabindex={abierta ? -1 : 0}
              onmousedown={sinQuitarFoco}
              onclick={() => preguntar(s)}
            >
              <span class="f-asis-idea-icono"><Icono nombre={ICONO_IDEA[i]} tamano={17} /></span>
              <span class="f-asis-idea-texto">{s}</span>
              <Icono nombre="r-derecha" tamano={14} />
            </button>
          {/each}
        </div>
      </div>
    {:else}
      <div class="f-asis-chat" aria-live="polite">
        {#each platica.mensajes as m, i (i)}
          {#if m.rol === 'cliente'}
            <div class="f-asis-ella">{m.texto}</div>
          {:else if m.rol === 'aviso'}
            {@render aviso(m.motivo, i === platica.nuevo)}
          {:else}
            {@const lasTarjetas = tarjetas(m)}
            {#snippet respuesta()}
              {#if m.segundos && m.pasos?.length}
                <button
                  type="button"
                  class="f-asis-pense"
                  aria-expanded={pensesAbiertos.has(i)}
                  onclick={() => (pensesAbiertos.has(i) ? pensesAbiertos.delete(i) : pensesAbiertos.add(i))}
                >
                  {t.pense(m.segundos)}<Icono nombre="r-derecha" tamano={14} />
                </button>
                {#if pensesAbiertos.has(i)}
                  <div class="f-asis-pense-lista">{@render pasosLista(m.pasos.map((clave) => ({ clave, hecho: true })), false)}</div>
                {/if}
              {/if}
              <div class="f-asis-md">
                {#each parrafos(m.texto) as p, j (j)}<p>{p}</p>{/each}
              </div>
              {#if lasTarjetas.length}
                <div class="f-asis-tarjetas">
                  {#each lasTarjetas as p (p.id)}
                    <button type="button" class="f-asis-tarjeta" onclick={(e) => alAbrirProducto(p, e.currentTarget)}>
                      {#if p.imagen_ruta}<img src={urlImagen(p.imagen_ruta)} alt="" loading="lazy" decoding="async" />{/if}
                      <span class="t">
                        <b>{enSuLengua(p.nombre, p.nombre_en, lengua)}</b>
                        <span><Precio producto={p} {moneda} {t} enLinea /></span>
                      </span>
                      <Icono nombre="siguiente" tamano={18} />
                    </button>
                  {/each}
                </div>
              {/if}
            {/snippet}
            {#if i === platica.nuevo}
              <div class="f-asis-resp" use:revelar>{@render respuesta()}</div>
            {:else}
              <div class="f-asis-resp">{@render respuesta()}</div>
            {/if}
          {/if}
        {/each}

        {#if avisoAlFinal}{@render aviso('sin_ia', false)}{/if}

        {#if platica.pendiente !== null}
          <div class="f-asis-ella entra">{platica.pendiente}</div>
          <div class="f-asis-piensa" role="status">
            <span class="f-puntos" aria-hidden="true"><span class="f-giro"><i></i><i></i><i></i></span></span>
            <div class="f-asis-piensa-cuerpo">
              <div class="f-asis-piensa-cabeza"><span class="f-asis-brillo">{t.pensando}</span></div>
              {#if platica.pasos.length}{@render pasosLista(platica.pasos, true)}{/if}
            </div>
          </div>
        {/if}
      </div>
    {/if}
    <!-- La revisión de Cloudflare vive aquí; invisible mientras no duda. -->
    <div class="f-asis-hueco" bind:this={hueco}></div>
  </div>

  <div class="f-asis-abajo">
    {#if platica.noContesto}
      <div class="m-aviso" role="alert"><Icono nombre="alerta" tamano={17} /><span>{t.noContesto}</span></div>
    {/if}
    <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
    <div class="f-asis-caja" class:pildora={!abierta} class:apagada={!contesta} class:escribiendo bind:this={caja} onclick={abrirCaja}>
      <button type="button" class="f-asis-ph" tabindex={abierta ? -1 : 0} disabled={!contesta}>{t.escribe}</button>
      <textarea
        bind:this={campo}
        bind:value={platica.borrador}
        rows="1"
        maxlength="300"
        placeholder={t.escribe}
        aria-label={t.escribe}
        enterkeyhint="send"
        tabindex={abierta ? 0 : -1}
        disabled={!contesta}
        onkeydown={alTeclear}
        oninput={alEscribir}
      ></textarea>
      <button
        type="button"
        class="f-asis-mandar"
        aria-label={t.enviarPregunta}
        disabled={!contesta || ocupado || !platica.borrador.trim()}
        onmousedown={sinQuitarFoco}
        onclick={(e) => {
          e.stopPropagation();
          preguntar(platica.borrador.trim());
        }}
      >
        <Icono nombre="sube" tamano={18} grosor={2.2} />
      </button>
    </div>
    <p class="f-asis-marca">{t.marcaIa}</p>
  </div>
</section>

<style>
  /* Invisible mientras Cloudflare no duda: no ocupa lugar. */
  .f-asis-hueco {
    display: contents;
  }

  a.f-asis-wa {
    text-decoration: none;
  }

  .f-asis-abajo .m-aviso {
    margin: 0;
  }
</style>
