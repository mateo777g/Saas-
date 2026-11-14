<!--
  «Crear anuncios» (se llamó «Crear contenido» hasta el 4 de noviembre de 2026, y el código conserva
  ese nombre; parte 7b-1 de la libreta 7; sus decisiones en planes/trabajo/7b/lista-7b.md).

  Por pasos desde el 13 nov 2026 (la idea del developer y sus 11 encuestas, en planes/trabajo/rediseno/crear-anuncios.md):
  1 Productos (la búsqueda grande de Mi menú y los productos grandes, que entran en cascada), 2 Tu anuncio (a la
  izquierda ¿Qué quieres decir?, Estilo y color e «Irá en el anuncio»; a la derecha el formato en tres celulares, fijos
  al bajar) y 3 Listo (la rejilla de puntitos grande al centro, luego tu anuncio ahí mismo, y «Lo que pediste» a un
  lado). Los pasos van al centro de la barra de arriba y los botones en la barra de abajo, la de guardar de Tu menú en
  línea: Continuar; Atrás y Generar anuncio; Nuevo anuncio, Otra vez, Ponerlo en mi menú y Descargar.

  Lo lee todo de Postgres con crear_contenido, al abrir, cada vez que realtime avisa de un cambio en
  sus anuncios, cada 30 segundos mientras uno se hace (por si se perdió un aviso) y al volver a la
  pestaña. Los estilos y sus reglas vienen del Worker. Las palabras que Don Chuy no escribe las escoge
  el paso de texto un momento después de que deja de cambiar los productos o el estilo, para no
  pagar una vuelta por cada producto que pica.
