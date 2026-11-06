<!--
  La búsqueda grande de Inicio (maqueta V64Pv4gmANPRZuJW5hTe5D; Ctrl K desde cualquier vista): encuentra
  vistas y acciones sin leer la base, sin que estorben los acentos ni las mayúsculas. Sin escribir, salen
  Recientes y las primeras 4 acciones. Se mueve con ↑ ↓, Enter abre y Esc cierra. Cada panel pone sus
  renglones.
-->
<script lang="ts" module>
  export type RenglonBusqueda = { clave: string; texto: string; de?: string; icono: string; alPicar: () => void };
</script>

<script lang="ts">
  import { tick } from 'svelte';
  import Icono from './Icono.svelte';

  let {
    vistas,
    acciones,
    recientes,
  }: {
    vistas: RenglonBusqueda[];
    acciones: RenglonBusqueda[];
    recientes: RenglonBusqueda[];
  } = $props();

  type Seccion = { titulo: string; renglones: RenglonBusqueda[] };

  let texto = $state('');
  let abierta = $state(false);
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
      return [
        { titulo: 'Recientes', renglones: recientes },
        { titulo: 'Acciones', renglones: acciones.slice(0, 4) },
      ].filter((s) => s.renglones.length);
    }
    const hallados = vistas.filter((v) => limpio(v.texto).includes(q));
    const hechos = acciones.filter((a) => limpio(`${a.texto} ${a.de ?? ''}`).includes(q));
    return [
      { titulo: 'Vistas', renglones: hallados },
      { titulo: 'Acciones', renglones: hechos },
    ].filter((s) => s.renglones.length);
  });
  const todos = $derived(secciones.flatMap((s) => s.renglones));

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
    texto = '';
    abierta = false;
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
      abierta = false;
      campo.blur();
    }
  }

  export function enfocar() {
    campo.focus();
    abierta = true;
  }
</script>

<div class="buscador">
  <label class="campo">
    <Icono nombre="r-buscar" tamano={18} />
    <input
      bind:this={campo}
      bind:value={texto}
      type="text"
      autocomplete="off"
      placeholder="Busca una vista o una acción…"
      role="combobox"
      aria-label="Busca una vista o una acción"
      aria-controls="resultados-busqueda"
      aria-expanded={abierta}
      onfocus={() => (abierta = true)}
      oninput={() => (abierta = true)}
      onblur={() => setTimeout(() => (abierta = false), 120)}
      onkeydown={alTeclear}
    />
    <kbd>Ctrl</kbd><kbd>K</kbd>
  </label>

  {#if abierta}
    <div class="lista">
      <div class="lista-cuerpo" id="resultados-busqueda" bind:this={cuerpo} role="listbox" aria-label="Resultados">
        {#if !todos.length}
          <div class="vacia">No hay una vista ni una acción con «{texto.trim()}».</div>
        {/if}
        {#each secciones as s (s.titulo)}
          <div class="etiqueta seccion">{s.titulo}</div>
          {#each s.renglones as r (r.texto)}
            {@const i = todos.indexOf(r)}
            <button
              type="button"
              class="renglon"
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
  {/if}
</div>

<style>
  .buscador {
    position: relative;
    width: 100%;
    max-width: 780px;
    margin: 30px auto 0;
  }

  .campo {
    height: 54px;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 14px 0 18px;
    border: 1px solid var(--linea-fuerte);
    border-radius: 14px;
    background: var(--solido);
    box-shadow: 0 0 0 5px var(--chip);
    color: var(--tenue);
  }

  .campo:focus-within {
    border-color: var(--texto);
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
</style>
