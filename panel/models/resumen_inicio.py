"""
models/resumen_inicio.py
Los números de Inicio que salen de las ventas: lo vendido hoy, las mesas abiertas ahora y lo
más vendido por periodo. Todo sale de las tablas reales (ventas, venta_items, mesas); nada se
inventa (regla del diseño nuevo, planes/plan panel.txt).

Las reglas de conteo son las del agente de IA y se toman de models/ia_controller.py en vez de
copiarlas, para que Inicio y el agente nunca den dos cifras distintas para lo mismo:
- solo cuentan las ventas CERRADAS; las abiertas son "por cobrar",
- el día del negocio va de las 6:00 a las 6:00 (_dia_de_negocio),
- las mesas se unifican sin importar mayúsculas (gana el nombre del catálogo),
- los productos se agrupan por platillo_id (hay nombres que chocan).

Bloqueante (supabase-py es síncrono): la vista lo llama con asyncio.to_thread. Igual que los
DAOs, no atrapa excepciones.
"""
import datetime
import os

from models.generador_anuncios import RUTA_BIBLIOTECA
from models.ia_controller import (_agrupar_por_producto, _canonizar_mesas, _dia_de_negocio,
                                  _fecha_local, _normalizar_mesa)
from models.mesa_dao import MesaDAO
from models.venta_dao import VentaDAO

# Cuántos productos lista "Lo más vendido".
TOPE_PRODUCTOS = 5

_EXTENSIONES_ANUNCIO = (".png", ".jpg", ".jpeg", ".webp")


def _mas_vendidos(ventas: list[dict]) -> list[dict]:
    """[{nombre, unidades, importe}] de mayor a menor por piezas vendidas (a igualdad, por
    dinero). La tarjeta cuenta piezas: es lo que el dueño ve salir de la cocina."""
    productos = [
        {"nombre": nombre, "unidades": unidades, "importe": importe}
        for nombre, _, unidades, importe in _agrupar_por_producto(ventas)
        if unidades > 0
    ]
    productos.sort(key=lambda p: (p["unidades"], p["importe"]), reverse=True)
    return productos[:TOPE_PRODUCTOS]


def leer_ventas() -> dict:
    """Lo de las ventas y las mesas, ya sumado:
    - vendido_hoy / ventas_hoy: las cerradas del día de negocio de hoy.
    - por_cobrar / abiertas: las cuentas abiertas ahora mismo.
    - mesas: [{nombre, ocupada, total}] del catálogo, más las mesas con cuenta abierta que ya
      no estén en el catálogo (ventas.mesa es texto libre, no llave foránea).
    - mas_vendido: {"hoy", "semana", "mes"} -> _mas_vendidos() de ese periodo.
    """
    ventas = VentaDAO.obtener_ventas_con_items()
    catalogo = MesaDAO.obtener_todos()
    nombres = _canonizar_mesas(ventas, catalogo)

    cerradas = [v for v in ventas if (v.get("estado") or "").lower() == "cerrada"]
    abiertas = [v for v in ventas if (v.get("estado") or "").lower() == "abierta"]

    hoy = _dia_de_negocio(datetime.datetime.now().astimezone())
    lunes = hoy - datetime.timedelta(days=hoy.weekday())
    primero_del_mes = hoy.replace(day=1)

    def desde(dia_inicial):
        seleccion = []
        for v in cerradas:
            dia = _dia_de_negocio(_fecha_local(v.get("created_at")))
            if dia and dia_inicial <= dia <= hoy:
                seleccion.append(v)
        return seleccion

    de_hoy = desde(hoy)

    # Lo abierto, por mesa (una mesa puede tener más de una cuenta abierta).
    abierto_por_mesa: dict[str, float] = {}
    for v in abiertas:
        clave = _normalizar_mesa(v.get("mesa"))
        abierto_por_mesa[clave] = abierto_por_mesa.get(clave, 0.0) + float(v.get("total") or 0)

    mesas = []
    vistas = set()
    for mesa in catalogo:
        clave = _normalizar_mesa(mesa.get("nombre"))
        vistas.add(clave)
        mesas.append({"nombre": (mesa.get("nombre") or "").strip(),
                      "ocupada": clave in abierto_por_mesa,
                      "total": abierto_por_mesa.get(clave, 0.0)})
    for clave, total in abierto_por_mesa.items():
        if clave not in vistas:
            mesas.append({"nombre": nombres.get(clave, clave), "ocupada": True, "total": total})

    return {
        "vendido_hoy": sum(float(v.get("total") or 0) for v in de_hoy),
        "ventas_hoy": len(de_hoy),
        "abiertas": len(abiertas),
        "por_cobrar": sum(abierto_por_mesa.values()),
        "mesas": mesas,
        "mas_vendido": {
            "hoy": _mas_vendidos(de_hoy),
            "semana": _mas_vendidos(desde(lunes)),
            "mes": _mas_vendidos(desde(primero_del_mes)),
        },
    }


def contar_anuncios_del_mes() -> int:
    """Cuántos anuncios generó este mes el asistente de contenido: los archivos de la
    biblioteca (panel/biblioteca/) modificados en el mes en curso. Carpeta ausente = 0 (se
    crea con el primer anuncio, ver generador_anuncios.py)."""
    if not os.path.isdir(RUTA_BIBLIOTECA):
        return 0
    hoy = datetime.date.today()
    cuenta = 0
    for nombre in os.listdir(RUTA_BIBLIOTECA):
        if not nombre.lower().endswith(_EXTENSIONES_ANUNCIO):
            continue
        try:
            fecha = datetime.date.fromtimestamp(os.path.getmtime(f"{RUTA_BIBLIOTECA}/{nombre}"))
        except OSError:
            continue    # se borró entre el listdir y aquí
        if fecha.year == hoy.year and fecha.month == hoy.month:
            cuenta += 1
    return cuenta
