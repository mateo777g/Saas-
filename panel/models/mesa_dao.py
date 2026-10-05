"""
models/mesa_dao.py
Acceso a la tabla public.mesas (Fase 5.1) — el catálogo fijo de mesas del
negocio, que el dueño administra desde el panel (views/mesas_view.py) y que
mesas.html usa para pintar la lista de mesas con su estado (disponible/
ocupada) en vez del campo de texto libre que tenía antes.

Mismo patrón que models/platillo_dao.py: no se atrapan excepciones aquí
(ni de red ni de la API), y actualizar()/eliminar() revisan que `data` no
venga vacío antes de dar por buena la escritura — ver el docstring largo de
platillo_dao.py para el porqué completo (UPDATE/DELETE bloqueado por RLS
"tiene éxito" con data=[] en vez de lanzar un error).
"""
from models.supabase_client import client


class EscrituraSinEfecto(Exception):
    """Ver la clase homónima en platillo_dao.py — mismo significado aquí."""


_COLUMNAS = "id, nombre, orden"


class MesaDAO:
    @staticmethod
    def obtener_todos() -> list[dict]:
        """Todas las mesas, en el orden en que se deben mostrar tanto en el
        panel como en mesas.html."""
        respuesta = (
            client.from_("mesas").select(_COLUMNAS).order("orden").order("id").execute()
        )
        return respuesta.data or []

    @staticmethod
    def _siguiente_orden() -> int:
        """Mismo mecanismo que PlatilloDAO._siguiente_orden(): una mesa
        nueva siempre cae al final de la lista."""
        respuesta = (
            client.from_("mesas").select("orden").order("orden", desc=True).limit(1).execute()
        )
        filas = respuesta.data or []
        if not filas:
            return 1
        return int(filas[0]["orden"] or 0) + 1

    @staticmethod
    def crear(nombre: str) -> dict:
        fila = {"nombre": nombre, "orden": MesaDAO._siguiente_orden()}
        respuesta = client.from_("mesas").insert(fila).execute()
        if not respuesta.data:
            raise EscrituraSinEfecto("El insert de mesas no devolvió ninguna fila.")
        return respuesta.data[0]

    @staticmethod
    def actualizar(id_mesa: int, nombre: str) -> dict:
        """Solo renombra — no toca `orden` (no hay todavía una forma de
        reordenar mesas a mano, igual que platillos antes de tener un drag
        and drop; se puede agregar después si hace falta)."""
        respuesta = (
            client.from_("mesas").update({"nombre": nombre}).eq("id", id_mesa).execute()
        )
        if not respuesta.data:
            raise EscrituraSinEfecto(
                f"El update de mesas id={id_mesa} no afectó ninguna fila."
            )
        return respuesta.data[0]

    @staticmethod
    def eliminar(id_mesa: int) -> None:
        """Borra la mesa del catálogo. OJO: esto NO toca ventas.mesa — esa
        columna es un snapshot de texto (ver CLAUDE.md, Fase 5), así que una
        venta ya cerrada con esa mesa se queda intacta con su nombre tal
        cual quedó escrito, aunque la mesa se borre de este catálogo
        después. La vista es responsable de confirmar antes de llamar
        aquí, igual que con PlatilloDAO.eliminar()."""
        respuesta = client.from_("mesas").delete().eq("id", id_mesa).execute()
        if not respuesta.data:
            raise EscrituraSinEfecto(
                f"El delete de mesas id={id_mesa} no afectó ninguna fila."
            )
