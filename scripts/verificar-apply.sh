#!/usr/bin/env bash
# Verifica, despues de un terraform apply en el Learner Lab, lo que no se puede
# saber antes de probar: LabRole en Lambda y Step Functions, db.t3.micro,
# PostGIS, logs del API y el camino completo de las posiciones.
#
# Uso (desde la raiz del repo, con las credenciales del Lab ya exportadas):
#   ./scripts/verificar-apply.sh
set -uo pipefail

TF="terraform -chdir=terraform/organization"
REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$REGION"

out() { $TF output -raw "$1"; }
ok() { printf '  \033[32mOK\033[0m   %s\n' "$*"; }
mal() { printf '  \033[31mFALLA\033[0m %s\n' "$*"; FALLAS=$((FALLAS + 1)); }
FALLAS=0

PROYECTO=$(out proyecto)
API=$(out api_url)
POOL=$(out cognito_user_pool_id)
CLIENTE=$($TF output -json cognito_client_ids | python3 -c 'import json,sys; print(json.load(sys.stdin)["repartidor"])')
BUCKET=$(out bucket_archivos)
DESDE=$(( $(date +%s) * 1000 ))

echo "1. LabRole en Lambda y Step Functions"
for f in $(aws lambda list-functions --query "Functions[?starts_with(FunctionName, '${PROYECTO}-')].FunctionName" --output text); do
  rol=$(aws lambda get-function-configuration --function-name "$f" --query Role --output text)
  [[ "$rol" == */LabRole ]] && ok "$f" || mal "$f usa $rol"
done
SFN=$(aws stepfunctions list-state-machines --query "stateMachines[?name=='${PROYECTO}-procesar-pedido'].stateMachineArn" --output text)
[[ "$(aws stepfunctions describe-state-machine --state-machine-arn "$SFN" --query roleArn --output text)" == */LabRole ]] \
  && ok "state machine con LabRole" || mal "state machine sin LabRole"

# Comercio inexistente: crear-pedido tira PedidoInvalido y el Catch lo lleva a
# PedidoRechazado. Si termina SUCCEEDED, Step Functions pudo invocar la Lambda
# y la Lambda pudo hablar con RDS.
EJEC=$(aws stepfunctions start-execution --state-machine-arn "$SFN" --name "verificar-$(date +%s)" \
  --input '{"pedido_id":"00000000-0000-0000-0000-000000000000","comercio_id":-1,"cliente_id":"verificacion","items":[{"producto_id":-1,"cantidad":1}],"entrega":{"direccion":"x","lat":0,"lng":0}}' \
  --query executionArn --output text)
for _ in $(seq 1 20); do
  estado=$(aws stepfunctions describe-execution --execution-arn "$EJEC" --query status --output text)
  [[ "$estado" != RUNNING ]] && break; sleep 3
done
[[ "$estado" == SUCCEEDED ]] && ok "ejecucion de prueba SUCCEEDED (Step Functions -> Lambda -> RDS)" || mal "ejecucion de prueba: $estado"

echo "2. Instancia RDS"
read -r clase motor estado < <(aws rds describe-db-instances --db-instance-identifier "$PROYECTO" \
  --query 'DBInstances[0].[DBInstanceClass,EngineVersion,DBInstanceStatus]' --output text)
[[ "$clase" == db.t3.micro && "$estado" == available ]] && ok "$clase, postgres $motor, $estado" || mal "$clase / $estado"

echo "3. PostGIS"
version=$($TF output -json migracion | python3 -c 'import json,sys; print(json.load(sys.stdin).get("postgis",""))')
[[ -n "$version" ]] && ok "postgis $version" || mal "la migracion no devolvio version de PostGIS"

echo "4. Logs del API"
codigo=$(curl -s -o /dev/null -w '%{http_code}' "$API/comercios")
[[ "$codigo" == 401 ]] && ok "sin token -> 401" || mal "sin token devolvio $codigo"

