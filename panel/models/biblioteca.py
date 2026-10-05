"""
models/biblioteca.py
Lo que hay en la carpeta biblioteca/ (los anuncios generados), ya leído: de cada archivo, su
fecha, su formato (post o historia), su medida y el producto. Lo usa Mi biblioteca
(views/biblioteca_view.py); las llamadas son de disco, así que la vista las corre con
asyncio.to_thread.

SIN TABLA EN SUPABASE, a propósito: todo sale del archivo mismo. El generador
(models/generador_ia.py) pone la fecha y el producto en el nombre:
20261001-153543-taco-arabe-ia-post.png
Un archivo que no siga ese patrón (copiado a mano) toma la fecha de modificación y el formato de
su medida. Una tabla con lo mismo se desfasaría en cuanto alguien borre un archivo desde el
Explorador.

La carpeta (RUTA_BIBLIOTECA) y el slug del producto viven aquí: generador_ia.py escribe con los
mismos dos, así que el nombre que pone y el que se busca aquí nunca se desfasan.
"""
import datetime
import os
import re
import shutil
import subprocess

from PIL import Image

from models.config_usuario import obtener_ruta_exportacion

# Relativa a panel/ (el cwd de la app). Se arman las rutas con diagonal, nunca con
# os.path.join: ft.Image(src=...) no carga rutas con "\".
RUTA_BIBLIOTECA = "biblioteca"

EXTENSIONES = (".png", ".jpg", ".jpeg", ".webp")

_DE_IA = re.compile(r"^(\d{8}-\d{6})-(.+)-ia-(post|historia)\.\w+$", re.IGNORECASE)

_MAPA_ACENTOS = str.maketrans("áéíóúüñ", "aeiouun")


def _slug(texto: str) -> str:
    """El producto como va en el nombre del archivo: "Taco Árabe" -> "taco-arabe"."""
    texto = texto.strip().lower().translate(_MAPA_ACENTOS)
    limpio = "".join(c if c.isalnum() else "-" for c in texto)
    while "--" in limpio:
        limpio = limpio.replace("--", "-")
    return limpio.strip("-") or "producto"


def _medida(ruta):
    # Pillow solo lee la cabecera: no carga la imagen entera.
    with Image.open(ruta) as imagen:
        return imagen.size


def _leer(nombre_archivo):
    ruta = f"{RUTA_BIBLIOTECA}/{nombre_archivo}"
    try:
        mtime = os.path.getmtime(ruta)
        ancho, alto = _medida(ruta)
    except OSError:
        return None     # se borró entre el listdir y aquí, o no es una imagen que se pueda abrir
    fecha, formato, slug = None, None, ""
    if coincide := _DE_IA.match(nombre_archivo):
        fecha = datetime.datetime.strptime(coincide.group(1), "%Y%m%d-%H%M%S")
        slug, formato = coincide.group(2), coincide.group(3).lower()
    if fecha is None:
        fecha = datetime.datetime.fromtimestamp(mtime)
    if formato is None:
        formato = "historia" if alto / ancho > 1.5 else "post"
    return {"ruta": ruta, "archivo": nombre_archivo, "fecha": fecha, "formato": formato,
            "slug": slug, "ancho": ancho, "alto": alto}


def listar() -> list[dict]:
    """Los anuncios de la carpeta, del más nuevo al más viejo. Carpeta ausente = vacía (se crea
    con el primer anuncio). Un error al leer la carpeta misma se deja subir: la vista lo dice."""
    if not os.path.isdir(RUTA_BIBLIOTECA):
        return []
    anuncios = [a for a in (_leer(n) for n in os.listdir(RUTA_BIBLIOTECA)
                            if n.lower().endswith(EXTENSIONES)) if a]
    anuncios.sort(key=lambda a: a["fecha"], reverse=True)
    return anuncios


def poner_nombres(anuncios, platillos):
    """El nombre real del producto: el slug del archivo se busca entre los platillos del menú
    ("taco-arabe" -> "Taco Árabe"). Si ya no está en el menú (o no se pudo leer), el slug
    legible ("Taco arabe")."""
    por_slug = {}
    for platillo in platillos or []:
        por_slug.setdefault(_slug(platillo.get("nombre") or ""), platillo.get("nombre"))
    for anuncio in anuncios:
        slug = anuncio["slug"]
        anuncio["nombre"] = (por_slug.get(slug) or slug.replace("-", " ").capitalize()
                             or "Anuncio")
    return anuncios


def exportar(anuncio) -> str:
    """Copia el anuncio a la carpeta de exportación de Ajustes (~/Downloads si no hay).
    Devuelve esa carpeta."""
    carpeta = obtener_ruta_exportacion()
    shutil.copy2(anuncio["ruta"], os.path.join(carpeta, anuncio["archivo"]))
    return carpeta


def eliminar(anuncio):
    os.remove(anuncio["ruta"])


def mostrar_en_carpeta(anuncio=None):
    # El Explorador con el anuncio ya marcado; sin anuncio, la carpeta biblioteca/ abierta.
    if anuncio and os.path.exists(anuncio["ruta"]):
        subprocess.Popen(["explorer", "/select,",
                          os.path.normpath(os.path.abspath(anuncio["ruta"]))])
    else:
        os.makedirs(RUTA_BIBLIOTECA, exist_ok=True)
        os.startfile(os.path.abspath(RUTA_BIBLIOTECA))
