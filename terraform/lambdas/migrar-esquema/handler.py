from pathlib import Path

import db

SCHEMA = (Path(__file__).parent / "schema.sql").read_text()


def handler(event, context):
    conn = db.conexion()
    conn.run(SCHEMA)
    version = conn.run("SELECT postgis_version()")[0][0]
    return {"postgis": version}
