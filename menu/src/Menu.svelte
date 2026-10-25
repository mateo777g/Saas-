<!--
  El menú en línea de un restaurante, pidemenu.mx/<slug> (libreta 6, parte 6a; maqueta
  Qx4C5CbKJYpeAsJCfw4ghn, sección 1): una sola página para todos los restaurantes; el slug elige cuál
  (menu_publico). Arriba la barra del color de Don Chuy, el buscador, sus carteles y las categorías,
  que se quedan pegadas al bajar; luego sus productos. Se vuelve a leer al regresar a la pestaña y
  cada 5 minutos, para que «Abierto» y lo agotado estén al día.

  Con ?muestra=menu|barra es la vista previa de «Tu menú en línea» en el panel (lib/muestra.ts):
  siempre en español y en pesos, sin poder tocarse, y pinta lo que el panel le mande sin guardar.
-->
<script lang="ts">
  import { onMount, tick } from 'svelte';
  import { estiloColor } from '@app/lib/color';
  import Aviso from './componentes/Aviso.svelte';
  import Barra from './componentes/Barra.svelte';
  import Buscador from './componentes/Buscador.svelte';
  import Carteles from './componentes/Carteles.svelte';
  import Fila from './componentes/Fila.svelte';
  import HojaInfo from './componentes/HojaInfo.svelte';
  import HojaOrdenar from './componentes/HojaOrdenar.svelte';
  import HojaProducto from './componentes/HojaProducto.svelte';
  import Icono from './componentes/Icono.svelte';
  import Pestanas from './componentes/Pestanas.svelte';
  import Visor from './componentes/Visor.svelte';
  import { leerMenu, urlImagen, type MenuPublico, type Producto } from './lib/datos';
  import { avisarAlPanel, escucharPanel, modoMuestra, type Pintura } from './lib/muestra';
  import { guardarPreferencias, leerPreferencias, lenguaDelCelular, type Moneda } from './lib/preferencias';
  import { enSuLengua, TEXTOS, textoEstado, type Lengua } from './lib/textos';

  const CADA = 5 * 60 * 1000;
  // El slug es lo primero del camino: pidemenu.mx/fonda-don-chuy.
  const slug = decodeURIComponent(location.pathname.split('/').filter(Boolean)[0] ?? '');
  const muestra = modoMuestra();

  let menu = $state<MenuPublico | null>(null);
  let paso = $state<'leyendo' | 'listo' | 'apagado' | 'sinred'>('leyendo');
  // Lo que el panel manda pintar sin guardar (solo en la vista previa).
  let pintura = $state<Pintura | null>(null);

  const recordado = muestra ? {} : leerPreferencias();
  let lengua = $state<Lengua>(muestra ? 'es' : (recordado.lengua ?? lenguaDelCelular()));
  let monedaElegida = $state<Moneda>(muestra ? 'mxn' : (recordado.moneda ?? 'mxn'));

  const tema = $derived(pintura?.tema ?? menu?.restaurante.tema ?? 'claro');
  const color = $derived(pintura ? pintura.color : (menu?.restaurante.color ?? null));
  // MXN / USD solo sale si Don Chuy puso a cuánto toma el dólar.
  const conDolares = $derived((pintura ? pintura.tipo_cambio_usd : (menu?.restaurante.tipo_cambio_usd ?? null)) !== null);
  const moneda = $derived<Moneda>(conDolares ? monedaElegida : 'mxn');
  const t = $derived(TEXTOS[lengua]);

  function elegirLengua(l: Lengua) {
    lengua = l;
    guardarPreferencias({ lengua, moneda: monedaElegida });
  }

  function elegirMoneda(m: Moneda) {
    monedaElegida = m;
    guardarPreferencias({ lengua, moneda: monedaElegida });
  }

  // ─── Leer ───
  // Una lectura que falla de fondo deja lo que ya se veía; solo la primera enseña el aviso.
  async function cargar(deFondo = false) {
    if (!slug) {
      paso = 'apagado';
      return;
    }
    try {
      const datos = await leerMenu(slug);
      menu = datos;
      paso = datos ? 'listo' : 'apagado';
      if (muestra) {
        await tick();
        avisarAlPanel({ fragmentless: 'menu-listo' });
      }
    } catch (error) {
      console.error('[menu] no se pudo leer el menú:', error);
      if (!deFondo || !menu) paso = 'sinred';
    }
  }

  // ─── Buscar y ordenar ───
  let busqueda = $state('');
  let orden = $state(0);

  // Sin acentos ni mayúsculas: «pastor» encuentra «Pastór».
  const plano = (s: string | null) =>
    (s ?? '')
      .normalize('NFD')
      .replace(/\p{M}/gu, '')
      .toLowerCase();
  const consulta = $derived(plano(busqueda.trim()));

  function ordenados(productos: Producto[]): Producto[] {
    if (orden === 0) return productos;
    const nombre = (p: Producto) => enSuLengua(p.nombre, p.nombre_en, lengua);
    return [...productos].sort((a, b) =>
      orden === 1 ? a.precio - b.precio : orden === 2 ? b.precio - a.precio : nombre(a).localeCompare(nombre(b), lengua),
    );
  }

  const categorias = $derived((menu?.categorias ?? []).map((c) => ({ ...c, productos: ordenados(c.productos) })));
  const hallados = $derived(
    consulta
      ? categorias.flatMap((c) =>
          c.productos
            .filter((p) => [p.nombre, p.nombre_en, p.descripcion, p.descripcion_en].some((x) => plano(x).includes(consulta)))
            .map((p) => ({ p, categoria: enSuLengua(c.nombre, c.nombre_en, lengua) })),
        )
      : [],
  );

  // ─── Lo que se abre encima ───
  type Encima = { tipo: 'producto'; producto: Producto; foto: boolean } | { tipo: 'ordenar' } | { tipo: 'info' } | null;
  let encima = $state<Encima>(null);

  // Cada hoja deja su paso en el historial, para que «atrás» del celular la cierre y no se salga.
  function abrir(e: NonNullable<Encima>) {
    history.pushState({ menuEncima: true }, '');
    encima = e;
  }

  function verFoto() {
    if (encima?.tipo !== 'producto') return;
    history.pushState({ menuEncima: true }, '');
    encima = { ...encima, foto: true };
  }

  // Mientras llega el «atrás» que la cierra, un segundo toque en la X o en el velo no hace nada: si
  // también hiciera «atrás», sacaría al cliente del menú (decidido el 24 de octubre de 2026).
  let cerrando = false;

  function cerrar() {
    if (cerrando) return;
    cerrando = true;
    history.back();
  }

  function alAtras() {
    cerrando = false;
    if (encima?.tipo === 'producto' && encima.foto) encima = { ...encima, foto: false };
    else encima = null;
  }

  // ─── Las categorías al bajar ───
  let activa = $state<number | null>(null);
  let pausaHasta = 0;
  const ALTO_PESTANAS = 49;

  $effect(() => {
    if (activa === null || !categorias.some((c) => c.id === activa)) activa = categorias[0]?.id ?? null;
  });

  // La marcada es la de la sección que está debajo de las pestañas; hasta abajo, la última.
  function alBajar() {
    if (consulta || Date.now() < pausaHasta || !categorias.length) return;
    const alFondo = window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 2;
    let actual = categorias[0].id;
    for (const el of document.querySelectorAll<HTMLElement>('[data-seccion]')) {
      if (el.getBoundingClientRect().top <= ALTO_PESTANAS + 8) actual = Number(el.dataset.seccion);
    }
    activa = alFondo && window.scrollY > 0 ? categorias[categorias.length - 1].id : actual;
  }

  function irA(id: number) {
    const el = document.querySelector<HTMLElement>(`[data-seccion="${id}"]`);
    if (!el) return;
    activa = id;
    pausaHasta = Date.now() + 900;
    // Como en la maqueta («Bajando»): la sección queda 4 abajo de las pestañas.
    window.scrollTo({ top: el.getBoundingClientRect().top + window.scrollY - ALTO_PESTANAS - 4, behavior: 'smooth' });
  }

  // ─── La página ───
  let raiz = $state<HTMLElement>();

  $effect(() => {
    document.title = menu?.restaurante.nombre ?? (paso === 'apagado' ? t.apagado : 'Menú');
    document.documentElement.lang = lengua;
    document.documentElement.style.background = tema === 'oscuro' ? '#0f0f0f' : '#ffffff';
    document.querySelector('meta[name="theme-color"]')?.setAttribute('content', color ?? (tema === 'oscuro' ? '#1f1f1f' : '#121212'));
  });

  // El logo es el ícono de la pestaña.
  $effect(() => {
    const logo = menu?.restaurante.logo_ruta;
    let enlace = document.querySelector<HTMLLinkElement>('link[rel="icon"]');
    if (!logo) return enlace?.remove();
    if (!enlace) {
      enlace = document.createElement('link');
      enlace.rel = 'icon';
      document.head.append(enlace);
    }
    enlace.href = urlImagen(logo);
  });

  // Con algo abierto encima, lo de atrás no se mueve.
  $effect(() => {
    document.documentElement.style.overflow = encima ? 'hidden' : '';
  });

  // La tira de la ventana del color le dice al panel cuánto mide.
  $effect(() => {
    if (muestra !== 'barra' || !raiz) return;
    const el = raiz;
    const avisar = () => avisarAlPanel({ fragmentless: 'alto', alto: Math.ceil(el.getBoundingClientRect().height) });
    const observador = new ResizeObserver(avisar);
    observador.observe(el);
    return () => observador.disconnect();
  });

  onMount(() => {
    cargar();
    const reloj = setInterval(() => cargar(true), CADA);
    const alVolver = () => {
      if (!document.hidden) cargar(true);
    };
    document.addEventListener('visibilitychange', alVolver);
    const dejarDeEscuchar = muestra
      ? escucharPanel(
          (p) => (pintura = p),
          () => cargar(true),
        )
      : () => {};
    return () => {
      clearInterval(reloj);
      document.removeEventListener('visibilitychange', alVolver);
      dejarDeEscuchar();
    };
  });
