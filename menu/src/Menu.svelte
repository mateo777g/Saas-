<!--
  El menú en línea de un restaurante, pidemenu.mx/<slug> (libreta 6, parte 6a; maqueta
  Qx4C5CbKJYpeAsJCfw4ghn, sección 1): una sola página para todos los restaurantes; el slug elige cuál
  (menu_publico). Arriba la barra del color de Don Chuy, el buscador, sus carteles y las categorías,
  que se quedan pegadas al bajar; luego sus productos. Se vuelve a leer al regresar a la pestaña y
  cada 5 minutos, para que «Abierto» y lo agotado estén al día.

  Con ?muestra=menu|barra es la vista previa de «Tu menú en línea» en el panel (lib/muestra.ts):
  siempre en español y en pesos, sin poder tocarse, y pinta lo que el panel le mande sin guardar.

  Con la 6b (maqueta G2nxGb3xBgiPEYrDb6CgcW) se pide: el «+» de cada producto, «Ver tu pedido» abajo,
  «Tu pedido», «Hacer pedido» (Worker /menu/pedido) y luego «Falta un paso» y «Pedido enviado».

  Con la 6c (maqueta 2UPwZw31WrcYRZkH8jaT1Y) llega el asistente: la burbuja ∫∫ abajo a la derecha y
  su plática (Worker /menu/pregunta); la hoja de un producto que nombró se abre encima de la plática.
