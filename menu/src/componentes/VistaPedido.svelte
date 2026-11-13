<!--
  Tu pedido como vista completa («Tu menú en línea», maqueta v53, v57 y v58; encuestas 35, 42 a 44 y 47). Se llega por
  la pestaña Pedido de la barra de abajo, que se queda a la vista. Arriba la barra de tu menú; luego «Tu pedido» como
  lista (la foto, el nombre, sus opciones y su nota, el precio, y el − n + a la derecha; tocar un renglón lo abre para
  cambiarlo), «¿Cómo lo recibes?» como interruptor de dos, tus datos en tarjetas por lo que significan (lo de a
  domicilio se despliega), el resumen como ticket y la nota de WhatsApp; abajo, fijo, «Pedir por WhatsApp», del color de
  tu menú y clarito mientras falte un dato (tocarlo así te lleva al que falta). Sin nada, la carita; sin pedidos,
  cuándo los reciben; mandado, «Pedido enviado» con la palomita que se dibuja y «Abrir WhatsApp otra vez» abajo.
  Cambia cómo se ve, no cómo se manda (planes/trabajo/pedir-por-whatsapp/pedido.md): el toque único, la revisión de
  Cloudflare por adelantado en su hueco y «Falta un paso» de respaldo siguen como antes, en Menu.svelte. El CSS es el de
  la maqueta, en formas.css.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import { dinero } from '@app/lib/formato';
  import { urlImagen, type Producto } from '../lib/datos';
  import type { Formas } from '../lib/formas';
  import { quieto, rueda } from '../lib/movimiento';
  import { enlaceWhatsApp, mensajeWhatsApp, precioUnitario, type Cliente, type EnCarrito, type Hecho, type Tipo } from '../lib/pedido';
  import type { Moneda } from '../lib/preferencias';
  import { enSuLengua, type Lengua, type Textos } from '../lib/textos';
  import { quitarRevision } from '../lib/turnstile';
  import Icono from './Icono.svelte';

  let {
    renglones,
    productos,
    iconos,
    lengua,
    moneda,
    formas,
    t,
    barra,
    cerrado,
    conAsistente,
    haceEnvios,
    tipoCambio,
    telefono,
    tipo = $bindable(),
    cliente = $bindable(),
    aviso,
    limite,
    ocupado,
    hueco = $bindable(),
    hecho,
    alCantidad,
    alAbrirRenglon,
    alHacer,
    alEnviar,
    alMenu,
    alAsistente,
  }: {
    renglones: EnCarrito[];
    productos: Map<number, Producto>;
    // El ícono de la categoría de cada producto, para el cuadro de los que no tienen foto.
    iconos: Map<number, string>;
    lengua: Lengua;
    moneda: Moneda;
    formas: Formas;
    t: Textos;
    barra: Snippet;
    // Por qué no se reciben pedidos ahora (null: sí se reciben).
    cerrado: { icono: 'reloj' | 'apagado'; texto: string } | null;
    conAsistente: boolean;
    haceEnvios: boolean;
    tipoCambio: number | null;
    telefono: string;
    tipo: Tipo;
    cliente: Cliente & { pagaCon: string };
    aviso: { titulo?: string; texto: string } | null;
    limite: boolean;
    ocupado: boolean;
    hueco: HTMLDivElement | undefined;
    hecho: Hecho | null;
    alCantidad: (i: number, cambio: number) => void;
    alAbrirRenglon: (i: number, desde: HTMLElement) => void;
    alHacer: () => void;
    alEnviar: () => void;
    alMenu: () => void;
    alAsistente: () => void;
  } = $props();

  let cuerpo = $state<HTMLDivElement>();
  let boton = $state<HTMLButtonElement>();
  let icono = $state<HTMLSpanElement>();

  const dom = $derived(tipo === 'domicilio');
  // El pedido va siempre en pesos; con dólares, «MX$» y abajo del total su «≈ US$».
  const pesos = (n: number) => `${moneda === 'usd' ? 'MX' : ''}${dinero(n)}`;
  const unidad = (r: EnCarrito) => {
    const p = productos.get(r.producto_id);
    return p ? precioUnitario(p, r.opciones) : r.precio;
  };
  const importe = (r: EnCarrito) => Math.round(unidad(r) * r.cantidad * 100) / 100;
  // Lo tachado (ya no viene en el menú) no cuenta: se quita al volver a pedir.
  const vigentes = $derived(renglones.filter((r) => !r.aviso?.fuera));
  const cuantos = $derived(vigentes.reduce((s, r) => s + r.cantidad, 0));
  const total = $derived(Math.round(vigentes.reduce((s, r) => s + importe(r), 0) * 100) / 100);
  // Solo un «aprox.» para orientarse, con el dólar del día: el pedido se cobra en pesos.
  const usd = $derived(tipoCambio ? (total / tipoCambio).toFixed(2) : null);

  const que = $derived(hecho ? 'hecho' : cerrado ? 'cerrado' : renglones.length ? 'lista' : 'vacio');

  // Dos renglones iguales ya se sumaron en uno (mismoRenglon): su producto, sus opciones y su nota no se repiten.
  const llave = (r: EnCarrito) => `${r.producto_id}|${[...r.opciones].sort((a, b) => a - b).join(',')}|${r.nota}`;

  function opcionesTexto(r: EnCarrito): string {
    const p = productos.get(r.producto_id);
    if (!p) return '';
    return p.grupos
      .flatMap((g) => g.opciones)
      .filter((o) => r.opciones.includes(o.id))
      .map((o) => enSuLengua(o.nombre, o.nombre_en, lengua))
      .join(' · ');
  }

  // ─── Lo que falta para mandarlo: el botón se ve clarito y tocarlo te lleva ahí ───
  const digitos = (s: string) => s.replace(/[\s().-]/g, '');
  const falta = $derived.by((): string | null => {
    if (!cliente.nombre.trim()) return 'nombre';
    if (!/^\d{10}$/.test(digitos(cliente.telefono))) return 'telefono';
    if (dom && !cliente.direccion.trim()) return 'direccion';
    if (dom && cliente.pagaCon.trim() && !Number.isFinite(Number(cliente.pagaCon.trim()))) return 'pagaCon';
    return null;
  });
  const apagado = $derived(!!falta || limite || !vigentes.length);

  function alBoton() {
    if (ocupado) return;
    if (falta) return irAlQueFalta(falta);
    if (!apagado) alHacer();
  }

  function irAlQueFalta(k: string) {
    const i = cuerpo?.querySelector<HTMLInputElement>(`[data-campo="${k}"]`);
    const c = i?.closest<HTMLElement>('.f-campo');
    if (!cuerpo || !i || !c) return;
    const arriba = cuerpo.scrollTop + c.getBoundingClientRect().top - cuerpo.getBoundingClientRect().top - 90;
    cuerpo.scrollTo({ top: arriba, behavior: quieto() ? 'auto' : 'smooth' });
    i.focus({ preventScroll: true });
    // Tiembla otra vez aunque ya estuviera marcada.
    c.classList.remove('falta');
    void c.offsetWidth;
    c.classList.add('falta');
  }

  function sinFalta(e: Event) {
    (e.currentTarget as HTMLElement).closest('.f-campo')?.classList.remove('falta');
  }

  // ─── El − n + ───
  // Con 1, el bote: el renglón se encoge y se va antes de quitarlo.
  let quitando = false;
  function cambiar(e: MouseEvent, i: number, d: number) {
    const r = renglones[i];
    const l = (e.currentTarget as HTMLElement).closest<HTMLElement>('.f-ped-linea');
    if (r.cantidad + d > 0 || quieto() || !l) return alCantidad(i, d);
    if (quitando) return;
    quitando = true;
    const a = l.animate(
      [
        { opacity: 1, height: `${l.offsetHeight}px` },
        { opacity: 0, height: '0px', paddingTop: '0px', paddingBottom: '0px' },
      ],
      { duration: 220, easing: 'cubic-bezier(0.4, 0, 0.2, 1)', fill: 'forwards' },
    );
    a.onfinish = () => {
      quitando = false;
      alCantidad(i, d);
    };
  }

  // ─── El texto del botón siempre cabe ───
  // Lo más largo es inglés a domicilio en un celular angosto: primero se esconde el ícono y luego la letra baja de medio
  // en medio punto, hasta 12.
  function ajustar() {
    const b = boton;
    if (!b) return;
    const estilo = getComputedStyle(b);
    const lugar = b.clientWidth - parseFloat(estilo.paddingLeft) - parseFloat(estilo.paddingRight);
    const rango = document.createRange();
    const cabe = () => {
      rango.selectNodeContents(b);
      return rango.getBoundingClientRect().width <= lugar + 0.5;
    };
    b.style.fontSize = '';
    if (icono) icono.style.display = '';
    if (cabe()) return;
    if (icono) icono.style.display = 'none';
    for (let px = 15; px >= 12 && !cabe(); px -= 0.5) b.style.fontSize = `${px}px`;
  }

  $effect(() => {
    // Lo que cambia el texto del botón.
    void [total, dom, moneda, lengua, ocupado, boton];
    ajustar();
  });

  // También al cambiar el ancho (girar el celular) y cuando termina de llegar la letra del menú.
  $effect(() => {
    if (!boton) return;
    const observador = new ResizeObserver(ajustar);
    observador.observe(boton);
    document.fonts?.ready.then(ajustar).catch((error) => console.warn('[menu] no se supo si llegó la letra:', error));
    return () => observador.disconnect();
  });

  // La revisión de Cloudflare vive mientras se ve la lista (su hueco).
  $effect(() => {
    if (!hueco) return;
    return () => quitarRevision();
  });

  // ─── Mandado ───
  // Cada renglón como lo guardó Postgres; en inglés, con el inglés del menú si lo tiene.
  const hechos = $derived.by(() => {
    if (!hecho) return [];
    const { pedido, ids = [] } = hecho;
    return pedido.renglones.map((r, i) => {
      const p = ids.length === pedido.renglones.length ? productos.get(ids[i].producto_id) : undefined;
      if (!p || lengua === 'es') return { ...r, opciones: r.opciones.map((o) => o.opcion) };
      const elegidas = p.grupos.flatMap((g) => g.opciones).filter((o) => ids[i].opciones.includes(o.id));
      return {
        ...r,
        nombre: enSuLengua(r.nombre, p.nombre_en, lengua),
        opciones: elegidas.length === r.opciones.length ? elegidas.map((o) => enSuLengua(o.nombre, o.nombre_en, lengua)) : r.opciones.map((o) => o.opcion),
      };
    });
  });
  const enlace = $derived(hecho ? enlaceWhatsApp(telefono, mensajeWhatsApp(hecho.pedido)) : '');

  function aparece(_el: Element) {
    if (quieto()) return { duration: 0 };
    return { duration: 180, css: (x: number) => `opacity: ${x}` };
  }
  function seVa(_el: Element) {
    if (quieto()) return { duration: 0 };
    return { duration: 150, css: (x: number) => `opacity: ${x}` };
  }
