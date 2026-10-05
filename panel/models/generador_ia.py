"""
models/generador_ia.py
Crear contenido con IA (01/10): arma el prompt del flyer y le pide la imagen a OpenAI
(gpt-image-2.5-sunburst, calidad "high"). La vista (views/contenido_view.py) solo elige el
producto, el formato y el mensaje; los datos del negocio salen de datos_negocio (Supabase).

EL PROMPT: la ESTRUCTURA es la del prompt que escribió y probó el desarrollador
(planes/crear contenido referencias/prompt-base-flyer.txt, "el bueno": rojo arriba / crema
abajo, corte recto, producto al centro, letra condensada limpia, lista de prohibidos, "no
inventes texto"). Lo que allí era fijo para Don Pepe aquí es variable: el producto (con su foto
de R2 como referencia), su precio, el mensaje del usuario (va tal cual como "Promotion") y los
datos del negocio. Decidido con el desarrollador (01/10): precio del menú SÍ va ("Price"),
colores fijos rojo/crema, llamado a la acción fijo "ORDENA AHORA". POST lleva nombre y teléfono;
HISTORIA, nombre, teléfono, página web y dirección. Lo vacío no se manda.

OPCIONALES (01/10, noche; maqueta https://claude.ai/artifact/AuWieY9WJjgHoNnVpb7hiw):
- COLOR: un hex que reemplaza al rojo (fondo de arriba, precio, promoción y botón). Sin color, el
  prompt es EXACTAMENTE el de antes ("Solid vivid red background"...). El crema de abajo es fijo,
  no negociable. Si el color es claro (es_claro, luminancia > 0.45) se pide letra oscura encima.
- COMBO: hasta 2 productos extra que acompañan al principal. Van sus fotos como referencias (en
  orden: principal y extras), el titular es SOLO el principal (decisión del desarrollador: los
  extra solo acompañan, sin su nombre), no va precio del menú (el del combo va en el mensaje) y
  se pide dibujarlos más chicos mientras más sean.

LA LLAMADA: con foto(s) -> images.edit (las fotos como referencia); sin ninguna -> images.generate.
El modelo pide tamaños múltiplos de 16, así que se pide 1152x1440 (post 4:5) o 1152x2048
(historia 9:16) y Pillow la baja a 1080x1350 / 1080x1920 exactos. Se guarda como PNG en
biblioteca/ (RUTA_BIBLIOTECA), donde Mi biblioteca ya la ve. El `usage` de la respuesta se
escribe en consola para saber el costo real por imagen.

Modelo y calidad: no se cambian sin que el desarrollador lo pida (si gasta mucho, la calidad
baja a "low"). El modelo se puede sobreescribir con OPENAI_MODEL_IMAGEN en el .env.

generar() es bloqueante (descarga + OpenAI + Pillow): la vista lo llama con asyncio.to_thread.
"""
import base64
import io
import os
import time
from datetime import datetime
from pathlib import Path

import httpx
from dotenv import load_dotenv
from openai import OpenAI
from PIL import Image

from models.biblioteca import RUTA_BIBLIOTECA, _slug

load_dotenv(Path(__file__).resolve().parents[2] / ".env")

_MODELO = os.getenv("OPENAI_MODEL_IMAGEN", "gpt-image-2.5-sunburst")
_CALIDAD = "high"
# Alta calidad tarda: el SDK corta a los 10 min por defecto, pero un minuto y pico es lo normal.
_TIEMPO_MAXIMO = 300

# formato -> (lo que se le pide al modelo, lo que se guarda, cómo se dice en el prompt)
FORMATOS = {
    "post": ("1152x1440", (1080, 1350), "vertical 4:5 Instagram feed post (1080x1350)"),
    "historia": ("1152x2048", (1080, 1920), "vertical 9:16 Instagram story (1080x1920)"),
}

LLAMADO_A_LA_ACCION = "ORDENA AHORA"

_cliente_openai = None


class SinLlave(Exception):
    """No hay OPENAI_API_KEY en el .env."""


def _cliente() -> OpenAI:
    # Mismo criterio que saludo_ia.py: se crea la primera vez que hace falta.
    global _cliente_openai
    if _cliente_openai is None:
        llave = os.getenv("OPENAI_API_KEY")
        if not llave:
            raise SinLlave("Falta OPENAI_API_KEY en el .env.")
        _cliente_openai = OpenAI(api_key=llave, timeout=_TIEMPO_MAXIMO)
    return _cliente_openai