USUARIO="repartidor.prueba@example.com"
CLAVE="Prueba1234"
aws cognito-idp admin-create-user --user-pool-id "$POOL" --username "$USUARIO" --message-action SUPPRESS \
  --user-attributes Name=email,Value="$USUARIO" Name=email_verified,Value=true >/dev/null 2>&1 || true
aws cognito-idp admin-set-user-password --user-pool-id "$POOL" --username "$USUARIO" --password "$CLAVE" --permanent
aws cognito-idp admin-add-user-to-group --user-pool-id "$POOL" --username "$USUARIO" --group-name repartidor
TOKEN=$(aws cognito-idp admin-initiate-auth --user-pool-id "$POOL" --client-id "$CLIENTE" \
  --auth-flow ADMIN_USER_PASSWORD_AUTH --auth-parameters USERNAME="$USUARIO",PASSWORD="$CLAVE" \
  --query AuthenticationResult.AccessToken --output text)
[[ -n "$TOKEN" && "$TOKEN" != None ]] && ok "token de repartidor de prueba" || mal "no se pudo obtener token"

echo "5. Posiciones: API -> Kinesis -> RDS y S3"
# actualizar-posicion solo guarda posiciones de repartidores que ya existen en
# la tabla repartidor; el PUT de estado es el que los da de alta.
codigo=$(curl -s -o /dev/null -w '%{http_code}' -X PUT "$API/repartidores/me/estado" \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"disponible":true}')
[[ "$codigo" == 200 ]] && ok "PUT estado -> 200 (repartidor dado de alta en RDS)" || mal "PUT estado -> $codigo"
for i in 1 2 3; do
  codigo=$(curl -s -o /dev/null -w '%{http_code}' -X PUT "$API/repartidores/me/posicion" \
    -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
    -d "{\"lat\":-34.60$i,\"lng\":-58.38$i}")
  [[ "$codigo" == 202 ]] && ok "PUT posicion $i -> 202" || mal "PUT posicion $i -> $codigo"
  sleep 1
done

echo "   esperando a los consumidores..."
sleep 20
# filter-log-events pagina solo y --query imprime un resultado por pagina: se suman.
sumar() { awk '{s += $1} END {print s + 0}'; }
eventos=$(aws logs filter-log-events --log-group-name "/aws/apigateway/${PROYECTO}" --start-time "$DESDE" \
  --query 'length(events)' --output text | sumar)
[[ "$eventos" -ge 5 ]] && ok "$eventos lineas en el access log del API" || mal "access log del API con $eventos lineas"

# Se mira el log de la Lambda (no un mensaje propio del handler) para que el
# chequeo no dependa de como este escrita: invocaciones vs. errores.
LOG_ACT="/aws/lambda/${PROYECTO}-actualizar-posicion"
invocaciones=$(aws logs filter-log-events --log-group-name "$LOG_ACT" --start-time "$DESDE" \
  --filter-pattern '"REPORT RequestId"' --query 'length(events)' --output text | sumar)
errores=$(aws logs filter-log-events --log-group-name "$LOG_ACT" --start-time "$DESDE" \
  --filter-pattern '"[ERROR]"' --query 'events[].message' --output text | head -1)
if [[ "$invocaciones" -ge 1 && -z "$errores" ]]; then
  ok "actualizar-posicion: $invocaciones invocaciones sin errores"
else
  mal "actualizar-posicion: $invocaciones invocaciones, primer error: $errores"
fi

# La cola de fallidas existe solo si se mergeo el PR de consumidores de Kinesis.
if COLA=$($TF output -raw cola_posiciones_fallidas 2>/dev/null); then
  fallidas=$(aws sqs get-queue-attributes --queue-url "$COLA" \
    --attribute-names ApproximateNumberOfMessages --query Attributes.ApproximateNumberOfMessages --output text)
  [[ "$fallidas" == 0 ]] && ok "cola de posiciones fallidas vacia" || mal "$fallidas lotes en la cola de fallidas"
fi

