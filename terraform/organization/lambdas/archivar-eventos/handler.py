import json
import logging
import os
from collections import defaultdict

import boto3

import db

log = logging.getLogger()
log.setLevel(logging.INFO)

s3 = boto3.client("s3")
BUCKET = os.environ["BUCKET"]


# Archiva en S3 los cambios de estado de los pedidos que publica el topic
# estado_pedido (llegan por SQS, en lotes). Cada evento se completa con los
# datos del pedido que hacen falta para analizar: comercio, repartidor, total y
# punto de entrega. Quedan en pedidos/fecha=AAAA-MM-DD/ del bucket historico, junto a las
# posiciones, con el mismo lifecycle y consultables desde Athena.
def handler(event, context):
    eventos = []
    for registro in event["Records"]:
        try:
            sobre = json.loads(registro["body"])  # sobre de SNS
            mensaje = json.loads(sobre["Message"])
            eventos.append(
                {
                    "pedido_id": mensaje["pedido_id"],
                    "estado": mensaje["estado"],
                    "cliente_id": mensaje.get("cliente_id"),
                    "ts": sobre["Timestamp"],
                    "mensaje_id": sobre["MessageId"],
                }
            )
        except (ValueError, KeyError, TypeError):
            # Un mensaje roto no puede trabar la cola: se descarta y se registra.
            log.warning("mensaje descartado: %s", registro.get("messageId"))

    datos = _datos_de_pedidos(sorted({e["pedido_id"] for e in eventos}))
    por_fecha = defaultdict(list)
    for e in eventos:
        e.update(datos.get(e["pedido_id"], {}))
        por_fecha[e["ts"][:10]].append(e)

    for fecha, lote in por_fecha.items():
        # El id del primer mensaje hace que un reintento del mismo lote pise el
        # mismo objeto en vez de duplicarlo.
        clave = f"pedidos/fecha={fecha}/{lote[0]['mensaje_id']}.jsonl"
        s3.put_object(Bucket=BUCKET, Key=clave, Body="\n".join(json.dumps(e) for e in lote).encode())

    resumen = {"eventos": len(eventos), "archivos": len(por_fecha)}
    log.info(json.dumps(resumen))
    return resumen


def _datos_de_pedidos(ids):
    if not ids:
        return {}
    filas = db.consultar(
        "SELECT p.id::text AS pedido_id, p.comercio_id, c.nombre AS comercio,"
        " p.repartidor_id, p.total,"
        " ST_Y(p.ubicacion_entrega::geometry) AS entrega_lat,"
        " ST_X(p.ubicacion_entrega::geometry) AS entrega_lng"
        " FROM pedido p JOIN comercio c ON c.id = p.comercio_id"
        " WHERE p.id::text = ANY(CAST(:ids AS text[]))",
        ids=ids,
    )
    return {f.pop("pedido_id"): f for f in filas}