-->
<script lang="ts">
  import { onMount, tick } from 'svelte';
  import { estiloColor } from '@app/lib/color';
  import { dinero } from '@app/lib/formato';
  import Aviso from './componentes/Aviso.svelte';
  import Barra from './componentes/Barra.svelte';
  import BarraPedido from './componentes/BarraPedido.svelte';
  import Burbuja from './componentes/Burbuja.svelte';
  import Buscador from './componentes/Buscador.svelte';
  import Carteles from './componentes/Carteles.svelte';
  import Fila from './componentes/Fila.svelte';
  import HojaAsistente from './componentes/HojaAsistente.svelte';
  import HojaHecho from './componentes/HojaHecho.svelte';
  import HojaInfo from './componentes/HojaInfo.svelte';
  import HojaOrdenar from './componentes/HojaOrdenar.svelte';
  import HojaPedido from './componentes/HojaPedido.svelte';
  import HojaProducto from './componentes/HojaProducto.svelte';
  import Icono from './componentes/Icono.svelte';
  import Pestanas from './componentes/Pestanas.svelte';
  import Visor from './componentes/Visor.svelte';
  import { Platica } from './lib/asistente.svelte';
  import { leerMenu, urlImagen, type MenuPublico, type Producto } from './lib/datos';
  import { avisarAlPanel, escucharPanel, modoMuestra, type Pintura } from './lib/muestra';
  import {
    guardarCarrito,
    guardarCliente,
    guardarHecho,
    hacerPedido,
    leerCarrito,
    leerCliente,
    leerHecho,
    mismoRenglon,
    NoSeMando,
    precioUnitario,
    type EnCarrito,
    type Hecho,
    type Renglon,
    type Tipo,
  } from './lib/pedido';
  import { guardarPreferencias, leerPreferencias, lenguaDelCelular, type Moneda } from './lib/preferencias';
  import { enSuLengua, enSuLenguaElNo, esLimite, TEXTOS, textoEstado, type Lengua } from './lib/textos';
  import { pedirToken } from './lib/turnstile';

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
      const primera = !menu;
      menu = datos;
      paso = datos ? 'listo' : 'apagado';
      if (datos && primera && !muestra) {
        carrito = leerCarrito(slug);
        const h = leerHecho(slug, datos.ahora.fecha);
        if (h) {
          hecho = h;
          abrir({ tipo: 'hecho' });
        }
      }
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
  // Una pila: desde «Tu pedido» se abre la hoja de un renglón y, al cerrarla, se vuelve al pedido.
  type Encima =
    | { tipo: 'producto'; producto: Producto; foto: boolean; editando: number | null }
    | { tipo: 'ordenar' }
    | { tipo: 'info' }
    | { tipo: 'pedido' }
    | { tipo: 'hecho' }
    | { tipo: 'asistente' };
  let pila = $state<Encima[]>([]);
  const encima = $derived(pila.at(-1) ?? null);

  // Cada hoja deja su paso en el historial, para que «atrás» del celular la cierre y no se salga.
  function abrir(e: Encima) {
    history.pushState({ menuEncima: true }, '');
    pila.push(e);
  }

  function verFoto() {
    if (encima?.tipo !== 'producto') return;
    abrir({ ...encima, foto: true });
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
    pila.pop();
  }

  // ─── El pedido (parte 6b) ───
  // Pide solo quien está en el menú de verdad (no la vista previa del panel) mientras Postgres dice
  // que recibe: con teléfono, dentro del horario y sin pausa.
  const recibe = $derived(!muestra && !!menu?.recibe_pedidos);
  const productos = $derived(new Map((menu?.categorias ?? []).flatMap((c) => c.productos).map((p) => [p.id, p])));

  let carrito = $state<EnCarrito[]>([]);
  // Un producto que ya no viene en el menú (se agotó, o lo quitaron) sale tachado.
  const vistaCarrito = $derived(
    carrito.map((r) =>
      productos.has(r.producto_id) || !menu
        ? r
        : { ...r, aviso: { fuera: true, texto: t.yaNoHay(enSuLengua(r.nombre, r.nombre_en, lengua)) } },
    ),
  );
  const cuantos = $derived(carrito.reduce((s, r) => s + r.cantidad, 0));
  const pesos = (n: number) => `${moneda === 'usd' ? 'MX' : ''}${dinero(n)}`;
  const totalCarrito = $derived(
    Math.round(
      vistaCarrito
        .filter((r) => !r.aviso?.fuera)
        .reduce((s, r) => s + precioUnitario(productos.get(r.producto_id)!, r.opciones) * r.cantidad, 0) * 100,
    ) / 100,
  );
  const lleva = (id: number) => carrito.reduce((s, r) => s + (r.producto_id === id ? r.cantidad : 0), 0);

  // La clave del pedido cambia con cada cambio, como el borrador de Pepe: tocar dos veces «Hacer
  // pedido» con lo mismo no lo guarda dos veces.
  let clave = crypto.randomUUID();
  function cambiarCarrito(nuevo: EnCarrito[]) {
    carrito = nuevo;
    clave = crypto.randomUUID();
    guardarCarrito(slug, carrito);
  }

  // Lo mismo con las mismas opciones y nota se suma en un renglón (hasta 99).
  function sumar(lista: EnCarrito[], r: Renglon, p: Producto): EnCarrito[] {
    const igual = lista.findIndex((x) => mismoRenglon(x, r));
    if (igual === -1) return [...lista, { ...r, nombre: p.nombre, nombre_en: p.nombre_en, precio: precioUnitario(p, r.opciones) }];
    return lista.map((x, i) => (i === igual ? { ...x, cantidad: Math.min(99, x.cantidad + r.cantidad) } : x));
  }

  let globo = $state<string | null>(null);
  let reloj: ReturnType<typeof setTimeout> | undefined;

  // El «+»: sin opciones agrega 1 al momento y lo dice abajo; con opciones abre su hoja.
  function alMas(p: Producto) {
    if (p.grupos.length) return abrir({ tipo: 'producto', producto: p, foto: false, editando: null });
    cambiarCarrito(sumar(carrito, { producto_id: p.id, cantidad: 1, opciones: [], nota: '' }, p));
    globo = enSuLengua(p.nombre, p.nombre_en, lengua) + t.enTuPedido;
    clearTimeout(reloj);
    reloj = setTimeout(() => (globo = null), 2000);
  }

  function alAgregar(p: Producto, r: Renglon, editando: number | null) {
    const resto = editando === null ? carrito : carrito.filter((_, i) => i !== editando);
    const lista = sumar(resto, r, p);
    // Al cambiar un renglón, se queda en su lugar.
    if (editando !== null && lista.length > resto.length) lista.splice(editando, 0, lista.pop()!);
    cambiarCarrito(lista);
    cerrar();
  }

  function alCantidad(i: number, cambio: number) {
    const r = carrito[i];
    const cantidad = r.cantidad + cambio;
    cambiarCarrito(cantidad < 1 ? carrito.filter((_, j) => j !== i) : carrito.map((x, j) => (j === i ? { ...x, cantidad: Math.min(99, cantidad) } : x)));
    if (!carrito.length) cerrar();
  }

  function abrirRenglon(i: number) {
    const p = productos.get(carrito[i].producto_id);
    if (p) abrir({ tipo: 'producto', producto: p, foto: false, editando: i });
  }

  // «Tu pedido»: lo que escribe, recordado en este celular para la próxima vez.
  const recordadoCliente = leerCliente();
  let cliente = $state({ ...recordadoCliente, pagaCon: '' });
  let tipo = $state<Tipo>('para_llevar');
  let avisoPedido = $state<{ titulo?: string; texto: string } | null>(null);
  let limite = $state(false);
  let ocupado = $state(false);
  let hueco = $state<HTMLDivElement>();
  let hecho = $state<Hecho | null>(null);

  $effect(() => {
    if (menu && !menu.restaurante.hace_envios && tipo === 'domicilio') tipo = 'para_llevar';
  });

  async function hacer() {
    if (!menu || ocupado || !hueco) return;
    // Lo tachado se quita al volver a pedir; los demás avisos también.
    const limpio = vistaCarrito.filter((r) => !r.aviso?.fuera).map(({ aviso: _aviso, ...r }) => r);
    if (limpio.length !== carrito.length || carrito.some((r) => r.aviso)) cambiarCarrito(limpio);
    avisoPedido = null;
    limite = false;
    ocupado = true;
    const dom = tipo === 'domicilio';
    try {
      let token: string;
      try {
        token = await pedirToken(hueco, lengua);
      } catch (error) {
        console.error('[menu] la revisión de Cloudflare no contestó:', error);
        throw new NoSeMando(t.noSeMando);
      }
      const respuesta = await hacerPedido(
        {
          slug,
          clave,
          tipo,
          cliente_nombre: cliente.nombre.trim(),
          cliente_telefono: dom ? cliente.telefono : null,
          cliente_direccion: dom ? cliente.direccion : null,
          cliente_referencias: dom ? cliente.referencias : null,
          paga_con: dom && cliente.pagaCon.trim() ? Number(cliente.pagaCon.trim()) : null,
          renglones: carrito.map((r) => ({
            producto_id: r.producto_id,
            cantidad: r.cantidad,
            opciones: r.opciones,
            nota: r.nota,
            precio: precioUnitario(productos.get(r.producto_id)!, r.opciones),
          })),
          turnstile: token,
        },
        t.noSeMando,
      );
      guardarCliente({ nombre: cliente.nombre.trim(), telefono: cliente.telefono, direccion: cliente.direccion, referencias: cliente.referencias });
      if (respuesta.ok) {
        const ids = carrito.map((r) => ({ producto_id: r.producto_id, opciones: r.opciones }));
        hecho = { pedido: respuesta, ids, fecha: menu.ahora.fecha, enviado: false };
        guardarHecho(slug, hecho);
        cambiarCarrito([]);
        cliente.pagaCon = '';
        pila[pila.length - 1] = { tipo: 'hecho' };
      } else if (respuesta.motivo === 'no_recibe') {
        avisoPedido = { texto: t.noRecibimos };
        await cargar(true);
      } else {
        // Nada se guardó: cada renglón dice qué cambió y el menú se vuelve a leer con los precios nuevos.
        cambiarCarrito(
          carrito.map((r, i) => {
            const c = respuesta.cambios.find((x) => x.renglon === i + 1);
            if (!c) return r;
            const nombre = enSuLengua(r.nombre, r.nombre_en, lengua);
            if (c.cambio === 'precio') return { ...r, aviso: { fuera: false, texto: t.ahoraCuesta(nombre, pesos(c.precio ?? 0)) } };
            if (c.cambio === 'opciones') return { ...r, aviso: { fuera: true, texto: t.cambiaronOpciones(nombre) } };
            return { ...r, aviso: { fuera: true, texto: t.yaNoHay(c.opcion ?? nombre) } };
          }),
        );
        avisoPedido = { titulo: t.cambio, texto: t.cambioTexto };
        await cargar(true);
      }
    } catch (error) {
      if (!(error instanceof NoSeMando)) console.error('[menu] el pedido falló:', error);
      const mensaje = error instanceof NoSeMando ? error.message : t.noSeMando;
      avisoPedido = { texto: enSuLenguaElNo(mensaje, lengua) };
      limite = esLimite(mensaje);
    } finally {
      ocupado = false;
    }
  }

  function alEnviar() {
    if (!hecho) return;
    hecho = { ...hecho, enviado: true };
    guardarHecho(slug, hecho);
  }

  function alVolver() {
    hecho = null;
    guardarHecho(slug, null);
    cerrar();
  }

  // Abajo: «Ver tu pedido», o por qué no se reciben pedidos.
  const avisoAbajo = $derived.by((): { icono: 'reloj' | 'apagado'; texto: string } | null => {
    if (!menu || recibe) return null;
    const e = menu.estado;
    if (!menu.pedidos_pausados && menu.restaurante.telefono && e && !e.abierto) {
      const dia = menu.horario.find((h) => h.dia === e.abre.dia);
      if (dia) return { icono: 'reloj', texto: t.recibimos(dia.abre, dia.cierra) };
    }
    return { icono: 'apagado', texto: t.noRecibimos };
  });
  const conAbajo = $derived(!muestra && !!menu && (avisoAbajo !== null || carrito.length > 0));

  // ─── El asistente (parte 6c) ───
  // La plática no vive en su hoja: si ella la cierra mientras piensa, la respuesta llega igual.
  const platica = new Platica(slug);
  const conPlatica = $derived(pila.some((e) => e.tipo === 'asistente'));

  async function preguntarAlAsistente(pregunta: string, hueco: HTMLElement) {
    const motivo = await platica.preguntar(pregunta, { lengua, moneda, revision: () => pedirToken(hueco, lengua) });
    // Se acabó su sobre a media plática: la caja se apaga ya y el menú se vuelve a leer.
    if (motivo === 'sin_ia' && menu) {
      menu = { ...menu, asistente_contesta: false };
      cargar(true);
    }
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
    document.documentElement.style.overflow = pila.length ? 'hidden' : '';
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
    if (e.key === 'Escape' && encima && !(encima.tipo === 'hecho' && !hecho?.enviado)) cerrar();
  }}