</script>

<section
  class="f-ped"
  class:f-asis-pildora={formas.abajo === 'pildora'}
  class:f-asis-chica={!formas.abajo_con_nombres}
  class:dom
  aria-label={t.tuPedido}
  in:aparece
  out:seVa
>
  {@render barra()}

  <div class="f-asis-cuerpo f-ped-cuerpo" bind:this={cuerpo}>
    {#if que === 'hecho' && hecho}
      {@const p = hecho.pedido}
      <!-- Mandado: la palomita de línea que se dibuja, el título y su texto, que suben, y lo que pediste como ticket. Si el
           celular no dejó abrir WhatsApp, «Falta un paso» (el respaldo), con el globo del mensaje en lugar de la palomita. -->
      <div class="f-ped-exito entra">
        <div class="f-exito-arriba">
          {#if hecho.enviado}
            <svg class="f-exito-ic" viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <circle class="aro" cx="24" cy="24" r="19"></circle><path class="pal" d="M16 24.5l5.5 5.5L32.5 19"></path>
            </svg>
            <h2>{t.enviadoN(p.numero)}</h2>
            <p>{t.enviadoTexto}</p>
          {:else}
            <svg class="f-exito-ic falta" viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <path d="M15.8 40A18 18 0 1 0 8 32.2L4 44z"></path>
            </svg>
            <h2>{t.falta1}</h2>
            <p>{t.pedidoN(p.numero)} · {t.faltaTexto}</p>
          {/if}
        </div>
        <section class="f-ped-resumen f-exito-ticket">
          <div class="f-exito-tit"><span>{t.loQue}</span><span>{t.productos(p.renglones.reduce((s, r) => s + r.cantidad, 0))}</span></div>
          {#each hechos as r, i (i)}
            <div class="f-exito-l">
              <span class="n"><span><b>{r.cantidad} ×</b> {r.nombre}</span>{#if r.opciones.length}<small>{r.opciones.join(' · ')}</small>{/if}</span>
              <span>{pesos(r.importe)}</span>
            </div>
          {/each}
          <div class="f-ped-res-corte" aria-hidden="true"></div>
          <div class="t">
            <span>{t.total}</span>
            <span class="f-ped-total"><b>{pesos(p.total)}</b>{#if p.tipo === 'domicilio'}<small>{t.masEnvio}</small>{/if}</span>
          </div>
        </section>
      </div>
    {:else if que === 'cerrado' && cerrado}
      <!-- Sin pedidos: cuándo los reciben, y a dónde ir mientras. Como la de sin nada (13 nov 2026, el developer: «que sea
           parecida»): el título grande que sube, el reloj de línea del color de la carita, sin cuadro, y los botones cortos
           de contorno con su ícono, del mismo ancho. -->
      <div class="f-ped-vacio nada">
        <h2>{cerrado.texto}</h2>
        <p>{conAsistente ? t.cerradoTexto : t.cerradoSinAsistente}</p>
        <svg class="f-carita" viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <circle cx="24" cy="24" r="19"></circle>
          {#if cerrado.icono === 'reloj'}<path d="M24 14.5V24l6.5 4"></path>{:else}<path d="M10.6 10.6l26.8 26.8"></path>{/if}
        </svg>
        <div class="botones">
          <button type="button" class="f-ped-ir suave corto" onclick={alMenu}><Icono nombre="lista" tamano={17} grosor={1.9} />{t.verMenu}</button>
          {#if conAsistente}
            <button type="button" class="f-ped-ir suave corto" onclick={alAsistente}><Icono nombre="asistente" tamano={17} grosor={1.9} />{t.preguntar}</button>
          {/if}
        </div>
      </div>
    {:else if que === 'vacio'}
      <!-- Sin nada todavía: tranquila como la bienvenida del asistente, con la carita de línea que parpadea. -->
      <div class="f-ped-vacio nada">
        <h2>{t.vacio}</h2>
        <p>{t.vacioTexto}</p>
        <svg class="f-carita" viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true">
          <circle cx="24" cy="24" r="19"></circle><path class="ojo" d="M17.5 20.5v2"></path><path class="ojo" d="M30.5 20.5v2"></path><path
            class="boca"
            d="M16.5 33c2-2.6 4.6-3.9 7.5-3.9s5.5 1.3 7.5 3.9"
          ></path>
        </svg>
        <button type="button" class="f-ped-ir suave corto" onclick={alMenu}><Icono nombre="lista" tamano={17} grosor={1.9} />{t.verMenu}</button>
      </div>
    {:else}
      <div class="f-ped-dentro">
        <div class="f-ped-cabeza"><h2>{t.tuPedido}</h2><span>{t.productos(cuantos)}</span></div>

        <div class="f-ped-lineas">
          {#each renglones as r, i (llave(r))}
            {@const fuera = !!r.aviso?.fuera}
            {@const p = productos.get(r.producto_id)}
            {@const ops = opcionesTexto(r)}
            {@const cat = iconos.get(r.producto_id)}
            <div class="f-ped-linea" class:fuera>
              <button type="button" class="f-ped-q" disabled={fuera} onclick={(e) => alAbrirRenglon(i, e.currentTarget.closest<HTMLElement>('.f-ped-linea') ?? e.currentTarget)}>
                {#if p?.imagen_ruta}
                  <img src={urlImagen(p.imagen_ruta)} alt="" loading="lazy" decoding="async" />
                {:else}
                  <span class="sin-foto">{#if cat}<Icono categoria={cat} tamano={22} />{/if}</span>
                {/if}
                <span class="t">
                  <b>{enSuLengua(r.nombre, r.nombre_en, lengua)}</b>
                  {#if ops}<span class="d">{ops}</span>{/if}
                  {#if r.nota}<span class="d">{t.notaRenglon}{r.nota}</span>{/if}
                  {#if r.aviso}<span class="cambio"><Icono nombre="alerta" tamano={14} />{r.aviso.texto}</span>{/if}
                  <span class="imp"
                    >{pesos(importe(r))}{#if r.cantidad > 1}<small>{` · ${pesos(unidad(r))} ${t.cadaUno}`}</small>{/if}</span
                  >
                </span>
              </button>
              {#if !fuera}
                <span class="f-paso chico" role="group" aria-label={t.cantidad}>
                  <button type="button" aria-label={r.cantidad === 1 ? t.quitar : t.unoMenos} onclick={(e) => cambiar(e, i, -1)}>
                    <Icono nombre={r.cantidad === 1 ? 'eliminar' : 'menos'} tamano={15} grosor={2} />
                  </button>
                  <span class="n" use:rueda={r.cantidad}>{r.cantidad}</span>
                  <button type="button" aria-label={t.unoMas} disabled={r.cantidad >= 99} onclick={(e) => cambiar(e, i, 1)}>
                    <Icono nombre="mas" tamano={15} grosor={2} />
                  </button>
                </span>
              {/if}
            </div>
          {/each}
        </div>

        {#if haceEnvios}
          <!-- Un interruptor de dos: la elegida en una pastilla que se desliza. -->
          <section class="f-ped-seccion">
            <h3>{t.comoLoRecibes}</h3>
            <div class="f-ped-tipos" role="group" aria-label={t.comoLoRecibes}>
              <span class="f-ped-tipos-luz" aria-hidden="true"></span>
              <button type="button" class="f-ped-tipo" aria-pressed={!dom} onclick={() => (tipo = 'para_llevar')}>{t.llevar}</button>
              <button type="button" class="f-ped-tipo" aria-pressed={dom} onclick={() => (tipo = 'domicilio')}>{t.domicilio}</button>
            </div>
          </section>
        {/if}

        <!-- Tus datos en tarjetas por lo que significan: tú (el teléfono también para llevar: la caja te puede llamar si tu
             mensaje no llegó); a domicilio, a dónde y cómo pagas, que se despliegan. -->
        <section class="f-ped-seccion">
          <h3>{t.tusDatos}</h3>
          <div class="f-ped-tarjetas">
            <div class="f-ped-campos f-ped-tu">
              <div class="f-campo">
                <label for="f-ped-nombre">{t.tuNombre}</label>
                <input
                  id="f-ped-nombre"
                  data-campo="nombre"
                  bind:value={cliente.nombre}
                  placeholder={t.nombreEjemplo}
                  maxlength="60"
                  autocomplete="name"
                  oninput={sinFalta}
                />
              </div>
              <div class="f-campo">
                <label for="f-ped-tel">{t.telefono}</label>
                <input
                  id="f-ped-tel"
                  data-campo="telefono"
                  bind:value={cliente.telefono}
                  placeholder={t.telefonoEjemplo}
                  inputmode="tel"
                  autocomplete="tel-national"
                  oninput={sinFalta}
                />
              </div>
            </div>
            {#if haceEnvios}
              <div class="f-ped-dom" inert={!dom}>
                <div>
                  <div class="f-ped-dom-tarjetas">
                    <div class="f-ped-campos">
                      <div class="f-campo">
                        <label for="f-ped-dir">{t.tuDireccion}</label>
                        <input
                          id="f-ped-dir"
                          data-campo="direccion"
                          bind:value={cliente.direccion}
                          placeholder={t.direccionEjemplo}
                          maxlength="200"
                          autocomplete="street-address"
                          oninput={sinFalta}
                        />
                      </div>
                      <div class="f-campo">
                        <label for="f-ped-ref">{t.referencias}</label>
                        <input
                          id="f-ped-ref"
                          data-campo="referencias"
                          bind:value={cliente.referencias}
                          placeholder={t.referenciasEjemplo}
                          maxlength="120"
                          autocomplete="off"
                          oninput={sinFalta}
                        />
                      </div>
                    </div>
                    <div class="f-ped-campos">
                      <div class="f-campo">
                        <label for="f-ped-paga">{t.pagaCon}</label>
                        <input
                          id="f-ped-paga"
                          data-campo="pagaCon"
                          bind:value={cliente.pagaCon}
                          placeholder={t.pagaConEjemplo}
                          inputmode="decimal"
                          autocomplete="off"
                          oninput={sinFalta}
                        />
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            {/if}
          </div>
        </section>

        <!-- El resumen como un ticket: el subtotal (y a domicilio, el envío), el corte y el total, que rueda al cambiar. -->
        <section class="f-ped-resumen">
          <div class="f-ped-res-renglon"><span>{t.subtotal} · {t.productos(cuantos)}</span><span>{pesos(total)}</span></div>
          <div class="f-ped-res-renglon f-ped-envio"><span>{t.envio}</span><span>{t.envioTexto}</span></div>
          <div class="f-ped-res-corte" aria-hidden="true"></div>
          <div class="t">
            <span>{t.total}</span>
            <span class="f-ped-total"><b use:rueda={total}>{pesos(total)}</b><small class="f-ped-mas-envio">{t.masEnvio}</small></span>
          </div>
          {#if moneda === 'usd' && usd !== null}<div class="aprox">≈ US${usd} {t.aprox}</div>{/if}
        </section>
        <p class="f-ped-pista">{t.hacerPista}</p>
        <!-- La revisión de Cloudflare vive aquí; invisible mientras no duda. -->
        <div class="f-ped-hueco" bind:this={hueco}></div>
      </div>
    {/if}
  </div>

  {#if que === 'hecho' && hecho}
    <!-- Abajo, fijo donde estaba «Pedir por WhatsApp». -->
    <div class="f-ped-pie f-exito-pie entra">
      {#if hecho.enviado}
        <p>{t.noSeAbrio}</p>
        <a class="f-ped-ir suave" href={enlace} target="_blank" rel="noopener"><Icono nombre="mensaje" tamano={17} grosor={1.8} />{t.otraVez}</a>
      {:else}
        <a class="f-ped-boton" href={enlace} target="_blank" rel="noopener" onclick={alEnviar}
          ><Icono nombre="mensaje" tamano={18} grosor={1.9} /><span>{t.enviar}</span></a
        >
      {/if}
    </div>
  {:else if que === 'lista'}
    <div class="f-ped-pie">
      {#if aviso}
        <!-- Lo que no salió (cambió algo, un límite, sin internet), justo arriba del botón. -->
        <div class="m-aviso" role="alert">
          <Icono nombre="alerta" tamano={17} />
          <span>
            {#if aviso.titulo}<b>{aviso.titulo}.</b>{/if}
            {aviso.texto}
            {#if limite}
              <a class="f-asis-wa" href={`https://wa.me/52${telefono}`} target="_blank" rel="noopener"
                ><Icono nombre="mensaje" tamano={15} />{t.escribir}</a
              >
            {/if}
          </span>
        </div>
      {/if}
      <button type="button" class="f-ped-boton" aria-disabled={apagado} aria-busy={ocupado} onclick={alBoton} bind:this={boton}>
        {#if ocupado}
          <span class="f-ped-puntos" aria-hidden="true"><i></i><i></i><i></i></span><span>{t.mandando}</span>
        {:else}
          <span class="icono" bind:this={icono}><Icono nombre="mensaje" tamano={18} grosor={1.9} /></span><span
            >{t.hacer} · {pesos(total)}{dom ? t.masEnvio : ''}</span
          >
        {/if}
      </button>
    </div>
  {/if}
</section>

<style>
  /* Sin foto: el cuadro con el ícono de su categoría, como las tarjetas del menú. */
  .sin-foto {
    width: 52px;
    height: 52px;
    flex: none;
    display: grid;
    place-items: center;
    border-radius: 12px;
    background: var(--m-hoja);
    color: var(--m-suave);
  }

  /* Lo que cambió desde que lo agregaste (Postgres lo dijo al mandar): su aviso en el renglón; lo que ya no hay,
     tachado y sin − n +. */
  .cambio {
    display: flex;
    align-items: flex-start;
    gap: 6px;
    margin-top: 2px;
    font-size: 12.5px;
    font-weight: 700;
    line-height: 1.35;
    color: var(--m-texto);
  }

  .cambio :global(svg) {
    flex: none;
    margin-top: 1px;
  }

  .fuera b,
  .fuera .imp {
    color: var(--m-tenue);
    text-decoration: line-through;
  }

  .fuera .d,
  .fuera img {
    opacity: 0.55;
  }

  .f-ped-q:disabled {
    cursor: default;
  }

  /* La revisión de Cloudflare no ocupa lugar mientras no duda; si duda, va al centro. */
  .f-ped-hueco {
    display: contents;
  }

  .f-ped-hueco > :global(*) {
    align-self: center;
  }

  .f-ped-pie .m-aviso {
    margin: 0 0 10px;
  }

  .f-ped-pie .m-aviso .f-asis-wa {
    margin-top: 10px;
    text-decoration: none;
  }

  .icono {
    display: flex;
  }

  a.f-ped-boton,
  a.f-ped-ir {
    text-decoration: none;
  }

  /* Sin pedidos: los dos botones uno sobre otro, del ancho del más largo. */
  .botones {
    display: inline-grid;
    gap: 8px;
  }

  /* «Falta un paso»: el globo del mensaje, del color de tu menú, ya dibujado. */
  .f-exito-ic.falta {
    color: var(--m-asis);
  }
</style>
