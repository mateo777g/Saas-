import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';

// La vista previa de Claude Code usa el puerto 8125 (.claude/launch.json, "app").
export default defineConfig({
  plugins: [svelte()],
  server: { port: 8125, strictPort: true },
  // El convertidor de respaldo de las fotos (@jsquash/webp) busca su .wasm junto a su propio
  // archivo: si Vite lo empaqueta en desarrollo, deja de encontrarlo.
  optimizeDeps: { exclude: ['@jsquash/webp'] },
});
