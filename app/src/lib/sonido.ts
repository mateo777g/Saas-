// «Pepe lo oye» (libreta 5, decidido el 17 de octubre de 2026): cuando la cocina marca «Lista»
// una comanda suya, el aparato suena y vibra una vez. El sonido es un tono hecho aquí, sin
// archivo. Los navegadores no dejan sonar hasta que la persona toca la pantalla: el primer toque
// lo prepara. En iPhone solo suena, porque Safari no deja vibrar.

let audio: AudioContext | null = null;

export function prepararSonido(): void {
  try {
    audio ??= new AudioContext();
    if (audio.state === 'suspended') audio.resume().catch((e) => console.error('[sonido] no se pudo prender:', e));
  } catch (error) {
    console.error('[sonido] este navegador no deja sonar:', error);
  }
}

// Dos notas cortas, como un timbre.
export function avisarLista(): void {
  try {
    navigator.vibrate?.(200);
  } catch (error) {
    console.error('[sonido] no se pudo vibrar:', error);
  }
  if (!audio || audio.state !== 'running') {
    console.error('[sonido] no sonó: nadie ha tocado la pantalla desde que se abrió');
    return;
  }
  const ahora = audio.currentTime;
  [
    { nota: 880, desde: 0 },
    { nota: 1175, desde: 0.16 },
  ].forEach(({ nota, desde }) => {
    const tono = audio!.createOscillator();
    const volumen = audio!.createGain();
    tono.type = 'sine';
    tono.frequency.value = nota;
    volumen.gain.setValueAtTime(0.0001, ahora + desde);
    volumen.gain.exponentialRampToValueAtTime(0.35, ahora + desde + 0.02);
    volumen.gain.exponentialRampToValueAtTime(0.0001, ahora + desde + 0.3);
    tono.connect(volumen).connect(audio!.destination);
    tono.start(ahora + desde);
    tono.stop(ahora + desde + 0.32);
  });
}
