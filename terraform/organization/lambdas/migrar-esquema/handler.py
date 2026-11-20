import os
import time
from pathlib import Path

import db

AQUI = Path(__file__).parent
SCHEMA = (AQUI / "schema.sql").read_text()
SEED = (AQUI / "seed.sql").read_text()


def handler(event, context):
    conn = _conectar(context)
    conn.run(SCHEMA)
    if os.environ.get("CARGAR_DATOS_DEMO") == "true":
        conn.run(SEED)
    version = conn.run("SELECT postgis_version()")[0][0]
    comercios = conn.run("SELECT count(*) FROM comercio")[0][0]
    return {"postgis": version, "comercios": comercios}


# Terraform invoca la migracion apenas se registra la instancia en el proxy,
# pero el target tarda unos minutos en pasar a AVAILABLE: hasta entonces el
# proxy rechaza las conexiones. Se reintenta mientras quede tiempo.
def _conectar(context):
    while True:
        try:
            return db.conexion()
        except Exception as e:
            if context.get_remaining_time_in_millis() < 30_000:
                raise
            print(f"proxy todavia no disponible ({type(e).__name__}: {e}); reintentando")
            db._descartar()
            time.sleep(10)
