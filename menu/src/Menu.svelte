<!--
  El menú en línea de un restaurante, pidemenu.mx/<slug> (libreta 6, parte 6a; maqueta
  Qx4C5CbKJYpeAsJCfw4ghn, sección 1): una sola página para todos los restaurantes; el slug elige cuál
  (menu_publico). Arriba la barra del color de Don Chuy, el buscador, sus carteles y las categorías,
  que se quedan pegadas al bajar; luego sus productos. Se vuelve a leer al regresar a la pestaña y
  cada 5 minutos, para que «Abierto» y lo agotado estén al día.

  Con ?muestra=menu|barra es la vista previa de «Tu menú en línea» en el panel (lib/muestra.ts): nace en español y en
  pesos, y pinta lo que el panel le mande sin guardar. La tira (barra) no se toca. El teléfono (menu), desde la parte C2
  (13 nov 2026), se toca como lo toca un cliente, sin mandar pedidos ni preguntas de verdad y sin leer ni guardar nada
  en el navegador; lleva el reloj del teléfono, va a la pieza que cambió y, en el modo Producto, tiene un producto
  abierto que cambia al momento con sus formas.

  Con la 6b (maqueta G2nxGb3xBgiPEYrDb6CgcW) se pide: el «+» de cada producto, «Ver tu pedido» abajo y
  «Tu pedido». Desde el 9 de noviembre de 2026 (maqueta 3smEgFNCNVBkLMukDTdXWw) es un solo botón,
  «Pedir por WhatsApp»: un toque guarda el pedido (Worker /menu/pedido) y abre WhatsApp; luego «Pedido
  enviado», o «Falta un paso» si el celular no dejó abrir WhatsApp.

  Con la 6c (maqueta 2UPwZw31WrcYRZkH8jaT1Y) llega el asistente: la burbuja con la estrella abajo a la derecha y
  su plática (Worker /menu/pregunta); la hoja de un producto que nombró se abre encima de la plática.
