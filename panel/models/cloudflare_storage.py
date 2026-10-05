"""
models/cloudflare_storage.py
Sube/borra las fotos de los platillos en Cloudflare R2 (Fase 3) — siempre a
través del Worker "taku-monky-uploads" (código en cloudflare/index.js),
nunca directo: el panel no tiene ninguna credencial de R2, solo manda el
access_token de la sesión de Supabase Auth del admin, y el Worker lo valida
contra ADMIN_EMAIL antes de tocar el bucket. Mismo patrón de
EJEMPLOS/lilshop.html, portado de <canvas>+fetch (navegador) a Pillow+httpx
(Python) — ver CLAUDE.md → sección de Fase 3 para el detalle completo.

Este archivo es de CLOUDFLARE, no de Supabase — platillo_dao.py sigue siendo
el único que le pega a la tabla platillos (crear/actualizar ahora aceptan un
"image_url" opcional en el dict que reciben, pero quien sube/borra el
archivo de verdad es este módulo).

Todas las funciones de aquí son SÍNCRONAS y BLOQUEANTES (comprimir con
Pillow = CPU; subir/borrar con httpx = red) — igual que PlatilloDAO, es
responsabilidad de quien llama mandarlas a un hilo aparte con
asyncio.to_thread (ver views/components/dialogo_platillo.py, que es hoy el
único que las usa).

ORDEN DE REVERSA (pedido explícito del dueño para la Fase 3) — igual que
EJEMPLOS/lilshop.html:
  - Alta:    se sube la imagen PRIMERO, se inserta la fila DESPUÉS. Si el
             insert falla, se borra la imagen recién subida (no dejar
             huérfano de un platillo que nunca se guardó).
  - Edición con foto nueva: se sube la imagen nueva, se actualiza la fila.
             Si el update falla, se borra la imagen NUEVA (revertir, la fila
             sigue apuntando a la vieja). Si el update sale bien, RECIÉN
             ENTONCES se borra la imagen VIEJA (ya es seguro, la fila ya
             quedó apuntando a la nueva).
  - Borrado: PlatilloDAO.eliminar() ya borra la fila primero; solo cuando
             eso sale bien, dialogo_platillo.py llama a eliminar_imagen()
             con la image_url que tenía esa fila.
  Ese orden vive en views/components/dialogo_platillo.py (es lógica de
  flujo, no de esta capa) — este módulo solo expone las piezas sueltas.

HUÉRFANOS EN R2 — la preocupación #1 que dejó dicha el dueño para esta fase,
por lo que le pasó en Anxie Store. En EJEMPLOS/lilshop.html,
borrarImagenDeR2() atrapa CUALQUIER error y solo lo manda a console.error:
si el borrado en R2 falla, el producto/platillo se queda borrado igual y la
imagen se queda huérfana en el bucket PARA SIEMPRE, sin que nadie se entere
nunca. Aquí NO se repite eso. eliminar_imagen():
  1. Manda el detalle técnico a consola (print), igual que el resto del
     proyecto.
  2. ANTES de dejar subir la excepción, escribe un registro en
     %LOCALAPPDATA%\\TakuMonky\\huerfanos_r2.json (mismo lugar que
     sesion.json — fuera del repo) con el nombre del archivo, su URL
     completa, el motivo y la fecha.
  3. Deja subir LimpiezaImagenFallida — nunca la atrapa en silencio.
El AVISO EN PANTALLA (el banner rojo que ve el dueño) lo arma la vista
(dialogo_platillo.py / menu_view.py), no este módulo — pero gracias a los 3
pasos de arriba, el fallo NUNCA desaparece sin dejar rastro aunque en algún
punto futuro alguien decida atrapar la excepción y no mostrar nada: ya quedó
en el registro de huérfanos para poder limpiarlo a mano.

RECORTE DE FONDO (Fase 4.3, la "carta" de celular del index) — recortar_fondo()
usa rembg (modelo "u2net", ya bajado a C:\\Users\\<usuario>\\.rembg\\models\\)
para quitar el fondo de la foto y dejar el platillo CON su tabla/plato (el
dueño vio ambas opciones — con y sin tabla — y eligió con tabla, se ve más
"rústico/premium" que el producto flotando en el vacío puro). Solo se usa
para categoría Platillos, con tope de 5 y toda la lógica de cuándo generar/
regenerar/borrar en views/components/dialogo_platillo.py — este módulo solo
expone la función suelta, igual que con validar_y_comprimir()/subir_imagen().
Un fallo aquí NUNCA debe tumbar el guardado normal del platillo: el recorte
es un extra para la carta, no el platillo en sí — dialogo_platillo.py atrapa
RecorteFallido aparte del resto de excepciones de guardado.
"""
import io
import json
import os
import time
from pathlib import Path
from typing import Optional

