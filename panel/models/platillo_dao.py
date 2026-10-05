"""
models/platillo_dao.py
Acceso a la tabla public.platillos — capa DAO, sigue el patrón de VentaDAO
que usa EJEMPLOS/ia_controller.py (VentaDAO.obtener_todas_las_ventas()): una
clase con un método que hace la consulta contra Supabase y regresa los datos
ya listos para pintar, sin lógica de UI aquí.

Fase 2 pasos 2.1-2.5: solo lectura, obtener_todos(). Fase 2.6: se agregan las
operaciones de escritura — crear/actualizar/eliminar/cambiar_visibilidad —
para cablear el botón "Agregar platillo" y los íconos de ojo/lápiz.

No se atrapan excepciones en este archivo: tanto errores de red (httpx,
si Supabase no responde) como errores de la API (postgrest.APIError, por
ejemplo si RLS rechaza algo o un CHECK de la tabla lo rechaza) se dejan subir
tal cual, igual que sign_in_with_password en views/sesion_view.py — es la
vista la que decide qué mensaje mostrar para cada caso.

OJO — esto SÍ se atrapa/convierte aquí, y es la razón de EscrituraSinEfecto
(ver clase abajo): a diferencia de INSERT, un UPDATE o DELETE que RLS bloquea
NO lanza un error de Postgres/PostgREST — simplemente no encuentra ninguna
fila que coincida con la política (WHERE ... AND <política de RLS>) y
"tiene éxito" devolviendo data=[]. Se comprobó en vivo contra Supabase real
en la verificación de la Fase 2.6: con una sesión sin permisos de escritura,
cambiar_visibilidad() devolvía 200 con data=[] y el código original tomaba
eso como éxito, prendiendo el badge OCULTO en pantalla aunque la fila seguía
visible=true en la base — un falso positivo. actualizar/eliminar/
cambiar_visibilidad ahora revisan que `data` no venga vacío y levantan
EscrituraSinEfecto si acaso, para que la vista SÍ se entere y muestre error.
"""
from models.supabase_client import client


class EscrituraSinEfecto(Exception):
    """Supabase respondió sin error pero la escritura no afectó ninguna
    fila — típicamente porque RLS la bloqueó en silencio (ver nota arriba),
    o porque el id ya no existe. Se trata como cualquier otro fallo de
    guardado: la vista la atrapa con el `except Exception` genérico que ya
    tenía y muestra el mismo mensaje amigable de "no se pudo guardar"."""

# Solo las columnas que menu_view.py realmente pinta en la tabla, MÁS
# image_url_recortada — nunca select('*'). Mismo criterio que
# EJEMPLOS/catalog-cache.js.
# (created_at existe en la tabla pero ninguna vista la usa todavía; "orden"
# tampoco se pinta como texto, solo se usa para el ORDER BY de abajo, así
# que no hace falta traerla también en el select de obtener_todos().)
# image_url_recortada (Fase 4.3) es la ÚNICA excepción a "solo lo que se
# pinta": menu_view.py no la muestra, pero dialogo_platillo.py sí la
# necesita al editar un platillo — para saber si YA tenía un recorte
# generado (y así no perder el cupo de 5, ver ese archivo) sin tener que
# hacer una consulta aparte solo para eso.
_COLUMNAS = "id, nombre, descripcion, categoria, precio, visible, image_url, image_url_recortada"

# Mismas 3 categorías del CHECK de la tabla y de _CATEGORIAS en
# dialogo_platillo.py — fijas a propósito, no hay categoría libre. Las usa
# obtener_estadisticas() (Fase 2.7) para saber en cuántas de las 3 hay al
# menos un platillo, sin traer la columna completa para sacar un distinct.
_CATEGORIAS_FIJAS = ("Platillos", "Bebidas", "Postres")

# Solo lo que pinta la tarjeta "Lo último de tu menú" de home_view.py
# (Fase 2.7) — igual que _COLUMNAS arriba, nunca select('*'). Trae
# updated_at además de created_at porque el dueño decidió (2026-08-25)
# agregar esa columna + un trigger (trg_platillos_updated_at, ver
# CLAUDE.md/roadmap) para que la tarjeta detecte ediciones de verdad, no
# solo altas.
_COLUMNAS_RECIENTES = "id, nombre, image_url, created_at, updated_at"

# Solo lo que pinta el selector de platillo del asistente de contenido
# (Fase 7.3, views/contenido_view.py) — igual criterio que _COLUMNAS
# arriba, nunca select('*'). No trae precio/descripcion/categoria porque
# ese paso solo necesita mostrar la foto recortada y el nombre.
_COLUMNAS_CON_RECORTE = "id, nombre, image_url_recortada"