-->
<script lang="ts">
  import { onMount, untrack } from 'svelte';
  import { fade, fly } from 'svelte/transition';
  import BarraArriba from '../../diseno/BarraArriba.svelte';
  import Boton from '../../diseno/Boton.svelte';
  import BotonCuadro from '../../diseno/BotonCuadro.svelte';
  import CajaError from '../../diseno/CajaError.svelte';
  import { cascada } from '../../diseno/cascada';
  import Esqueleto from '../../diseno/Esqueleto.svelte';
  import GrupoCampos from '../../diseno/GrupoCampos.svelte';
  import Haz from '../../diseno/Haz.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import { vidrio } from '../../diseno/vidrio';
  import {
    anuncioVisto,
    cuantosLleva,
    datosQueVan,
    descargarAnuncio,
    escucharAnuncios,
    formatoDe,
    hacerAnuncio,
    leerCrearContenido,
    leerEstilosDeHoy,
    lugaresDe,
    pedirPalabras,
    pistaDe,
    sinAcentos,
    textoSinAnuncios,
    vacioDe,
    vaCon,
    type DatosCrearContenido,
    type EstiloDeHoy,
    type Formato,
    type LugarListo,
    type NoSePuede,
    type Pedido,
    type Resultado as ResultadoDeAnuncio,
  } from '../../lib/crearContenido';
  import { ponerEnMiMenu } from '../../lib/biblioteca';
  import { esDeRed, Fallo, mensajeDeError, SIN_CONEXION } from '../../lib/errores';
  import { anchos, filasDeLaUltimaVez, recordarFilas } from '../../lib/esqueletos';
  import { diaYMes, pesos, plural } from '../../lib/formato';
  import { urlFoto } from '../../lib/fotos';
  import type { Sucursal } from '../../lib/gerente';
  import CajaSucursales from './CajaSucursales.svelte';
  import Celulares from './crearContenido/Celulares.svelte';
  import PasoListo, { type LoQueSeVe } from './crearContenido/PasoListo.svelte';
  import Pasos, { type Paso } from './crearContenido/Pasos.svelte';
  import VentanaColor from './crearContenido/VentanaColor.svelte';
  import VentanaEstilos from './crearContenido/VentanaEstilos.svelte';
  import VentanaPalabra from './crearContenido/VentanaPalabra.svelte';

  let {
    sucursal,
    sucursales,
    alElegir,
    alIr,
  }: {
    sucursal: Sucursal;
    sucursales: Sucursal[];
    alElegir: (sucursal: Sucursal) => void;
    // «Editar tus datos» abre Tu restaurante.
    alIr: (vista: 'restaurante') => void;
  } = $props();

  const MAXIMO_PRODUCTOS = 5;
  const YA_NO_ESTA = 'Este estilo ya no está. Elige otro.';

  let datos = $state<DatosCrearContenido | null>(null);
  let errorLectura = $state<string | null>(null);
  let estilos = $state<EstiloDeHoy[] | null>(null);
  let errorEstilos = $state<string | null>(null);

  // En qué paso va. Entra en el 1; si al entrar hay uno haciéndose o uno terminado sin ver, en el 3.
  let paso = $state<Paso>(1);

  // Lo que va armando: los productos en el orden en que los picó (el 1 va en el titular), el
  // formato (entra con el post al centro), el estilo, su mensaje y el color de este anuncio (null = el de su marca).
  let elegidos = $state<number[]>([]);
  let formato = $state<Formato>('post');
  let estiloId = $state<number | null>(null);
  let mensaje = $state('');
  let color = $state<string | null>(null);
  let busqueda = $state('');
  let nota = $state<string | null>(null);
  let error = $state<string | null>(null);

  // Las palabras del paso de texto y las que cambió él (por llave).
  let palabras = $state<Record<string, string> | null>(null);
  let cambiadas = $state<Record<string, string>>({});
  let escogiendo = $state(false);
  let falloPalabras = $state<string | null>(null);

  let ventana = $state<null | { tipo: 'estilos' } | { tipo: 'color' } | { tipo: 'palabra'; lugar: LugarListo }>(null);

  let se = $state<LoQueSeVe>({ fase: 'vacio' });
  // El anuncio del paso 3, como lo guardó Postgres («Lo que pediste»).
  let pedido = $state<ResultadoDeAnuncio | null>(null);
  // El último terminado que enseña: «Otra vez» lo repite tal cual.
  let mostrado = $state<ResultadoDeAnuncio | null>(null);
  let enviando = $state(false);

  // El que se apagó con la vista abierta se queda a la vista, con su aviso, hasta que elija otro.
  let perdido = $state<EstiloDeHoy | null>(null);
  const estilo = $derived(estilos?.find((e) => e.id === estiloId) ?? (perdido?.id === estiloId ? perdido : null));
  const productos = $derived(datos?.productos ?? []);
  const restaurante = $derived(datos?.restaurante ?? null);
  const marca = $derived(restaurante?.color ?? null);
  // Los que van: los primeros, hasta el máximo del estilo (desde los pasos, el estilo siempre los lleva todos).
  const van = $derived(
    elegidos
      .slice(0, estilo?.maximo ?? MAXIMO_PRODUCTOS)
      .map((id) => productos.find((p) => p.id === id))
      .filter((p) => p !== undefined),
  );
  const lugares = $derived(estilo ? lugaresDe(estilo, van.length) : []);
  const chips = $derived(lugares.filter((l) => !l.vacio));
  const colorDelAnuncio = $derived(estilo?.color ? (color ?? marca) : null);

  // Con tope 0 o el sobre acabado tampoco se escogen las palabras: el paso de texto gasta.
  const sinIa = $derived(datos && !datos.ia.puede ? datos.ia : null);
  const aviso = $derived.by(() => {
    if (!datos) return null;
    // Si ya hizo los que le caben gana ese aviso, aunque también se haya acabado el dinero.
    if (datos.de > 0 && datos.quedan <= 0) return `Ya hiciste tus ${datos.de} anuncios de este mes. Vuelven el ${diaYMes(datos.vuelve)}.`;
    if (sinIa) return textoSinAnuncios(sinIa);
    return null;
  });

  const largo = $derived([...mensaje].length);
  const pasado = $derived(!!estilo && estilo.mensaje > 0 && largo > estilo.mensaje);
  const haciendo = $derived(se.fase === 'haciendo' || enviando);
  const faltanPalabras = $derived(lugares.length > 0 && !palabras);
  const sinEstilos = $derived(estilos !== null && estilos.length === 0);

  const listo = $derived(
    !!estilo &&
      !!datos &&
      vaCon(estilo, elegidos.length) &&
      !pasado &&
      !faltanPalabras &&
      !aviso &&
      error !== YA_NO_ESTA &&
      !haciendo,
  );

  // Si el estilo no lleva los productos que eligió (solo pasa si se apagó o cambió de reglas con la vista abierta).
  const notaDelEstilo = $derived.by((): string | null => {
    const n = elegidos.length;
    if (!estilo || !n) return null;
    if (n < estilo.minimo) return `Este estilo es para combos: pica ${estilo.minimo} o ${estilo.maximo}.`;
    if (n > estilo.maximo) return `Este estilo lleva ${estilo.maximo === 1 ? '1 producto' : `hasta ${estilo.maximo} productos`}: regresa a Productos y quita ${n - estilo.maximo}.`;
    return null;
  });

  const visibles = $derived.by(() => {
    const b = sinAcentos(busqueda.trim());
    return b ? productos.filter((p) => sinAcentos(p.nombre).includes(b)) : productos;
  });

  // Los elegidos por su nombre, para la barra de abajo: «Torta de pastor, Taco al pastor y Burrito al pastor».
  const nombresElegidos = $derived.by(() => {
    const n = elegidos.map((id) => productos.find((p) => p.id === id)?.nombre).filter((x) => x !== undefined);
    return n.length > 1 ? `${n.slice(0, -1).join(', ')} y ${n[n.length - 1]}` : (n[0] ?? '');
  });

  // «Irá en el anuncio»: su mensaje (o lo que sale vacío, en gris) y los datos de su restaurante.
  const linea = $derived.by((): { texto: string; vacio: boolean }[] => {
    if (!estilo || !restaurante) return [];
    const partes: { texto: string; vacio: boolean }[] = [];
    if (estilo.mensaje > 0) {
      if (mensaje.trim()) partes.push({ texto: mensaje.trim(), vacio: false });
      else {
        const v = vacioDe(estilo, van, restaurante, palabras);
        if (v) partes.push({ texto: v, vacio: true });
      }
    }
    for (const d of datosQueVan(estilo, formato, restaurante, van)) partes.push({ texto: d, vacio: false });
    return partes;
  });

  // Los nombres de los lugares de las palabras, si caben: con más de 3 palabras se explican solas.
  function nombreDeGrupo(lugar: LugarListo, cuantos: number): string {
    if (lugar.cuando !== 'por_producto' || cuantos < 2) return lugar.nombre;
    const [articulo, ...resto] = lugar.nombre.split(' ');
    const sustantivo = resto.join(' ');
    const plural = /[aeiouáéíóú]$/i.test(sustantivo) ? `${sustantivo}s` : `${sustantivo}es`;
    return `${articulo === 'El' ? 'Los' : articulo === 'La' ? 'Las' : articulo} ${plural}`;
  }
  function tituloDeLugar(lugar: LugarListo): string {
    const p = lugar.producto ? van[lugar.producto - 1] : null;
    return p ? `${lugar.nombre} de ${p.nombre}` : lugar.nombre;
  }
  const palabraDe = (lugar: LugarListo) => cambiadas[lugar.llave] ?? palabras?.[lugar.llave] ?? '';

  // Los «no» del Worker ya vienen en español; los de Postgres, como siempre.
  const mensajeDe = (e: unknown) => (e instanceof Fallo ? e.message : mensajeDeError(e));

  // ─── Leer ──────────────────────────────────────────────────────────────────────────────────

  let haciendoId: number | null = null;
  const llaveEsqueleto = $derived(`anuncio-productos-${sucursal.id}`);

  async function leer() {
    let nuevos: DatosCrearContenido;
    try {
      nuevos = await leerCrearContenido(sucursal.id);
    } catch (e) {
      // Con algo ya en pantalla se queda; la primera vez, la caja de error.
      if (!datos) errorLectura = esDeRed(e) ? SIN_CONEXION : mensajeDeError(e);
      return;
    }
    const primera = datos === null;
    errorLectura = null;
    datos = nuevos;
    recordarFilas(llaveEsqueleto, nuevos.productos.length);
    alLeer(nuevos.resultado);
    if (primera && se.fase !== 'vacio') paso = 3;
  }

  function alLeer(r: ResultadoDeAnuncio | null) {
    const antes = se;
    if (!r) {
      // Uno que ya enseñó terminado se queda mientras siga en la vista; uno que se hacía (el de
      // otro gerente de la sucursal) ya no es suyo: queda vacío.
      if (antes.fase === 'haciendo') {
        se = { fase: 'vacio' };
        pedido = null;
        if (paso === 3) paso = elegidos.length ? 2 : 1;
      }
      haciendoId = null;
      return;
    }
    pedido = r;
    if (r.estado === 'haciendo') {
      const desde = antes.fase === 'haciendo' && haciendoId === r.id ? antes.desde : Date.now() - r.segundos * 1000;
      haciendoId = r.id;
      se = { fase: 'haciendo', formato: r.formato, nombres: r.productos.map((p) => p.nombre).join(' + '), desde };
      return;
    }
    // Terminado y sin ver: si lo vio hacerse, por qué no salió; si no, que no se pudo hacer.
    const loVio = antes.fase === 'haciendo' && haciendoId === r.id;
    haciendoId = null;
    if (r.estado === 'listo' && r.ruta) {
      se = { fase: 'listo', formato: r.formato, id: r.id, ruta: r.ruta };
      mostrado = r;
    } else {
      se = { fase: 'fallo', formato: r.formato, motivo: loVio ? (r.motivo ?? 'no_salio') : 'cerrada' };
    }
    anuncioVisto(r.id);
  }

  // Con el que entra: el Clásico; si hoy no le sale, el primero de «Para todos». Con productos ya elegidos, el
  // primero de esos que los lleve.
  function deEntrada(lista: EstiloDeHoy[], n: number | null): EstiloDeHoy | undefined {
    const sirve = (e: EstiloDeHoy) => n === null || vaCon(e, n);
    return lista.find((e) => e.clave === 'clasico' && sirve(e)) ?? lista.find((e) => e.grupo === 'para_todos' && sirve(e)) ?? lista.find(sirve);
  }

  async function leerEstilos() {
    try {
      const lista = await leerEstilosDeHoy(sucursal.id);
      const antes = estilo;
      estilos = lista;
      errorEstilos = null;
      if (estiloId === null) {
        estiloId = deEntrada(lista, elegidos.length || null)?.id ?? lista[0]?.id ?? null;
      } else if (antes && !lista.some((e) => e.id === antes.id)) {
        perdido = antes;
        error = YA_NO_ESTA;
      }
    } catch (e) {
      errorEstilos = mensajeDe(e);
    }
  }

  // ─── Las palabras del paso de texto ────────────────────────────────────────────────────────

  // Se vuelven a escoger cuando cambian los productos que van o el estilo; las que cambió él se van,
  // porque los lugares ya son otros. El formato y el color no las tocan.
  const claveDePalabras = $derived(
    estilo && lugares.length > 0 && van.length >= estilo.minimo && !sinIa ? `${estilo.id}:${van.map((p) => p.id).join(',')}` : null,
  );
  let ultimaClave: string | null = null;
  let turno = 0;
  let espera = 0;
  $effect(() => {
    const clave = claveDePalabras;
    untrack(() => cambiarPalabras(clave));
  });

  function cambiarPalabras(clave: string | null) {
    if (clave === ultimaClave) return;
    ultimaClave = clave;
    cambiadas = {};
    palabras = null;
    falloPalabras = null;
    clearTimeout(espera);
    turno++;
    if (!clave) {
      escogiendo = false;
      return;
    }
    escogiendo = true;
    const mio = turno;
    espera = window.setTimeout(() => escoger(mio), 800);
  }

  async function escoger(mio: number) {
    if (!estilo) return;
    const ids = van.map((p) => p.id);
    try {
      const r = await pedirPalabras(sucursal.id, estilo.id, ids);
      if (mio !== turno) return;
      if (r.ok) palabras = r.palabras;
      else noSePuede(r);
    } catch (e) {
      if (mio !== turno) return;
      falloPalabras = mensajeDe(e);
    } finally {
      if (mio === turno) escogiendo = false;
    }
  }

  function reintentar() {
    ultimaClave = null;
    cambiarPalabras(claveDePalabras);
  }

  // ─── Hacer el anuncio ──────────────────────────────────────────────────────────────────────

  function noSePuede(r: NoSePuede) {
    if (r.motivo === 'estilo') {
      error = YA_NO_ESTA;
      leerEstilos();
    }
    // Sin IA, el límite, los que le caben o uno que ya se hace: lo dice la lectura.
    leer();
  }

  // true si el Worker lo aceptó (ya se está haciendo).
  async function mandar(p: Pedido): Promise<boolean> {
    enviando = true;
    error = null;
    try {
      const r = await hacerAnuncio(sucursal.id, p);
      if (r.ok) {
        await leer();
        return true;
      }
      noSePuede(r);
    } catch (e) {
      error = mensajeDe(e);
    } finally {
      enviando = false;
    }
    return false;
  }

  async function generar() {
    if (!listo || !estilo) return;
    const llaves = new Set(lugares.map((l) => l.llave));
    const todas = { ...(palabras ?? {}), ...cambiadas };
    const aceptado = await mandar({
      estiloId: estilo.id,
      formato,
      productos: van.map((p) => p.id),
      mensaje: estilo.mensaje > 0 ? mensaje.trim() : '',
      color: estilo.color ? color : null,
      palabras: Object.fromEntries(Object.entries(todas).filter(([llave]) => llaves.has(llave))),
    });
    if (aceptado) paso = 3;
  }

  // «Otra vez»: el mismo anuncio, con las mismas palabras (las suyas incluidas). Cuenta uno.
  function otraVez() {
    const r = mostrado;
    if (!r) return;
    mandar({
      estiloId: r.estilo_id,
      formato: r.formato,
      productos: r.productos.map((p) => p.id),
      mensaje: r.mensaje ?? '',
      color: r.color,
      palabras: r.palabras ?? {},
    });
  }

  // ─── Descargar y Ponerlo en mi menú (estaban en Resultado) ─────────────────────────────────

  let bajando = $state(false);
  let descargado = $state(false);
  let errorDescarga = $state<string | null>(null);

  async function descargar(id: number) {
    bajando = true;
    errorDescarga = null;
    try {
      await descargarAnuncio(id);
      descargado = true;
      setTimeout(() => (descargado = false), 1600);
    } catch (e) {
      errorDescarga = mensajeDe(e);
    } finally {
      bajando = false;
    }
  }

  // Los carteles que ya puso en su menú, mientras siga en la vista: el botón se queda en «En tu menú».
  let puestos = $state<number[]>([]);
  let poniendo = $state(false);
  let errorPoner = $state<string | null>(null);

  async function poner(id: number) {
    if (poniendo || puestos.includes(id)) return;
    poniendo = true;
    errorPoner = null;
    try {
      await ponerEnMiMenu(sucursal.id, id);
      puestos = [...puestos, id];
    } catch (e) {
      if (!(e instanceof Fallo)) console.error('[crear contenido] no se pudo poner el cartel en el menú:', e);
      errorPoner = mensajeDe(e);
    } finally {
      poniendo = false;
    }
  }

  // ─── Lo que se toca ────────────────────────────────────────────────────────────────────────

  function picar(id: number) {
    nota = null;
    error = null;
    if (elegidos.includes(id)) elegidos = elegidos.filter((x) => x !== id);
    else if (elegidos.length >= MAXIMO_PRODUCTOS) nota = `Máximo ${MAXIMO_PRODUCTOS} productos en un anuncio.`;
    else elegidos = [...elegidos, id];
  }

  const puede = (n: Paso) => n === 1 || (n === 2 ? elegidos.length > 0 : se.fase !== 'vacio');

  function ir(n: Paso) {
    if (!puede(n)) return;
    // Al paso 2 con un estilo que lleve los productos que eligió (encuesta 2): si el de ahorita no, el de entrada.
    if (n === 2 && estilos?.length && (!estilo || !vaCon(estilo, elegidos.length))) {
      const otro = deEntrada(estilos, elegidos.length);
      if (otro) {
        estiloId = otro.id;
        perdido = null;
        if (error === YA_NO_ESTA) error = null;
      }
    }
    paso = n;
  }

  // «Nuevo anuncio» (encuesta 11): al paso 1 sin nada elegido. El que se hace se queda en el 3.
  function nuevo() {
    elegidos = [];
    mensaje = '';
    color = null;
    busqueda = '';
    nota = null;
    error = null;
    formato = 'post';
    if (estilos?.length) estiloId = deEntrada(estilos, null)?.id ?? estiloId;
    perdido = null;
    if (se.fase !== 'haciendo') {
      se = { fase: 'vacio' };
      pedido = null;
    }
    errorDescarga = null;
    errorPoner = null;
    paso = 1;
  }

  function usarEstilo(e: EstiloDeHoy) {
    if (e.id !== estiloId) {
      estiloId = e.id;
      perdido = null;
      error = null;
    }
    ventana = null;
  }

  function usarColor(hex: string | null) {
    color = hex === null || hex === marca ? null : hex;
    error = null;
    ventana = null;
  }

  function usarPalabra(lugar: LugarListo, texto: string) {
    const nuevas = { ...cambiadas };
    if (texto === palabras?.[lugar.llave]) delete nuevas[lugar.llave];
    else nuevas[lugar.llave] = texto;
    cambiadas = nuevas;
    error = null;
    ventana = null;
  }

  // Los productos entran en cascada (diseno/cascada.ts) al llegar la primera vez y cada vez que se vuelve al paso 1;
  // al buscar o al releer, quietos.
  let rejilla = $state<HTMLDivElement>();
  let yaEntraron: HTMLElement | null = null;
  $effect(() => {
    const r = rejilla;
    if (!r || !datos || yaEntraron === r) return;
    yaEntraron = r;
    requestAnimationFrame(() => cascada(r));
  });

  // Lo que mide el paso 3 entre las dos barras: el anuncio se achica si no cabe.
  let anchoTres = $state(0);
  let altoTres = $state(0);

  // Mientras uno se hace, se vuelve a leer cada 30 segundos: si se perdió el aviso de realtime, o
  // si el trabajo se cayó y Postgres lo suelta a los 15 minutos, igual se entera.
  $effect(() => {
    if (se.fase !== 'haciendo') return;
    const cada = window.setInterval(leer, 30_000);
    return () => clearInterval(cada);
  });

  onMount(() => {
    leer();
    leerEstilos();
    const dejar = escucharAnuncios(sucursal.id, leer);
    const alVolver = () => {
      if (document.visibilityState === 'visible') leer();
    };
    document.addEventListener('visibilitychange', alVolver);
    return () => {
      dejar();
      document.removeEventListener('visibilitychange', alVolver);
      clearTimeout(espera);
    };
  });