import httpx
from PIL import Image, ImageOps, UnidentifiedImageError
from rembg import new_session, remove

from models.supabase_client import client

CLOUDFLARE_WORKER_URL = os.getenv("CLOUDFLARE_WORKER_URL", "").rstrip("/")
CLOUDFLARE_R2_PUBLIC_BASE = os.getenv("CLOUDFLARE_R2_PUBLIC_BASE", "").rstrip("/")

if not CLOUDFLARE_WORKER_URL or not CLOUDFLARE_R2_PUBLIC_BASE:
    raise RuntimeError(
        "Faltan CLOUDFLARE_WORKER_URL o CLOUDFLARE_R2_PUBLIC_BASE en el .env "
        "— revisa que existan en la raíz del proyecto."
    )

# Mismo criterio pedido para la Fase 3 (igual que EJEMPLOS/lilshop.html):
# WebP calidad 80 + tope de resolución, para que una foto de celular
# (4000px+ de lado) no se suba tal cual y llene el bucket.
_CALIDAD_WEBP = 80
_LADO_MAXIMO = 1600

# Modelo de rembg para el recorte de fondo (Fase 4.3) — decisión final del
# dueño (2026-09-03) tras comparar 3 modelos en la foto real del "Taco Arabe
# con Queso": u2net es el único que CONSERVA la tabla/plato en vez de dejar
# el producto pelado. Ver el docstring del módulo.
_MODELO_RECORTE = "u2net"

# Tope del archivo ORIGINAL (antes de comprimir) que se deja elegir. A
# propósito generoso: una foto de celular normal pesa 3-8 MB y NO debe
# rechazarse, solo comprimirse — esto solo frena algo verdaderamente
# absurdo (un archivo gigante o que ni siquiera es una foto).
TAMANO_MAXIMO_ORIGINAL = 15 * 1024 * 1024  # 15 MB

_NOMBRE_CARPETA = "TakuMonky"
_ARCHIVO_HUERFANOS = "huerfanos_r2.json"


class ArchivoInvalido(Exception):
    """El archivo elegido no es una imagen válida o excede el tamaño
    permitido — se revisa ANTES de gastar tiempo comprimiendo o subiendo,
    para que el dueño nunca vea un error crudo de Pillow o de red. El
    mensaje de esta excepción ya está en español y listo para pantalla."""


class SubidaFallida(Exception):
    """No se pudo subir la imagen al Worker (red, sesión vencida, o el
    Worker respondió con error). El mensaje ya está pensado para mostrarse
    en pantalla tal cual."""


class LimpiezaImagenFallida(Exception):
    """No se pudo borrar una imagen de R2 (ver el bloque HUÉRFANOS arriba
    en el docstring del módulo). Quien la atrape ya sabe que el intento de
    borrado quedó anotado en huerfanos_r2.json antes de que esta excepción
    subiera — ver _registrar_huerfano()."""

    def __init__(self, nombre_archivo: str, causa: Exception):
        self.nombre_archivo = nombre_archivo
        self.causa = causa
        super().__init__(f"No se pudo borrar '{nombre_archivo}' de R2: {causa}")


