import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';

// La vista previa de Claude Code usa el puerto 8125 (.claude/launch.json, "app").
export default defineConfig({
  plugins: [svelte()],
  server: { port: 8125, strictPort: true },
});