def formatear_precio(valor) -> str:
    # Mismo criterio que _formatear_precio() de menu_view.py: sin decimales si es entero.
    if valor is None or valor == "":
        return ""
    numero = float(valor)
    return f"${int(numero):,}" if numero.is_integer() else f"${numero:,.2f}"


def datos_que_van(formato: str, datos: dict) -> list[str]:
    """Los datos del negocio que lleva cada formato, sin los vacíos y en orden. Lo usan el prompt
    y la línea "Irá en el anuncio: ..." de la vista, así nunca dicen cosas distintas."""
    claves = ("nombre", "telefono", "pagina_web", "direccion") if formato == "historia" \
        else ("nombre", "telefono")
    return [(datos.get(c) or "").strip() for c in claves if (datos.get(c) or "").strip()]


def luminancia(color_hex: str) -> float:
    """Luminancia relativa (WCAG) de "#RRGGBB": 0 negro, 1 blanco."""
    valor = int(color_hex.lstrip("#"), 16)
    canales = []
    for corrimiento in (16, 8, 0):
        c = ((valor >> corrimiento) & 255) / 255
        canales.append(c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4)
    return 0.2126 * canales[0] + 0.7152 * canales[1] + 0.0722 * canales[2]


def es_claro(color_hex: str) -> bool:
    # Sobre un color así el texto blanco no se lee: las letras encima van oscuras. Mismo umbral
    # que la ventana de color (views/components/dialogo_color.py) para que el aviso no mienta.
    return luminancia(color_hex) > 0.45


