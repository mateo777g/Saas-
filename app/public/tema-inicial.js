// Pone el tema y el estilo en <html data-tema="…" data-estilo="…"> antes de que se pinte nada: los que
// se eligieron en Ajustes en este navegador o, si nunca se eligieron, los de por defecto. No es un
// módulo a propósito: corre al leerse, antes que la app. Ajustes los cambia con src/lib/tema.ts y
// src/lib/estilo.ts, con las mismas llaves.
(function () {
  var raiz = document.documentElement;
  var TEMA_POR_DEFECTO = 'claro'; // el developer lo pidió el 11 de octubre de 2026 (Flet abría en oscuro)
  var tema = TEMA_POR_DEFECTO;
  try {
    var guardado = localStorage.getItem('fragmentless-tema');
    if (guardado === 'claro' || guardado === 'oscuro') tema = guardado;
  } catch (error) {
    console.error('[tema] no se pudo leer el tema guardado; va el de por defecto:', error);
  }
  raiz.dataset.tema = tema;

  // El estilo del panel, «Simple» o «Cristal» (libreta 4, «El estilo Cristal»). El aparato del equipo
  // (/equipo) va en Simple hasta que su pantalla tenga su propia opción (su maqueta). Mientras Cristal se
  // construye nace en Simple, para no cambiarles la app a las otras sesiones; al terminar, nace en Cristal
  // (lo mismo en src/lib/estilo.ts).
  var ESTILO_POR_DEFECTO = 'simple';
  var estilo = ESTILO_POR_DEFECTO;
  var esAparato = location.pathname === '/equipo' || location.pathname.indexOf('/equipo/') === 0;
  if (esAparato) estilo = 'simple';
  else {
    try {
      var elegido = localStorage.getItem('fragmentless-estilo');
      if (elegido === 'simple' || elegido === 'cristal') estilo = elegido;
    } catch (error) {
      console.error('[estilo] no se pudo leer el estilo guardado; va el de por defecto:', error);
    }
  }
  raiz.dataset.estilo = estilo;
})();