-->
<script lang="ts">
  import { onMount, tick, untrack } from 'svelte';
  import { estiloMenu } from '@app/lib/color';
  import { dinero } from '@app/lib/formato';
  import Abajo from './componentes/Abajo.svelte';
  import Ajustes from './componentes/Ajustes.svelte';
  import Aviso from './componentes/Aviso.svelte';
  import Barra from './componentes/Barra.svelte';
  import Buscador from './componentes/Buscador.svelte';
  import Carteles from './componentes/Carteles.svelte';
  import Categorias from './componentes/Categorias.svelte';
  import Esqueleto from './componentes/Esqueleto.svelte';
  import Fila from './componentes/Fila.svelte';
  import VentanaInfo from './componentes/VentanaInfo.svelte';
  import VistaAsistente from './componentes/VistaAsistente.svelte';
  import VistaPedido from './componentes/VistaPedido.svelte';
  import VistaProducto from './componentes/VistaProducto.svelte';
  import Icono from './componentes/Icono.svelte';
  import TarjetaBusca from './componentes/TarjetaBusca.svelte';
  import TarjetaProducto from './componentes/TarjetaProducto.svelte';
  import { Platica } from './lib/asistente.svelte';
  import { leerMenu, urlImagen, type MenuPublico, type Producto } from './lib/datos';
  import { guardarEsqueleto, leerEsqueleto, medirEsqueleto } from './lib/esqueleto';
  import { esperarFotos, fotosDeArriba } from './lib/fotos';
  import { leerFormas, type Pestana } from './lib/formas';
  import { avisarAlPanel, escucharPanel, irAPieza, modoMuestra, type Cambio, type ModoPanel, type Pintura } from './lib/muestra';
  import {
    abrirWhatsApp,
    centavos,
    enlaceWhatsApp,
    guardarCarrito,
    guardarCliente,
    guardarHecho,
    hacerPedido,
    leerCarrito,
    leerCliente,
    leerHecho,
    mensajeWhatsApp,
    mismoRenglon,
    NoSeMando,
    precioUnitario,
    type EnCarrito,
    type Guardado,
    type Hecho,
    type Renglon,
    type Tipo,
  } from './lib/pedido';
  import { quieto } from './lib/movimiento';
  import { guardarPreferencias, leerPreferencias, lenguaDelCelular, type Moneda } from './lib/preferencias';
  import { enSuLengua, enSuLenguaElNo, esLimite, TEXTOS, textoEstado, type Lengua } from './lib/textos';
  import { adelantarToken, pedirToken, type Adelantado } from './lib/turnstile';

  const CADA = 5 * 60 * 1000;
  // El slug es lo primero del camino: pidemenu.mx/fonda-don-chuy.
  const slug = decodeURIComponent(location.pathname.split('/').filter(Boolean)[0] ?? '');
  const muestra = modoMuestra();
  // El teléfono de la vista previa: arriba va su reloj, como en un iPhone (la maqueta dibuja el menú a 390 × 849 con 36
  // de arriba, lo de los comparar_*.py).
  const enTelefono = muestra === 'menu';
  if (enTelefono) document.documentElement.style.setProperty('--arriba-seguro', '36px');

  let menu = $state<MenuPublico | null>(null);
  let paso = $state<'leyendo' | 'listo' | 'apagado' | 'sinred'>('leyendo');
  // Lo que el panel manda pintar sin guardar (solo en la vista previa).
  let pintura = $state<Pintura | null>(null);

  // El esqueleto mientras llega el menú (12 nov 2026): el que recuerda este navegador si se midió con este mismo ancho
  // de columna; si no, el general. La vista previa del panel no lleva este (el suyo es de la parte C2).
  const recordadoEsqueleto = muestra ? null : leerEsqueleto(slug);
  const recuerdo =
    recordadoEsqueleto && Math.abs(recordadoEsqueleto.ancho - Math.min(document.documentElement.clientWidth, 520)) <= 1 ? recordadoEsqueleto : null;

  const recordado = muestra ? {} : leerPreferencias();
  let lengua = $state<Lengua>(muestra ? 'es' : (recordado.lengua ?? lenguaDelCelular()));
  let monedaElegida = $state<Moneda>(muestra ? 'mxn' : (recordado.moneda ?? 'mxn'));

  const tema = $derived(pintura?.tema ?? menu?.restaurante.tema ?? 'claro');
  const color = $derived(pintura ? pintura.color : (menu?.restaurante.color ?? null));
  // «Tu menú en línea»: el color de la barra, el fondo y las formas (lo que no mande el panel, como está guardado).
  const colorBarra = $derived(pintura?.colorBarra !== undefined ? pintura.colorBarra : (menu?.restaurante.color_barra ?? null));
  const fondo = $derived(pintura?.fondo !== undefined ? pintura.fondo : (menu?.restaurante.fondo ?? null));
  const formas = $derived(pintura?.formas ?? leerFormas(menu?.restaurante.formas));
  // MXN / USD siempre sale: el dólar es uno para todos y lo pone el Worker cada día (Mi menú). Si un día
  // faltara, el menú solo enseña pesos.
  const conDolares = $derived((menu?.restaurante.tipo_cambio_usd ?? null) !== null);
  const moneda = $derived<Moneda>(conDolares ? monedaElegida : 'mxn');
  const t = $derived(TEXTOS[lengua]);

  // En la vista previa se cambian ahí mismo y se olvidan: el navegador de Don Chuy no recuerda nada de su teléfono.
  function elegirLengua(l: Lengua) {
    lengua = l;
    if (!muestra) guardarPreferencias({ lengua, moneda: monedaElegida });
  }

  function elegirMoneda(m: Moneda) {
    monedaElegida = m;
    if (!muestra) guardarPreferencias({ lengua, moneda: monedaElegida });
  }

  // ─── Leer ───
  // Una lectura que falla de fondo deja lo que ya se veía; solo la primera enseña el aviso.
  async function cargar(deFondo = false) {
    if (!slug) {
      paso = 'apagado';
      return;
    }
    // «Intentar otra vez» enseña otra vez el esqueleto mientras lee.
    if (!deFondo && !menu) paso = 'leyendo';
    try {
      const datos = await leerMenu(slug);
      const primera = !menu;
      menu = datos;
      paso = datos ? 'listo' : 'apagado';
      if (!datos && !muestra) guardarEsqueleto(slug, null);
      if (datos && primera && !muestra) {
        recordarEsqueleto();
        carrito = leerCarrito(slug);
        const h = leerHecho(slug, datos.ahora.fecha);
        if (h) {
          hecho = h;
          abrir({ tipo: 'pedido' });
        }
      }
      if (datos && primera && enTelefono) {
        recordarEsqueleto();
        if (modoPanel === 'producto') abrirDeMuestra();
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

  // ─── El esqueleto que recuerda este navegador ───
  // Se mide del menú ya armado (lib/esqueleto.ts), con la página hasta arriba y sin buscar: al llegar, y otra vez
  // cuando ya llegaron las fotos de arriba, porque al llegar un logo todavía no sabe su ancho.
  let columna = $state<HTMLElement>();

  // En la vista previa no se guarda: se le manda al panel, que lo pinta con sus colores en la pantalla del teléfono
  // mientras lee (y lo recuerda él), medido solo de lo que se ve en la pantalla y sin nada abierto encima.
  function recordar() {
    if (!raiz || !columna || scrollY > 0 || consulta || lupaAbierta || (enTelefono && pila.length)) return;
    try {
      const abajo = raiz.querySelector<HTMLElement>('nav.f-app');
      if (enTelefono) avisarAlPanel({ fragmentless: 'esqueleto', esqueleto: medirEsqueleto(raiz, columna, abajo, innerHeight) });
      else guardarEsqueleto(slug, medirEsqueleto(raiz, columna, abajo, Math.ceil(innerHeight * 1.25)));
    } catch (error) {
      console.error('[menu] no se pudo medir el esqueleto del menú:', error);
    }
  }

  async function recordarEsqueleto() {
    await tick();
    recordar();
    if (!columna) return;
    await fotosDeArriba(columna, 8000);
    // Lo que acaba de llegar aparece en 0.3 s: se mide ya quieto, y cuando el celular no está ocupado (Safari no tiene
    // requestIdleCallback).
    setTimeout(() => ('requestIdleCallback' in window ? requestIdleCallback(recordar, { timeout: 2000 }) : recordar()), 400);
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
  // Una pila: desde «Tu pedido» se abre el producto de un renglón y, al cerrarlo, se vuelve al pedido. Tu pedido es una
  // vista: enseña la lista, «sin nada», «sin pedidos» o el pedido mandado, según el caso. El producto guarda lo que lo
  // abrió: de ahí crece y ahí regresa.
  type Encima =
    | { tipo: 'producto'; producto: Producto; editando: number | null; desde: HTMLElement | null }
    | { tipo: 'info'; desde: HTMLElement }
    | { tipo: 'ajustes' }
    | { tipo: 'pedido' }
    | { tipo: 'asistente' };
  let pila = $state<Encima[]>([]);
  const encima = $derived(pila.at(-1) ?? null);

  // Cada hoja deja su paso en el historial, para que «atrás» del celular la cierre y no se salga. En la vista previa no:
  // el teléfono vive dentro del panel, y su historial es el de la pestaña del panel (el «atrás» del navegador cerraría
  // cosas dentro del teléfono en lugar de salir de la vista).
  function abrir(e: Encima) {
    if (!muestra) history.pushState({ menuEncima: true }, '');
    pila.push(e);
  }

  // Mientras llega el «atrás» que la cierra, un segundo toque en la X o en el velo no hace nada: si
  // también hiciera «atrás», sacaría al cliente del menú (decidido el 24 de octubre de 2026).
  let cerrando = false;

  function cerrar() {
    if (muestra) return void pila.pop();
    if (cerrando) return;
    cerrando = true;
    history.back();
  }

  // Las pestañas de abajo regresan varios pasos de una vez (cada hoja tiene el suyo en el historial) y dejan
  // la pila como debe quedar: vacía con «Menú», o solo la pestaña nueva.
  let alRegresar: Encima[] | null = null;
  function regresarA(nueva: Encima[]) {
    if (muestra) {
      pila = nueva;
      return;
    }
    if (cerrando) return;
    const pasos = pila.length - nueva.length;
    if (pasos <= 0) {
      pila = nueva;
      return;
    }
    cerrando = true;
    alRegresar = nueva;
    history.go(-pasos);
  }

  function alAtras() {
    cerrando = false;
    if (alRegresar) {
      pila = alRegresar;
      alRegresar = null;
      return;
    }
    pila.pop();
  }

  // ─── El pedido (parte 6b) ───
  // Pide quien está en el menú de verdad mientras Postgres dice que recibe: con teléfono, dentro del horario y sin pausa.
  // En el teléfono de la vista previa basta con el teléfono (el WhatsApp), a cualquier hora y aunque esté en pausa, para
  // que Don Chuy vea siempre su menú con el «+», Tu pedido y «Agregar al pedido»; el pedido no se manda (simularPedido).
  const recibe = $derived(enTelefono ? !!menu?.restaurante.telefono : !muestra && !!menu?.recibe_pedidos);
  const productos = $derived(new Map((menu?.categorias ?? []).flatMap((c) => c.productos).map((p) => [p.id, p])));
  // El ícono de la categoría de cada producto (el cuadro de Tu pedido cuando no tiene foto).
  const iconos = $derived(new Map((menu?.categorias ?? []).flatMap((c) => c.productos.map((p) => [p.id, c.icono] as const))));
  // Cada cartel con su producto, si es uno de Mi menú (Postgres solo manda los que salen en el menú).
  const carteles = $derived(
    (menu?.carteles ?? []).map((c) => ({ ruta: c.ruta, producto: c.producto_id === null ? null : (productos.get(c.producto_id) ?? null) })),
  );

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
  const lleva = (id: number) => carrito.reduce((s, r) => s + (r.producto_id === id ? r.cantidad : 0), 0);

  // La clave del pedido cambia con cada cambio, como el borrador de Pepe: tocar dos veces «Pedir por
  // WhatsApp» con lo mismo no lo guarda dos veces.
  let clave = crypto.randomUUID();
  function cambiarCarrito(nuevo: EnCarrito[]) {
    carrito = nuevo;
    clave = crypto.randomUUID();
    if (!muestra) guardarCarrito(slug, carrito);
  }

  // El pedido mandado se recuerda en el celular; el de la vista previa, no.
  function recordarHecho(h: Hecho | null) {
    if (!muestra) guardarHecho(slug, h);
  }

  // Lo mismo con las mismas opciones y nota se suma en un renglón (hasta 99).
  function sumar(lista: EnCarrito[], r: Renglon, p: Producto): EnCarrito[] {
    const igual = lista.findIndex((x) => mismoRenglon(x, r));
    if (igual === -1) return [...lista, { ...r, nombre: p.nombre, nombre_en: p.nombre_en, precio: precioUnitario(p, r.opciones) }];
    return lista.map((x, i) => (i === igual ? { ...x, cantidad: Math.min(99, x.cantidad + r.cantidad) } : x));
  }

  // El «+» ya no suma de una vez: siempre abre el producto, donde se agrega («Tu menú en línea», 12 de
  // noviembre de 2026, el developer: «si no, está medio confuso así»).
  function abrirProducto(p: Producto, desde: HTMLElement | null) {
    abrir({ tipo: 'producto', producto: p, editando: null, desde });
  }

  // Al agregar desde el menú o el asistente, cuando el producto ya se cerró, un globo arriba de la barra de abajo dice
  // que ya está en tu pedido (2 s), como en la maqueta; desde Tu pedido no hace falta: ahí se ve.
  let globo = $state<string | null>(null);
  let relojGlobo: ReturnType<typeof setTimeout> | undefined;
  function avisarGlobo(texto: string) {
    clearTimeout(relojGlobo);
    relojGlobo = setTimeout(
      () => {
        globo = texto;
        relojGlobo = setTimeout(() => (globo = null), 2000);
      },
      quieto() ? 0 : 300,
    );
  }

  function alAgregar(p: Producto, r: Renglon, editando: number | null) {
    const resto = editando === null ? carrito : carrito.filter((_, i) => i !== editando);
    const lista = sumar(resto, r, p);
    // Al cambiar un renglón, se queda en su lugar.
    if (editando !== null && lista.length > resto.length) lista.splice(editando, 0, lista.pop()!);
    cambiarCarrito(lista);
    // Un pedido nuevo: el que ya se mandó deja de enseñarse (como en la maqueta).
    if (hecho) {
      hecho = null;
      recordarHecho(null);
    }
    if (!conPedido) avisarGlobo(enSuLengua(p.nombre, p.nombre_en, lengua) + t.enTuPedido);
    cerrar();
  }

  // Sin nada, Tu pedido se queda abierto con su carita.
  function alCantidad(i: number, cambio: number) {
    const r = carrito[i];
    const cantidad = r.cantidad + cambio;
    cambiarCarrito(cantidad < 1 ? carrito.filter((_, j) => j !== i) : carrito.map((x, j) => (j === i ? { ...x, cantidad: Math.min(99, cantidad) } : x)));
  }

  function abrirRenglon(i: number, desde: HTMLElement) {
    const p = productos.get(carrito[i].producto_id);
    if (p) abrir({ tipo: 'producto', producto: p, editando: i, desde });
  }

  // «Tu pedido»: lo que escribe, recordado en este celular para la próxima vez (en la vista previa, las cajas vacías).
  const recordadoCliente = muestra ? { nombre: '', telefono: '', direccion: '', referencias: '' } : leerCliente();
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

  // La revisión de Cloudflare corre al abrirse «Tu pedido» (cuando aparece su hueco), no al tocar el
  // botón: así el toque solo espera al Worker (lib/turnstile.ts, «Por adelantado»).
  // En la vista previa no corre: ahí nada se manda.
  let revision: Adelantado | null = null;
  $effect(() => {
    const donde = hueco;
    if (!donde || muestra) return;
    const r = adelantarToken(donde, untrack(() => lengua));
    revision = r;
    return () => {
      r.soltar();
      if (revision === r) revision = null;
    };
  });

  // El toque único: guarda el pedido y abre WhatsApp con lo que guardó Postgres.
  async function hacer() {
    const rev = revision;
    if (!menu || ocupado || !rev) return;
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
        token = await rev.tomar();
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
          // Desde el 12 de noviembre de 2026 el teléfono se pide también para llevar.
          cliente_telefono: cliente.telefono,
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
        // Primero se apunta en el celular (por si el navegador cambia de página al abrir WhatsApp) y
        // enseguida, sin esperar nada más, se abre WhatsApp: Safari solo lo deja cerca del toque. Si no
        // lo dejó, queda «Falta un paso» con su botón; el pedido ya está guardado y en el panel.
        const ids = carrito.map((r) => ({ producto_id: r.producto_id, opciones: r.opciones }));
        hecho = { pedido: respuesta, ids, fecha: menu.ahora.fecha, enviado: true };
        guardarHecho(slug, hecho);
        cambiarCarrito([]);
        if (!abrirWhatsApp(enlaceWhatsApp(menu.restaurante.telefono ?? '', mensajeWhatsApp(respuesta)))) {
          hecho = { ...hecho, enviado: false };
          guardarHecho(slug, hecho);
        }
        cliente.pagaCon = '';
      } else if (respuesta.motivo === 'no_recibe') {
        avisoPedido = { texto: t.noRecibimos };
        rev.renovar();
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
        rev.renovar();
        await cargar(true);
      }
    } catch (error) {
      if (!(error instanceof NoSeMando)) console.error('[menu] el pedido falló:', error);
      const mensaje = error instanceof NoSeMando ? error.message : t.noSeMando;
      avisoPedido = { texto: enSuLenguaElNo(mensaje, lengua) };
      limite = esLimite(mensaje);
      // El token ya se gastó (o no salió): otro por adelantado para el siguiente toque.
      if (!limite) rev.renovar();
    } finally {
      ocupado = false;
    }
  }

  function alEnviar() {
    if (!hecho) return;
    hecho = { ...hecho, enviado: true };
    guardarHecho(slug, hecho);
  }

  // La vista previa del panel: «Mandando tu pedido…» y luego «Pedido enviado», como en el teléfono de la maqueta, sin la
  // revisión de Cloudflare, sin el Worker y sin WhatsApp. Nada se guarda. El número es el de muestra de la maqueta.
  const PEDIDO_DE_MUESTRA = 27;
  async function simularPedido() {
    if (!menu || ocupado) return;
    avisoPedido = null;
    limite = false;
    ocupado = true;
    await new Promise((listo) => setTimeout(listo, quieto() ? 300 : 1100));
    const dom = tipo === 'domicilio';
    const van = carrito.filter((r) => productos.has(r.producto_id));
    const renglones: Guardado['renglones'] = van.map((r) => {
      const p = productos.get(r.producto_id)!;
      const opciones = p.grupos.flatMap((g) =>
        g.opciones.filter((o) => r.opciones.includes(o.id)).map((o) => ({ grupo: g.nombre, opcion: o.nombre, precio_extra: o.precio_extra })),
      );
      return { nombre: p.nombre, cantidad: r.cantidad, importe: centavos(precioUnitario(p, r.opciones) * r.cantidad), opciones, nota: r.nota || null };
    });
    const pedido: Guardado = {
      numero: PEDIDO_DE_MUESTRA,
      tipo,
      cliente_nombre: cliente.nombre.trim(),
      cliente_telefono: cliente.telefono.replace(/[\s().-]/g, ''),
      cliente_direccion: dom ? cliente.direccion.trim() : null,
      cliente_referencias: dom ? cliente.referencias.trim() || null : null,
      paga_con: dom && cliente.pagaCon.trim() ? Number(cliente.pagaCon.trim()) : null,
      total: centavos(renglones.reduce((s, r) => s + r.importe, 0)),
      renglones,
    };
    hecho = { pedido, ids: van.map((r) => ({ producto_id: r.producto_id, opciones: r.opciones })), fecha: menu.ahora.fecha, enviado: true };
    cambiarCarrito([]);
    cliente.pagaCon = '';
    ocupado = false;
  }

  // «Pedido enviado» se queda hasta que sale de Tu pedido (a Menú, al asistente o con «atrás»); «Falta un paso» se
  // queda hasta que lo manda, porque su botón es el que abre WhatsApp.
  const conPedido = $derived(pila.some((e) => e.tipo === 'pedido'));
  $effect(() => {
    if (conPedido || !hecho?.enviado) return;
    hecho = null;
    recordarHecho(null);
  });

  // Por qué no se reciben pedidos: se ve al abrir Pedido.
  const avisoPedidos = $derived.by((): { icono: 'reloj' | 'apagado'; texto: string } | null => {
    if (!menu || recibe) return null;
    const e = menu.estado;
    if (!menu.pedidos_pausados && menu.restaurante.telefono && e && !e.abierto) {
      const dia = menu.horario.find((h) => h.dia === e.abre.dia);
      if (dia) return { icono: 'reloj', texto: t.recibimos(dia.abre, dia.cierra) };
    }
    return { icono: 'apagado', texto: t.noRecibimos };
  });

  function aparece(_el: Element) {
    if (quieto()) return { duration: 0 };
    return { duration: 180, css: (x: number) => `opacity: ${x}` };
  }

  // ─── Lo de abajo («Tu menú en línea»): Menú, Pedido y Asistente ───
  // Sin WhatsApp no sale Pedido y sin asistente no sale Asistente; si solo queda Menú, no sale nada. Si el
  // asistente se queda sin IA con su vista abierta, su pestaña se queda hasta que salga de ella (la vista lo avisa).
  const pestanas = $derived.by((): Pestana[] => {
    if (!menu || muestra === 'barra') return [];
    const lista: Pestana[] = ['menu'];
    if (menu.restaurante.telefono) lista.push('pedido');
    if (menu.asistente_contesta || conPlatica) lista.push('asistente');
    return lista.length > 1 ? lista : [];
  });
  const pestanaActiva = $derived.by((): Pestana => {
    if (pila.some((e) => e.tipo === 'asistente')) return 'asistente';
    if (conPedido) return 'pedido';
    return 'menu';
  });

  function alPestana(p: Pestana) {
    if (p === 'menu') return regresarA([]);
    if (p === pestanaActiva) return;
    // Una pestaña sustituye a la otra: lo que hubiera encima se reemplaza.
    const nueva: Encima = p === 'asistente' ? { tipo: 'asistente' } : { tipo: 'pedido' };
    if (pila.length) regresarA([nueva]);
    else abrir(nueva);
  }

  // ─── Ajustes y la lupa (con el logo al centro) ───
  let lupaAbierta = $state(false);
  let campoLupa = $state<HTMLInputElement>();

  function alLupa() {
    lupaAbierta = !lupaAbierta;
    if (lupaAbierta) setTimeout(() => campoLupa?.focus({ preventScroll: true }), 120);
  }

  // La lupa de la barra del asistente: regresa al menú y abre ahí la búsqueda.
  function buscarDesdeVista() {
    regresarA([]);
    if (!lupaAbierta) alLupa();
  }

  // ─── El asistente (parte 6c) ───
  // La plática no vive en su hoja: si ella la cierra mientras piensa, la respuesta llega igual.
  const platica = new Platica(slug, !muestra);
  const conPlatica = $derived(pila.some((e) => e.tipo === 'asistente'));

  // Todos los productos, en el orden del menú (sin el orden que eligió el cliente).
  const enOrden = () => (menu?.categorias ?? []).flatMap((c) => c.productos);

  async function preguntarAlAsistente(pregunta: string, hueco: HTMLElement) {
    // En la vista previa contesta de muestra, con las tarjetas de sus dos primeros productos con foto: así Don Chuy ve
    // cómo se ven, sin gastar de su sobre.
    if (muestra) {
      const conFoto = enOrden().filter((p) => p.imagen_ruta).slice(0, 2).map((p) => p.id);
      return platica.simular(pregunta, t.respuestaDeMuestra, conFoto);
    }
    const motivo = await platica.preguntar(pregunta, { lengua, moneda, revision: () => pedirToken(hueco, lengua) });
    // Se acabó su sobre a media plática: la caja se apaga ya y el menú se vuelve a leer.
    if (motivo === 'sin_ia' && menu) {
      menu = { ...menu, asistente_contesta: false };
      cargar(true);
    }
  }

  // ─── El teléfono de la vista previa (parte C2) ───
  // El modo Producto del panel: un producto abierto que cambia al momento con sus formas; si Don Chuy lo cierra, una
  // forma nueva lo vuelve a abrir, y al regresar a Tu menú se cierra. Se elige solo: el primero del menú con opciones y
  // foto (si no hay, con opciones; luego con foto; luego el primero).
  let modoPanel: ModoPanel = 'menu';
  let prodConBarra = $state(false);

  function abrirDeMuestra() {
    const todos = enOrden();
    const p = todos.find((x) => x.grupos.length && x.imagen_ruta) ?? todos.find((x) => x.grupos.length) ?? todos.find((x) => x.imagen_ruta) ?? todos[0];
    if (p) abrir({ tipo: 'producto', producto: p, editando: null, desde: null });
  }

  function alModo(m: ModoPanel) {
    if (!enTelefono) return;
    modoPanel = m;
    pila = [];
    if (m === 'producto' && menu) abrirDeMuestra();
  }

  // Al elegir una forma, el teléfono va a esa pieza (lib/muestra.ts); los colores y el tema no lo mueven.
  async function alPintar(p: Pintura, cambio: Cambio | null) {
    pintura = p;
    if (!cambio || !enTelefono || !raiz || !menu) return;
    if (cambio.startsWith('producto_') && modoPanel === 'producto' && encima?.tipo !== 'producto') abrirDeMuestra();
    await tick();
    irAPieza(raiz, cambio);
  }

  // El panel sabe si hay algo abierto en el teléfono: su Escape cierra primero sus ventanas y luego lo del teléfono.
  $effect(() => {
    if (enTelefono) avisarAlPanel({ fragmentless: 'encima', abierto: pila.length > 0 });
  });

  // El reloj del teléfono (el «14:32» de la maqueta): la hora del restaurante, que llega con el menú, y sigue andando.
  let reloj = $state('');
  $effect(() => {
    const hora = enTelefono ? menu?.ahora.hora : null;
    if (!hora) return;
    const [h, m] = hora.split(':').map(Number);
    const leida = performance.now();
    const poner = () => {
      const min = (h * 60 + m + Math.floor((performance.now() - leida) / 60000)) % 1440;
      reloj = `${Math.floor(min / 60)}:${String(min % 60).padStart(2, '0')}`;
    };
    poner();
    const cada = setInterval(poner, 10000);
    return () => clearInterval(cada);
  });

  // ─── Las categorías al bajar ───
  let activa = $state<number | null>(null);
  let pausaHasta = 0;
  // Lo que tapan las categorías pegadas arriba: cambia con su forma (las pestañas, 49; los círculos, más).
  let navCategorias = $state<HTMLElement>();
  const altoCategorias = () => navCategorias?.offsetHeight ?? 49;

  $effect(() => {
    if (activa === null || !categorias.some((c) => c.id === activa)) activa = categorias[0]?.id ?? null;
  });

  // La marcada es la de la sección que está debajo de las pestañas; hasta abajo, la última.
  function alBajar() {
    if (consulta || Date.now() < pausaHasta || !categorias.length) return;
    const alFondo = window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 2;
    let actual = categorias[0].id;
    for (const el of document.querySelectorAll<HTMLElement>('[data-seccion]')) {
      if (el.getBoundingClientRect().top <= altoCategorias() + 8) actual = Number(el.dataset.seccion);
    }
    activa = alFondo && window.scrollY > 0 ? categorias[categorias.length - 1].id : actual;
  }

  function irA(id: number) {
    const el = document.querySelector<HTMLElement>(`[data-seccion="${id}"]`);
    if (!el) return;
    activa = id;
    pausaHasta = Date.now() + 900;
    // Como en la maqueta («Bajando»): la sección queda 4 abajo de las pestañas.
    window.scrollTo({ top: el.getBoundingClientRect().top + window.scrollY - altoCategorias() - 4, behavior: 'smooth' });
  }

  // ─── La página ───
  let raiz = $state<HTMLElement>();

  // Mientras se ve el esqueleto, la página y lo de arriba del celular van de sus colores: los que recuerda, o el blanco
  // y el gris de la barra del general.
  const conEsqueleto = $derived(paso === 'leyendo' && !menu && muestra === null);

  $effect(() => {
    document.title = menu?.restaurante.nombre ?? (paso === 'apagado' ? t.apagado : 'Menú');
    document.documentElement.lang = lengua;
    document.documentElement.style.background = conEsqueleto
      ? (recuerdo?.fondo ?? '#ffffff')
      : (fondo ?? (tema === 'oscuro' ? '#0f0f0f' : '#ffffff'));
    document
      .querySelector('meta[name="theme-color"]')
      ?.setAttribute(
        'content',
        conEsqueleto
          ? (recuerdo?.barra?.fondo ?? recuerdo?.fondo ?? '#f4f4f4')
          : (colorBarra ?? color ?? (tema === 'oscuro' ? '#1f1f1f' : '#121212')),
      );
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
    // Cada foto late en su lugar hasta que llega.
    const soltarFotos = raiz ? esperarFotos(raiz) : () => {};
    const reloj = setInterval(() => cargar(true), CADA);
    const alVolver = () => {
      if (!document.hidden) cargar(true);
    };
    document.addEventListener('visibilitychange', alVolver);
    const dejarDeEscuchar = muestra
      ? escucharPanel({
          alPintar,
          alRecargar: () => cargar(true),
          alModo,
          alCerrar: () => {
            if (encima) cerrar();
          },
        })
      : () => {};
    return () => {
      clearInterval(reloj);
      document.removeEventListener('visibilitychange', alVolver);
      dejarDeEscuchar();
      soltarFotos();
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

{#if conEsqueleto}
  <Esqueleto {recuerdo} texto={t.cargando} />
{/if}

<div
  class="menu"
  class:f-con-fondo={!!fondo}
  class:f-con-barra={!!colorBarra}
  class:f-info-abajo={formas.info_lugar === 'abajo'}
  data-tema={tema}
  style={estiloMenu(color, colorBarra, fondo)}
  class:f-con-prod={enTelefono && encima?.tipo === 'producto'}
  class:f-prod-con-barra={enTelefono && encima?.tipo === 'producto' && prodConBarra}
  bind:this={raiz}
  inert={muestra === 'barra'}
>
  {#if paso === 'apagado'}
    <Aviso titulo={t.apagado} texto={t.apagadoTexto} />
  {:else if paso === 'sinred'}
    <Aviso titulo={t.sinRed} texto={t.sinRedTexto} boton={t.reintentar} alBoton={() => cargar()} />
  {:else if menu}
    {@const r = menu.restaurante}
    {@const conCarteles = muestra !== 'barra' && carteles.length > 0}
    {@const estadoBarra = textoEstado(menu.estado, lengua)}
    {@const abiertoBarra = !!menu.estado?.abierto}
    <!-- La barra del menú; la del asistente es la misma, y su lupa regresa al menú para buscar ahí. -->
    {#snippet barra(enVista: boolean)}
      <Barra
        nombre={r.nombre}
        logo={r.logo_ruta}
        estado={estadoBarra}
        abierto={abiertoBarra}
        {lengua}
        {moneda}
        {conDolares}
        {formas}
        {conCarteles}
        {t}
        arriba={muestra === 'barra' ? '14px' : 'calc(14px + var(--arriba-seguro))'}
        lupaAbierta={enVista ? false : lupaAbierta}
        ajustesAbierto={encima?.tipo === 'ajustes'}
        alLengua={elegirLengua}
        alMoneda={elegirMoneda}
        alInfo={(desde) => abrir({ tipo: 'info', desde })}
        alLupa={enVista ? buscarDesdeVista : alLupa}
        alAjustes={() => abrir({ tipo: 'ajustes' })}
      />
    {/snippet}
    {#snippet barraDeVista()}{@render barra(true)}{/snippet}
    <div
      class="columna"
      class:f-con-app={pestanas.length > 0}
      class:f-con-app-chica={pestanas.length > 0 && !formas.abajo_con_nombres}
      bind:this={columna}
    >
      {@render barra(false)}

      {#if muestra === 'barra'}
        <Categorias categorias={menu.categorias} activa={menu.categorias[0]?.id ?? null} forma={formas.categorias} {lengua} {t} pegadas={false} />
      {:else}
        <!-- Las tres piezas de en medio, en el orden que eligió. Mientras busca, solo la búsqueda. -->
        {#each formas.orden as pieza (pieza)}
          {#if pieza === 'carteles' && conCarteles && !consulta}
            <Carteles
              {carteles}
              {formas}
              estado={textoEstado(menu.estado, lengua)}
              abierto={!!menu.estado?.abierto}
              {lengua}
              {moneda}
              {t}
              alInfo={(desde) => abrir({ tipo: 'info', desde })}
              alProducto={abrirProducto}
            />
          {:else if pieza === 'busqueda'}
            {#if formas.barra === 'centro'}
              <div class="f-lupa-caja" class:abierta={lupaAbierta || !!consulta} inert={!lupaAbierta && !consulta}>
                <div><Buscador bind:busqueda bind:campo={campoLupa} {orden} blanca {t} alOrdenar={(i) => (orden = i)} /></div>
              </div>
            {:else if formas.busqueda === 'tarjeta'}
              <TarjetaBusca bind:busqueda {orden} {t} alOrdenar={(i) => (orden = i)} />
            {:else}
              <Buscador bind:busqueda {orden} blanca={formas.busqueda === 'blanca'} {t} alOrdenar={(i) => (orden = i)} />
            {/if}
          {:else if pieza === 'categorias' && !consulta}
            <Categorias {categorias} {activa} forma={formas.categorias} {lengua} {t} bind:nav={navCategorias} alElegir={irA} />
          {/if}
        {/each}

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
                  alAbrir={(desde) => abrirProducto(h.p, desde)}
                  alMas={recibe ? (desde) => abrirProducto(h.p, desde) : null}
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
          <div
            class="contenido"
            class:f-intercalado={formas.productos === 'intercalado'}
            class:f-dos={formas.productos === 'dos_en_dos'}
            class:f-clasicas={formas.productos === 'clasicas'}
          >
            {#each categorias as c (c.id)}
              {@const nombre = enSuLengua(c.nombre, c.nombre_en, lengua)}
              <section class="seccion" data-seccion={c.id}>
                <!-- El título va aparte de cómo se acomodan los productos: con su ícono, solo el nombre, o grande con la
                     raya del color que se desvanece. -->
                {#if formas.titulos === 'raya'}
                  <h2 class="f-titulo-grande">{nombre}</h2>
                  <div class="f-raya-titulo"></div>
                {:else}
                  <h2 class="seccion-titulo">{#if formas.titulos === 'icono'}<Icono categoria={c.icono} tamano={20} />{/if}{nombre}</h2>
                {/if}
                {#if formas.productos === 'dos_en_dos' || formas.productos === 'clasicas'}
                  <div class="f-rejilla">
                    {#each c.productos as p (p.id)}
                      <TarjetaProducto
                        producto={p}
                        forma={formas.productos}
                        icono={c.icono}
                        {lengua}
                        {moneda}
                        {t}
                        lleva={lleva(p.id)}
                        alAbrir={(desde) => abrirProducto(p, desde)}
                        alMas={recibe ? (desde) => abrirProducto(p, desde) : null}
                      />
                    {/each}
                  </div>
                {:else}
                  {#each c.productos as p (p.id)}
                    <Fila
                      producto={p}
                      {lengua}
                      {moneda}
                      {t}
                      lleva={lleva(p.id)}
                      alAbrir={(desde) => abrirProducto(p, desde)}
                      alMas={recibe ? (desde) => abrirProducto(p, desde) : null}
                    />
                  {/each}
                {/if}
              </section>
            {/each}
          </div>
        {/if}
      {/if}
    </div>

    {#if pestanas.length}
      <Abajo {pestanas} activa={pestanaActiva} cuantos={recibe ? cuantos : 0} {formas} {t} alElegir={alPestana} />
    {/if}

    {#if conPlatica}
      <VistaAsistente
        {platica}
        {menu}
        {productos}
        {lengua}
        {moneda}
        {tema}
        {color}
        {fondo}
        {formas}
        {t}
        barra={barraDeVista}
        alPreguntar={preguntarAlAsistente}
        alAbrirProducto={abrirProducto}
      />
    {/if}

    {#if conPedido}
      <VistaPedido
        renglones={vistaCarrito}
        {productos}
        {iconos}
        {lengua}
        {moneda}
        {formas}
        {t}
        barra={barraDeVista}
        cerrado={avisoPedidos}
        conAsistente={pestanas.includes('asistente')}
        haceEnvios={r.hace_envios}
        tipoCambio={r.tipo_cambio_usd}
        telefono={r.telefono ?? ''}
        bind:tipo
        bind:cliente
        aviso={avisoPedido}
        {limite}
        {ocupado}
        bind:hueco
        {hecho}
        {alCantidad}
        alAbrirRenglon={abrirRenglon}
        alHacer={muestra ? simularPedido : hacer}
        deMuestra={!!muestra}
        {alEnviar}
        alMenu={() => alPestana('menu')}
        alAsistente={() => alPestana('asistente')}
      />
    {/if}

    <!-- La vista del producto tapa todo, la barra de abajo también: desde el menú, la plática o Tu pedido. Va en un
         {#each} de uno para que, mientras se va, siga leyendo su renglón, que ya salió de la pila. -->
    {#each encima?.tipo === 'producto' ? [encima] : [] as abierto (abierto)}
      <VistaProducto
        producto={abierto.producto}
        {formas}
        {lengua}
        {moneda}
        {t}
        {recibe}
        inicial={abierto.editando === null ? null : (carrito[abierto.editando] ?? null)}
        desde={abierto.desde}
        alAgregar={(r) => alAgregar(abierto.producto, r, abierto.editando)}
        alCerrar={cerrar}
        vivas={enTelefono}
        bind:barraArriba={prodConBarra}
      />
    {/each}
    {#if encima?.tipo === 'info'}
      <VentanaInfo {menu} {t} {lengua} desde={encima.desde} alCerrar={cerrar} />
    {/if}
    {#if encima?.tipo === 'ajustes'}
      <Ajustes {lengua} {moneda} {conDolares} {t} alLengua={elegirLengua} alMoneda={elegirMoneda} alCerrar={cerrar} />
    {/if}

    {#if globo}
      <div
        class="globo"
        class:f-sobre-app={formas.abajo === 'barra'}
        class:f-sobre-pildora={formas.abajo === 'pildora'}
        class:f-sobre-chica={!formas.abajo_con_nombres}
        role="status"
        transition:aparece
      >
        <Icono nombre="check" tamano={14} grosor={2} />{globo}
      </div>
    {/if}

    {#if enTelefono && reloj}
      <div class="tel-reloj" aria-hidden="true">{reloj}</div>
    {/if}
  {/if}
</div>

<style>
  /* En la compu, el menú es una columna al centro, del ancho de un celular grande. */
  .columna {
    max-width: 520px;
    margin: 0 auto;
  }

  /* El globo de «· en tu pedido» (el de siempre; formas.css lo sube arriba de la barra de abajo). */
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
