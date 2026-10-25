/// <reference types="svelte" />
/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_SUPABASE_URL: string;
  readonly VITE_SUPABASE_LLAVE_PUBLICABLE: string;
  readonly VITE_R2_PUBLICO: string;
  readonly VITE_ORIGENES_APP: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
