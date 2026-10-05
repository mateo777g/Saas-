"""
models/estado_mesas.py
Qué mesa del catálogo está ocupada, cuánto lleva su cuenta y desde cuándo: lo que pinta la tabla
de la vista Mesas (ESTADO / ABIERTA / CUENTA).

Mismo criterio que "Mesas ahora" de Inicio (models/resumen_inicio.py) para no dar dos respuestas
distintas: ventas.mesa es texto libre, así que se empareja con el catálogo por nombre sin
importar mayúsculas ni espacios (_normalizar_mesa del agente), y una mesa con dos cuentas
abiertas suma las dos.

Sin consultas propias: recibe lo que ya leyeron MesaDAO.obtener_todos() y
VentaDAO.obtener_abiertas() (la vista hace las dos, una tras otra).
"""
from models.ia_controller import _fecha_local, _normalizar_mesa


def cuentas_por_mesa(abiertas: list[dict]) -> dict:
    """clave normalizada de la mesa -> {"total": suma de sus cuentas abiertas, "desde": la hora
    local en que se abrió la más vieja (o None si la fecha viene rota)}."""
    cuentas: dict[str, dict] = {}
    for venta in abiertas:
        clave = _normalizar_mesa(venta.get("mesa"))
        cuenta = cuentas.setdefault(clave, {"total": 0.0, "desde": None})
        cuenta["total"] += float(venta.get("total") or 0)
        abierta = _fecha_local(venta.get("created_at"))
        if abierta and (cuenta["desde"] is None or abierta < cuenta["desde"]):
            cuenta["desde"] = abierta
    return cuentas


def cuenta_de(mesa: dict, cuentas: dict) -> dict | None:
    # La cuenta abierta de una mesa del catálogo, o None si está disponible.
    return cuentas.get(_normalizar_mesa(mesa.get("nombre")))