class RecorteFallido(Exception):
    """No se pudo recortar el fondo de la foto (rembg/onnxruntime truena, o
    el resultado quedó sin ningún píxel con alfa > 0). A diferencia de
    ArchivoInvalido/SubidaFallida, esto NUNCA debe impedir guardar el
    platillo: el recorte es un extra para la carta de celular (Fase 4.3),
    no el platillo en sí. Quien la atrape (dialogo_platillo.py) debe seguir
    con el guardado normal y solo avisar que la carta se quedó sin su
    versión recortada esta vez."""


# ----------------------------------------------------------------------
# Validar + comprimir (Pillow) — corre ANTES de tocar la red.
# ----------------------------------------------------------------------
def validar_y_comprimir(ruta_archivo: str) -> bytes:
    """Valida que `ruta_archivo` sea una imagen de verdad y no exceda
    TAMANO_MAXIMO_ORIGINAL, y devuelve sus bytes ya convertidos a WebP
    calidad 80 con el lado mayor recortado a máximo 1600px — mismo criterio
    que convertirAWebP() de EJEMPLOS/lilshop.html, aquí con Pillow en vez de
    <canvas>. Llamada BLOQUEANTE (CPU): mandar a un hilo aparte.
    """
    try:
        tamano = os.path.getsize(ruta_archivo)
    except OSError as e:
        raise ArchivoInvalido("No se pudo leer el archivo seleccionado.") from e

    if tamano > TAMANO_MAXIMO_ORIGINAL:
        limite_mb = TAMANO_MAXIMO_ORIGINAL // (1024 * 1024)
        raise ArchivoInvalido(
            f"La imagen pesa más de {limite_mb} MB. Elige una foto más ligera."
        )

    try:
        with Image.open(ruta_archivo) as imagen:
            imagen.verify()  # detecta archivos corruptos o que no son imágenes de verdad
    except (UnidentifiedImageError, OSError) as e:
        raise ArchivoInvalido("El archivo seleccionado no es una imagen válida.") from e

    # verify() deja la imagen inutilizable para seguir trabajando con ella
    # (así lo documenta Pillow) — se vuelve a abrir para el procesamiento real.
    with Image.open(ruta_archivo) as imagen:
        # Corrige la rotación que traen muchas fotos de celular en su EXIF
        # (si no, algunas se suben de lado o de cabeza).
        imagen = ImageOps.exif_transpose(imagen)
        if imagen.mode not in ("RGB", "RGBA"):
            imagen = imagen.convert("RGBA" if "A" in imagen.getbands() else "RGB")

        ancho, alto = imagen.size
        lado_mayor = max(ancho, alto)
        if lado_mayor > _LADO_MAXIMO:
            escala = _LADO_MAXIMO / lado_mayor
            imagen = imagen.resize(
                (round(ancho * escala), round(alto * escala)), Image.LANCZOS
            )

        buffer = io.BytesIO()
        imagen.save(buffer, format="WEBP", quality=_CALIDAD_WEBP)
        return buffer.getvalue()


# ----------------------------------------------------------------------
# Recorte de fondo (Fase 4.3, rembg) — corre DESPUÉS de validar_y_comprimir()
# y ANTES de subir_imagen(), ver docstring del módulo.
# ----------------------------------------------------------------------
_sesion_rembg = None  # singleton perezoso — ver _sesion_recorte()


def _sesion_recorte():
    """Crea la sesión de rembg (carga el modelo ONNX, ~168MB) la PRIMERA
    vez que de verdad se necesita, y la reusa siempre después. A propósito
    NO se crea al importar este módulo: cargar el modelo en cada arranque
    del panel —aunque el dueño solo vaya a editar una Bebida— sería un
    costo fijo innecesario. Pero sí se reusa entre fotos dentro de la misma
    sesión del panel: crearla por cada foto es lentísimo (es lo que pide
    evitar el roadmap de la Fase 4.3)."""
    global _sesion_rembg
    if _sesion_rembg is None:
        _sesion_rembg = new_session(_MODELO_RECORTE)
    return _sesion_rembg