echo "   S3 (archivar-posiciones escribe cada archivo_ventana_segundos; por defecto 5 s sin el PR de consumidores, 60 s con el)"
objetos=$(aws s3api list-objects-v2 --bucket "$BUCKET" --prefix historico/posiciones/ --query 'KeyCount' --output text)
[[ "$objetos" =~ ^[0-9]+$ && "$objetos" -ge 1 ]] && ok "$objetos objetos en s3://$BUCKET/historico/posiciones/" \
  || echo "  ...  todavia sin objetos: reintentar con 'aws s3 ls s3://$BUCKET/historico/posiciones/ --recursive' en unos minutos"

# Misma llamada firmada, por HTTP y por HTTPS: la policy tiene que cortar solo la primera.
if aws s3api list-objects-v2 --bucket "$BUCKET" --max-items 1 --endpoint-url "http://s3.${REGION}.amazonaws.com" >/dev/null 2>&1; then
  mal "S3 acepto una llamada sin TLS"
else
  ok "S3 rechaza llamadas sin TLS"
fi
aws s3api list-objects-v2 --bucket "$BUCKET" --max-items 1 >/dev/null 2>&1 && ok "S3 acepta la misma llamada por HTTPS" || mal "S3 rechazo la llamada por HTTPS"

echo "6. Escalado del stream (programado y reactivo)"
FUNCION=$(out funcion_escalado)
STREAM=$(out stream_posiciones)
if [[ -z "$FUNCION" ]]; then
  echo "  ...  escalado deshabilitado (escalado.habilitado = false)"
else
  schedules=$(aws scheduler list-schedules --group-name "${PROYECTO}-escalado" --query 'length(Schedules[?State==`ENABLED`])' --output text)
  [[ "$schedules" -ge 2 ]] && ok "$schedules schedules habilitados en ${PROYECTO}-escalado" || mal "faltan schedules ($schedules)"
  acciones=$(aws cloudwatch describe-alarms --alarm-names "${PROYECTO}-posiciones-escrituras-rechazadas"     --query 'MetricAlarms[0].AlarmActions' --output text)
  [[ "$acciones" == *":function:${FUNCION}"* ]] && ok "la alarma de escrituras rechazadas invoca $FUNCION" || mal "la alarma no invoca $FUNCION"

  # Cada cambio de shards consume 1 de los 10 cambios diarios del stream.
  # VERIFICAR_ESCALADO=0 saltea la prueba de subir y bajar.
  if [[ "${VERIFICAR_ESCALADO:-1}" == 1 ]]; then
    shards() { aws kinesis describe-stream-summary --stream-name "$STREAM"       --query 'StreamDescriptionSummary.[StreamStatus,OpenShardCount]' --output text; }
    esperar_activo() { for _ in $(seq 60); do [[ "$(shards)" == ACTIVE* ]] && return; sleep 5; done; }
    invocar() { aws lambda invoke --function-name "$FUNCION" --cli-binary-format raw-in-base64-out       --payload "{\"accion\":\"$1\",\"origen\":\"verificar-apply\"}" "$TMP_ESC" >/dev/null && cat "$TMP_ESC"; }
    TMP_ESC=$(mktemp)
    esperar_activo
    inicial=$(shards | awk '{print $2}')
    r=$(invocar pico); esperar_activo; despues=$(shards | awk '{print $2}')
    [[ "$despues" -gt "$inicial" || "$r" == *'"antes": '"$despues"* ]] && ok "pico: $inicial -> $despues shards" || mal "pico no subio los shards: $r"
    r=$(invocar base); esperar_activo; final=$(shards | awk '{print $2}')
    [[ "$final" -lt "$despues" || "$final" == "$inicial" ]] && ok "base: $despues -> $final shards" || mal "base no bajo los shards: $r"
    rm -f "$TMP_ESC"
  fi
fi

echo
[[ $FALLAS -eq 0 ]] && echo "Todo OK" || echo "$FALLAS verificaciones fallaron"
exit $FALLAS
