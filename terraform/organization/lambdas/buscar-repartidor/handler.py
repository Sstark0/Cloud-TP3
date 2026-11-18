import os

import db

MAX_INTENTOS = int(os.environ["MAX_INTENTOS"])
RADIO_METROS = int(os.environ["RADIO_METROS"])
VELOCIDAD_MS = float(os.environ["VELOCIDAD_KMH"]) / 3.6


# Se agotaron las ofertas: el workflow cancela el pedido.
class OfertasAgotadas(Exception):
    pass


# No hay nadie cerca en este momento: el workflow reintenta durante
# asignacion_espera_segundos antes de cancelar.
class SinCandidatos(Exception):
    pass


def handler(event, context):
    pedido_id = event["pedido_id"]

    intentos = db.consultar(
        "SELECT count(*) AS n FROM asignacion WHERE pedido_id = :id", id=pedido_id
    )[0]["n"]
    if intentos >= MAX_INTENTOS:
        raise OfertasAgotadas(f"{intentos} ofertas sin aceptar")

    # Entre los repartidores libres y cerca del comercio se elige por el momento
    # en que el pedido puede salir: max(llegada del repartidor, comida lista).
    # - Si nadie llega antes de que este lista, gana el que llega primero.
    # - Si varios llegan a tiempo, todos retiran a la misma hora: gana el que
    #   llega mas justo (el mas lejano de ellos), asi no espera en la puerta y
    #   los mas cercanos quedan libres para pedidos que ya estan listos.
    # Lo que falta de preparacion se descuenta desde que se creo el pedido, asi
    # una reasignacion tras un rechazo usa el tiempo que realmente queda.
    candidatos = db.consultar(
        "WITH candidato AS ("
        " SELECT r.id AS repartidor_id,"
        " ST_Distance(rp.ubicacion, c.ubicacion) AS distancia_m,"
        " ST_Distance(rp.ubicacion, c.ubicacion) / :velocidad AS llegada_s,"
        " GREATEST(0, c.tiempo_preparacion_min * 60"
        "   - EXTRACT(EPOCH FROM now() - p.creado_en)) AS listo_s"
        " FROM pedido p"
        " JOIN comercio c ON c.id = p.comercio_id"
        " JOIN repartidor r ON r.disponible"
        " JOIN repartidor_posicion rp ON rp.repartidor_id = r.id"
        " WHERE p.id = :pedido"
        " AND rp.actualizado_en > now() - interval '5 minutes'"
        " AND ST_DWithin(rp.ubicacion, c.ubicacion, :radio)"
        " AND NOT EXISTS (SELECT 1 FROM asignacion a"
        "   WHERE a.repartidor_id = r.id AND (a.pedido_id = p.id OR a.estado = 'PENDIENTE'))"
        " AND NOT EXISTS (SELECT 1 FROM pedido o"
        "   WHERE o.repartidor_id = r.id AND o.estado = 'ASIGNADO')"
        ")"
        " SELECT repartidor_id, distancia_m::int AS distancia_m,"
        " llegada_s::int AS llegada_s, listo_s::int AS listo_s"
        " FROM candidato"
        " ORDER BY GREATEST(llegada_s, listo_s), llegada_s DESC"
        " LIMIT 1",
        pedido=pedido_id,
        radio=RADIO_METROS,
        velocidad=VELOCIDAD_MS,
    )
    if not candidatos:
        raise SinCandidatos("no hay repartidores disponibles cerca")
    return candidatos[0]
    