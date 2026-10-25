<!--
  El horario de los 7 días en «Tu restaurante» (maqueta de la 6a Qx4C5CbKJYpeAsJCfw4ghn, sección 2;
  libreta 6, decidido el 20 de octubre de 2026): cada día dice «Abre» con sus dos horas, o
  «Cerrado». Si cierra antes de la hora en que abre, cierra al día siguiente y lo dice («del
  sábado»). Las horas van de media en media; una que ya estaba guardada fuera de esa lista también
  sale.
-->
<script module lang="ts">
  export type Dia = { abre: string; cierra: string } | null;
</script>

<script lang="ts">
  let {
    dias = $bindable(),
    hoy,
    apagado = false,
  }: { dias: Dia[]; hoy: number; apagado?: boolean } = $props();

  const NOMBRES = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
  const HORAS = Array.from({ length: 48 }, (_, i) => `${Math.floor(i / 2)}:${i % 2 ? '30' : '00'}`);

  function minutos(t: string) {
    const [h, m] = t.split(':');
    return Number(h) * 60 + Number(m);
  }

  // La lista con la hora guardada en su lugar, si no es de media en media.
  function horasCon(valor: string) {
    if (HORAS.includes(valor)) return HORAS;
    return [...HORAS, valor].sort((a, b) => minutos(a) - minutos(b));
  }

  function alternar(i: number) {
    dias[i] = dias[i] ? null : { abre: '9:00', cierra: '18:00' };
  }
</script>

<div class="dias">
  {#each NOMBRES as nombre, i (nombre)}
    {@const d = dias[i]}
    <div class="dia" class:hoy={i === hoy}>
      <span class="dia-nombre">{nombre}</span>
      <button
        type="button"
        class="interruptor"
        role="switch"
        aria-checked={!!d}
        aria-label="{nombre}: {d ? 'abre' : 'cerrado'}"
        disabled={apagado}
        onclick={() => alternar(i)}
      >
        <span class="riel"></span>{d ? 'Abre' : 'Cerrado'}
      </button>
      <span class="horas">
        {#if d}
          <select aria-label="Abre el {nombre}" bind:value={d.abre} disabled={apagado}>
            {#each horasCon(d.abre) as h (h)}<option value={h}>{h}</option>{/each}
          </select>
          <span class="a">a</span>
          <select aria-label="Cierra el {nombre}" bind:value={d.cierra} disabled={apagado}>
            {#each horasCon(d.cierra) as h (h)}<option value={h}>{h}</option>{/each}
          </select>
          {#if minutos(d.cierra) < minutos(d.abre)}
            <span class="siguiente">del {NOMBRES[(i + 1) % 7].toLowerCase()}</span>
          {/if}
        {/if}
      </span>
    </div>
  {/each}
</div>

<style>
  .dias {
    display: flex;
    flex-direction: column;
  }

  .dia {
    display: grid;
    grid-template-columns: 96px 112px 1fr;
    align-items: center;
    gap: 14px;
    min-height: 52px;
    border-bottom: 1px solid var(--linea);
  }

  .dia:last-child {
    border-bottom: 0;
  }

  .dia-nombre {
    font-size: 13.5px;
    font-weight: 700;
  }

  .dia.hoy .dia-nombre::after {
    content: 'Hoy';
    margin-left: 8px;
    font-family: var(--mono);
    font-size: 10px;
    letter-spacing: 0.1em;
    color: var(--tenue);
    font-weight: 500;
    text-transform: uppercase;
  }

  .interruptor {
    display: inline-flex;
    align-items: center;
    gap: 9px;
    border: 0;
    background: transparent;
    padding: 0;
    font-size: 12.5px;
    font-weight: 600;
    color: var(--texto);
  }

  .riel {
    width: 34px;
    height: 20px;
    border-radius: 10px;
    background: var(--linea-fuerte);
    position: relative;
    flex: none;
    transition: background-color 150ms;
  }

  .riel::after {
    content: '';
    position: absolute;
    top: 2px;
    left: 2px;
    width: 16px;
    height: 16px;
    border-radius: 8px;
    background: var(--solido);
    box-shadow: 0 1px 2px var(--sombra-segmento);
    transition: transform 150ms;
  }

  .interruptor[aria-checked='true'] .riel {
    background: var(--tinta);
  }

  .interruptor[aria-checked='true'] .riel::after {
    transform: translateX(14px);
  }

  .interruptor[aria-checked='false'] {
    color: var(--tenue);
  }

  .horas {
    display: flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
  }

  select {
    height: 36px;
    padding: 0 8px;
    border: 1px solid var(--linea);
    border-radius: 10px;
    background: var(--solido);
    color: var(--texto);
    font-family: var(--mono);
    font-size: 13px;
    outline: none;
  }

  select:focus {
    border-color: var(--suave);
  }

  .a {
    font-size: 12.5px;
    color: var(--tenue);
  }

  .siguiente {
    font-size: 11.5px;
    font-weight: 600;
    color: var(--suave);
    background: var(--chip);
    border-radius: 7px;
    padding: 3px 8px;
    white-space: nowrap;
  }

  @media (prefers-reduced-motion: reduce) {
    .riel,
    .riel::after {
      transition: none;
    }
  }
</style>
