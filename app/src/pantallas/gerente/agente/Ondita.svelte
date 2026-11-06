<!--
  La ondita del agente (encuesta 19 del rediseño; maqueta V64Pv4gmANPRZuJW5hTe5D, de DelicateAsciiDots de
  21st.dev): la vista está en blanco y, al picarle a un espacio vacío del fondo, sale una ondita de
  puntitos braille donde picaste, que crece poco (22 celdas, unos 240 px) y se apaga en 1.9 s. Naranja en
  claro y azul en oscuro. Sin ondas no se dibuja nada, y con «reducir movimiento» no sale.
-->
<script lang="ts">
  import { onDestroy } from 'svelte';
  import { temaActual } from '../../../lib/tema';

  const CHARS = '⣧⣩⣪⣫⣬⣭⣮⣯⣱⣲⣳⣴⣵⣶⣷⣹⣺⣻⣼⣽⣾⣿⣧⣩⣪⣫⣬⣭⣮⣯⣱⣲⣳⣴⣵⣶⣷⣹⣺⣻⣼⣽⣾⣿⣧⣩⣪⣫⣬⣭⣮⣯⣱⣲⣳⣴⣵⣶⣷⣹⣺⣻⣼⣽⣾⣿⣧⣩⣪⣫⣬⣭⣮⣯⣱⣲⣳⣴⣵⣶⣷⣹⣺⣻⣼⣽⣾⣿⣧⣩⣪⣫⣬⣭⣮⣯⣱⣲⣳⣴⣵⣶⣷⣹⣺⣻⣼⣽⣾⣿⣧⣩⣪⣫⣬⣭⣮⣯⣱⣲⣳⣴⣵⣶⣷⣹⣺⣻⣼⣽⣾⣿⠁⠂⠄⠈⠐⠠⡀⢀⠃⠅⠘⠨⠊⠋⠌⠍⠎⠏⠑⠒⠓⠔⠕⠖⠗⠙⠚⠛⠜⠝⠞⠟⠡⠢⠣⠤⠥⠦⠧⠩⠪⠫⠬⠭⠮⠯⠱⠲⠳⠴⠵⠶⠷⠹⠺⠻⠼⠽⠾⠿⡁⡂⡃⡄⡅⡆⡇⡉⡊⡋⡌⡍⡎⡏⡑⡒⡓⡔⡕⡖⡗⡙⡚⡛⡜⡝⡞⡟⡡⡢⡣⡤⡥⡦⡧⡩⡪⡫⡬⡭⡮⡯⡱⡲⡳⡴⡵⡶⡷⡹⡺⡻⡼⡽⡾⡿⢁⢂⢃⢄⢅⢆⢇⢉⢊⢋⢌⢍⢎⢏⢑⢒⢓⢔⢕⢖⢗⢙⢚⢛⢜⢝⢞⢟⢡⢢⢣⢤⢥⢦⢧⢩⢪⢫⢬⢭⢮⢯⢱⢲⢳⢴⢵⢶⢷⢹⢺⢻⢼⢽⢾⢿⣀⣁⣂⣃⣄⣅⣆⣇⣉⣊⣋⣌⣍⣎⣏⣑⣒⣓⣔⣕⣖⣗⣙⣚⣛⣜⣝⣞⣟⣡⣢⣣⣤⣥⣦⣧⣩⣪⣫⣬⣭⣮⣯⣱⣲⣳⣴⣵⣶⣷⣹⣺⣻⣼⣽⣾⣿';
  // Como el acento (el azul, un poco más claro para que se vea).
  const COLOR = { claro: '232, 98, 42', oscuro: '79, 134, 247' };
  const CEL = 11;
  const DURA = 1900;
  const RADIO = 22;
  const BANDA = 5;

  type Clic = { x: number; y: number; t: number; semilla: number };

  let lienzo: HTMLCanvasElement;
  let raf: number | null = null;
  let clics: Clic[] = [];
  let ancho = 0;
  let alto = 0;
  let cols = 0;
  let filas = 0;

  function medir() {
    const r = lienzo.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    if (r.width === ancho && r.height === alto) return;
    ancho = r.width;
    alto = r.height;
    lienzo.width = Math.round(ancho * dpr);
    lienzo.height = Math.round(alto * dpr);
    lienzo.getContext('2d')?.setTransform(dpr, 0, 0, dpr, 0, 0);
    cols = Math.ceil(ancho / CEL);
    filas = Math.ceil(alto / CEL);
  }

  function cuadro() {
    const lapiz = lienzo?.getContext('2d');
    if (!lapiz) return;
    const ahora = Date.now();
    clics = clics.filter((c) => ahora - c.t < DURA);
    lapiz.clearRect(0, 0, ancho, alto);
    if (!clics.length) {
      raf = null;
      return;
    }
    const color = COLOR[temaActual()];
    const celdas = new Map<number, number>();
    for (const c of clics) {
      const avance = (ahora - c.t) / DURA;
      const r = avance * RADIO;
      const apaga = Math.pow(1 - avance, 1.5);
      const x0 = Math.max(0, Math.floor(c.x - RADIO - BANDA));
      const x1 = Math.min(cols - 1, Math.ceil(c.x + RADIO + BANDA));
      const y0 = Math.max(0, Math.floor(c.y - RADIO - BANDA));
      const y1 = Math.min(filas - 1, Math.ceil(c.y + RADIO + BANDA));
      for (let y = y0; y <= y1; y++) {
        for (let x = x0; x <= x1; x++) {
          const d = Math.hypot(x - c.x, y - c.y);
          const lejos = Math.abs(d - r);
          if (lejos >= BANDA) continue;
          const fuerza = apaga * (1 - lejos / BANDA) * (0.6 + 0.4 * Math.sin((d - r) * 1.6 + c.semilla));
          const k = y * cols + x;
          celdas.set(k, Math.min(1, (celdas.get(k) ?? 0) + fuerza));
        }
      }
    }
    lapiz.font = `${CEL * 0.8}px monospace`;
    lapiz.textAlign = 'center';
    lapiz.textBaseline = 'middle';
    for (const [k, v] of celdas) {
      if (v < 0.08) continue;
      const x = k % cols;
      const y = Math.floor(k / cols);
      const i = Math.min(CHARS.length - 1, Math.floor(v * (CHARS.length - 1)));
      lapiz.fillStyle = `rgba(${color}, ${(0.25 + v * 0.6).toFixed(2)})`;
      lapiz.fillText(CHARS[CHARS.length - 1 - i], x * CEL + CEL / 2, y * CEL + CEL / 2);
    }
    raf = requestAnimationFrame(cuadro);
  }

  // Lo llama la vista cuando el clic fue en el fondo.
  export function picar(e: MouseEvent) {
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    medir();
    const r = lienzo.getBoundingClientRect();
    clics.push({ x: (e.clientX - r.left) / CEL, y: (e.clientY - r.top) / CEL, t: Date.now(), semilla: Math.random() * Math.PI * 2 });
    if (raf === null) cuadro();
  }

  onDestroy(() => {
    if (raf !== null) cancelAnimationFrame(raf);
  });
</script>

<canvas class="puntos" bind:this={lienzo} aria-hidden="true"></canvas>

<style>
  .puntos {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    pointer-events: none;
  }
</style>
