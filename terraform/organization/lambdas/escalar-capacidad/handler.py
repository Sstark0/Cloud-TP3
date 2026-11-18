import json
import logging
import math
import os
import re
import time

import boto3

log = logging.getLogger()
log.setLevel(logging.INFO)

kinesis = boto3.client("kinesis")
sns = boto3.client("sns")
cloudwatch = boto3.client("cloudwatch")

STREAM = os.environ["STREAM_NAME"]
MINIMO = int(os.environ["SHARDS_MINIMO"])
PICO = int(os.environ["SHARDS_PICO"])
MAXIMO = int(os.environ["SHARDS_MAXIMO"])
TOPIC_ALERTAS = os.environ["TOPIC_ALERTAS"]
NAMESPACE = os.environ["NAMESPACE_METRICAS"]
ALARMA = os.environ["ALARMA"]
ENFRIAMIENTO = int(os.environ.get("ENFRIAMIENTO_SEGUNDOS", "300"))

ACCIONES = {"pico", "subir", "base"}

# Marca que la Lambda deja en el motivo de la alarma al rearmarla, con el
# momento del ultimo escalado. La alarma la devuelve en previousState.
MARCA = re.compile(r"escalado@(\d+)")


# El stream esta cambiando de tamano: se lanza para que el origen reintente
# (Scheduler con su politica de reintentos, la alarma con los reintentos de la
# invocacion asincrona).
class StreamOcupado(Exception):
    pass


def handler(event, context):
    accion, origen = _leer_evento(event)
    if accion is None:
        log.info(json.dumps({"ignorado": event}))
        return {"accion": None}

    # Enfriamiento: la ventana de la alarma todavia incluye los rechazos de
    # antes del ultimo escalado. Hasta que pase, solo se rearma la alarma (con
    # la marca original) para que siga evaluando sin volver a duplicar.
    if origen == "alarma":
        ultimo = _ultimo_escalado(event)
        if ultimo and time.time() - ultimo < ENFRIAMIENTO:
            _rearmar_alarma(ultimo, "en enfriamiento")
            resultado = {"accion": accion, "origen": origen, "enfriamiento": True}
            log.info(json.dumps(resultado))
            return resultado

    resumen = kinesis.describe_stream_summary(StreamName=STREAM)["StreamDescriptionSummary"]
    estado = resumen["StreamStatus"]
    actual = resumen["OpenShardCount"]
    if estado != "ACTIVE":
        raise StreamOcupado(f"stream en {estado}")

    objetivo = _objetivo(accion, actual)
    resultado = {"accion": accion, "origen": origen, "antes": actual, "despues": objetivo}

    if objetivo != actual:
        try:
            kinesis.update_shard_count(
                StreamName=STREAM,
                TargetShardCount=objetivo,
                ScalingType="UNIFORM_SCALING",
            )
        except kinesis.exceptions.LimitExceededException as e:
            # Kinesis permite 10 cambios por stream cada 24 h. Si se agotaron,
            # se avisa y se sigue: reintentar no sirve hasta que se libere cupo.
            resultado.update(despues=actual, error="cupo de cambios agotado")
            _avisar(f"No se pudo escalar {STREAM} de {actual} a {objetivo} shards: {e}")
        except kinesis.exceptions.ResourceInUseException as e:
            raise StreamOcupado(str(e)) from e
        else:
            _avisar(f"{STREAM}: {actual} -> {objetivo} shards ({accion}, {origen}).")
            if origen == "alarma":
                _rearmar_alarma(int(time.time()), f"escalado a {objetivo} shards")

    _metrica(resultado["despues"], cambio=resultado["despues"] - actual)
    log.info(json.dumps(resultado))
    return resultado


def _leer_evento(event):
    # Alarma de CloudWatch con accion Lambda: solo interesa la entrada en ALARM.
    if event.get("source") == "aws.cloudwatch":
        estado = event.get("alarmData", {}).get("state", {}).get("value")
        return ("subir" if estado == "ALARM" else None), "alarma"
    accion = event.get("accion")
    if accion not in ACCIONES:
        raise ValueError(f"accion invalida: {accion!r} (se esperaba {sorted(ACCIONES)})")
    return accion, event.get("origen", "manual")


def _objetivo(accion, actual):
    if accion == "pico":
        deseado = max(actual, PICO)
    elif accion == "subir":
        deseado = actual * 2
    else:
        deseado = MINIMO
    # UpdateShardCount solo puede duplicar o dividir a la mitad en cada llamada:
    # si hace falta mas, el resto lo hacen las ejecuciones siguientes.
    paso = min(max(deseado, math.ceil(actual / 2)), actual * 2)
    return min(max(paso, MINIMO), MAXIMO)


def _ultimo_escalado(event):
    motivo = event.get("alarmData", {}).get("previousState", {}).get("reason", "")
    m = MARCA.search(motivo)
    return int(m.group(1)) if m else None


def _rearmar_alarma(momento, detalle):
    # Una alarma solo actua al cambiar de estado: si con los shards nuevos el
    # pico sigue, se quedaria en ALARM sin volver a invocar. Se la pasa a OK y
    # en la proxima evaluacion vuelve a ALARM (y a duplicar) si sigue el rechazo.
    try:
        cloudwatch.set_alarm_state(
            AlarmName=ALARMA,
            StateValue="OK",
            StateReason=f"escalar-capacidad: {detalle}; escalado@{momento}",
        )
    except Exception:
        log.exception("no se pudo rearmar la alarma")


def _avisar(mensaje):
    try:
        sns.publish(TopicArn=TOPIC_ALERTAS, Subject=f"Escalado de {STREAM}", Message=mensaje)
    except Exception:
        log.exception("no se pudo publicar la alerta")


def _metrica(shards, cambio):
    # Embedded Metric Format: CloudWatch convierte esta linea de log en metricas
    # sin llamar a PutMetricData.
    print(json.dumps({
        "_aws": {
            "Timestamp": int(time.time() * 1000),
            "CloudWatchMetrics": [{
                "Namespace": NAMESPACE,
                "Dimensions": [["StreamName"]],
                "Metrics": [{"Name": "Shards", "Unit": "Count"}, {"Name": "CambioShards", "Unit": "Count"}],
            }],
        },
        "StreamName": STREAM,
        "Shards": shards,
        "CambioShards": cambio,
    }))
