<!--
  La plática con el asistente (parte 6c; maqueta 2UPwZw31WrcYRZkH8jaT1Y, sección 1): sube desde abajo,
  casi a toda la pantalla, como las otras hojas del menú. Arriba «Asistente de La Fonda de Don Chuy»
  y su X; luego el saludo fijo (no gasta) con las 3 sugeridas antes de la primera pregunta, sus
  preguntas en burbujas del color de Don Chuy y las respuestas con la estrella de Fragmentless a un
  lado, con las tarjetas de los productos que nombró (su foto y su precio del menú; al tocarlas se
  abre su hoja, encima). Abajo la caja y «IA de Fragmentless · puede equivocarse» con la estrella.
  La estrella, en degradado, en su versión para el fondo de la hoja: la oficial en el tema claro, la
  de fondo negro en el oscuro (decidido en la prueba de Banderitas, el 31 de octubre de 2026; antes,
  la ∫∫ en la tinta del tema).

  Sin IA, el aviso va en lugar del saludo y la caja se apaga; con plática guardada, el aviso va al
  final (encuesta 1 de planes/trabajo/6c/menu-6c.md). En el límite, el aviso sale como respuesta y
  la caja sigue prendida. La revisión de Cloudflare vive en su hueco, abajo de su pregunta.
-->
<script lang="ts">
  import { onMount, tick, type Snippet } from 'svelte';
  import type { Mensaje, Motivo, Platica } from '../lib/asistente.svelte';
  import { urlImagen, type MenuPublico, type Producto } from '../lib/datos';
  import type { Moneda } from '../lib/preferencias';
  import { enSuLengua, type Lengua, type Textos } from '../lib/textos';
  import { quitarRevision } from '../lib/turnstile';
  import Estrella from './Estrella.svelte';
  import Icono from './Icono.svelte';
  import Precio from './Precio.svelte';

  let {
    platica,
    menu,
    productos,
    lengua,
    moneda,
    tema,
    t,
    alPreguntar,
    alAbrirProducto,
    alCerrar,
  }: {
    platica: Platica;
    menu: MenuPublico;
    productos: Map<number, Producto>;
    lengua: Lengua;
    moneda: Moneda;
    tema: string;
    t: Textos;
    alPreguntar: (pregunta: string, hueco: HTMLElement) => void;
    alAbrirProducto: (p: Producto) => void;
    alCerrar: () => void;
  } = $props();

  // La caja crece hasta 4 renglones: 8 px arriba y abajo y 23.2 por renglón.
  const ALTO_CAJA = 40;
  const ALTO_MAXIMO = 109;

  let hoja: HTMLDivElement;
  let lista = $state<HTMLDivElement>();
  let campo = $state<HTMLTextAreaElement>();
  let hueco = $state<HTMLDivElement>();

  const fondo = $derived(tema === 'oscuro' ? 'negro' : 'blanco');
  const nombre = $derived(menu.restaurante.nombre);
  const telefono = $derived(menu.restaurante.telefono);
  const contesta = $derived(menu.asistente_contesta);
  const ultimo = $derived(platica.mensajes.at(-1));
  const avisoAlFinal = $derived(
    !contesta && platica.mensajes.length > 0 && !(ultimo?.rol === 'aviso' && ultimo.motivo === 'sin_ia'),
  );
  const sugeridas = $derived(
    contesta && !platica.mensajes.length && platica.pendiente === null && !platica.noContesto,
  );
  const ocupado = $derived(platica.pendiente !== null);

  function textoAviso(motivo: Motivo): string {
    if (motivo === 'sin_ia') return t.sinIa + (telefono ? t.sinIaWa : '');
    return (motivo === 'limite_celular' ? t.limiteCelular : t.limiteConexion) + (telefono ? t.limiteWa : t.limiteTarde);
  }

  const parrafos = (texto: string) => texto.split(/\n+/).filter((p) => p.trim());
  const tarjetas = (m: Mensaje) =>
    m.rol === 'asistente' ? m.productos.map((id) => productos.get(id)).filter((p): p is Producto => !!p) : [];

  function enviar() {
    const pregunta = platica.borrador.trim();
    if (!pregunta || ocupado || !contesta || !hueco) return;
    platica.borrador = '';
    alPreguntar(pregunta, hueco);
  }

  function sugerir(pregunta: string) {
    if (!ocupado && hueco) alPreguntar(pregunta, hueco);
  }

  function alTeclear(e: KeyboardEvent) {
    if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
      e.preventDefault();
      enviar();
    }
  }

  $effect(() => {
    void platica.borrador;
    const c = campo;
    if (!c) return;
    c.style.height = 'auto';
    c.style.height = `${Math.min(Math.max(c.scrollHeight, ALTO_CAJA), ALTO_MAXIMO)}px`;
  });

  // Al abrir, y cada vez que llega algo, baja hasta lo último.
  $effect(() => {
    void platica.mensajes;
    void platica.pendiente;
    void platica.noContesto;
    void contesta;
    tick().then(() => {
      if (lista) lista.scrollTop = lista.scrollHeight;
    });
  });

  onMount(() => {
    hoja.focus({ preventScroll: true });
    return () => quitarRevision();
  });