</script>

<BarraArriba
  titulo="Crear anuncios"
  chipAntes
  estado={datos
    ? { texto: datos.de > 0 ? `Te quedan ${datos.quedan} de ${datos.de} este mes` : 'Sin anuncios este mes', vivo: true, hueco: datos.quedan <= 0 }
    : { texto: errorLectura ? 'No se pudo leer' : 'Leyendo…', vivo: false }}
>
  {#snippet junto()}
    <Pasos actual={paso} {puede} alIr={ir} />
  {/snippet}
  <CajaSucursales {sucursales} actual={sucursal} {alElegir} />
</BarraArriba>

{#if errorLectura && !datos}
  <main class="cuerpo-error"><CajaError mensaje={errorLectura} /></main>
{:else}
  <main class="paso-cuerpo" class:tres={paso === 3}>
    {#if paso === 1}
      <!-- 1 Productos -->
      <div class="paso-uno">
        <div class="herramientas">
          <Haz>
            <label class="buscador" use:vidrio={'control'}>
              <Icono nombre="buscar" tamano={18} />
              <input type="search" aria-label="Buscar en tu menú" placeholder="Buscar en tu menú" bind:value={busqueda} autocomplete="off" />
            </label>
          </Haz>
          <span class="crece"></span>
          <span class="etiqueta">
            {#if datos}{plural(productos.length, 'PRODUCTO', 'PRODUCTOS')}{:else}<Esqueleto ancho="80px" alto="10px" />{/if}
          </span>
        </div>
        <p class="nota">De tu menú. Pica uno o varios: el 1 va en el titular.</p>
        <div class="cuerpo rejilla" bind:this={rejilla}>
          {#each visibles as p (p.id)}
            {@const i = elegidos.indexOf(p.id)}
            <button type="button" class="fila prod" class:elegido={i >= 0} aria-pressed={i >= 0} onclick={() => picar(p.id)}>
              <span class="prod-foto" style:background-image={p.imagen_ruta ? `url(${urlFoto(p.imagen_ruta)})` : undefined}></span>
              <span class="prod-textos"><span class="prod-nombre">{p.nombre}</span><span class="prod-precio">{pesos(p.precio)}</span></span>
              {#if i >= 0}<span class="numero">{i + 1}</span>{/if}
            </button>
          {:else}
            {#if datos}
              <div class="nota-rejilla">{productos.length ? 'No hay productos con ese nombre en tu menú.' : 'Todavía no hay productos en tu menú.'}</div>
            {:else}
              <!-- El esqueleto de la primera lectura (regla «Los esqueletos»): tantos productos como la última vez. -->
              <span class="solo-lector">Leyendo tu menú…</span>
              {#each anchos(['78%', '60%', '84%', '66%', '72%'], filasDeLaUltimaVez(llaveEsqueleto)) as ancho, i (i)}
                <div class="prod quieto" aria-hidden="true">
                  <Esqueleto proporcion="4 / 3" redondo="10px" />
                  <span class="prod-textos"><Esqueleto {ancho} alto="12px" /><Esqueleto ancho="36%" alto="10px" /></span>
                </div>
              {/each}
            {/if}
          {/each}
        </div>
      </div>
    {:else if paso === 2}
      <!-- 2 Tu anuncio -->
      <div class="paso-dos" in:fly={{ y: 12, duration: 350 }}>
        <div class="columna">
          <section class="tarjeta">
            <div class="encabezado">
              <span class="cuadro"><Icono nombre="mensaje" tamano={18} /></span>
              <div class="titulos"><span class="titulo">¿Qué quieres decir?</span></div>
              {#if estilo && estilo.mensaje > 0}<span class="letras" class:pasado>{largo} / {estilo.mensaje}</span>{/if}
            </div>
            {#if !estilo || estilo.mensaje > 0}
              <GrupoCampos>
                <label class="caja-mensaje" class:pasado>
                  <textarea rows="2" placeholder={estilo ? pistaDe(estilo) : ''} aria-label="¿Qué quieres decir?" bind:value={mensaje}></textarea>
                </label>
              </GrupoCampos>
            {:else}
              <div class="sin-mensaje"><Icono nombre="info" tamano={16} /><span>{estilo.nombre} no lleva mensaje: sus letras salen de tu producto.</span></div>
            {/if}
          </section>

          <section class="tarjeta">
            <div class="encabezado">
              <span class="cuadro"><Icono nombre="contraste" tamano={18} /></span>
              <div class="titulos">
                <span class="titulo">Estilo y color</span>
                {#if estilo}<span class="sub">{estilo.descripcion}</span>{:else if estilos === null}<Esqueleto ancho="70%" alto="10px" />{/if}
              </div>
            </div>
            <div class="opciones">
              <button type="button" class="opcion alta" disabled={!estilos?.length} onclick={() => (ventana = { tipo: 'estilos' })}>
                <span class="estilo-mini" style:background-image={estilo ? `url(${urlFoto(estilo.muestras.post)})` : undefined}></span>
                <span class="op-textos">
                  {#if estilos === null}
                    <Esqueleto ancho="90px" alto="12px" /><Esqueleto ancho="60px" alto="10px" />
                  {:else}
                    <span class="op-nombre">{estilo?.nombre ?? (sinEstilos ? 'Ninguno' : '…')}</span>
                    {#if estilo}<span class="op-sub">{cuantosLleva(estilo)}</span>{/if}
                  {/if}
                </span>
                <span class="op-cambiar">Cambiar estilo</span><Icono nombre="derecha" tamano={16} />
              </button>
              {#if estilo && !estilo.color}
                <div class="sin-color"><span class="gota-chica vacia"></span>{estilo.nombre} sale con sus colores.</div>
              {:else}
                <div class="fila-color">
                  <button type="button" class="opcion" disabled={!estilo} onclick={() => (ventana = { tipo: 'color' })}>
                    {#if colorDelAnuncio}
                      <span class="gota-chica" style:background={colorDelAnuncio}></span><span class="op-nombre">Color</span><span class="valor">{colorDelAnuncio}</span>
                    {:else}
                      <span class="gota-chica vacia"></span><span class="op-nombre">Color</span><span class="valor">Los de tu estilo</span>
                    {/if}
                    <span class="op-cambiar">Cambiar color</span><Icono nombre="derecha" tamano={16} />
                  </button>
                  <BotonCuadro
                    icono="volver"
                    grande
                    ayuda={marca ? 'Volver al color de tu marca' : 'Volver a los de tu estilo'}
                    etiqueta="Volver al color de tu marca"
                    apagado={color === null}
                    onclick={() => (color = null)}
                  />
                </div>
              {/if}
            </div>
          </section>

          <section class="tarjeta">
            <div class="encabezado">
              <span class="cuadro"><Icono nombre="tienda" tamano={18} /></span>
              <div class="titulos"><span class="titulo">Irá en el anuncio</span></div>
              <button type="button" class="enlace" onclick={() => alIr('restaurante')}>Editar tus datos</button>
            </div>
            <div class="ira-linea">
              {#if !datos}
                <Esqueleto ancho="62%" alto="10px" />
              {:else if linea.length}
                {#each linea as parte, n (n)}{n ? ' · ' : ''}<span class:vacio={parte.vacio}>{parte.texto}</span>{/each}
              {:else}
                <span class="vacio">Sin datos de tu restaurante: solo tu producto.</span>
              {/if}
            </div>
            {#if escogiendo}
              <div class="palabras"><span class="escogiendo"><span class="rueda-chica"></span>Escogiendo las palabras…</span></div>
            {:else if falloPalabras}
              <div class="palabras">
                <span class="escogiendo fallo"><Icono nombre="alerta" tamano={14} />{falloPalabras}</span>
                <button type="button" class="enlace" onclick={reintentar}>Reintentar</button>
              </div>
            {:else if palabras && chips.length}
              <div class="palabras">
                {#each chips as lugar, n (lugar.llave)}
                  {#if chips.length <= 3 && (n === 0 || chips[n - 1].clave !== lugar.clave)}
                    <span class="lugar">{nombreDeGrupo(lugar, chips.filter((l) => l.clave === lugar.clave).length)}</span>
                  {/if}
                  <span class="palabra" title={palabraDe(lugar)}
                    ><span class="palabra-texto">{palabraDe(lugar)}</span><button type="button" class="enlace" onclick={() => (ventana = { tipo: 'palabra', lugar })}
                      >Cambiar</button
                    ></span
                  >
                {/each}
              </div>
            {/if}
          </section>
        </div>

        <div class="lado">
          <Celulares
            {formato}
            {estilo}
            nombre={restaurante?.nombre ?? sucursal.nombre}
            color={marca}
            slug={sucursal.slug}
            restauranteId={sucursal.id}
            alElegir={(f) => (formato = f)}
          />
        </div>
      </div>
    {:else}
      <!-- 3 Listo -->
      <div class="paso-tres" in:fade={{ duration: 250 }} bind:clientWidth={anchoTres} bind:clientHeight={altoTres}>
        <PasoListo
          {se}
          {pedido}
          {productos}
          estilo={estilos?.find((e) => e.id === pedido?.estilo_id) ?? null}
          {restaurante}
          lugar={[anchoTres, altoTres]}
        />
      </div>
    {/if}
  </main>

  <!-- La barra de abajo: la de guardar de Tu menú en línea (encuestas 1, 7 y 11). -->
  <footer class="barra-abajo">
    {#key paso}
      <div class="barra-contenido" in:fade={{ duration: 200 }}>
        {#if paso === 1}
          <div class="estado" role="status">
            {#if nota}
              <span class="aviso-chico"><Icono nombre="alerta" tamano={15} />{nota}</span>
            {:else if elegidos.length}
              <b>{plural(elegidos.length, 'producto elegido', 'productos elegidos')}</b><small>{nombresElegidos}</small>
            {:else}
              <span class="tenue">Ningún producto elegido</span>
            {/if}
          </div>
          <Boton etiqueta="Continuar" tono="verde" apagado={!elegidos.length} onclick={() => ir(2)} />
        {:else if paso === 2}
          <div class="estado" role="status">
            {#if aviso}
              <CajaError mensaje={aviso} tamano={12} compacta />
            {:else if error}
              <CajaError mensaje={error} tamano={12} compacta />
            {:else if errorEstilos}
              <CajaError mensaje={errorEstilos} tamano={12} compacta />
            {:else if sinEstilos}
              <CajaError mensaje="Todavía no hay estilos para tus anuncios." tipo="info" tamano={12} compacta />
            {:else if notaDelEstilo}
              <span class="aviso-chico"><Icono nombre="info" tamano={15} />{notaDelEstilo}</span>
            {:else if pasado && estilo}
              <span class="aviso-chico"><Icono nombre="info" tamano={15} />Tu mensaje no cabe en {estilo.nombre}: córtalo a {estilo.mensaje} letras.</span>
            {:else}
              <span class="tenue">{plural(elegidos.length, 'producto', 'productos')}{estilo ? ` · ${estilo.nombre}` : ''} · {formatoDe(formato).texto}</span>
            {/if}
          </div>
          <Boton etiqueta="Atrás" icono="anterior" onclick={() => ir(1)} />
          <Boton etiqueta={se.fase === 'haciendo' ? 'Haciendo…' : 'Generar anuncio'} tono="verde" apagado={!listo && !enviando} cargando={enviando} onclick={generar} />
        {:else}
          <Boton etiqueta="Nuevo anuncio" icono="mas" onclick={nuevo} />
          <div class="estado" role="status">
            {#if errorDescarga}
              <CajaError mensaje={errorDescarga} tamano={12} compacta />
            {:else if errorPoner}
              <CajaError mensaje={errorPoner} tamano={12} compacta />
            {:else if se.fase === 'haciendo'}
              <b>{se.nombres} · {formatoDe(se.formato).texto}</b><small>Puede tardar un par de minutos.</small>
            {/if}
          </div>
          {#if se.fase === 'listo'}
            {@const id = se.id}
            {@const puesto = puestos.includes(id)}
            <span class="acciones" in:fly={{ x: 8, duration: 250 }}>
              <Boton etiqueta="Otra vez" icono="actualizar" apagado={!!aviso || haciendo} onclick={otraVez} />
              {#if se.formato === 'cartel'}
                <Boton
                  etiqueta={puesto ? 'En tu menú' : poniendo ? 'Poniéndolo en tu menú…' : 'Ponerlo en mi menú'}
                  icono="cartel"
                  cargando={poniendo}
                  exito={puesto}
                  onclick={() => poner(id)}
                />
              {/if}
              <Boton etiqueta={descargado ? 'Descargado' : 'Descargar'} tono="verde" cargando={bajando} exito={descargado} onclick={() => descargar(id)} />
            </span>
          {/if}
        {/if}
      </div>
    {/key}
  </footer>
{/if}

{#if ventana?.tipo === 'estilos' && estilos?.length}
  <VentanaEstilos {estilos} elegido={estiloId} {formato} productos={elegidos.length} alUsar={usarEstilo} alCerrar={() => (ventana = null)} />
{:else if ventana?.tipo === 'color' && estilo}
  <VentanaColor inicial={colorDelAnuncio} {marca} {estilo} alUsar={usarColor} alCerrar={() => (ventana = null)} />
{:else if ventana?.tipo === 'palabra'}
  {@const lugar = ventana.lugar}
  <VentanaPalabra
    titulo={tituloDeLugar(lugar)}
    inicial={palabraDe(lugar)}
    tope={lugar.tope}
    mayusculas={lugar.mayusculas}
    alUsar={(texto) => usarPalabra(lugar, texto)}
    alCerrar={() => (ventana = null)}
  />
{/if}

<style>
  .cuerpo-error {
    position: absolute;
    left: var(--vista-izquierda);
    right: var(--vista-derecha);
    top: var(--vista-arriba);
  }

  /* Entre la barra de arriba (56) y la de abajo (64), sobre el fondo de las vistas. */
  .paso-cuerpo {
    position: absolute;
    left: 0;
    right: 0;
    top: 56px;
    bottom: 64px;
    overflow-y: auto;
    padding: 20px 20px 24px 24px;
  }

  .crece {
    flex-grow: 1;
  }

  .solo-lector {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip: rect(0 0 0 0);
  }

  /* ─── 1 Productos ─── */
  .paso-uno {
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  .herramientas {
    position: relative;
    flex: none;
    min-height: 48px;
    display: flex;
    align-items: center;
    gap: 12px;
  }

  /* La búsqueda de Mi menú: píldora de 48 con el brillo de Haz, hasta 780 de ancho. */
  .herramientas > :global(div.haz) {
    flex: 0 1 780px;
    min-width: 0;
  }

  .buscador {
    width: 100%;
    height: 48px;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 14px 0 18px;
    border: 1px solid var(--borde-tarjeta);
    border-radius: 999px;
    background: var(--solido);
    color: var(--tenue);
  }

  .buscador:focus-within {
    border-color: var(--linea-fuerte);
  }

  :global(:root[data-estilo='cristal']) .buscador {
    position: relative;
  }

  .buscador input {
    flex: 1;
    min-width: 0;
    border: 0;
    background: transparent;
    color: var(--texto);
    font-size: 15px;
    font-weight: 400;
    outline: none;
  }

  .buscador input::placeholder {
    color: var(--tenue);
  }

  .etiqueta {
    font-family: var(--mono);
    font-size: 10.5px;
    letter-spacing: 0.14em;
    color: var(--tenue);
  }

  .nota {
    margin: 0;
    padding: 0 4px;
    font-size: 12.5px;
    font-weight: 500;
    color: var(--suave);
  }

  /* Los productos grandes: tarjetas del panel con su foto a 4:3. */
  .rejilla {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(196px, 1fr));
    gap: 14px;
    align-content: start;
  }

  .prod {
    position: relative;
    display: flex;
    flex-direction: column;
    gap: 10px;
    padding: 8px 8px 12px;
    border-radius: 14px;
    border: 1px solid var(--borde-tarjeta);
    background: var(--solido);
    color: var(--texto);
    text-align: left;
    min-width: 0;
    cursor: pointer;
    transition:
      box-shadow 0.2s ease,
      border-color 0.2s ease,
      transform 0.15s ease;
  }

  .prod:not(.quieto):active {
    transform: scale(0.98);
  }

  .prod:focus-visible {
    outline: none;
    box-shadow: 0 0 0 2px var(--campo-aro);
  }

  .prod.quieto {
    cursor: default;
  }

  /* Lo elegido, en el azul del aro de las cajas (como los roles de Empleados). */
  .prod.elegido {
    box-shadow: 0 0 0 2px var(--campo-aro);
    border-color: transparent;
  }

  /* Sin foto, el cuadro negro (como sin-foto.png de Flet). */
  .prod-foto {
    aspect-ratio: 4 / 3;
    border-radius: 10px;
    background: #000000 center / cover no-repeat;
  }

  .prod-textos {
    padding: 0 4px;
    display: flex;
    flex-direction: column;
    gap: 4px;
    min-width: 0;
  }

  .prod-nombre {
    font-size: 14px;
    font-weight: 700;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .prod-precio {
    font-family: var(--mono);
    font-size: 12px;
    color: var(--tenue);
  }

  /* Su número (el 1 va en el titular) sale con el rebote de lo que se abre. */
  .numero {
    position: absolute;
    top: 16px;
    right: 16px;
    width: 26px;
    height: 26px;
    border-radius: 8px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--campo-aro);
    color: #ffffff;
    font-family: var(--mono);
    font-size: 12px;
    font-weight: 700;
    animation: sale 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275) both;
  }

  @keyframes sale {
    from {
      opacity: 0;
      transform: scale(0.4);
    }
  }

  .nota-rejilla {
    grid-column: 1 / -1;
    padding: 56px 8px;
    text-align: center;
    font-size: 13px;
    color: var(--suave);
  }

  /* ─── 2 Tu anuncio ─── */
  .paso-dos {
    display: grid;
    grid-template-columns: minmax(0, 1fr) 590px;
    align-items: start;
    gap: 28px;
  }

  .columna {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  /* Cada bloque, en su tarjeta (como las filas de Tu menú en línea). */
  .tarjeta {
    padding: 20px;
    background: var(--solido);
    border: 1px solid var(--borde-tarjeta);
    border-radius: 14px;
    display: flex;
    flex-direction: column;
    gap: 16px;
    min-width: 0;
  }

  .encabezado {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .cuadro {
    width: 36px;
    height: 36px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 11px;
    background: var(--chip);
    color: var(--texto);
  }

  .titulos {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .titulo {
    font-size: 14.5px;
    font-weight: 700;
  }

  .sub {
    font-size: 12.5px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .lado {
    position: sticky;
    top: 0;
  }

  .letras {
    font-family: var(--mono);
    font-size: 11px;
    color: var(--tenue);
    font-variant-numeric: tabular-nums;
  }

  .letras.pasado {
    color: var(--rojo);
    font-weight: 700;
  }

  /* Como las cajas de texto (diseno/Campo.svelte, el Input de HeroUI), en su gris (GrupoCampos). */
  .caja-mensaje {
    display: block;
    padding: 11px 15px;
    border-radius: 12px;
    background: var(--campo-fondo);
    box-shadow: var(--campo-sombra);
    cursor: text;
    transition:
      background-color 0.15s ease,
      box-shadow 0.15s ease-out;
  }

  .caja-mensaje:hover:not(:focus-within) {
    background: var(--campo-encima);
  }

  .caja-mensaje:focus-within {
    box-shadow: 0 0 0 2px var(--campo-aro);
  }

  .caja-mensaje.pasado {
    box-shadow: 0 0 0 1px var(--rojo);
  }

  .caja-mensaje.pasado:focus-within {
    box-shadow: 0 0 0 2px var(--rojo);
  }

  .caja-mensaje textarea {
    display: block;
    width: 100%;
    height: 41px;
    padding: 0;
    border: 0;
    resize: none;
    background: transparent;
    outline: none;
    color: var(--texto);
    font-size: 13.5px;
    font-weight: 400;
    line-height: 1.5;
  }

  .caja-mensaje textarea::placeholder {
    color: var(--tenue);
  }

  .sin-mensaje {
    display: flex;
    align-items: center;
    gap: 10px;
    min-height: 56px;
    padding: 0 14px;
    border-radius: 12px;
    border: 1.5px dashed var(--linea-fuerte);
    font-size: 12.5px;
    font-weight: 500;
    color: var(--suave);
  }

  .opciones {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .opcion {
    flex: 1;
    min-width: 0;
    height: 44px;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 12px;
    border-radius: 12px;
    border: 1px solid var(--linea);
    background: transparent;
    color: var(--texto);
    text-align: left;
    cursor: pointer;
    transition:
      background-color 0.15s ease,
      transform 0.15s ease;
  }

  .opcion.alta {
    height: 60px;
    padding-left: 10px;
  }

  .opcion:hover:not(:disabled) {
    background: var(--chip);
  }

  .opcion:active:not(:disabled) {
    transform: scale(0.99);
  }

  .opcion:focus-visible {
    outline: none;
    box-shadow: 0 0 0 2px var(--campo-aro);
  }

  .opcion:disabled {
    cursor: default;
    opacity: 0.5;
  }

  .opcion > :global(svg) {
    flex: none;
    color: var(--tenue);
  }

  .op-textos {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .op-nombre {
    font-size: 13.5px;
    font-weight: 700;
    white-space: nowrap;
  }

  .op-sub {
    font-size: 12px;
    font-weight: 500;
    color: var(--tenue);
  }

  .op-cambiar {
    margin-left: auto;
    font-size: 12.5px;
    font-weight: 600;
    color: var(--suave);
    white-space: nowrap;
  }

  .estilo-mini {
    width: 32px;
    height: 40px;
    flex: none;
    border-radius: 7px;
    background: #000000 center / cover no-repeat;
  }

  .fila-color {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .gota-chica {
    width: 20px;
    height: 20px;
    border-radius: 6px;
    flex: none;
    box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.12);
  }

  .gota-chica.vacia {
    box-shadow: none;
    border: 1.5px dashed var(--tenue);
  }

  .valor {
    font-family: var(--mono);
    font-size: 11.5px;
    color: var(--tenue);
    white-space: nowrap;
  }

  .sin-color {
    height: 44px;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 12px;
    border-radius: 12px;
    background: var(--fondo);
    font-size: 12.5px;
    font-weight: 500;
    color: var(--suave);
  }

  .enlace {
    border: 0;
    background: transparent;
    padding: 0;
    font-size: 12px;
    font-weight: 600;
    color: var(--texto);
    text-decoration: underline;
    text-underline-offset: 2px;
    cursor: pointer;
    white-space: nowrap;
  }

  .ira-linea {
    font-size: 13px;
    font-weight: 600;
    color: var(--suave);
    line-height: 1.5;
  }

  .ira-linea .vacio {
    color: var(--tenue);
    font-weight: 500;
  }

  .palabras {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 6px;
    min-height: 28px;
  }

  .lugar {
    margin-right: 2px;
    font-size: 12px;
    font-weight: 500;
    color: var(--tenue);
    white-space: nowrap;
  }

  .palabra {
    display: inline-flex;
    align-items: center;
    height: 28px;
    padding: 0 0 0 9px;
    border-radius: 9px;
    background: var(--chip);
    font-size: 11.5px;
    font-weight: 700;
    letter-spacing: 0.02em;
    white-space: nowrap;
    flex: none;
    min-width: 0;
  }

  /* Las largas (las capas de la Anatomía) se cortan: «Cambiar» las enseña completas. */
  .palabra-texto {
    max-width: 180px;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .palabra .enlace {
    padding: 0 8px 0 7px;
    font-size: 11px;
    font-weight: 600;
    color: var(--suave);
    letter-spacing: 0;
  }

  .escogiendo {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    font-size: 12px;
    font-weight: 500;
    color: var(--suave);
  }

  .escogiendo.fallo {
    color: var(--texto);
    font-weight: 600;
  }

  .rueda-chica {
    width: 14px;
    height: 14px;
    border-radius: 50%;
    border: 2px solid var(--linea-fuerte);
    border-top-color: var(--texto);
    animation: girar 0.9s linear infinite;
    flex: none;
  }

  @keyframes girar {
    to {
      transform: rotate(360deg);
    }
  }

  /* ─── 3 Listo ─── */
  .paso-cuerpo.tres {
    display: flex;
    flex-direction: column;
  }

  .paso-tres {
    flex: 1;
    min-height: 0;
  }

  /* ─── La barra de abajo: la de guardar de Tu menú en línea (64, pegada abajo de lo ancho de la vista) ─── */
  .barra-abajo {
    position: absolute;
    left: 0;
    right: 0;
    bottom: 0;
    height: 64px;
    z-index: 2;
    background: var(--solido);
    border-top: 1px solid var(--linea);
  }

  .barra-contenido {
    height: 100%;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 20px 0 24px;
  }

  .estado {
    flex: 1;
    min-width: 0;
    display: flex;
    align-items: center;
    gap: 10px;
    font-size: 13px;
    white-space: nowrap;
  }

  .estado b {
    font-weight: 600;
    flex: none;
  }

  .estado small {
    min-width: 0;
    font-size: 12.5px;
    font-weight: 500;
    color: var(--suave);
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .estado .tenue {
    font-weight: 500;
    color: var(--suave);
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .estado :global(.caja) {
    flex: 1;
    min-width: 0;
  }

  .aviso-chico {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
    font-weight: 600;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .aviso-chico :global(svg) {
    flex: none;
    color: var(--suave);
  }

  .acciones {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  @media (prefers-reduced-motion: reduce) {
    .prod,
    .opcion,
    .caja-mensaje {
      transition: none;
    }

    .numero {
      animation: none;
    }

    .rueda-chica {
      animation-duration: 3s;
    }
  }
</style>
