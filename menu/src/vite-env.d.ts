/// <reference types="svelte" />
/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_SUPABASE_URL: string;
  readonly VITE_SUPABASE_LLAVE_PUBLICABLE: string;
  readonly VITE_R2_PUBLICO: string;
  readonly VITE_ORIGENES_APP: string;
  readonly VITE_API_URL: string;
  readonly VITE_TURNSTILE_SITIO: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
