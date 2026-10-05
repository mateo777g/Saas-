"""
models/perfil.py
El perfil de quien usa el panel: su nombre completo y cómo quiere que
Fragmentless lo llame (la ventana "Perfil", al pulsar el pie de la barra
lateral). Lo segundo sale en el pie de la barra ("Ary · Básico", con su
inicial en el círculo) y en el saludo de Inicio.

Se guarda en el mismo config.json de models/config_usuario.py
(panel/config.json, en panel/.gitignore: el repo es público), con las claves
"nombre_completo" y "como_llamarte". Cada quien cambia solo sus claves.
"""
from models.config_usuario import guardar_config, leer_config

# Mientras no se haya elegido otro en Perfil. PENDIENTE (pregunta al dueño):
# era el "Ary" escrito a mano en Inicio y en el login; se conserva hasta que
# el dueño diga otro.
POR_DEFECTO = "Ary"


def nombre_completo():
    return (leer_config().get("nombre_completo") or "").strip()


def elegido():
    # Lo que escribió, sin el de por defecto (el campo de Perfil sale vacío).
    return (leer_config().get("como_llamarte") or "").strip()


def como_llamarte():
    # Cómo lo llama el panel: lo que eligió; si no eligió nada, POR_DEFECTO.
    return elegido() or POR_DEFECTO


def guardar(nombre, llamarte):
    guardar_config({"nombre_completo": nombre.strip(), "como_llamarte": llamarte.strip()})
