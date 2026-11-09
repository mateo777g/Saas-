<!--
  La búsqueda grande de Inicio (maqueta V64Pv4gmANPRZuJW5hTe5D; Ctrl K desde cualquier vista): encuentra
  vistas y acciones sin leer la base, sin que estorben los acentos ni las mayúsculas. Sin escribir, salen
  Recientes y las primeras 4 acciones. Se mueve con ↑ ↓, Enter abre y Esc cierra. Cada panel pone sus
  renglones. Desde el 7 de noviembre es una píldora con el brillo de Haz, y su ventanita sale como las ideas
  del Agente IA: ella primero y luego, en fila, cada título y cada renglón (maqueta 4B6Qhre6dkK3pJgXtryyEV v3).
  Con `alCerrar` va dentro de BuscarAqui (la que se abre en cualquier vista, 9 nov 2026): no se cierra al perder el
  foco, Esc y elegir algo la cierran, y toma el ancho de su ventana.
-->
<script lang="ts" module>
  export type RenglonBusqueda = { clave: string; texto: string; de?: string; icono: string; alPicar: () => void };
</script>

<script lang="ts">
  import { tick } from 'svelte';
  import Haz from './Haz.svelte';
  import Icono from './Icono.svelte';

  let {
    vistas,
    acciones,
    recientes,
    placeholder = 'Busca una vista o una acción…',
    alCerrar,
  }: {
    vistas: RenglonBusqueda[];
    acciones: RenglonBusqueda[];
    recientes: RenglonBusqueda[];
    // El distribuidor no tiene acciones: «Busca una vista…» (8 nov 2026).
    placeholder?: string;
    // Solo en BuscarAqui: cierra su ventana.
    alCerrar?: () => void;
  } = $props();

  type Seccion = { titulo: string; renglones: RenglonBusqueda[] };

  let texto = $state('');
  let abierta = $state(false);
  // Ya se escribió desde que abrió: los resultados cambian sin esperar la fila.
  let ya = $state(false);
  let marcado = $state(0);
  let campo: HTMLInputElement;
  let cuerpo = $state<HTMLDivElement | null>(null);

  const limpio = (s: string) =>
    s
      .normalize('NFD')
      .replace(/[̀-ͯ]/g, '')
      .toLowerCase();

  const secciones = $derived.by((): Seccion[] => {
    const q = limpio(texto.trim());
    if (!q) {
      const hay = [
        { titulo: 'Recientes', renglones: recientes },
        { titulo: 'Acciones', renglones: acciones.slice(0, 4) },
      ].filter((s) => s.renglones.length);
      // Sin recientes ni acciones (el distribuidor la primera vez), salen sus vistas y no un «no hay».
      return hay.length ? hay : [{ titulo: 'Vistas', renglones: vistas }];
    }
    const hallados = vistas.filter((v) => limpio(v.texto).includes(q));
    const hechos = acciones.filter((a) => limpio(`${a.texto} ${a.de ?? ''}`).includes(q));
    return [
      { titulo: 'Vistas', renglones: hallados },
      { titulo: 'Acciones', renglones: hechos },
    ].filter((s) => s.renglones.length);
  });
  const todos = $derived(secciones.flatMap((s) => s.renglones));

  // El lugar de cada título en la fila (la ventanita es el 0); sus renglones van justo después.
  const lugares = $derived.by(() => {
    let i = 1;
    return secciones.map((s) => {
      const lugar = i;
      i += 1 + s.renglones.length;
      return lugar;
    });
  });

  $effect(() => {
    void texto;
    marcado = 0;
  });

  $effect(() => {
    void marcado;
    tick().then(() => cuerpo?.querySelector('.marcado')?.scrollIntoView({ block: 'nearest' }));
  });

  function elegir(r: RenglonBusqueda | undefined) {
    if (!r) return;
    if (alCerrar) {
      alCerrar();
      r.alPicar();
      return;
    }
    texto = '';
    abierta = false;
    ya = false;
    campo.blur();
    r.alPicar();
  }

  function alTeclear(e: KeyboardEvent) {
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      marcado = Math.min(marcado + 1, todos.length - 1);
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      marcado = Math.max(marcado - 1, 0);
    } else if (e.key === 'Enter') {
      e.preventDefault();
      elegir(todos[marcado]);
    } else if (e.key === 'Escape') {
      if (alCerrar) {
        e.preventDefault();
        alCerrar();
        return;
      }
      abierta = false;
      campo.blur();
    }
  }

  export function enfocar() {
    campo.focus();
    abierta = true;
  }
</script>

