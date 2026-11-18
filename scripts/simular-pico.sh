#!/usr/bin/env bash
# Simula un pico de posiciones para mostrar el escalado reactivo: escribe en el
# stream mas de lo que admite un shard (1000 registros/s) durante unos minutos.
# Kinesis rechaza el excedente (WriteProvisionedThroughputExceeded), la alarma
# entra en ALARM y la Lambda escalar-capacidad duplica los shards.
#
# Los registros usan repartidores "simulacion-N" que no existen en la base:
# actualizar-posicion no los guarda, y archivar-posiciones los deja en el
# historico de S3 como cualquier otra posicion.
#
# Uso (desde la raiz del repo, con las credenciales del Lab ya exportadas):
#   ./scripts/simular-pico.sh [segundos=240] [llamadas_en_paralelo=16]
set -euo pipefail

SEGUNDOS="${1:-240}"
PARALELO="${2:-16}"
PYTHON="${PYTHON:-python3}"
TF="terraform -chdir=terraform/organization"
export AWS_DEFAULT_REGION="${AWS_REGION:-us-east-1}"

STREAM=$($TF output -raw stream_posiciones)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# 500 registros por llamada (el maximo de PutRecords), repartidos en 100
# repartidores para que caigan en todos los shards.
"$PYTHON" - > "$TMP/registros.json" <<'PY'
import base64, json, random
from datetime import datetime, timezone
ts = datetime.now(timezone.utc).isoformat()
registros = []
for i in range(500):
    rep = f"simulacion-{i % 100}"
    dato = {"repartidor_id": rep, "lat": -34.6 + random.random() / 100,
            "lng": -58.4 + random.random() / 100, "ts": ts}
    registros.append({"Data": base64.b64encode(json.dumps(dato).encode()).decode(),
                      "PartitionKey": rep})
print(json.dumps(registros))
PY

shards() {
  aws kinesis describe-stream-summary --stream-name "$STREAM" \
    --query 'StreamDescriptionSummary.[OpenShardCount,StreamStatus]' --output text
}

echo "Stream $STREAM: $(shards) (shards, estado)"
echo "Escribiendo durante ${SEGUNDOS}s con $PARALELO llamadas en paralelo..."

FIN=$(( $(date +%s) + SEGUNDOS ))
while (( $(date +%s) < FIN )); do
  seq "$PARALELO" | xargs -P "$PARALELO" -I{} \
    aws kinesis put-records --stream-name "$STREAM" --records "file://$TMP/registros.json" \
      --query FailedRecordCount --output text >> "$TMP/fallidos.txt" 2>/dev/null || true
  enviados=$(( $(wc -l < "$TMP/fallidos.txt") * 500 ))
  rechazados=$(awk '{s += $1} END {print s + 0}' "$TMP/fallidos.txt")
  printf '\r  enviados: %d  rechazados por falta de capacidad: %d' "$enviados" "$rechazados"
done
echo

echo "Listo. Estado del stream: $(shards)"
echo "La alarma evalua por minuto (2 de 3 minutos con rechazos); seguir con:"
echo "  aws cloudwatch describe-alarms --alarm-names $($TF output -raw proyecto)-posiciones-escrituras-rechazadas --query 'MetricAlarms[0].StateValue'"
echo "  aws kinesis describe-stream-summary --stream-name $STREAM --query 'StreamDescriptionSummary.OpenShardCount'"
