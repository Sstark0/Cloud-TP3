import api
import db


def handler(event, context):
    if "repartidor" not in api.grupos(event):
        return api.respuesta(403, {"error": "solo para repartidores"})

    repartidor_id = api.claims(event)["sub"]
    ruta = event["routeKey"]

    if ruta == "PUT /repartidores/me/estado":
        try:
            disponible = api.cuerpo_json(event)["disponible"]
        except (ValueError, KeyError, TypeError):
            return api.respuesta(400, {"error": "falta 'disponible'"})
        if not isinstance(disponible, bool):
            return api.respuesta(400, {"error": "'disponible' tiene que ser true o false"})

        db.consultar(
            "INSERT INTO repartidor (id, disponible) VALUES (:id, :disponible)"
            " ON CONFLICT (id) DO UPDATE SET disponible = EXCLUDED.disponible",
            id=repartidor_id,
            disponible=disponible,
        )
        return api.respuesta(200, {"disponible": disponible})

    return api.respuesta(404, {"error": "ruta no encontrada"})
    