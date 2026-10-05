"""
models/configuracion_negocio_dao.py
Acceso a la tabla public.configuracion_negocio — el "interruptor" de licencia
del software.

QUÉ ES: una tabla de UN SOLO renglón, exclusiva de ESTE proyecto (Taku Monky).
No es un catálogo de clientes: cada negocio que rente esta plantilla después
tendría su propio proyecto de Supabase con su propia tablita igual a esta. El
renglón guarda el nombre del negocio, las fechas de inicio/fin de la
suscripción (SOLO de referencia — nada las revisa automáticamente, no expira
solo) y el booleano `activo`, que es el interruptor de verdad.

QUIÉN LO USA: views/sesion_view.py, y solo por licencia_activa() — el
CANDADO. Se llama justo después de un login correcto: si `activo` es false (o
si no se pudo averiguar), el panel cierra la sesión recién abierta y no deja
entrar. mesas.js hace lo mismo por su lado, con su propia consulta en JS.

Su otro método, actualizar(), ya NO le sirve a nadie: desde el 2026-09-05 el
dueño solo tiene SELECT sobre esta tabla (le quitaron INSERT/UPDATE/DELETE
justo para que no pudiera reactivarse la licencia él mismo). Quien sí puede
escribir es panel_licencias/licencia_dao.py, que es una copia instanciable de
este DAO —el panel del desarrollador maneja N proyectos a la vez y este usa el
`client` único compartido—. Se deja aquí de todos modos por simetría con el
resto de los DAO, no porque tenga uso.

Mismo patrón que models/mesa_dao.py y models/platillo_dao.py: no se atrapan
excepciones aquí (ni de red ni de la API), y actualizar() revisa que `data` no
venga vacío antes de dar por buena la escritura — ver el docstring largo de
platillo_dao.py para el porqué completo (un UPDATE bloqueado por RLS NO lanza
error: "tiene éxito" devolviendo data=[]).
"""
from models.supabase_client import client


class EscrituraSinEfecto(Exception):
    """Ver la clase homónima en platillo_dao.py — mismo significado aquí."""


_COLUMNAS = "id, nombre, fecha_inicio, fecha_fin, activo"

# Los únicos campos que actualizar() acepta. id/created_at/updated_at quedan
# fuera a propósito: los dos primeros no se tocan nunca y updated_at lo pone
# el trigger trg_configuracion_negocio_updated_at, no el cliente.
_CAMPOS_EDITABLES = ("nombre", "fecha_inicio", "fecha_fin", "activo")


class ConfiguracionNegocioDAO:
    @staticmethod
    def obtener() -> dict:
        """El único renglón de la tabla.

        Siempre debería haber exactamente uno (se insertó junto con la tabla).
        Si no hay ninguno se levanta un error en vez de devolver None: que la
        tabla esté vacía no es un caso normal que la UI deba dibujar bonito,
        es una señal de que algo se borró a mano.
        """
        respuesta = (
            client.from_("configuracion_negocio")
            .select(_COLUMNAS)
            .order("id")
            .limit(1)
            .execute()
        )
        filas = respuesta.data or []
        if not filas:
            raise EscrituraSinEfecto(
                "configuracion_negocio no devolvió ninguna fila — o la tabla "
                "está vacía, o esta sesión no tiene permiso de leerla (RLS)."
            )
        return filas[0]

    @staticmethod
    def licencia_activa() -> bool:
        """True si el software tiene permitido arrancar. Es EL CANDADO.

        Se llama desde views/sesion_view.py justo después de un login
        correcto, no antes: leer esta tabla requiere sesión (anon no tiene
        ninguna política aquí), así que el orden obligado es autenticar
        primero y preguntar por la licencia después.

        NO atrapa errores a propósito — si no se pudo averiguar, quien llama
        tiene que tratarlo como "no se puede entrar", nunca como "sí".
        Fallar hacia el lado abierto convertiría el candado en un adorno:
        bastaría con tumbar esta consulta para saltárselo. Y no cuesta nada
        ser estricto, porque si Supabase no responde el panel no sirve de
        todos modos (el menú, las ventas y las mesas viven ahí).
        """
        return bool(ConfiguracionNegocioDAO.obtener().get("activo"))

    @staticmethod
    def actualizar(datos: dict) -> dict:
        """Actualiza el renglón único con SOLO los campos que vengan en
        `datos` (nombre / fecha_inicio / fecha_fin / activo). Un campo que no
        venga en el dict no se toca — mismo criterio que el image_url opcional
        de PlatilloDAO.actualizar().

        Las fechas se mandan como string 'YYYY-MM-DD' o None; la columna es
        `date`, así que Postgres las castea sola.
        """
        cambios = {k: v for k, v in datos.items() if k in _CAMPOS_EDITABLES}
        if not cambios:
            raise ValueError(
                "actualizar() no recibió ningún campo editable "
                f"(esperaba alguno de {_CAMPOS_EDITABLES})."
            )

        id_fila = ConfiguracionNegocioDAO.obtener()["id"]
        respuesta = (
            client.from_("configuracion_negocio")
            .update(cambios)
            .eq("id", id_fila)
            .execute()
        )
        if not respuesta.data:
            raise EscrituraSinEfecto(
                f"El update de configuracion_negocio id={id_fila} no afectó "
                "ninguna fila."
            )
        return respuesta.data[0]
