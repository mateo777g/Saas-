import { mount } from 'svelte';
import './diseno/base.css';

// Dos puertas en la misma app: /equipo es el aparato del equipo (la tableta de la caja, el celular
// de Pepe), con su propia sesión y sin el portero del panel; todo lo demás es el panel. Cada una
// se descarga solo donde se usa, así el aparato nunca abre la conexión del panel.
const destino = document.getElementById('app')!;
const esAparato = location.pathname === '/equipo' || location.pathname.startsWith('/equipo/');

(esAparato ? import('./Aparato.svelte') : import('./App.svelte'))
  .then(({ default: Pantalla }) => mount(Pantalla, { target: destino }))
  .catch((error) => console.error('[app] no se pudo abrir la app:', error));