<div class="buscador" class:abierta class:ya class:flotante={!!alCerrar}>
  <Haz>
    <label class="campo">
      <Icono nombre="r-buscar" tamano={18} />
      <input
        bind:this={campo}
        bind:value={texto}
        type="text"
        autocomplete="off"
        {placeholder}
        role="combobox"
        aria-label="Busca una vista o una acción"
        aria-controls="resultados-busqueda"
        aria-expanded={abierta}
        onfocus={() => {
          ya = false;
          abierta = true;
        }}
        oninput={() => {
          abierta = true;
          ya = true;
        }}
        onblur={() => {
          if (alCerrar) return;
          setTimeout(() => {
            abierta = false;
            ya = false;
          }, 120);
        }}
        onkeydown={alTeclear}
      />
      <kbd>Ctrl</kbd><kbd>K</kbd>
    </label>
  </Haz>

  <!-- Siempre está puesta: cerrada no se ve ni se puede picar, y así puede salir en fila al abrir. -->
  <div class="lista aparece" style:--i={0}>
    <div class="lista-cuerpo" id="resultados-busqueda" bind:this={cuerpo} role="listbox" aria-label="Resultados">
      {#if !todos.length}
        <div class="vacia">No hay una vista ni una acción con «{texto.trim()}».</div>
      {/if}
      {#each secciones as s, si (s.titulo)}
        <div class="etiqueta seccion aparece" style:--i={lugares[si]}>{s.titulo}</div>
        {#each s.renglones as r, j (r.texto)}
          {@const i = todos.indexOf(r)}
          <button
            type="button"
            class="renglon aparece"
            style:--i={lugares[si] + 1 + j}
            class:marcado={i === marcado}
              role="option"
            aria-selected={i === marcado}
            onmousemove={() => (marcado = i)}
            onmousedown={(e) => {
              e.preventDefault();
              elegir(r);
            }}
          >
            <span class="icono"><Icono nombre={r.icono} tamano={18} /></span>
            <span>{r.texto}</span>
            {#if r.de}<span class="de">— {r.de}</span>{/if}
            <span class="ir"><Icono nombre="r-derecha" tamano={14} /></span>
          </button>
        {/each}
      {/each}
    </div>
    <div class="lista-pie"><span>↑ ↓ para moverte</span><span>↵ para abrir</span><span>Esc para cerrar</span></div>
  </div>
</div>

<style>
  .buscador {
    position: relative;
    width: 100%;
    max-width: 780px;
    margin: 30px auto 0;
  }

  .buscador.flotante {
    max-width: none;
    margin: 0;
  }

  /* Como la píldora del Agente IA: 48 px, sin aro, el borde de las tarjetas y, con foco, el fuerte. */
  .campo {
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

  .campo:focus-within {
    border-color: var(--linea-fuerte);
  }

  input {
    flex: 1;
    min-width: 0;
    border: 0;
    outline: 0;
    background: none;
    font-size: 15px;
    font-weight: 400;
    color: var(--texto);
  }

  input::placeholder {
    color: var(--tenue);
    opacity: 1;
  }

  kbd {
    font-weight: 400;
    padding: 1px 5px;
    border: 1px solid var(--linea);
    border-radius: 5px;
    background: var(--suelo);
    font-family: var(--mono);
    font-size: 10.5px;
    color: var(--tenue);
  }

  .lista {
    position: absolute;
    z-index: 20;
    left: 0;
    right: 0;
    top: calc(100% + 8px);
    overflow: hidden;
    background: var(--solido);
    border: 1px solid var(--linea-fuerte);
    border-radius: 14px;
    box-shadow: 0 18px 40px var(--sombra-menu);
  }

  .lista-cuerpo {
    max-height: 340px;
    overflow-y: auto;
    padding: 8px;
  }

  .seccion {
    padding: 10px 10px 6px;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  .renglon {
    width: 100%;
    height: 40px;
    display: flex;
    align-items: center;
    gap: 11px;
    padding: 0 10px;
    border: 0;
    border-radius: 9px;
    background: transparent;
    color: var(--texto);
    font-size: 14px;
    font-weight: 400;
    text-align: left;
  }

  .renglon.marcado {
    background: var(--chip);
  }

  .icono {
    display: flex;
    color: var(--suave);
  }

  .de {
    font-size: 13px;
    color: var(--tenue);
  }

  .ir {
    display: flex;
    margin-left: auto;
    color: var(--tenue);
    opacity: 0;
  }

  .marcado .ir {
    opacity: 1;
  }

  .lista-pie {
    display: flex;
    gap: 16px;
    padding: 9px 16px;
    border-top: 1px solid var(--linea);
    font-size: 11.5px;
    font-weight: 400;
    color: var(--tenue);
  }

  .vacia {
    padding: 18px 12px;
    font-size: 13.5px;
    font-weight: 400;
    color: var(--suave);
  }

  /* La ventanita, como las ideas del Agente IA: sube 10 px desde 97 % con su resorte, a 220 ms + 80 ms × i.
     Al cerrar se van juntos en 0.15 s. */
  .buscador .aparece {
    opacity: 0;
    visibility: hidden;
    transform: translateY(10px) scale(0.97);
    transition:
      opacity 0.15s ease,
      transform 0.15s ease,
      visibility 0s linear 0.15s;
  }

  .buscador.abierta .aparece {
    --espera: calc(220ms + var(--i) * 80ms);
    opacity: 1;
    visibility: visible;
    transform: none;
    transition:
      opacity 0.35s ease var(--espera),
      transform 0.45s cubic-bezier(0.175, 0.885, 0.32, 1.275) var(--espera),
      visibility 0s linear var(--espera);
  }

  /* Mientras escribes, los resultados cambian sin esperar. */
  .buscador.abierta.ya .aparece {
    transition: none;
  }

  @media (prefers-reduced-motion: reduce) {
    .buscador .aparece,
    .buscador.abierta .aparece {
      transition: none !important;
    }
  }
</style>
