import uuid

import api
import db


def handler(event, context):
    usuario = api.claims(event)["sub"]
    ruta = event["routeKey"]

    if ruta == "GET /pedidos":
        if "cliente" not in api.grupos(event):
            return api.respuesta(403, {"error": "solo para clientes"})
        pedidos = db.consultar(
            "SELECT p.id, c.nombre AS comercio, p.estado, p.total, p.creado_en"
            " FROM pedido p JOIN comercio c ON c.id = p.comercio_id"
            " WHERE p.cliente_id = :cliente ORDER BY p.creado_en DESC LIMIT 50",
            cliente=usuario,
        )
        return api.respuesta(200, pedidos)

    try:
        pedido_id = str(uuid.UUID(event["pathParameters"]["id"]))
    except ValueError:
        return api.respuesta(400, {"error": "id invalido"})

    if ruta == "GET /pedidos/{id}":
        pedido = db.consultar(
            "SELECT p.id, c.nombre AS comercio, p.estado, p.total,"
            " p.direccion_entrega, p.repartidor_id, p.creado_en"
            " FROM pedido p JOIN comercio c ON c.id = p.comercio_id"
            " WHERE p.id = :id AND (p.cliente_id = :usuario OR p.repartidor_id = :usuario)",
            id=pedido_id,
            usuario=usuario,
        )
        if not pedido:
            return api.respuesta(404, {"error": "pedido no encontrado"})

        detalle = pedido[0]
        detalle["items"] = db.consultar(
            "SELECT pr.nombre, pi.cantidad, pi.precio_unitario"
            " FROM pedido_item pi JOIN producto pr ON pr.id = pi.producto_id"
            " WHERE pi.pedido_id = :id ORDER BY pr.nombre",
            id=pedido_id,
        )
        detalle["eventos"] = db.consultar(
            "SELECT estado, creado_en FROM pedido_evento"
            " WHERE pedido_id = :id ORDER BY creado_en",
            id=pedido_id,
        )
        return api.respuesta(200, detalle)

    if ruta == "POST /pedidos/{id}/calificacion":
        if "cliente" not in api.grupos(event):
            return api.respuesta(403, {"error": "solo para clientes"})
        try:
            datos = api.cuerpo_json(event)
            puntaje = datos["puntaje"]
            comentario = datos.get("comentario")
        except (ValueError, KeyError, TypeError):
            return api.respuesta(400, {"error": "falta 'puntaje'"})
        if type(puntaje) is not int or not 1 <= puntaje <= 5:
            return api.respuesta(400, {"error": "'puntaje' tiene que ser un entero de 1 a 5"})
        if comentario is not None and (not isinstance(comentario, str) or len(comentario) > 500):
            return api.respuesta(400, {"error": "'comentario' tiene que ser texto de hasta 500 caracteres"})

        guardada = db.consultar(
            "INSERT INTO calificacion (pedido_id, puntaje, comentario)"
            " SELECT id, :puntaje, :comentario FROM pedido"
            " WHERE id = :id AND cliente_id = :cliente AND estado = 'ENTREGADO'"
            " ON CONFLICT (pedido_id) DO NOTHING RETURNING pedido_id",
            puntaje=puntaje,
            comentario=comentario,
            id=pedido_id,
            cliente=usuario,
        )
        if not guardada:
            return api.respuesta(
                409, {"error": "el pedido no es tuyo, no fue entregado o ya esta calificado"}
            )
        return api.respuesta(201, {"pedido_id": pedido_id, "puntaje": puntaje})

    return api.respuesta(404, {"error": "ruta no encontrada"})
    