class PlatilloDAO:
    @staticmethod
    def obtener_todos() -> list[dict]:
        """Trae los platillos ordenados como se muestran en el panel (por
        `orden` y, a igualdad, por `id`) — usa el mismo índice
        platillos_orden_idx que ya existe en la tabla.

        Esto es el panel del ADMIN, no el menú público: RLS deja ver tanto
        los visibles como los ocultos mientras haya una sesión de admin
        activa (ver policy platillos_auth_select en el roadmap). Es llamada
        bloqueante (supabase-py es síncrona) — quien la use desde la UI debe
        mandarla a un hilo aparte (asyncio.to_thread) para no congelar la
        ventana, igual que hace sesion_view.py con el login.
        """
        respuesta = (
            client.from_("platillos")
            .select(_COLUMNAS)
            .order("orden")
            .order("id")
            .execute()
        )
        return respuesta.data or []

    @staticmethod
    def _siguiente_orden() -> int:
        """El siguiente valor de `orden` para que un platillo nuevo caiga al
        FINAL de la lista. `orden` tiene default 0 en la tabla, así que si no
        se manda algo explícito todos los platillos nuevos se irían hasta
        arriba — por eso crear() siempre calcula esto primero.

        Solo trae la columna `orden` (nunca select('*')) del último registro
        por orden descendente; si la tabla está vacía, arranca en 1."""
        respuesta = (
            client.from_("platillos")
            .select("orden")
            .order("orden", desc=True)
            .limit(1)
            .execute()
        )
        filas = respuesta.data or []
        if not filas:
            return 1
        return int(filas[0]["orden"] or 0) + 1

    @staticmethod
    def crear(datos: dict) -> dict:
        """Inserta un platillo nuevo. `datos` trae nombre/descripcion/
        categoria/precio ya validados por la vista (categoría dentro de las
        3 fijas, precio numérico no-negativo — los CHECK de la tabla son el
        respaldo final, pero validar antes en el formulario evita que el
        usuario vea un error crudo de Postgres).

        `image_url` (Fase 3, Cloudflare R2) es OPCIONAL en `datos`: si la
        llave viene (el dueño eligió una foto en el diálogo y ya se subió a
        R2 — ver views/components/dialogo_platillo.py), se manda tal cual;
        si no viene, la columna se queda NULL y la fila cae al placeholder
        assets/sin-foto.png, exactamente igual que antes de la Fase 3. Sí manda
        `orden`, calculado aquí, para que el platillo quede al final de la
        lista.

        `image_url_recortada` (Fase 4.3) es igual de OPCIONAL y con el mismo
        criterio: solo se manda si la llave viene en `datos` (el dueño creó
        un Platillo con foto y sí se generó su recorte — ver
        dialogo_platillo.py). Un alta nunca la manda en None a propósito:
        no hay recorte "viejo" que limpiar en una fila que no existía.
        """
        fila = {
            "nombre": datos["nombre"],
            "descripcion": datos.get("descripcion") or None,
            "categoria": datos["categoria"],
            "precio": datos["precio"],
            "orden": PlatilloDAO._siguiente_orden(),
        }
        if "image_url" in datos:
            fila["image_url"] = datos["image_url"]
        if "image_url_recortada" in datos:
            fila["image_url_recortada"] = datos["image_url_recortada"]
        respuesta = client.from_("platillos").insert(fila).execute()
        if not respuesta.data:
            # No debería pasar (un INSERT bloqueado por RLS sí lanza error de
            # Postgres, a diferencia de UPDATE/DELETE) pero se cubre por
            # consistencia con actualizar()/cambiar_visibilidad() y por si
            # algún día cambian las políticas.
            raise EscrituraSinEfecto("El insert no devolvió ninguna fila.")
        return respuesta.data[0]

    @staticmethod
    def actualizar(id_platillo: int, datos: dict) -> dict:
        """Actualiza nombre/descripcion/categoria/precio de un platillo
        existente. No toca `visible` ni `orden` — eso lo maneja
        cambiar_visibilidad() por separado.

        `image_url` (Fase 3) es OPCIONAL igual que en crear(): solo se
        incluye en el UPDATE si el dueño cambió la foto en el diálogo (ya
        subida a R2 antes de llamar aquí — ver dialogo_platillo.py). Si la
        llave no viene en `datos`, la columna no se toca y la fila conserva
        la foto que ya tenía.

        `image_url_recortada` (Fase 4.3) sigue el mismo criterio de
        "solo si la llave viene", pero a diferencia de `image_url` SÍ puede
        venir con valor `None` a propósito: es como dialogo_platillo.py
        limpia la columna cuando el platillo deja de ser categoría
        "Platillos" (o cuando el recorte viejo hay que soltarlo). Por eso
        aquí se revisa con `"image_url_recortada" in datos`, nunca con
        `datos.get(...)`, que trataría None como "no venía"."""
        fila = {
            "nombre": datos["nombre"],
            "descripcion": datos.get("descripcion") or None,
            "categoria": datos["categoria"],
            "precio": datos["precio"],
        }
        if "image_url" in datos:
            fila["image_url"] = datos["image_url"]
        if "image_url_recortada" in datos:
            fila["image_url_recortada"] = datos["image_url_recortada"]
        respuesta = (
            client.from_("platillos").update(fila).eq("id", id_platillo).execute()
        )
        if not respuesta.data:
            # RLS bloqueó el UPDATE en silencio (0 filas coincidieron) — ver
            # la nota de EscrituraSinEfecto al inicio del archivo. Sin este
            # chequeo, esto se vería como un guardado exitoso que en
            # realidad no tocó la base.
            raise EscrituraSinEfecto(
                f"El update de platillos id={id_platillo} no afectó ninguna fila."
            )
        return respuesta.data[0]

    @staticmethod
    def eliminar(id_platillo: int) -> None:
        """Borra la fila de verdad — a diferencia de ocultar (visible=false),
        esto no se puede deshacer. La vista es responsable de pedir
        confirmación ANTES de llamar a este método."""
        respuesta = client.from_("platillos").delete().eq("id", id_platillo).execute()
        if not respuesta.data:
            # Mismo caso que actualizar(): un DELETE que RLS bloquea también
            # "tiene éxito" con data=[] en vez de lanzar un error.
            raise EscrituraSinEfecto(
                f"El delete de platillos id={id_platillo} no afectó ninguna fila."
            )

    @staticmethod
    def cambiar_visibilidad(id_platillo: int, visible: bool) -> dict:
        """Solo cambia la columna `visible` — nunca borra la fila. Al ponerla
        en False, el platillo deja de salir en el menú público (RLS de anon
        exige visible = true) pero se queda intacto en Supabase y en la tabla
        del panel, con el badge en rojo diciendo OCULTO."""
        respuesta = (
            client.from_("platillos")
            .update({"visible": visible})
            .eq("id", id_platillo)
            .execute()
        )
        if not respuesta.data:
            # El bug real que se encontró verificando la Fase 2.6 contra
            # Supabase de verdad (ver la nota grande al inicio del archivo):
            # sin este chequeo, el ojito se pintaba en rojo aunque la fila
            # seguía visible=true en la base.
            raise EscrituraSinEfecto(
                f"El cambio de visibilidad de platillos id={id_platillo} no afectó ninguna fila."
            )
        return respuesta.data[0]

    @staticmethod
    def ocultar_varios(ids: list[int]) -> list[dict]:
        """"Ocultar varios" de Mi menú: pone visible=false a todos los ids en UNA consulta.
        Igual que cambiar_visibilidad(), nunca borra. Si RLS bloquea alguna fila, no viene en
        `data`: se levanta EscrituraSinEfecto aunque las demás sí se hayan ocultado (la vista
        recarga la tabla para mostrar lo que de verdad quedó)."""
        respuesta = (
            client.from_("platillos")
            .update({"visible": False})
            .in_("id", list(ids))
            .execute()
        )
        if len(respuesta.data or []) != len(set(ids)):
            raise EscrituraSinEfecto(
                f"Ocultar platillos {sorted(ids)} afectó {len(respuesta.data or [])} filas."
            )
        return respuesta.data

    @staticmethod
    def obtener_recientes(limite: int = 3) -> list[dict]:
        """Para la tarjeta "Lo último de tu menú" de home_view.py (Fase 2.7):
        los últimos platillos que tuvieron un alta O una edición (incluye
        ocultar/mostrar, que también es un UPDATE), más recientes primero.

        Ordena por `updated_at` en vez de `created_at`: el trigger
        trg_platillos_updated_at (agregado en Fase 2.7 vía la Management
        API, ver CLAUDE.md) deja updated_at IGUAL a created_at en el
        momento del INSERT y la mueve a now() en cada UPDATE posterior — un
        solo ORDER BY ya intercala altas y ediciones sin necesitar un
        GREATEST(created_at, updated_at) en SQL.

        Este método NO decide si una fila es "Nuevo" o "Editado" — regresa
        los dos timestamps tal cual y es home_view.py quien compara
        created_at == updated_at para pintar la etiqueta y el tiempo
        relativo, igual que _formatear_precio()/_texto_contador() en
        menu_view.py hacen su formateo del lado de la vista, no del DAO.
        """
        respuesta = (
            client.from_("platillos")
            .select(_COLUMNAS_RECIENTES)
            .order("updated_at", desc=True)
            .limit(limite)
            .execute()
        )
        return respuesta.data or []

    @staticmethod
    def obtener_estadisticas() -> dict:
        """Para la tarjeta "PRODUCTOS EN VENTA" de home_view.py (Fase 2.7):
        cuántos platillos están EN VENTA y en cuántas de las 3 categorías
        fijas (_CATEGORIAS_FIJAS arriba, mismo CHECK de la tabla) hay al
        menos uno en venta.

        SOLO CUENTA visible = true, a propósito (decisión del dueño,
        2026-08-25). La tarjeta se llama "PRODUCTOS EN VENTA": un platillo
        oculto NO se está vendiendo — no sale en el menú público — así que
        contarlo ahí sería otra forma de mentir. OJO, esto es distinto del
        título de menu_view.py ("N platillos en la mesa"), que sí cuenta
        todo porque esa pantalla es el inventario completo que administra
        el dueño, ocultos incluidos. Son dos preguntas distintas: "qué
        administro" vs "qué estoy vendiendo". No las unifiques.

        El filtro va explícito (.eq("visible", True)) y NO se deja a que
        RLS lo haga: con la sesión del ADMIN, la política
        platillos_auth_select deja ver también los ocultos, así que sin el
        .eq el número saldría inflado justo para quien usa el panel. Con
        anon el resultado es el mismo por partida doble, y está bien.

        Mismo patrón que cargarEstadisticas() de EJEMPLOS/lilshop.html:
        select(..., count='exact', head=True) — PostgREST regresa el total
        en el header Content-Range (queda en `.count`) y ninguna fila en el
        cuerpo (`.data` sale vacío), así que nunca se bajan las filas
        completas solo para contarlas. Son 4 requests HEAD en total (1
        global + 1 por categoría) porque el set de categorías es fijo y
        chico — más barato que traer la columna `categoria` completa nada
        más para sacar un distinct en Python.
        """
        total = (
            client.from_("platillos")
            .select("id", count="exact", head=True)
            .eq("visible", True)
            .execute()
        ).count or 0

        categorias_en_uso = 0
        for categoria in _CATEGORIAS_FIJAS:
            respuesta = (
                client.from_("platillos")
                .select("id", count="exact", head=True)
                .eq("categoria", categoria)
                .eq("visible", True)
                .execute()
            )
            if (respuesta.count or 0) > 0:
                categorias_en_uso += 1

        return {"total": total, "categorias_en_uso": categorias_en_uso}

    @staticmethod
    def contar_platillos_con_recorte() -> int:
        """Para el cupo de 5 de la Fase 4.3 (dialogo_platillo.py, la carta
        de celular del index): cuántos Platillos YA tienen
        image_url_recortada generado, para saber si todavía hay lugar antes
        de gastar tiempo/Cloudflare generando uno más.

        Mismo patrón que obtener_estadisticas(): count="exact", head=True,
        nunca baja las filas completas solo para contarlas. El filtro de
        categoría va explícito (no tiene sentido contar un recorte de un
        platillo que ya no es "Platillos" — aunque en la práctica
        dialogo_platillo.py ya limpia la columna en ese caso, este filtro
        es el respaldo correcto de todos modos)."""
        respuesta = (
            client.from_("platillos")
            .select("id", count="exact", head=True)
            .eq("categoria", "Platillos")
            .not_.is_("image_url_recortada", "null")
            .execute()
        )
        return respuesta.count or 0

    @staticmethod
    def obtener_con_recorte() -> list[dict]:
        """Para el paso 3 del asistente de contenido (Fase 7.3, "Elegir
        platillo"): solo los Platillos que YA tienen image_url_recortada
        generado — un anuncio siempre estampa la foto recortada, nunca la
        original con fondo (ver models/generador_anuncios.py). Mismo
        filtro que contar_platillos_con_recorte(), pero trayendo las filas
        en vez de solo el conteo — hoy son 5 (ids 5, 30, 31, 32, 33, ver
        CLAUDE.md → Fase 7)."""
        respuesta = (
            client.from_("platillos")
            .select(_COLUMNAS_CON_RECORTE)
            .eq("categoria", "Platillos")
            .not_.is_("image_url_recortada", "null")
            .order("orden")
            .order("id")
            .execute()
        )
        return respuesta.data or []