def armar_prompt(producto: dict, formato: str, mensaje: str, datos: dict,
                 con_foto: bool, color: str | None = None,
                 extras: list[dict] | None = None) -> str:
    """`color`: "#RRGGBB" elegido en la ventana de color, o None = el rojo de siempre (el prompt
    queda EXACTAMENTE como el probado). `extras`: hasta 2 productos que acompañan al principal
    (combo): se mandan sus fotos, pero el titular es solo el principal y no va precio del menú
    (el del combo lo escribe el usuario en el mensaje). El crema de abajo no cambia nunca."""
    extras = extras or []
    nombre_producto = (producto.get("nombre") or "").strip()
    titular = nombre_producto.upper()
    precio = "" if extras else formatear_precio(producto.get("precio"))
    mensaje = mensaje.strip()
    negocio = (datos.get("nombre") or "").strip().upper()
    telefono = (datos.get("telefono") or "").strip()
    web = (datos.get("pagina_web") or "").strip() if formato == "historia" else ""
    direccion = (datos.get("direccion") or "").strip() if formato == "historia" else ""
    descripcion_formato = FORMATOS[formato][2]
    # Cómo se nombra el color de arriba: "red" (lo de siempre) o el hex elegido.
    color_arriba = color or "red"

    if extras:
        nombres_extra = [(p.get("nombre") or "").strip() for p in extras]
        con_foto_extra = [bool(p.get("image_url")) for p in extras]
        # Las fotos van en este orden: la del principal (si tiene) y luego las de los extra.
        en_referencia = ([nombre_producto] if con_foto else []) + \
            [n for n, f in zip(nombres_extra, con_foto_extra) if f]
        acompanantes = " and ".join(f'"{n}"' for n in nombres_extra)
        total = 1 + len(extras)
        heroe = (f'Show {total} products together as one combo: the main product '
                 f'"{nombre_producto}", accompanied by {acompanantes}. The main product is the '
                 "largest, in the center, slightly overlapping the boundary between the "
                 f"{color_arriba} and cream sections; the accompanying products sit beside it, "
                 "smaller. "
                 f"Because there are {total} products, draw each one smaller than a single hero "
                 "product would be, so they all fit comfortably without crowding.")
        if en_referencia:
            heroe += ("\n\nThe reference images show, in this order: "
                      + ", ".join(f'"{n}"' for n in en_referencia) + ". "
                      "Keep each product's real look: same food or drink, same ingredients, same "
                      "shape and same presentation as in its reference image. Do not replace "
                      "them with different products.")
        sin_foto = [n for n, f in zip([nombre_producto] + nombres_extra,
                                      [con_foto] + con_foto_extra) if not f]
        if sin_foto:
            heroe += ("\n\nDraw " + ", ".join(f'"{n}"' for n in sin_foto)
                      + " photorealistic.")
    elif con_foto:
        heroe = (f'Place the product shown in the reference image, "{nombre_producto}", '
                 "large and prominently in the center, slightly overlapping the boundary "
                 f"between the {color_arriba} and cream sections.\n\n"
                 "Keep its real look: same food, same ingredients, same shape and same "
                 "presentation as in the reference image. Do not replace it with a different "
                 "dish.")
    else:
        heroe = (f'Place one large, photorealistic "{nombre_producto}" prominently in the '
                 f"center, slightly overlapping the boundary between the {color_arriba} and "
                 "cream sections.")

    # CONTENT: solo lo que hay, cada cosa con su etiqueta.
    contenido = []
    if negocio:
        contenido.append(f'Restaurant name:\n"{negocio}"')
    contenido.append(f'Main headline:\n"{titular}"')
    if precio:
        contenido.append(f'Price:\n"{precio}"')
    if mensaje:
        contenido.append(f'Promotion:\n"{mensaje}"')
    if telefono:
        contenido.append(f'Phone number:\n"{telefono}"')
    if web:
        contenido.append(f'Website:\n"{web}"')
    if direccion:
        contenido.append(f'Address:\n"{direccion}"')
    contenido.append(f'Call to action:\n"{LLAMADO_A_LA_ACCION}"')

    jerarquia = [f'Make "{titular}" large and prominent, but keep it clean and refined.']
    if precio:
        jerarquia.append(f'Make "{precio}" extremely large and visually dominant as the main '
                         "price.")
    if mensaje:
        jerarquia.append("Place the promotion close to the price in a compact, easy-to-read "
                         "format." if precio else
                         "Place the promotion close to the headline in a compact, easy-to-read "
                         "format.")
    if negocio:
        jerarquia.append(f'Place "{negocio}" as a smaller brand element.')
    contacto = [x for x in (telefono, web, direccion) if x]
    if contacto:
        jerarquia.append("Place the contact details (" + ", ".join(f'"{x}"' for x in contacto)
                         + ") small, clean and legible near the bottom.")
    jerarquia.append(f'Place "{LLAMADO_A_LA_ACCION}" as a simple modern call-to-action.')

    secciones = [
        "Create a premium commercial restaurant advertising flyer for a modern Mexican "
        "fast-food chain.",
        f"FORMAT:\nA {descripcion_formato}.",
        "IMPORTANT:\nThis is a GRAPHIC DESIGN composition first and a food photograph second.\n"
        "The design must feel like a professionally art-directed campaign from a large "
        "established restaurant brand, NOT like an AI-generated food poster.",
        "LAYOUT:\nCreate a clean vertical advertising poster with a strict 50/50 split "
        "background.",
        "TOP HALF:\n" + (f"Solid {color} background (use exactly this color)." if color
                         else "Solid vivid red background."),
        "BOTTOM HALF:\nSolid very light warm cream background.",
        "The separation between the two colors must be a perfectly straight horizontal line.\n"
        "NO wave.\nNO curved transition.\nNO gradient.\nNO texture.\n"
        "NO decorative background pattern.",
        "HERO PRODUCT:\n" + heroe,
        "The product should look premium and extremely appetizing.\n\n"
        "Keep the food photography highly realistic and detailed, but cleanly isolated from "
        "the background.",
        "GRAPHIC DESIGN STYLE:\nMinimal, bold, modern commercial fast-food advertising.",
        "Think sophisticated retail advertising rather than a traditional Mexican poster.",
        "Use strong visual hierarchy, generous negative space, clean alignment, simple "
        "geometric composition, and confident typography.",
        "TYPOGRAPHY:\nUse a bold modern condensed sans-serif typeface similar to contemporary "
        "fast-food advertising.",
        "Typography should be:\nclean, bold, highly legible, modern, compact, commercial and "
        "premium.",
        "DO NOT use:\n- distressed typography\n- grunge typography\n- hand-painted lettering\n"
        "- brush lettering\n- western fonts\n- vintage fonts\n- decorative fonts\n"
        "- cartoon lettering\n- excessive outlines\n- fake 3D text\n- textured lettering",
        "The typography must look like professionally typeset brand advertising.",
        "CONTENT:",
        *contenido,
        "TEXT HIERARCHY:\n" + "\n\n".join(jerarquia),
        "COLOR DIRECTION:\n" + _direccion_color(color),
        "IMPORTANT:\nDo not add decorative brush strokes, paint splashes, grunge textures, "
        "ribbons, badges, stars, flames, random icons, unnecessary shapes, or extra visual "
        "elements.",
        "Do not make the design overly busy.",
        "The final composition should feel intentionally simple, premium, highly commercial, "
        "and suitable for a major restaurant chain campaign.",
        f'The "{nombre_producto}" must remain the visual centerpiece.' if not extras else
        f'The "{nombre_producto}" must remain the visual centerpiece; the accompanying '
        "products only complement it. Do not write the names of the accompanying products.",
        "Do not invent additional text, prices, promotions, logos, addresses, phone numbers, "
        "or claims.",
        "Respect every provided business text exactly as written.",
    ]
    return "\n\n".join(secciones)


