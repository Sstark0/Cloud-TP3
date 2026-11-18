import db
import pg8000.native

VIOLACION_UNIQUE = "23505"


class RepartidorOcupado(Exception):
    pass


def handler(event, context):
    try:
        db.consultar(
            "INSERT INTO asignacion (pedido_id, repartidor_id, task_token, llegada_s, listo_s)"
            " VALUES (:pedido, :repartidor, :token, :llegada, :listo)"
            " ON CONFLICT (pedido_id, repartidor_id) DO UPDATE"
            " SET task_token = EXCLUDED.task_token,"
            " llegada_s = EXCLUDED.llegada_s, listo_s = EXCLUDED.listo_s"
            " WHERE asignacion.estado = 'PENDIENTE'",
            pedido=event["pedido_id"],
            repartidor=event["repartidor_id"],
            token=event["task_token"],
            llegada=event.get("llegada_s"),
            listo=event.get("listo_s"),
        )
    except pg8000.native.DatabaseError as e:
        if e.args and e.args[0].get("C") == VIOLACION_UNIQUE:
            raise RepartidorOcupado(event["repartidor_id"]) from e
        raise
        