<!--
  La hoja de un producto con opciones (maqueta Mesero y cocina, estado «Opciones»): pregunta cada
  grupo en el orden de Mi menú, con cómo se elige; sin elegir lo obligatorio no se agrega. Una
  opción agotada sale en gris y no se toca. Abajo, la nota, cuántos y «Agregar» con el precio que
  pondrá Postgres al mandarlo.
-->
<script lang="ts">
  import Icono from '../../diseno/Icono.svelte';
  import { dinero } from '../../lib/formato';
  import { regla } from '../../lib/opciones';
  import type { Grupo, ProductoPos } from '../../lib/pos';
  import Hoja from './Hoja.svelte';

  let {
    producto,
    alCerrar,
    alAgregar,
  }: {
    producto: ProductoPos;
    alCerrar: () => void;
    alAgregar: (opciones: number[], nota: string, cantidad: number) => void;
  } = $props();

  let elegidas = $state<Record<number, number[]>>({});
  let nota = $state('');
  let cantidad = $state(1);

  const falta = $derived(producto.grupos.find((g) => (elegidas[g.id]?.length ?? 0) < g.minimo) ?? null);
  const precio = $derived(
    producto.precio +
      producto.grupos.reduce(
        (s, g) => s + g.opciones.filter((o) => elegidas[g.id]?.includes(o.id)).reduce((t, o) => t + o.precio_extra, 0),
        0,
      ),
  );

  // De uno: tocar otra la cambia (y tocar la misma la quita si el grupo es opcional). De varios:
  // se prende y se apaga, hasta el máximo.
  function tocar(g: Grupo, id: number) {
    const ya = elegidas[g.id] ?? [];
    if (g.maximo === 1) elegidas[g.id] = ya.includes(id) && g.minimo === 0 ? [] : [id];
    else if (ya.includes(id)) elegidas[g.id] = ya.filter((x) => x !== id);
    else if (ya.length < g.maximo) elegidas[g.id] = [...ya, id];
  }

  function agregar() {
    // En el orden de los grupos y de sus opciones, como las guarda Postgres.
    const ids = producto.grupos.flatMap((g) => g.opciones.filter((o) => elegidas[g.id]?.includes(o.id)).map((o) => o.id));
    alAgregar(ids, nota.trim(), cantidad);
  }
</script>

<Hoja titulo={producto.nombre} sub={dinero(producto.precio)} {alCerrar}>
  {#each producto.grupos as g (g.id)}
    <div class="grupo-op">
      <div class="grupo-op-cabeza"><b>{g.nombre}</b><span>{regla(g.minimo, g.maximo)}</span></div>
      {#each g.opciones as o (o.id)}
        {@const si = elegidas[g.id]?.includes(o.id) ?? false}
        <button
          type="button"
          class="op"
          role={g.maximo === 1 ? 'radio' : 'checkbox'}
          aria-checked={si}
          disabled={!o.visible}
          onclick={() => tocar(g, o.id)}
        >
          <span class="marca" class:redonda={g.maximo === 1} class:cuadrada={g.maximo !== 1}>
            {#if si}<Icono nombre="check" tamano={11} />{/if}
          </span>
          {o.nombre}
          <span class="extra">{!o.visible ? 'Agotada' : o.precio_extra ? `+${dinero(o.precio_extra)}` : ''}</span>
        </button>
      {/each}
    </div>
  {/each}
  <div class="campo">
    <label class="etq" for="hoja-nota">Nota</label>
    <input id="hoja-nota" bind:value={nota} placeholder="Ej. «sin cebolla»" autocomplete="off" maxlength="200" />
  </div>
  <div class="fila-cant">
    <span class="paso">
      <button type="button" aria-label="Uno menos" onclick={() => (cantidad = Math.max(1, cantidad - 1))}>
        <Icono nombre="menos" tamano={16} />
      </button>
      <span>{cantidad}</span>
      <button type="button" aria-label="Uno más" onclick={() => (cantidad += 1)}><Icono nombre="mas" tamano={16} /></button>
    </span>
    <button type="button" class="cel-boton" disabled={!!falta} onclick={agregar}>
      {falta ? `Falta elegir ${falta.nombre.toLowerCase()}` : `Agregar · ${dinero(precio * cantidad)}`}
    </button>
  </div>
</Hoja>