/>

<div class="menu" data-tema={tema} style={estiloColor(color)} bind:this={raiz} inert={muestra !== null}>
  {#if paso === 'apagado'}
    <Aviso titulo={t.apagado} texto={t.apagadoTexto} />
  {:else if paso === 'sinred'}
    <Aviso titulo={t.sinRed} texto={t.sinRedTexto} boton={t.reintentar} alBoton={() => cargar()} />
  {:else if menu}
    {@const r = menu.restaurante}
    <div class="columna" class:con-abajo={conAbajo} class:con-burbuja={muestra !== 'barra'}>
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
                  lleva={lleva(h.p.id)}
                  alAbrir={() => abrir({ tipo: 'producto', producto: h.p, foto: false, editando: null })}
                  alMas={recibe ? () => alMas(h.p) : null}
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
                  <Fila
                    producto={p}
                    {lengua}
                    {moneda}
                    {t}
                    lleva={lleva(p.id)}
                    alAbrir={() => abrir({ tipo: 'producto', producto: p, foto: false, editando: null })}
                    alMas={recibe ? () => alMas(p) : null}
                  />
                {/each}
              </section>
            {/each}
          </div>
        {/if}
      {/if}
    </div>

    {#if conAbajo}
      <BarraPedido {cuantos} total={pesos(totalCarrito)} aviso={avisoAbajo} {t} alAbrir={() => abrir({ tipo: 'pedido' })} />
    {/if}
    {#if muestra !== 'barra'}
      <Burbuja {color} {tema} conBarra={conAbajo} {t} alAbrir={() => abrir({ tipo: 'asistente' })} />
    {/if}
    {#if globo}
      <div class="globo" role="status"><Icono nombre="check" tamano={14} />{globo}</div>
    {/if}

    {#if conPlatica}
      <HojaAsistente
        {platica}
        {menu}
        {productos}
        {lengua}
        {moneda}
        {tema}
        {t}
        alPreguntar={preguntarAlAsistente}
        alAbrirProducto={(p) => abrir({ tipo: 'producto', producto: p, foto: false, editando: null })}
        alCerrar={cerrar}
      />
    {/if}

    {#if encima?.tipo === 'producto'}
      {@const editando = encima.editando}
      {@const producto = encima.producto}
      <!-- Abierta desde la plática, va encima de ella, con su velo. -->
      <div class="encima" class:sobre-platica={conPlatica}>
        {#key encima}
          <HojaProducto
            {producto}
            {lengua}
            {moneda}
            {t}
            {recibe}
            inicial={editando === null ? null : (carrito[editando] ?? null)}
            alVerFoto={verFoto}
            alAgregar={(r) => alAgregar(producto, r, editando)}
            alCerrar={cerrar}
          />
        {/key}
        {#if encima.foto && encima.producto.imagen_ruta}
          <Visor
            ruta={encima.producto.imagen_ruta}
            nombre={enSuLengua(encima.producto.nombre, encima.producto.nombre_en, lengua)}
            descripcion={enSuLengua(encima.producto.descripcion, encima.producto.descripcion_en, lengua)}
            {t}
            alCerrar={cerrar}
          />
        {/if}
      </div>
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
    {:else if encima?.tipo === 'pedido'}
      <HojaPedido
        renglones={vistaCarrito}
        {productos}
        {lengua}
        {moneda}
        {t}
        haceEnvios={menu.restaurante.hace_envios}
        tipoCambio={menu.restaurante.tipo_cambio_usd}
        bind:tipo
        bind:cliente
        aviso={avisoPedido}
        {limite}
        telefono={menu.restaurante.telefono ?? ''}
        {ocupado}
        bind:hueco
        {alCantidad}
        alAbrirRenglon={abrirRenglon}
        alHacer={hacer}
        alCerrar={cerrar}
      />
    {:else if encima?.tipo === 'hecho' && hecho}
      <HojaHecho
        pedido={hecho.pedido}
        ids={hecho.ids ?? []}
        {productos}
        enviado={hecho.enviado}
        telefono={menu.restaurante.telefono ?? ''}
        {lengua}
        {moneda}
        {t}
        {alEnviar}
        {alVolver}
      />
    {/if}
  {/if}
</div>

<style>
  /* En la compu, el menú es una columna al centro, del ancho de un celular grande. */
  .columna {
    max-width: 520px;
    margin: 0 auto;
  }

  /* Lugar para «Ver tu pedido» abajo. */
  .columna.con-abajo .contenido {
    padding-bottom: 112px;
  }

  /* Y para la burbuja del asistente, sola o arriba de «Ver tu pedido». */
  .columna.con-burbuja .contenido {
    padding-bottom: calc(100px + env(safe-area-inset-bottom, 0px));
  }

  .columna.con-abajo.con-burbuja .contenido {
    padding-bottom: calc(176px + env(safe-area-inset-bottom, 0px));
  }

  .encima {
    display: contents;
  }

  .sobre-platica :global(.velo) {
    z-index: 9;
  }

  .sobre-platica :global(.hoja) {
    z-index: 10;
  }

  .sobre-platica :global(.visor) {
    z-index: 11;
  }

  .globo {
    position: fixed;
    left: 50%;
    bottom: 112px;
    transform: translateX(-50%);
    z-index: 6;
    height: 40px;
    padding: 0 16px;
    border-radius: 20px;
    display: inline-flex;
    align-items: center;
    gap: 8px;
    background: #232323;
    color: #ffffff;
    font-size: 13px;
    font-weight: 700;
    white-space: nowrap;
    box-shadow: 0 12px 30px var(--m-sombra);
  }

  .globo :global(svg) {
    color: #4cc26f;
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
