import base64
import json

import db


def handler(event, context):
    ultimas = {}
    for registro in event["Records"]:
        posicion = json.loads(base64.b64decode(registro["kinesis"]["data"]))
        actual = ultimas.get(posicion["repartidor_id"])
        if actual is None or posicion["ts"] > actual["ts"]:
            ultimas[posicion["repartidor_id"]] = posicion

    with db.transaccion():
        for p in ultimas.values():
            db.consultar(
                "INSERT INTO repartidor_posicion (repartidor_id, ubicacion, actualizado_en)"
                " SELECT id, ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography,"
                " CAST(:ts AS timestamptz) FROM repartidor WHERE id = :id"
                " ON CONFLICT (repartidor_id) DO UPDATE"
                " SET ubicacion = EXCLUDED.ubicacion, actualizado_en = EXCLUDED.actualizado_en"
                " WHERE repartidor_posicion.actualizado_en < EXCLUDED.actualizado_en",
                id=p["repartidor_id"],
                lat=p["lat"],
                lng=p["lng"],
                ts=p["ts"],
            )