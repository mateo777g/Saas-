"""
models/datos_negocio_dao.py
Acceso a la tabla public.datos_negocio (01/10): los datos generales del negocio que la IA pone
en los anuncios de Crear contenido (nombre, teléfono, página web, dirección), para que el dueño
no los escriba cada vez. Se editan en la ventana "Datos del negocio"
(views/components/dialogo_negocio.py).

Es UNA sola fila (creada con el DDL, nombre "Taku Monky"). RLS: el UID del dueño puede SELECT y
UPDATE, nada más (ni insert ni delete); cero políticas anon. NO es configuracion_negocio: esa es
el candado de la licencia y el dueño solo la lee.

Mismo patrón que los demás DAOs: no se atrapan excepciones aquí, y guardar() revisa que `data`
no venga vacío (un UPDATE bloqueado por RLS "tiene éxito" con data=[]; ver platillo_dao.py).
"""
from models.supabase_client import client


class EscrituraSinEfecto(Exception):
    """Ver la clase homónima en platillo_dao.py — mismo significado aquí."""


_COLUMNAS = "id, nombre, telefono, pagina_web, direccion"
_CAMPOS = ("nombre", "telefono", "pagina_web", "direccion")


class DatosNegocioDAO:
    @staticmethod
    def obtener() -> dict:
        """La fila del negocio, con los campos vacíos como "" (nunca None). Si la fila no se
        puede leer (no existe o RLS la esconde) lanza LookupError: sin `id` no hay qué guardar."""
        respuesta = client.from_("datos_negocio").select(_COLUMNAS).order("id").limit(1).execute()
        filas = respuesta.data or []
        if not filas:
            raise LookupError("La tabla datos_negocio no devolvió ninguna fila.")
        fila = filas[0]
        return {"id": fila["id"], **{c: (fila.get(c) or "").strip() for c in _CAMPOS}}

    @staticmethod
    def guardar(id_fila: int, nombre: str, telefono: str, pagina_web: str,
                direccion: str) -> dict:
        datos = {"nombre": nombre.strip(), "telefono": telefono.strip(),
                 "pagina_web": pagina_web.strip(), "direccion": direccion.strip()}
        respuesta = (
            client.from_("datos_negocio").update(datos).eq("id", id_fila).execute()
        )
        if not respuesta.data:
            raise EscrituraSinEfecto(
                f"El update de datos_negocio id={id_fila} no afectó ninguna fila."
            )
        return {"id": id_fila, **datos}