</script>

<svelte:window
  onpopstate={alAtras}
  onscroll={alBajar}
  onkeydown={(e) => {
    if (e.key === 'Escape' && encima) cerrar();
  }}
/>

<div class="menu" data-tema={tema} style={estiloColor(color)} bind:this={raiz} inert={muestra !== null}>
  {#if paso === 'apagado'}
    <Aviso titulo={t.apagado} texto={t.apagadoTexto} />
  {:else if paso === 'sinred'}
    <Aviso titulo={t.sinRed} texto={t.sinRedTexto} boton={t.reintentar} alBoton={() => cargar()} />
  {:else if menu}
    {@const r = menu.restaurante}
    <div class="columna">
      <Barra
        nombre={r.nombre}
        logo={r.logo_ruta}
        estado={textoEstado(menu.estado, lengua)}
        abierto={!!menu.estado?.abierto}
        {lengua}
        {moneda}
        {conDolares}
        {t}
        arriba={muestra === 'barra' ? '14px' : muestra === 'menu' ? '50px' : 'calc(14px + var(--arriba-seguro))'}
        alLengua={elegirLengua}
        alMoneda={elegirMoneda}
        alInfo={() => abrir({ tipo: 'info' })}
      />

      {#if muestra === 'barra'}
        <Pestanas categorias={menu.categorias} activa={menu.categorias[0]?.id ?? null} {lengua} {t} pegadas={false} />
      {:else}
        <Buscador bind:busqueda {t} alOrdenar={() => abrir({ tipo: 'ordenar' })} />

        {#if consulta}
          <div class="raya"></div>
          <div class="contenido">
            {#if hallados.length}
              <div class="resultados">{hallados.length} {hallados.length === 1 ? t.resultado : t.resultados}</div>
              {#each hallados as h (h.p.id)}
                <Fila
                  producto={h.p}
                  categoria={h.categoria}
                  {lengua}
                  {moneda}
                  {t}
                  alAbrir={() => abrir({ tipo: 'producto', producto: h.p, foto: false })}
                />
              {/each}
            {:else}
              <div class="vacio">
                <b>{t.nada(busqueda.trim())}</b>
                <span>{t.nadaTexto}</span>
              </div>
            {/if}
          </div>
        {:else}
          {#if menu.carteles.length}<Carteles rutas={menu.carteles} {t} />{/if}
          <Pestanas {categorias} {activa} {lengua} {t} alElegir={irA} />
          <div class="contenido">
            {#each categorias as c (c.id)}
              <section class="seccion" data-seccion={c.id}>
                <h2 class="seccion-titulo"><Icono categoria={c.icono} tamano={20} />{enSuLengua(c.nombre, c.nombre_en, lengua)}</h2>
                {#each c.productos as p (p.id)}
                  <Fila producto={p} {lengua} {moneda} {t} alAbrir={() => abrir({ tipo: 'producto', producto: p, foto: false })} />
                {/each}
              </section>
            {/each}
          </div>
        {/if}
      {/if}
    </div>

    {#if encima?.tipo === 'producto'}
      <HojaProducto producto={encima.producto} {lengua} {moneda} {t} alVerFoto={verFoto} alCerrar={cerrar} />
      {#if encima.foto && encima.producto.imagen_ruta}
        <Visor
          ruta={encima.producto.imagen_ruta}
          nombre={enSuLengua(encima.producto.nombre, encima.producto.nombre_en, lengua)}
          descripcion={enSuLengua(encima.producto.descripcion, encima.producto.descripcion_en, lengua)}
          {t}
          alCerrar={cerrar}
        />
      {/if}
    {:else if encima?.tipo === 'ordenar'}
      <HojaOrdenar
        {orden}
        {t}
        alElegir={(i) => {
          orden = i;
          cerrar();
        }}
        alCerrar={cerrar}
      />
    {:else if encima?.tipo === 'info'}
      <HojaInfo {menu} {t} alCerrar={cerrar} />
    {/if}
  {/if}
</div>

<style>
  /* En la compu, el menú es una columna al centro, del ancho de un celular grande. */
  .columna {
    max-width: 520px;
    margin: 0 auto;
  }

  .raya {
    height: 14px;
    border-bottom: 1px solid var(--m-linea);
  }

  .contenido {
    padding: 4px 16px calc(40px + env(safe-area-inset-bottom, 0px));
  }

  .seccion {
    padding-top: 20px;
  }

  .seccion-titulo {
    display: flex;
    align-items: center;
    gap: 9px;
    margin: 0 0 4px;
    font-size: 20px;
    font-weight: 800;
    letter-spacing: -0.4px;
  }

  .resultados {
    padding: 14px 0 0;
    font-size: 12.5px;
    color: var(--m-suave);
  }

  .vacio {
    padding: 54px 12px 30px;
    text-align: center;
    display: flex;
    flex-direction: column;
    gap: 8px;
    align-items: center;
  }

  .vacio b {
    font-size: 16px;
    font-weight: 800;
  }

  .vacio span {
    font-size: 13.5px;
    color: var(--m-suave);
    line-height: 1.5;
    max-width: 30ch;
  }
</style>
