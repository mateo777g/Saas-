"""
models/config_usuario.py
Configuración de quien usa el panel (panel/config.json): la ruta
secundaria de exportación que usa views/biblioteca_view.py (Fase 7.4), el
perfil y el tema. Ver "DÓNDE SE GUARDA".

NOTA DE ALCANCE, explícita a propósito (pedida así en el prompt de la Fase
7.4 en vez de asumirse en silencio): este archivo NO es la pantalla de
Ajustes. Nació como el pedacito de lógica que hacía falta para que el botón
"Exportar" de la biblioteca funcionara antes de que existiera un lugar en
la UI para elegir esa ruta. Desde la Fase 7.5 (2026-09-06) esa pantalla
(views/ajustes_view.py, con el mismo selector de carpeta por Tkinter que
dialogo_platillo.py ya usa para la foto) ya existe y lee/escribe por AQUÍ
(obtener_ruta_exportacion() / guardar_ruta_exportacion()) — ninguna de las
dos pantallas inventó su propio archivo, tal como pedía el roadmap en el
bloque "FASE 7" → "LOS AJUSTES": "la ruta la consultan DOS pantallas. Vive
en un solo lugar y las dos lo leen." obtener_ruta_exportacion() sigue
cayendo a ~/Downloads cuando el dueño nunca guardó nada (o la ruta
guardada ya no existe en disco) — ver esa función.

DÓNDE SE GUARDA (28/09, a pedido del dueño, como en Anxie): en un solo
config.json dentro de la carpeta del panel (panel/config.json, junto a
main.py), con todo lo de quien usa el panel: la carpeta de exportación
("ruta_exportacion"), el perfil ("nombre_completo", "como_llamarte",
models/perfil.py) y el tema ("tema", views/tema.py). Está en
panel/.gitignore: trae el nombre completo y rutas de la PC, y el repo es
PÚBLICO. Antes vivía en %LOCALAPPDATA%/TakuMonky/config.json; si ese
existe y el nuevo todavía no, se copia una vez (_migrar_config_viejo()).

Sin flet y sin Pillow, mismo estilo que models/tiempo.py: es solo datos de
configuración, nada que dependa de la UI.
"""
import json
import os
import traceback
from pathlib import Path

# La carpeta del panel (panel/), no el directorio actual: así el archivo
# cae en el mismo sitio aunque alguien importe esto sin pasar por main.py.
_RUTA_CONFIG = Path(__file__).resolve().parents[1] / "config.json"
_CLAVE_RUTA_EXPORTACION = "ruta_exportacion"


def _ruta_config_vieja() -> Path:
    base = os.getenv("LOCALAPPDATA") or str(Path.home())
    return Path(base) / "TakuMonky" / "config.json"


def _migrar_config_viejo() -> None:
    """Una sola vez: si todavía no hay panel/config.json pero sí el de
    %LOCALAPPDATA%, se copia su contenido para no perder la carpeta y el
    perfil ya guardados. El viejo se deja donde está (no se borra nada)."""
    if _RUTA_CONFIG.exists():
        return
    vieja = _ruta_config_vieja()
    try:
        if vieja.exists():
            datos = json.loads(vieja.read_text(encoding="utf-8"))
            if isinstance(datos, dict):
                _escribir(datos)
    except (OSError, json.JSONDecodeError):
        traceback.print_exc()


def _escribir(datos: dict) -> None:
    # A un .tmp y luego os.replace: un corte a medias no deja config.json roto.
    temporal = _RUTA_CONFIG.with_suffix(".json.tmp")
    temporal.write_text(json.dumps(datos, indent=2, ensure_ascii=False), encoding="utf-8")
    os.replace(temporal, _RUTA_CONFIG)


def _leer_config() -> dict:
    _migrar_config_viejo()
    try:
        return json.loads(_RUTA_CONFIG.read_text(encoding="utf-8")) if _RUTA_CONFIG.exists() else {}
    except (OSError, json.JSONDecodeError):
        # Un config.json corrupto no debe tumbar el panel -- se trata igual
        # que "el dueño nunca configuró nada", mismo criterio que ya sigue
        # _registrar_huerfano() en cloudflare_storage.py con su propio
        # archivo fuera del repo.
        return {}


def leer_config() -> dict:
    """Todo config.json como diccionario ({} si no existe o está roto). Lo
    comparten la ruta de exportación, el perfil (models/perfil.py) y el tema
    (views/tema.py): cada uno cambia SOLO sus claves con guardar_config()."""
    datos = _leer_config()
    return datos if isinstance(datos, dict) else {}


def guardar_config(cambios: dict) -> None:
    """Cambia solo las claves de `cambios` y deja las demás como estaban.
    Escribe a un .tmp y lo cambia por el bueno (os.replace): un corte a
    medias no deja config.json roto."""
    datos = leer_config()
    datos.update(cambios)
    _escribir(datos)


def obtener_ruta_exportacion() -> str:
    """La carpeta a la que "Exportar" debe copiar un anuncio. Si el dueño
    nunca configuró una (la 7.5 todavía no existe, así que hoy SIEMPRE es
    el caso), o la que configuró ya no existe en disco (se borró la
    carpeta, era una USB que ya no está conectada), cae a ~/Downloads --
    mismo respaldo que describe el roadmap para descargar_imagen() en
    EJEMPLOS 2. Nunca lanza: siempre hay alguna ruta que devolver, aunque
    ~/Downloads tampoco exista -- en ese caso el propio shutil.copy2() del
    llamador es quien debe fallar y avisar, no esta función."""
    ruta = _leer_config().get(_CLAVE_RUTA_EXPORTACION)
    if ruta and os.path.isdir(ruta):
        return ruta
    return str(Path.home() / "Downloads")


def guardar_ruta_exportacion(ruta: str) -> None:
    """Persiste la ruta elegida. Pensada para llamarse al pulsar "Guardar
    Ajustes" en la 7.5 -- NO en cuanto Tkinter la devuelve -- mismo
    criterio que ya sigue EJEMPLOS 2 (ver el roadmap, "LOS AJUSTES")."""
    guardar_config({_CLAVE_RUTA_EXPORTACION: os.path.normpath(ruta)})
