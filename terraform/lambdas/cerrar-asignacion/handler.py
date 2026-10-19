import db

RESULTADOS = {"ACEPTADA", "RECHAZADA", "VENCIDA", "CANCELADO"}


def handler(event, context):
    pedido_id = event["pedido_id"]
    resultado = event["resultado"]
    if resultado not in RESULTADOS:
        raise ValueError(f"resultado invalido: {resultado}")

    with db.transaccion():
        if resultado == "CANCELADO":
            _cambiar_estado(pedido_id, "CANCELADO")
            return {"estado": "CANCELADO"}

        repartidor_id = event["repartidor_id"]
        if resultado == "ACEPTADA" and event.get("respondio") != repartidor_id:
            raise ValueError("acepto un repartidor distinto al ofrecido")
        db.consultar(
            "UPDATE asignacion SET estado = :resultado, respondido_en = now()"
            " WHERE pedido_id = :pedido AND repartidor_id = :repartidor"
            " AND estado = 'PENDIENTE'",
            resultado=resultado,
            pedido=pedido_id,
            repartidor=repartidor_id,
        )

        if resultado == "ACEPTADA":
            db.consultar(
                "UPDATE pedido SET repartidor_id = :repartidor WHERE id = :pedido",
                repartidor=repartidor_id,
                pedido=pedido_id,
            )
            _cambiar_estado(pedido_id, "ASIGNADO")
            return {"estado": "ASIGNADO", "repartidor_id": repartidor_id}

    return {"estado": resultado}


def _cambiar_estado(pedido_id, estado):
    cambiado = db.consultar(
        "UPDATE pedido SET estado = :estado WHERE id = :id AND estado = 'CREADO' RETURNING id",
        estado=estado,
        id=pedido_id,
    )
    if cambiado:
        db.consultar(
            "INSERT INTO pedido_evento (pedido_id, estado) VALUES (:id, :estado)",
            id=pedido_id,
            estado=estado,
        )
