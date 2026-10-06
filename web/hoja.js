// hoja.js — la sección 3 de la página de Fragmentless (index.html).
// Una hoja blanca sube encima de la escena ya quieta, como entraban los planes en la página vieja
// (github.com/mateo777g/fragmentless-software): arranca al 90 % con las esquinas redondas, crece hasta
// llenar la pantalla y lo de adentro aparece a medio camino. Luego se queda quieta un tramo y sigue.
// Lo mueve el scroll, no el reloj: cada cuadro se calcula de dónde va la hoja.
(() => {
  const hoja = document.querySelector('.hoja');
  const fija = hoja.querySelector('.hoja-fija');
  const filaBarra = document.querySelector('.barra-fila');

  const limitar = (v) => Math.min(1, Math.max(0, v));

  // Dónde empieza la hoja en la página, sin contar su transform (offsetTop no lo ve).
  function arriba(el) {
    let y = 0;
    for (let n = el; n; n = n.offsetParent) y += n.offsetTop;
    return y;
  }

  let pendiente = false;

  function pintar() {
    pendiente = false;
    const altoPantalla = innerHeight;

    // 0 = su borde de arriba toca el de abajo de la pantalla; 1 = llegó hasta arriba.
    const subida = limitar((scrollY + altoPantalla - arriba(hoja)) / altoPantalla);
    hoja.style.setProperty('--subida', subida);
    hoja.style.setProperty('--aparecer', limitar((subida - 0.25) / 0.5));

    // Si lo de adentro mide más que la pantalla, el enganche la deja quieta por abajo, no cortada.
    fija.style.setProperty('--fija-arriba', `${Math.min(0, altoPantalla - fija.offsetHeight)}px`);

    // Desde que la hoja (ya con su escala) pasa la mitad de la barra y mientras siga debajo de ella, la barra
    // se queda a la vista y negra, también con el submenú abierto (style.css). Pasada la hoja, vuelve a ser blanca.
    const caja = hoja.getBoundingClientRect();
    const mitadBarra = filaBarra.offsetHeight / 2;
    document.documentElement.toggleAttribute('data-hoja', caja.top <= mitadBarra);
    document.documentElement.toggleAttribute('data-en-hoja', caja.top <= mitadBarra && caja.bottom > mitadBarra);
  }

  function pedirCuadro() {
    if (pendiente) return;
    pendiente = true;
    requestAnimationFrame(pintar);
  }

  addEventListener('scroll', pedirCuadro, { passive: true });
  addEventListener('resize', pedirCuadro);
  pintar();
})();
