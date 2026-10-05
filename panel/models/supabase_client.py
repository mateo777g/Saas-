"""
models/supabase_client.py
Cliente único de Supabase para todo el panel de Flet.

Se crea SIEMPRE con la ANON KEY (nunca service_role — esa llave ni siquiera
vive en el .env). Los permisos de escritura no salen de esta llave, salen
de la sesión que deja el login (ver views/sesion_view.py y models/sesion.py):
en cuanto la sesión queda activa en `client.auth`, este mismo cliente manda
el access_token del admin en cada request a `platillos`, y ahí es donde RLS
decide si puede escribir.

Equivalente en Python de EJEMPLOS/supabase-config.js — con una diferencia
a propósito: aquí NO se desactiva persistSession por el motivo que explica
ese archivo (Tracking Prevention del navegador bloqueando localStorage). Esa
razón no aplica a una app de escritorio; el cliente usa su storage en
memoria de siempre y quien persiste la sesión EN DISCO, a mano, es
models/sesion.py (fuera del repo, en %LOCALAPPDATA%).
"""
import os
from pathlib import Path

from dotenv import load_dotenv
from supabase import Client, create_client

# .env vive en la raíz del repo, dos niveles arriba (panel/models/ -> raíz).
_RUTA_ENV = Path(__file__).resolve().parents[2] / ".env"
load_dotenv(_RUTA_ENV)

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_ANON_KEY = os.getenv("SUPABASE_ANON_KEY")
# Correo del admin, para precargar el campo en la pantalla de login.
SUPABASE_ADMIN_EMAIL = os.getenv("SUPABASE_ADMIN_EMAIL", "")

if not SUPABASE_URL or not SUPABASE_ANON_KEY:
    raise RuntimeError(
        "Faltan SUPABASE_URL o SUPABASE_ANON_KEY en el .env — revisa que el "
        "archivo exista en la raíz del proyecto y tenga esas llaves."
    )

# Un solo cliente compartido por toda la app.
client: Client = create_client(SUPABASE_URL, SUPABASE_ANON_KEY)
