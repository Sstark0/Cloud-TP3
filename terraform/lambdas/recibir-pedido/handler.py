import base64
import json
import os
import uuid

import boto3

sqs = boto3.client("sqs")
QUEUE_URL = os.environ["QUEUE_URL"]


def handler(event, context):
    claims = event["requestContext"]["authorizer"]["jwt"]["claims"]
    if "cliente" not in _grupos(claims):
        return _respuesta(403, {"error": "solo los clientes pueden crear pedidos"})

    try:
        pedido = _validar(json.loads(_cuerpo(event)))
    except (ValueError, KeyError, TypeError) as e:
        return _respuesta(400, {"error": f"pedido invalido: {e}"})

    pedido["cliente_id"] = claims["sub"]

    sqs.send_message(
        QueueUrl=QUEUE_URL,
        MessageBody=json.dumps(pedido),
        MessageGroupId=str(pedido["comercio_id"]),
        MessageDeduplicationId=pedido["pedido_id"],
    )
    return _respuesta(202, {"pedido_id": pedido["pedido_id"]})


def _grupos(claims):
    return set(claims.get("cognito:groups", "").strip("[]").split())


def _cuerpo(event):
    cuerpo = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        cuerpo = base64.b64decode(cuerpo).decode()
    return cuerpo


def _validar(datos):
    items = [
        {"producto_id": int(i["producto_id"]), "cantidad": int(i["cantidad"])}
        for i in datos["items"]
    ]
    if not items or any(i["cantidad"] <= 0 for i in items):
        raise ValueError("items vacio o con cantidad invalida")

    entrega = datos["entrega"]
    lat, lng = float(entrega["lat"]), float(entrega["lng"])
    if not (-90 <= lat <= 90 and -180 <= lng <= 180):
        raise ValueError("coordenadas fuera de rango")

    return {
        "pedido_id": str(uuid.UUID(datos["pedido_id"])),
        "comercio_id": int(datos["comercio_id"]),
        "items": items,
        "entrega": {"direccion": str(entrega["direccion"]), "lat": lat, "lng": lng},
    }


def _respuesta(estado, cuerpo):
    return {
        "statusCode": estado,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(cuerpo),
    }
    