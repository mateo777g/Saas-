import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';

// El menú en línea toma de la app lo que no debe contarse de otra forma (libreta 6): el formato de
// los pesos, el color con su letra encima y los íconos. Se importa como '@app/…'.
const app = fileURLToPath(new URL('../app/src', import.meta.url));

// La vista previa de Claude Code usa el puerto 8126 (.claude/launch.json, "menu").
export default defineConfig({
  plugins: [svelte()],
  resolve: { alias: { '@app': app } },
  server: { port: 8126, strictPort: true, fs: { allow: ['.', app] } },
});