def recortar_fondo(datos_imagen: bytes) -> bytes:
    """Quita el fondo de `datos_imagen` (bytes de una imagen que Pillow ya
    puede abrir — se le pasa el mismo WebP que ya salió de
    validar_y_comprimir(), ya con la rotación EXIF corregida y el lado
    mayor topado a 1600px, para no reprocesar eso dos veces) usando rembg
    con el modelo _MODELO_RECORTE ("u2net": conserva la tabla/plato del
    platillo, ver docstring del módulo). Devuelve bytes WebP CON CANAL
    ALFA, recortados al bounding box de lo que quedó NO transparente (para
    no subir aire transparente de más alrededor del producto).

    Llamada BLOQUEANTE (CPU, ~0.2s con u2net) — igual que
    validar_y_comprimir(), quien la use la manda a un hilo aparte con
    asyncio.to_thread (ver views/components/dialogo_platillo.py).

    Levanta RecorteFallido si rembg truena o si el resultado sale sin
    ningún píxel con alfa > 0 (bbox vacío) — nunca deja pasar una imagen
    rota o completamente transparente en silencio.
    """
    try:
        resultado = remove(datos_imagen, session=_sesion_recorte())
        imagen = Image.open(io.BytesIO(resultado)).convert("RGBA")

        # Bounding box del CANAL ALFA, no de la imagen completa: rembg
        # conserva el color RGB original bajo las zonas transparentes, así
        # que Image.getbbox() (que mira los 4 canales juntos) no detectaría
        # el recorte real. alfa.getbbox() sí encuentra solo lo que quedó
        # visible de verdad.
        alfa = imagen.split()[-1]
        bbox = alfa.getbbox()
        if bbox is None:
            raise RecorteFallido(
                "rembg no dejó ningún píxel visible (imagen totalmente transparente)."
            )
        imagen = imagen.crop(bbox)

        buffer = io.BytesIO()
        imagen.save(buffer, format="WEBP", quality=_CALIDAD_WEBP)
        return buffer.getvalue()
    except RecorteFallido:
        raise
    except Exception as e:
        raise RecorteFallido(f"No se pudo recortar el fondo de la imagen: {e}") from e


# ----------------------------------------------------------------------
# Subida / borrado vía el Worker (nunca directo a R2 — ver docstring arriba)
# ----------------------------------------------------------------------
def _access_token() -> str:
    """Toma el access_token de la sesión activa de Supabase Auth — es lo
    que el Worker valida contra ADMIN_EMAIL antes de tocar el bucket (ver
    cloudflare/index.js). Si no hay sesión, ni tiene caso intentar la
    subida/borrado."""
    sesion = client.auth.get_session()
    if not sesion or not sesion.access_token:
        raise SubidaFallida("Tu sesión expiró. Vuelve a iniciar sesión.")
    return sesion.access_token


def subir_imagen(datos_webp: bytes) -> str:
    """POST de los bytes WebP ya comprimidos al Worker; devuelve la URL
    pública final (bajo CLOUDFLARE_R2_PUBLIC_BASE). Llamada BLOQUEANTE
    (red): mandar a un hilo aparte."""
    token = _access_token()
    try:
        respuesta = httpx.post(
            f"{CLOUDFLARE_WORKER_URL}/upload",
            content=datos_webp,
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "image/webp",
            },
            timeout=30,
        )
    except httpx.RequestError as e:
        raise SubidaFallida(
            "No se pudo conectar con el servidor de imágenes. Revisa tu internet."
        ) from e

    cuerpo = None
    if respuesta.headers.get("content-type", "").startswith("application/json"):
        try:
            cuerpo = respuesta.json()
        except ValueError:
            cuerpo = None

    if respuesta.status_code != 200 or not cuerpo or not cuerpo.get("ok"):
        detalle = (cuerpo or {}).get("error") or f"HTTP {respuesta.status_code}"
        print(f"[cloudflare_storage] subida rechazada por el Worker: {detalle}")
        raise SubidaFallida("No se pudo subir la foto.")

    return cuerpo["url"]


