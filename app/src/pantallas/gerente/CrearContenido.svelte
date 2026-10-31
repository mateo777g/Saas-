<!--
  «Crear contenido» (parte 7b-1 de la libreta 7; maqueta JQBw2yGFSiky1x9twUyYbe, aprobada el 30 de
  octubre de 2026; sus decisiones en planes/trabajo/7b/lista-7b.md). Una sola pantalla, como en Flet:
  el anuncio nuevo a la izquierda (1 Producto, 2 Formato, 3 ¿Qué quieres decir?, la fila «Opcional»
  con Color y Estilo, «Irá en el anuncio» y Generar anuncio) y «Resultado» a la derecha.

  Lo lee todo de Postgres con crear_contenido, al abrir, cada vez que realtime avisa de un cambio en
  sus anuncios, cada 30 segundos mientras uno se hace (por si se perdió un aviso) y al volver a la
  pestaña. Los estilos y sus reglas vienen del Worker. Las palabras que Don Chuy no escribe las escoge
  el paso de texto un momento después de que deja de cambiar los productos o el estilo, para no
  pagar una vuelta por cada producto que pica.
-->
<script lang="ts">
  import { onMount, untrack } from 'svelte';
  import BarraArriba from '../../diseno/BarraArriba.svelte';
  import BotonCuadro from '../../diseno/BotonCuadro.svelte';
  import CajaError from '../../diseno/CajaError.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import Vidrio from '../../diseno/Vidrio.svelte';
  import { textoSinTope } from '../../lib/agente';
  import {
    anuncioVisto,
    datosQueVan,
    descargarAnuncio,
    escucharAnuncios,
    FORMATOS,
    hacerAnuncio,
    leerCrearContenido,
    leerEstilosDeHoy,
    lugaresDe,
    pedirPalabras,
    pistaDe,
    sinAcentos,
    vacioDe,
    type DatosCrearContenido,
    type EstiloDeHoy,
    type Formato,
    type LugarListo,
    type NoSePuede,
    type Pedido,
    type Resultado as ResultadoDeAnuncio,
  } from '../../lib/crearContenido';
  import { esDeRed, Fallo, mensajeDeError, SIN_CONEXION } from '../../lib/errores';
  import { diaYMes, pesos } from '../../lib/formato';
  import { urlFoto } from '../../lib/fotos';
  import type { Sucursal } from '../../lib/gerente';
  import CajaSucursales from './CajaSucursales.svelte';
  import Resultado, { type LoQueSeVe } from './crearContenido/Resultado.svelte';
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

  // Lo que va armando: los productos en el orden en que los picó (el 1 va en el titular), el
  // formato, el estilo, su mensaje y el color de este anuncio (null = el de su marca).
  let elegidos = $state<number[]>([]);
  let formato = $state<Formato | null>(null);
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
  // El último terminado que enseña: «Otra vez» lo repite tal cual.
  let mostrado = $state<ResultadoDeAnuncio | null>(null);
  let enviando = $state(false);

  // El que se apagó con la vista abierta se queda a la vista, con su aviso, hasta que elija otro.
  let perdido = $state<EstiloDeHoy | null>(null);
  const estilo = $derived(estilos?.find((e) => e.id === estiloId) ?? (perdido?.id === estiloId ? perdido : null));
  const productos = $derived(datos?.productos ?? []);
  const restaurante = $derived(datos?.restaurante ?? null);
  const marca = $derived(restaurante?.color ?? null);
  // Los que van: los primeros, hasta el máximo del estilo; los de más se apagan, no se borran.
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
    if (sinIa) return textoSinTope(sinIa);
    if (datos.quedan <= 0) return `Ya hiciste tus ${datos.de} anuncios de este mes. Vuelven el ${diaYMes(datos.vuelve)}.`;
    return null;
  });

  const largo = $derived([...mensaje].length);
  const pasado = $derived(!!estilo && estilo.mensaje > 0 && largo > estilo.mensaje);
  const escrito = $derived(!!estilo && estilo.mensaje > 0 && mensaje.trim() !== '');
  const haciendo = $derived(se.fase === 'haciendo' || enviando);
  const faltanPalabras = $derived(lugares.length > 0 && !palabras);
  const sinEstilos = $derived(estilos !== null && estilos.length === 0);

  const listo = $derived(
    !!estilo &&
      !!datos &&
      van.length >= estilo.minimo &&
      formato !== null &&
      !pasado &&
      !faltanPalabras &&
      !aviso &&
      error !== YA_NO_ESTA &&
      !haciendo,
  );

  // Lo que dice bajo «Producto».
  const notaProductos = $derived.by((): { aviso: boolean; icono?: string; texto: string } => {
    if (nota) return { aviso: true, icono: 'alerta', texto: nota };
    const n = elegidos.length;
    if (estilo && n && n < estilo.minimo) return { aviso: true, icono: 'info', texto: `Este estilo es para combos: pica ${estilo.minimo} o ${estilo.maximo}.` };
    if (estilo && n > estilo.maximo) {
      const m = estilo.maximo;
      const cuales = m === 1 ? 'va el 1' : m === 2 ? 'van el 1 y el 2' : `van del 1 al ${m}`;
      return { aviso: true, icono: 'info', texto: `Este estilo lleva ${m === 1 ? '1 producto' : `hasta ${m} productos`}: ${cuales}.` };
    }
    return { aviso: false, texto: 'De tu menú. Pica uno o varios: el 1 va en el titular.' };
  });

  const visibles = $derived.by(() => {
    const b = sinAcentos(busqueda.trim());
    return b ? productos.filter((p) => sinAcentos(p.nombre).includes(b)) : productos;
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
    for (const d of datosQueVan(estilo, formato ?? 'post', restaurante, van)) partes.push({ texto: d, vacio: false });
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

  async function leer() {
    let nuevos: DatosCrearContenido;
    try {
      nuevos = await leerCrearContenido(sucursal.id);
    } catch (e) {
      // Con algo ya en pantalla se queda; la primera vez, la caja de error.
      if (!datos) errorLectura = esDeRed(e) ? SIN_CONEXION : mensajeDeError(e);
      return;
    }
    errorLectura = null;
    datos = nuevos;
    alLeer(nuevos.resultado);
  }

  function alLeer(r: ResultadoDeAnuncio | null) {
    const antes = se;
    if (!r) {
      // Uno que ya enseñó terminado se queda mientras siga en la vista; uno que se hacía (el de
      // otro gerente de la sucursal) ya no es suyo: queda vacío.
      if (antes.fase === 'haciendo') se = { fase: 'vacio' };
      haciendoId = null;
      return;
    }
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

  async function leerEstilos() {
    try {
      const lista = await leerEstilosDeHoy(sucursal.id);
      const antes = estilo;
      estilos = lista;
      errorEstilos = null;
      if (estiloId === null) {
        // Entra con el Clásico; si hoy no le sale, con el primero de «Para todos».
        estiloId = (lista.find((e) => e.clave === 'clasico') ?? lista.find((e) => e.grupo === 'para_todos') ?? lista[0])?.id ?? null;
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
    // Sin IA, el límite, los 20 o uno que ya se hace: lo dice la lectura.
    leer();
  }

  async function mandar(pedido: Pedido) {
    enviando = true;
    error = null;
    try {
      const r = await hacerAnuncio(sucursal.id, pedido);
      if (r.ok) await leer();
      else noSePuede(r);
    } catch (e) {
      error = mensajeDe(e);
    } finally {
      enviando = false;
    }
  }

  function generar() {
    if (!listo || !estilo || !formato) return;
    const llaves = new Set(lugares.map((l) => l.llave));
    const todas = { ...(palabras ?? {}), ...cambiadas };
    mandar({
      estiloId: estilo.id,
      formato,
      productos: van.map((p) => p.id),
      mensaje: estilo.mensaje > 0 ? mensaje.trim() : '',
      color: estilo.color ? color : null,
      palabras: Object.fromEntries(Object.entries(todas).filter(([llave]) => llaves.has(llave))),
    });
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

  // ─── Lo que se toca ────────────────────────────────────────────────────────────────────────

  function picar(id: number) {
    nota = null;
    error = null;
    if (elegidos.includes(id)) elegidos = elegidos.filter((x) => x !== id);
    else if (elegidos.length >= MAXIMO_PRODUCTOS) nota = `Máximo ${MAXIMO_PRODUCTOS} productos en un anuncio.`;
    else elegidos = [...elegidos, id];
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
  titulo="Crear contenido"
  estado={datos
    ? { texto: `Te quedan ${datos.quedan} de ${datos.de} este mes`, vivo: true, hueco: datos.quedan <= 0 }
    : { texto: errorLectura ? 'No se pudo leer' : 'Leyendo…', vivo: false }}
>
  <CajaSucursales {sucursales} actual={sucursal} {alElegir} />
</BarraArriba>

{#if errorLectura && !datos}
  <main class="cuerpo-error"><CajaError mensaje={errorLectura} /></main>
{:else}
  <Vidrio como="main" class="tarjeta-nuevo" radio={26}>
    <!-- 1 Producto -->
    <div class="seccion">
      <div class="paso-cabeza">
        <span class="paso" class:listo={!!estilo && van.length >= estilo.minimo}>
          {#if estilo && van.length >= estilo.minimo}<Icono nombre="check" tamano={13} />{:else}1{/if}
        </span>
        <div class="paso-textos">
          <span class="paso-titulo">Producto</span>
          <span class="paso-sub" class:aviso={notaProductos.aviso}>
            {#if notaProductos.icono}<Icono nombre={notaProductos.icono} tamano={14} />{/if}{notaProductos.texto}
          </span>
        </div>
        <label class="buscador">
          <Icono nombre="buscar" tamano={15} />
          <input type="search" placeholder="Buscar en tu menú" bind:value={busqueda} autocomplete="off" />
        </label>
      </div>
      <div class="rejilla">
        {#each visibles as p (p.id)}
          {@const i = elegidos.indexOf(p.id)}
          {@const deMas = i >= 0 && !!estilo && i >= estilo.maximo}
          <button type="button" class="prod" class:elegido={i >= 0 && !deMas} class:de-mas={deMas} aria-pressed={i >= 0} onclick={() => picar(p.id)}>
            <span class="prod-foto" style:background-image={p.imagen_ruta ? `url(${urlFoto(p.imagen_ruta)})` : undefined}></span>
            <span class="prod-textos"><span class="prod-nombre">{p.nombre}</span><span class="prod-precio">{pesos(p.precio)}</span></span>
            {#if i >= 0}<span class="numero" class:apagado={deMas}>{i + 1}</span>{/if}
          </button>
        {:else}
          <div class="nota-rejilla">{datos ? (productos.length ? 'No hay productos con ese nombre en tu menú.' : 'Todavía no hay productos en tu menú.') : 'Leyendo tu menú…'}</div>
        {/each}
      </div>
    </div>

    <!-- 2 Formato -->
    <div class="seccion">
      <div class="paso-cabeza">
        <span class="paso" class:listo={formato !== null}>{#if formato}<Icono nombre="check" tamano={13} />{:else}2{/if}</span>
        <span class="paso-titulo">Formato</span>
      </div>
      <div class="formatos">
        {#each FORMATOS as f (f.valor)}
          <button type="button" class="formato" class:elegido={formato === f.valor} aria-pressed={formato === f.valor} onclick={() => (formato = f.valor)}>
            <span class="caja-ic"><Icono nombre={f.valor} tamano={18} /></span>
            <span class="f-textos"><span class="f-titulo">{f.texto}</span><span class="f-medida">{f.medida}</span></span>
          </button>
        {/each}
      </div>
    </div>

    <!-- 3 ¿Qué quieres decir? -->
    <div class="seccion">
      <div class="paso-cabeza">
        <span class="paso" class:listo={escrito && !pasado}>{#if escrito && !pasado}<Icono nombre="check" tamano={13} />{:else}3{/if}</span>
        <span class="paso-titulo crece">¿Qué quieres decir?</span>
        {#if estilo && estilo.mensaje > 0}<span class="letras" class:pasado>{largo} / {estilo.mensaje}</span>{/if}
      </div>
      {#if !estilo || estilo.mensaje > 0}
        <label class="caja-mensaje" class:pasado>
          <textarea rows="2" placeholder={estilo ? pistaDe(estilo) : ''} aria-label="¿Qué quieres decir?" bind:value={mensaje}></textarea>
        </label>
      {:else}
        <div class="sin-mensaje"><Icono nombre="info" tamano={16} /><span>{estilo.nombre} no lleva mensaje: sus letras salen de tu producto.</span></div>
      {/if}
    </div>

    <!-- Opcional: Color y Estilo -->
    <div class="fila-opciones">
      <span class="etq">Opcional</span><span style="width:4px"></span>
      {#if estilo && !estilo.color}
        <span class="sin-color">{estilo.nombre} sale con sus colores.</span>
      {:else}
        <button type="button" class="boton-opcion" title="Elegir el color de este anuncio" disabled={!estilo} onclick={() => (ventana = { tipo: 'color' })}>
          {#if colorDelAnuncio}
            <span class="gota-chica" style:background={colorDelAnuncio}></span>Color<span class="valor">{colorDelAnuncio}</span>
          {:else}
            <span class="gota-chica vacia"></span>Color<span class="valor">Los de tu estilo</span>
          {/if}
        </button>
        <BotonCuadro
          icono="volver"
          ayuda={marca ? 'Volver al color de tu marca' : 'Volver a los de tu estilo'}
          etiqueta="Volver al color de tu marca"
          apagado={color === null}
          onclick={() => (color = null)}
        />
      {/if}
      <span class="separador"></span>
      <button type="button" class="boton-opcion" title="Elegir el estilo del anuncio" disabled={!estilos?.length} onclick={() => (ventana = { tipo: 'estilos' })}>
        <span class="estilo-mini" style:background-image={estilo ? `url(${urlFoto(estilo.muestras.post)})` : undefined}></span>Estilo<span class="valor"
          >{estilo?.nombre ?? (sinEstilos ? 'Ninguno' : '…')}</span
        >
      </button>
      {#if estilo}<span class="desc-estilo" title={estilo.descripcion}>{estilo.descripcion}</span>{/if}
    </div>

    <!-- Irá en el anuncio -->
    <div class="ira">
      <div class="ira-cabeza">
        <span class="etq crece">Irá en el anuncio</span>
        <button type="button" class="enlace" onclick={() => alIr('restaurante')}>Editar tus datos</button>
      </div>
      <div class="ira-linea">
        {#if linea.length}
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
    </div>

    <!-- Avisos y Generar anuncio -->
    <div class="pie-crear">
      {#if aviso}
        <CajaError mensaje={aviso} tamano={12} compacta />
      {:else if error}
        <CajaError mensaje={error} tamano={12} compacta />
      {:else if errorEstilos}
        <CajaError mensaje={errorEstilos} tamano={12} compacta />
      {:else if sinEstilos}
        <CajaError mensaje="Todavía no hay estilos para tus anuncios." tipo="info" tamano={12} compacta />
      {:else if pasado && estilo}
        <span class="nota-pie">Tu mensaje no cabe en {estilo.nombre}: córtalo a {estilo.mensaje} letras.</span>
      {:else}
        <span class="nota-pie"></span>
      {/if}
      <button type="button" class="boton-generar" disabled={!listo} onclick={generar}>
        <Icono nombre="ia" tamano={16} />{haciendo ? 'Haciendo…' : 'Generar anuncio'}
      </button>
    </div>
  </Vidrio>

  <Resultado
    {se}
    formatoElegido={formato}
    otraVez={!aviso && !haciendo}
    alOtraVez={otraVez}
    alDescargar={descargarAnuncio}
  />
{/if}

{#if ventana?.tipo === 'estilos' && estilos?.length}
  <VentanaEstilos {estilos} elegido={estiloId} formato={formato ?? 'post'} alUsar={usarEstilo} alCerrar={() => (ventana = null)} />
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
    left: 276px;
    right: 16px;
    top: 92px;
  }

  /* El anuncio nuevo: de la barra lateral hasta «Resultado» (440 px y sus márgenes). */
  :global(.tarjeta-nuevo) {
    position: absolute;
    left: 276px;
    right: 472px;
    top: 92px;
    bottom: 16px;
    padding: 20px;
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .etq {
    font-family: var(--mono);
    font-size: 10.5px;
    letter-spacing: 0.14em;
    color: var(--tenue);
    text-transform: uppercase;
  }

  .crece {
    flex-grow: 1;
  }

  .seccion {
    flex: none;
    padding: 14px 16px;
    background: var(--solido);
    border: 1px solid var(--linea);
    border-radius: 18px;
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .paso-cabeza {
    display: flex;
    align-items: center;
    gap: 10px;
    min-height: 24px;
  }

  .paso {
    width: 24px;
    height: 24px;
    border-radius: 12px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--chip);
    border: 1px solid var(--linea);
    font-family: var(--mono);
    font-size: 11px;
    color: var(--suave);
  }

  .paso.listo {
    background: var(--verde);
    border-color: var(--verde);
    color: #ffffff;
  }

  .paso-textos {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .paso-titulo {
    font-size: 14.5px;
    font-weight: 700;
  }

  .paso-sub {
    font-size: 12px;
    font-weight: 500;
    color: var(--tenue);
    display: flex;
    align-items: center;
    gap: 6px;
    min-width: 0;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .paso-sub.aviso {
    color: var(--texto);
    font-weight: 600;
  }

  .paso-sub.aviso :global(svg) {
    color: var(--suave);
  }

  .buscador {
    width: 220px;
    height: 36px;
    flex: none;
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 0 12px;
    border-radius: 11px;
    border: 1px solid var(--linea);
    color: var(--tenue);
  }

  .buscador input {
    flex: 1;
    min-width: 0;
    border: 0;
    background: transparent;
    outline: none;
    font-size: 12.5px;
    color: var(--texto);
  }

  .buscador input::placeholder {
    color: var(--tenue);
  }

  .rejilla {
    height: 150px;
    overflow-y: auto;
    padding: 2px;
    display: grid;
    grid-template-columns: repeat(5, minmax(0, 1fr));
    gap: 10px;
    align-content: start;
  }

  .prod {
    position: relative;
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 6px 6px 10px;
    border-radius: 14px;
    border: 1px solid var(--linea);
    background: var(--solido);
    color: var(--texto);
    text-align: left;
    min-width: 0;
    cursor: pointer;
  }

  .prod.elegido {
    box-shadow: 0 0 0 2px var(--tinta);
    border-color: transparent;
  }

  .prod.de-mas {
    box-shadow: 0 0 0 2px var(--linea-fuerte);
    border-color: transparent;
  }

  /* Sin foto, el cuadro negro (como sin-foto.png de Flet). */
  .prod-foto {
    height: 88px;
    border-radius: 10px;
    background: #000000 center / cover no-repeat;
  }

  .prod-textos {
    padding: 0 4px;
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }

  .prod-nombre {
    font-size: 12.5px;
    font-weight: 600;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .prod-precio {
    font-family: var(--mono);
    font-size: 11px;
    color: var(--tenue);
  }

  .numero {
    position: absolute;
    top: 12px;
    right: 12px;
    width: 22px;
    height: 22px;
    border-radius: 11px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--tinta);
    color: var(--sobre-tinta);
    font-family: var(--mono);
    font-size: 11px;
    font-weight: 700;
  }

  .numero.apagado {
    background: var(--solido);
    color: var(--tenue);
    box-shadow: inset 0 0 0 1.5px var(--linea-fuerte);
  }

  .nota-rejilla {
    grid-column: 1 / -1;
    padding: 40px 8px;
    text-align: center;
    font-size: 12.5px;
    color: var(--suave);
  }

  .formatos {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 10px;
  }

  .formato {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 11px 12px;
    border-radius: 14px;
    border: 1px solid var(--linea);
    background: var(--solido);
    color: var(--texto);
    text-align: left;
    min-width: 0;
    cursor: pointer;
  }

  .formato.elegido {
    box-shadow: 0 0 0 2px var(--tinta);
    border-color: transparent;
  }

  .caja-ic {
    width: 34px;
    height: 34px;
    border-radius: 10px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--chip);
  }

  .f-textos {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .f-titulo {
    font-size: 13.5px;
    font-weight: 700;
    white-space: nowrap;
  }

  .f-medida {
    font-family: var(--mono);
    font-size: 10.5px;
    color: var(--tenue);
    white-space: nowrap;
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

  .caja-mensaje {
    display: block;
    padding: 10px 14px;
    border: 1px solid var(--linea);
    border-radius: 12px;
    cursor: text;
  }

  .caja-mensaje:focus-within {
    border-color: var(--suave);
  }

  .caja-mensaje.pasado {
    border-color: var(--rojo);
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
    height: 63px;
    padding: 0 14px;
    border-radius: 12px;
    border: 1.5px dashed var(--linea-fuerte);
    font-size: 12.5px;
    font-weight: 500;
    color: var(--suave);
  }

  .fila-opciones {
    flex: none;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 12px 14px 12px 16px;
    background: var(--solido);
    border: 1px solid var(--linea);
    border-radius: 18px;
    min-width: 0;
  }

  .boton-opcion {
    height: 36px;
    flex: none;
    display: inline-flex;
    align-items: center;
    gap: 9px;
    padding: 0 12px 0 9px;
    border-radius: 11px;
    border: 1px solid var(--linea);
    background: transparent;
    color: var(--texto);
    font-size: 13px;
    font-weight: 600;
    cursor: pointer;
    transition: background-color 150ms;
  }

  .boton-opcion:hover:not(:disabled) {
    background: var(--chip);
  }

  .boton-opcion:disabled {
    cursor: default;
    opacity: 0.4;
  }

  .gota-chica {
    width: 18px;
    height: 18px;
    border-radius: 5px;
    flex: none;
    box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.12);
  }

  .gota-chica.vacia {
    box-shadow: none;
    border: 1.5px dashed var(--tenue);
  }

  .valor {
    font-family: var(--mono);
    font-size: 11px;
    font-weight: 400;
    color: var(--tenue);
  }

  .estilo-mini {
    width: 22px;
    height: 28px;
    border-radius: 5px;
    flex: none;
    background: #000000 center / cover no-repeat;
  }

  .separador {
    width: 1px;
    height: 24px;
    flex: none;
    background: var(--linea);
    margin: 0 4px;
  }

  .desc-estilo {
    flex: 1;
    min-width: 0;
    font-size: 12px;
    font-weight: 500;
    color: var(--tenue);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .sin-color {
    font-size: 12px;
    font-weight: 500;
    color: var(--tenue);
    white-space: nowrap;
  }

  .ira {
    flex: none;
    padding: 12px 16px 14px;
    background: var(--solido);
    border: 1px solid var(--linea);
    border-radius: 18px;
    display: flex;
    flex-direction: column;
    gap: 8px;
    min-width: 0;
  }

  .ira-cabeza {
    display: flex;
    align-items: center;
    gap: 12px;
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
  }

  .ira-linea {
    font-size: 12.5px;
    font-weight: 600;
    color: var(--suave);
    line-height: 1.4;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .ira-linea .vacio {
    color: var(--tenue);
    font-weight: 500;
  }

  .palabras {
    display: flex;
    align-items: center;
    gap: 5px;
    min-height: 28px;
    overflow: hidden;
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

  .pie-crear {
    flex: none;
    display: flex;
    align-items: center;
    gap: 14px;
    min-height: 44px;
    margin-top: auto;
  }

  .pie-crear :global(.caja) {
    flex: 1;
    min-width: 0;
  }

  .nota-pie {
    flex: 1;
    min-width: 0;
    font-size: 12px;
    font-weight: 500;
    color: var(--tenue);
    line-height: 1.4;
  }

  .boton-generar {
    height: 44px;
    flex: none;
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 0 20px;
    border: 0;
    border-radius: 12px;
    background: var(--tinta);
    color: var(--sobre-tinta);
    font-size: 13px;
    font-weight: 600;
    white-space: nowrap;
    cursor: pointer;
    transition: opacity 150ms;
  }

  .boton-generar:hover:not(:disabled) {
    opacity: 0.86;
  }

  .boton-generar:disabled {
    background: var(--chip);
    color: var(--tenue);
    cursor: default;
  }

  @media (prefers-reduced-motion: reduce) {
    .boton-opcion,
    .boton-generar {
      transition: none;
    }

    .rueda-chica {
      animation-duration: 3s;
    }
  }
</style>
