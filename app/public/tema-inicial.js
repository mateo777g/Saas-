// Pone el tema en <html data-tema="…"> antes de que se pinte nada: el que eligió en Ajustes en
// este navegador o, si nunca eligió, el de por defecto. No es un módulo a propósito: corre al
// leerse, antes que la app. Ajustes lo cambia con src/lib/tema.ts, con la misma llave.
(function () {
  var POR_DEFECTO = 'claro'; // el developer lo pidió el 11 de octubre de 2026 (Flet abría en oscuro)
  var tema = POR_DEFECTO;
  try {
    var guardado = localStorage.getItem('fragmentless-tema');
    if (guardado === 'claro' || guardado === 'oscuro') tema = guardado;
  } catch (error) {
    console.error('[tema] no se pudo leer el tema guardado; va el de por defecto:', error);
  }
  document.documentElement.dataset.tema = tema;
})();
