<!--
  «Tope de IA» (fila de Clientes), de la maqueta aprobada el 19 de octubre de 2026
  (KznKZdgQbLTZGs1EwVMvga): lo gastado este mes (uso_ia_cliente), el tope y quién paga, y el
  campo para cambiarlo con fijar_tope_ia. Postgres revisa que vaya de 0 a 10 dólares y con
  centavos. Al llegar al tope no dice el día (decidido el 19 de octubre de 2026: uso_ia_cliente
  no lo trae). La ventana sale cuando ya llegó lo gastado, para que el campo traiga el tope de hoy.

  Con la 6c (maqueta 2UPwZw31WrcYRZkH8jaT1Y, sección 2) cada sobre va en su renglón, con lo gastado
  «de» su parte, y cada uno avisa cuando llega a lo suyo, también sin día (encuesta 19 de
  planes/trabajo/6c/lista-6c.md). Las partes las calcula Postgres: la app nunca divide el tope.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import Aviso from '../../diseno/Aviso.svelte';
  import CajaError from '../../diseno/CajaError.svelte';
  import Campo from '../../diseno/Campo.svelte';
  import Formulario from '../../diseno/Formulario.svelte';
  import Ventana from '../../diseno/Ventana.svelte';
  import { decimal, diaYMes, dolares, mesSiguiente, nombreDelMes, plural } from '../../lib/formato';
  import { fijarTopeIa, leerUsoIa, type Cliente, type Lectura, type UsoIa } from '../../lib/panel';

  let {
    cliente,
    alCerrar,
    alGuardar,
  }: { cliente: Cliente; alCerrar: () => void; alGuardar: () => void } = $props();

  let uso = $state<Lectura<UsoIa> | null>(null);
  let valor = $state('');

  onMount(async () => {
    uso = await leerUsoIa(cliente.id);
    if (uso.ok) valor = uso.datos.tope.toFixed(2);
  });

  async function guardar() {
    const tope = decimal(valor);
    const r = await fijarTopeIa(cliente.id, tope);
    if (!r.ok) return { error: r.mensaje };
    alGuardar();
    return { listo: 'Tope guardado' };
  }
</script>

{#if uso && !uso.ok}
  <Ventana etiqueta="TOPE DE IA" titulo={cliente.nombre} {alCerrar}>
    <div class="error"><CajaError mensaje={uso.mensaje} /></div>
  </Ventana>
{:else if uso}
  {@const u = uso.datos}
  {@const vuelve = diaYMes(mesSiguiente(u.mes))}
  <Ventana etiqueta="TOPE DE IA" titulo={cliente.nombre} {alCerrar}>
    <Formulario boton={{ etiqueta: 'Guardar tope', icono: 'check' }} {guardar} alTerminar={alCerrar}>
      <div class="gasto">
        <span class="etiqueta">GASTADO EN {nombreDelMes(u.mes).toUpperCase()}</span>
        <div class="valor">
          <b>{dolares(u.gastado)}</b>
          <span>de {dolares(u.tope)} USD</span>
        </div>
        <span class="riel"><span class="lleno" style:width="{u.tope > 0 ? Math.min(100, (u.gastado / u.tope) * 100) : 0}%"></span></span>
        <div class="fila">
          <span>
            Agente IA · {u.consultas_agente || u.saludos || u.gastado_agente > 0
              ? `${plural(u.consultas_agente, 'pregunta', 'preguntas')} y ${plural(u.saludos, 'saludo', 'saludos')}`
              : 'Sin uso este mes'}
          </span>
          <span class="mono">{dolares(u.gastado_agente)} <span class="de">de {dolares(u.sobre_agente)}</span></span>
        </div>
        <div class="fila">
          <span>
            Asistente del menú · {u.consultas_menu || u.gastado_menu > 0
              ? plural(u.consultas_menu, 'pregunta', 'preguntas')
              : 'Sin uso este mes'}
          </span>
          <span class="mono">{dolares(u.gastado_menu)} <span class="de">de {dolares(u.sobre_menu)}</span></span>
        </div>
      </div>
      {#if u.tope === 0}
        <Aviso>Nació con el tope en 0, así que todavía no tiene IA. Ponle uno para prenderla.</Aviso>
      {/if}
      {#if u.agente_en_limite}
        <Aviso>El Agente IA llegó a sus {dolares(u.sobre_agente)}. Vuelve el {vuelve}, o antes si le subes el tope.</Aviso>
      {/if}
      {#if u.menu_en_limite}
        <Aviso>El asistente del menú llegó a sus {dolares(u.sobre_menu)}. Vuelve el {vuelve}, o antes si le subes el tope.</Aviso>
      {/if}
      <Campo id="tope-ia" etiqueta="TOPE AL MES (USD)" tipo="number" bind:valor min={0} step={0.01} modoTeclado="decimal" />
      <p class="pista">
        De 0 a 10 dólares. En 0 no tiene IA. La quinta parte es para el asistente del menú y el resto para el
        Agente IA. Cada uno se pausa hasta el {vuelve} al gastar lo suyo.
      </p>
      <p class="pista">
        {u.distribuidor
          ? `Lo que gasta se le descuenta a ${u.distribuidor} a fin de mes.`
          : 'Es cliente directo: su IA la paga Fragmentless.'}
      </p>
    </Formulario>
  </Ventana>
{/if}

<style>
  .error {
    margin-top: 22px;
  }

  .gasto {
    padding: 16px;
    border: 1px solid var(--linea);
    border-radius: 16px;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .valor {
    display: flex;
    align-items: baseline;
    gap: 8px;
  }

  .valor b {
    font-size: 26px;
    font-weight: 800;
    letter-spacing: -0.5px;
    font-variant-numeric: tabular-nums;
  }

  .valor span {
    font-size: 13px;
    color: var(--suave);
  }

  .riel {
    display: block;
    height: 6px;
    border-radius: 3px;
    background: var(--chip);
    overflow: hidden;
  }

  .lleno {
    display: block;
    height: 100%;
    border-radius: 3px;
    background: var(--tinta);
  }

  .fila {
    display: flex;
    justify-content: space-between;
    gap: 12px;
    font-size: 12.5px;
    color: var(--suave);
  }

  .fila .mono {
    font-family: var(--mono);
    color: var(--texto);
    white-space: nowrap;
  }

  .fila .de {
    color: var(--tenue);
  }
</style>