</script>

{#snippet botonWa()}
  <a class="boton-wa" href="https://wa.me/52{telefono}" target="_blank" rel="noopener"><Icono nombre="mensaje" tamano={15} />{t.escribir}</a>
{/snippet}

{#snippet respuesta(cuerpo: Snippet)}
  <div class="resp">
    <span class="logo"><Estrella {fondo} tamano={24} /></span>
    <div class="cuerpo">{@render cuerpo()}</div>
  </div>
{/snippet}

{#snippet aviso(motivo: Motivo)}
  {#snippet cuerpo()}
    <p>{textoAviso(motivo)}</p>
    {#if telefono}{@render botonWa()}{/if}
  {/snippet}
  {@render respuesta(cuerpo)}
{/snippet}

<!-- El velo es un atajo del dedo; con el teclado se cierra con Escape (Menu.svelte). -->
<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
<div class="velo" onclick={alCerrar}></div>
<div class="hoja" role="dialog" aria-modal="true" aria-label={t.asistente(nombre)} tabindex="-1" bind:this={hoja}>
  <div class="agarre"></div>
  <div class="cabeza">
    <h3 class="titulo">{t.asistente(nombre)}</h3>
    <button type="button" class="cerrar" aria-label={t.cerrar} onclick={alCerrar}><Icono nombre="cerrar" tamano={18} /></button>
  </div>

  <div class="mensajes" bind:this={lista} aria-live="polite">
    {#if !contesta && !platica.mensajes.length}
      {@render aviso('sin_ia')}
    {:else}
      {#snippet saludo()}
        <p>{t.saludo(nombre)}</p>
        {#if sugeridas}
          <div class="sugeridas">
            {#each t.sugeridas as s (s)}
              <button type="button" class="sugerida" onclick={() => sugerir(s)}>{s}</button>
            {/each}
          </div>
        {/if}
      {/snippet}
      {@render respuesta(saludo)}
    {/if}

    {#each platica.mensajes as m, i (i)}
      {#if m.rol === 'cliente'}
        <div class="ella">{m.texto}</div>
      {:else if m.rol === 'aviso'}
        {@render aviso(m.motivo)}
      {:else}
        {@const lasTarjetas = tarjetas(m)}
        {#snippet cuerpo()}
          {#each parrafos(m.texto) as p, j (j)}<p>{p}</p>{/each}
          {#if lasTarjetas.length}
            <div class="tarjetas">
              {#each lasTarjetas as p (p.id)}
                <button type="button" class="tarjeta" onclick={() => alAbrirProducto(p)}>
                  {#if p.imagen_ruta}<img class="foto" src={urlImagen(p.imagen_ruta)} alt="" loading="lazy" decoding="async" />{/if}
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
        {@render respuesta(cuerpo)}
      {/if}
    {/each}

    {#if avisoAlFinal}{@render aviso('sin_ia')}{/if}

    {#if platica.pendiente !== null}
      <div class="ella">{platica.pendiente}</div>
      <div class="pensando"><Estrella {fondo} tamano={26} pensando /><span>{t.pensando}</span></div>
    {/if}
    <div class="hueco" bind:this={hueco}></div>

    {#if platica.noContesto}
      <div class="m-aviso" role="alert"><Icono nombre="alerta" tamano={17} /><span>{t.noContesto}</span></div>
    {/if}
  </div>

  <div class="pie">
    <div class="caja" class:apagada={!contesta}>
      <textarea
        bind:this={campo}
        bind:value={platica.borrador}
        rows="1"
        maxlength="300"
        placeholder={t.escribe}
        aria-label={t.escribe}
        enterkeyhint="send"
        disabled={!contesta}
        onkeydown={alTeclear}
      ></textarea>
      <button type="button" class="enviar" aria-label={t.enviarPregunta} disabled={!contesta || ocupado} onclick={enviar}>
        <Icono nombre="flecha" tamano={18} />
      </button>
    </div>
    <p class="marca"><Estrella {fondo} tamano={16} /><span>{t.marcaIa}</span></p>
  </div>
</div>

<style>
  .velo {
    position: fixed;
    inset: 0;
    background: var(--m-velo);
    z-index: 5;
  }

  /* Como Hoja.svelte, pero alta: los mensajes arriba y la caja abajo. */
  .hoja {
    position: fixed;
    left: 0;
    right: 0;
    bottom: 0;
    width: 100%;
    max-width: 520px;
    height: 90%;
    margin: 0 auto;
    z-index: 6;
    background: var(--m-hoja);
    border-radius: 26px 26px 0 0;
    box-shadow: 0 -12px 40px var(--m-sombra);
    display: flex;
    flex-direction: column;
    outline: none;
  }

  .agarre {
    width: 38px;
    height: 5px;
    border-radius: 3px;
    background: var(--m-linea);
    margin: 9px auto 0;
    flex: none;
  }

  .cabeza {
    flex: none;
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 10px 18px 12px;
    border-bottom: 1px solid var(--m-linea);
  }

  .titulo {
    flex: 1;
    min-width: 0;
    margin: 0;
    font-size: 16.5px;
    font-weight: 800;
    letter-spacing: -0.3px;
    line-height: 1.25;
  }

  .cerrar {
    width: 40px;
    height: 40px;
    flex: none;
    border-radius: 20px;
    border: 1px solid var(--m-linea);
    background: transparent;
    color: var(--m-texto);
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0;
  }

  .mensajes {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    overscroll-behavior: contain;
    padding: 18px 18px 10px;
    display: flex;
    flex-direction: column;
    gap: 18px;
    scrollbar-width: none;
  }

  .mensajes::-webkit-scrollbar {
    display: none;
  }

  .resp {
    display: flex;
    gap: 10px;
    flex: none;
  }

  .logo {
    width: 26px;
    height: 26px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--m-texto);
  }

  .cuerpo {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 12px;
    padding-top: 2px;
  }

  .cuerpo p {
    margin: 0;
    font-size: 15px;
    line-height: 1.55;
    overflow-wrap: anywhere;
  }

  .ella {
    align-self: flex-end;
    max-width: 82%;
    padding: 10px 14px;
    border-radius: 18px 18px 6px 18px;
    background: var(--m-acento);
    color: var(--m-sobre-acento);
    font-size: 15px;
    line-height: 1.45;
    flex: none;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }

  .sugeridas {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }

  .sugerida {
    height: 38px;
    padding: 0 14px;
    border-radius: 19px;
    border: 1px solid var(--m-linea);
    background: transparent;
    color: var(--m-texto);
    font-size: 13.5px;
    font-weight: 600;
  }

  .boton-wa {
    align-self: flex-start;
    text-decoration: none;
    display: inline-flex;
    align-items: center;
    gap: 8px;
    height: 36px;
    padding: 0 14px;
    border-radius: 18px;
    border: 1px solid var(--m-linea);
    background: transparent;
    color: var(--m-texto);
    font-size: 13px;
    font-weight: 600;
  }

  .tarjetas {
    align-self: stretch;
    display: flex;
    flex-direction: column;
    border-radius: 16px;
    border: 1px solid var(--m-linea);
    overflow: hidden;
  }

  .tarjeta {
    display: flex;
    align-items: center;
    gap: 12px;
    width: 100%;
    padding: 10px 12px 10px 10px;
    border: 0;
    border-bottom: 1px solid var(--m-linea);
    background: transparent;
    color: var(--m-texto);
    text-align: left;
  }

  .tarjeta:last-child {
    border-bottom: 0;
  }

  .tarjeta > :global(svg) {
    color: var(--m-tenue);
  }

  .foto {
    width: 52px;
    height: 52px;
    border-radius: 12px;
    flex: none;
    object-fit: cover;
    background: var(--m-chip);
  }

  .t {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .t b {
    font-size: 14.5px;
    font-weight: 700;
    line-height: 1.3;
  }

  .t > span {
    font-size: 14px;
    font-weight: 800;
    font-variant-numeric: tabular-nums;
  }

  .pensando {
    display: flex;
    align-items: center;
    gap: 10px;
    color: var(--m-texto);
    flex: none;
  }

  .pensando span {
    font-size: 14px;
    font-weight: 500;
    color: var(--m-suave);
  }

  /* Invisible mientras Cloudflare no duda: no ocupa lugar ni hueco entre mensajes. */
  .hueco {
    display: contents;
  }

  .mensajes .m-aviso {
    margin-top: 0;
    flex: none;
  }

  .pie {
    flex: none;
    padding: 10px 16px calc(22px + env(safe-area-inset-bottom, 0px));
    border-top: 1px solid var(--m-linea);
    display: flex;
    flex-direction: column;
    gap: 10px;
    background: var(--m-hoja);
  }

  .caja {
    display: flex;
    align-items: flex-end;
    gap: 8px;
    padding: 5px 5px 5px 16px;
    border: 1px solid var(--m-linea);
    border-radius: 22px;
  }

  .caja.apagada {
    background: var(--m-chip);
  }

  textarea {
    flex: 1;
    min-width: 0;
    height: 40px;
    resize: none;
    border: 0;
    outline: none;
    background: transparent;
    color: var(--m-texto);
    font: inherit;
    font-size: 16px;
    line-height: 1.45;
    padding: 8px 0;
  }

  textarea::placeholder {
    color: var(--m-tenue);
    opacity: 1;
  }

  .enviar {
    width: 40px;
    height: 40px;
    flex: none;
    border-radius: 20px;
    border: 0;
    padding: 0;
    background: var(--m-acento);
    color: var(--m-sobre-acento);
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .enviar:disabled {
    opacity: 0.35;
    cursor: default;
  }

  .marca {
    margin: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    font-size: 11.5px;
    font-weight: 600;
    color: var(--m-tenue);
  }
</style>