def _direccion_color(color: str | None) -> str:
    if not color:
        # El rojo de siempre: el texto probado, sin tocar.
        return ("Use the red background as the main brand color.\n"
                "Use the cream background as the contrasting secondary color.\n"
                "Use black, dark brown, and white typography where appropriate for maximum "
                "readability.")
    lineas = [
        f"Use the {color} background as the main brand color. Do not use red anywhere: "
        f"{color} replaces it.",
        f"Use {color} for the price text, the promotion card and the call-to-action button "
        "(every accent element).",
        "Use the cream background as the contrasting secondary color.",
    ]
    if es_claro(color):
        lineas.append(f"{color} is a light color: any text placed on {color} must be black or "
                      "dark brown, never white.")
    lineas.append("Use black, dark brown, and white typography where appropriate for maximum "
                  "readability.")
    return "\n".join(lineas)


def _bajar_foto(url: str, numero: int = 1) -> tuple:
    # La foto del platillo en R2 es pública: se baja sin credenciales.
    respuesta = httpx.get(url, timeout=30, follow_redirects=True)
    respuesta.raise_for_status()
    tipo = respuesta.headers.get("content-type", "image/webp").split(";")[0].strip()
    extension = {"image/png": "png", "image/jpeg": "jpg"}.get(tipo, "webp")
    return (f"producto-{numero}.{extension}", respuesta.content, tipo)


def generar(producto: dict, formato: str, mensaje: str, datos: dict,
            color: str | None = None, extras: list[dict] | None = None) -> str:
    """Genera el flyer y lo guarda en biblioteca/. Devuelve la ruta con "/" (lista para
    ft.Image). No atrapa nada: la vista traduce los errores (sin llave, sin saldo, sin red).
    `color` y `extras`: ver armar_prompt (None / vacío = el anuncio de siempre)."""
    tamano_pedido, tamano_final, _ = FORMATOS[formato]
    cliente = _cliente()
    extras = extras or []
    url_foto = producto.get("image_url")
    prompt = armar_prompt(producto, formato, mensaje, datos, con_foto=bool(url_foto),
                          color=color, extras=extras)
    # Las fotos de referencia, en el orden que dice el prompt: principal y luego los extra.
    urls = [u for u in [url_foto] + [p.get("image_url") for p in extras] if u]

    inicio = time.monotonic()
    if urls:
        fotos = [_bajar_foto(u, i) for i, u in enumerate(urls, start=1)]
        resultado = cliente.images.edit(model=_MODELO, image=fotos, prompt=prompt,
                                        size=tamano_pedido, quality=_CALIDAD)
    else:
        resultado = cliente.images.generate(model=_MODELO, prompt=prompt, size=tamano_pedido,
                                            quality=_CALIDAD)
    print(f"[generador_ia] {_MODELO} {_CALIDAD} {tamano_pedido} "
          f"({len(urls)} foto{'s' if len(urls) != 1 else ''}, {1 + len(extras)} producto"
          f"{'s' if extras else ''}, color {color or 'rojo'}) en "
          f"{time.monotonic() - inicio:.1f} s — usage: {getattr(resultado, 'usage', None)}")

    imagen = Image.open(io.BytesIO(base64.b64decode(resultado.data[0].b64_json)))
    imagen = imagen.convert("RGB").resize(tamano_final, Image.Resampling.LANCZOS)

    os.makedirs(RUTA_BIBLIOTECA, exist_ok=True)
    marca = datetime.now().strftime("%Y%m%d-%H%M%S")
    # Diagonal, no os.path.join: ft.Image no carga rutas con "\" (ver models/biblioteca.py).
    ruta = f"{RUTA_BIBLIOTECA}/{marca}-{_slug(producto.get('nombre', ''))}-ia-{formato}.png"
    imagen.save(ruta)
    return ruta
