// ================================================================
// cloudflare/index.js
// Backend de subida/borrado de imágenes para el panel de Taku Monky
// (Fase 3). Portado de EJEMPLOS/index.js (proyecto Anxie Store) — mismo
// patrón exacto, solo cambian el bucket y las variables de entorno. Este
// archivo es el código FUENTE de lo que está desplegado en el Worker
// "taku-monky-uploads"; si algún día hay que redesplegarlo, los datos
// exactos (bindings, variables, receta curl) están en
// "Hey Claude Code, read this file..txt" → bloque "ACCESO A CLOUDFLARE"
// (ese .txt es el que trae las llaves; este .js no tiene ninguna).
//
// Por qué existe: el panel es una app de escritorio Flet/Python, no un
// navegador. Para subir/borrar en R2 sin poner ninguna credencial de R2 en
// la compu del dueño, este Worker tiene acceso nativo al bucket (binding
// R2, sin Access Key/Secret) y es él quien escribe. El panel solo le manda
// bytes ya comprimidos a WebP (ver models/cloudflare_storage.py) más su
// token de sesión.
//
// Autenticación: cada request debe traer el access_token de la sesión de
// Supabase Auth del admin (Authorization: Bearer <token>) — el mismo que
// ya usa el panel para escribir en Supabase. Este Worker valida ese token
// contra la API de Supabase Auth y confirma que el email coincide con
// ADMIN_EMAIL antes de tocar el bucket, exactamente igual que
// EJEMPLOS/index.js. No hay signup público ni service_role de por medio.
// ================================================================

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type",
};

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

async function verificarAdmin(request, env) {
  const auth = request.headers.get("Authorization") || "";
  const token = auth.replace(/^Bearer\s+/i, "");
  if (!token) return null;

  const resp = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
    headers: {
      Authorization: `Bearer ${token}`,
      apikey: env.SUPABASE_ANON_KEY,
    },
  });
  if (!resp.ok) return null;

  const user = await resp.json();
  if (!user || user.email !== env.ADMIN_EMAIL) return null;
  return user;
}

// Nombre de archivo generado por el servidor (nunca confiar en uno provisto
// por el cliente) -- mismo patrón que EJEMPLOS/index.js.
function nombreNuevo() {
  return `${Date.now()}.webp`;
}

// El panel ya comprime a WebP calidad 80 / lado máx. 1600px antes de subir
// (Pillow, ver models/cloudflare_storage.py), pero no hay que confiar solo
// en eso -- un bug o un cliente modificado podría mandar algo enorme. Mismo
// tope que EJEMPLOS/index.js.
const MAX_BYTES = 5 * 1024 * 1024; // 5 MB

// Solo permite borrar archivos con este patrón exacto -- evita que un
// valor raro en `file` (ej. con "../") toque otra cosa del bucket.
const NOMBRE_VALIDO = /^[0-9]+\.webp$/;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { headers: CORS_HEADERS });
    }

    if (url.pathname === "/upload" && request.method === "POST") {
      const user = await verificarAdmin(request, env);
      if (!user) return json({ ok: false, error: "No autorizado." }, 401);

      const contentType = request.headers.get("Content-Type") || "";
      if (!contentType.includes("image/webp")) {
        return json({ ok: false, error: "Solo se aceptan imágenes WebP." }, 400);
      }

      const contentLength = Number(request.headers.get("Content-Length") || 0);
      if (contentLength > MAX_BYTES) {
        return json({ ok: false, error: "La imagen supera el límite de 5 MB." }, 413);
      }

      const fileName = nombreNuevo();
      await env.FOTOS.put(fileName, request.body, {
        httpMetadata: { contentType: "image/webp" },
      });

      return json({ ok: true, fileName, url: `${env.R2_PUBLIC_BASE}/${fileName}` });
    }

    if (url.pathname === "/delete" && request.method === "DELETE") {
      const user = await verificarAdmin(request, env);
      if (!user) return json({ ok: false, error: "No autorizado." }, 401);

      const file = url.searchParams.get("file") || "";
      if (!NOMBRE_VALIDO.test(file)) {
        return json({ ok: false, error: "Nombre de archivo inválido." }, 400);
      }

      await env.FOTOS.delete(file);
      return json({ ok: true });
    }

    return json({ ok: false, error: "No encontrado." }, 404);
  },
};