def nombre_archivo_r2(image_url: Optional[str]) -> Optional[str]:
    """Igual que nombreArchivoR2() de EJEMPLOS/lilshop.html: extrae el
    nombre de archivo SOLO si `image_url` de verdad pertenece a nuestro
    bucket — cualquier otro valor (None, vacío, una URL de otro dominio)
    devuelve None, para que eliminar_imagen() nunca intente borrar algo que
    no es suyo."""
    if not image_url or not image_url.startswith(CLOUDFLARE_R2_PUBLIC_BASE + "/"):
        return None
    return image_url[len(CLOUDFLARE_R2_PUBLIC_BASE) + 1 :]


def eliminar_imagen(image_url: Optional[str]) -> None:
    """Borra una imagen de R2 a partir de su image_url completa. No hace
    nada si image_url no pertenece a nuestro bucket (ver
    nombre_archivo_r2()) — no es un error, simplemente no hay nada que
    borrar aquí.

    A diferencia de EJEMPLOS/lilshop.html, esta función SÍ deja subir la
    excepción si el borrado falla (ver el bloque HUÉRFANOS en el docstring
    del módulo) — pero antes deja anotado el huérfano en disco, así que el
    fallo nunca es invisible aunque quien llame decida solo avisar en
    pantalla y seguir. Llamada BLOQUEANTE (red): mandar a un hilo aparte.
    """
    nombre = nombre_archivo_r2(image_url)
    if not nombre:
        return

    try:
        token = _access_token()
        respuesta = httpx.delete(
            f"{CLOUDFLARE_WORKER_URL}/delete",
            params={"file": nombre},
            headers={"Authorization": f"Bearer {token}"},
            timeout=30,
        )
        if respuesta.status_code != 200:
            raise SubidaFallida(f"El Worker respondió HTTP {respuesta.status_code} al borrar.")
    except Exception as e:
        print(f"[cloudflare_storage] no se pudo borrar '{nombre}' de R2: {e}")
        _registrar_huerfano(nombre, str(e))
        raise LimpiezaImagenFallida(nombre, e) from e


# ----------------------------------------------------------------------
# Registro de huérfanos — ver el bloque HUÉRFANOS en el docstring del
# módulo. Fuera del repo, en la carpeta del usuario (%LOCALAPPDATA%\TakuMonky)
# — nunca dentro del proyecto. Desde que se borró models/sesion.py (2026-09-05)
# este es el ÚNICO archivo que vive ahí, y _ruta_huerfanos() crea la carpeta
# sola, así que no importa que no exista todavía.
# ----------------------------------------------------------------------
def _ruta_huerfanos() -> Path:
    base = os.getenv("LOCALAPPDATA") or str(Path.home())
    carpeta = Path(base) / _NOMBRE_CARPETA
    carpeta.mkdir(parents=True, exist_ok=True)
    return carpeta / _ARCHIVO_HUERFANOS


def _registrar_huerfano(nombre_archivo: str, motivo: str) -> None:
    """Agrega un registro a huerfanos_r2.json — nunca lo reemplaza, para no
    perder huérfanos anteriores que todavía no se hayan limpiado a mano."""
    ruta = _ruta_huerfanos()
    try:
        registros = json.loads(ruta.read_text(encoding="utf-8")) if ruta.exists() else []
    except (OSError, json.JSONDecodeError):
        registros = []

    registros.append(
        {
            "archivo": nombre_archivo,
            "url": f"{CLOUDFLARE_R2_PUBLIC_BASE}/{nombre_archivo}",
            "motivo": motivo,
            "fecha": time.strftime("%Y-%m-%d %H:%M:%S"),
        }
    )
    try:
        ruta.write_text(json.dumps(registros, ensure_ascii=False, indent=2), encoding="utf-8")
    except OSError as e:
        print(f"[cloudflare_storage] no se pudo escribir el registro de huérfanos: {e}")
