#!/usr/bin/env bash
# Compila el frontend con los outputs de Terraform y lo publica en Amplify
# Hosting con un despliegue manual (zip), sin conectar Amplify al repositorio.
#
# Uso (desde la raiz del repo, despues del terraform apply y con las
# credenciales del Lab exportadas):
#   ./scripts/publicar-frontend.sh
set -euo pipefail

RAIZ=$(cd "$(dirname "$0")/.." && pwd)
TF="terraform -chdir=$RAIZ/terraform/organization"
APP=$($TF output -raw amplify_app_id)
RAMA=$($TF output -raw amplify_branch)
URL=$($TF output -raw frontend_url)

# python3 en Linux/macOS; en Windows suele llamarse python.
PY=python3
"$PY" -c '' 2>/dev/null || PY=python

cd "$RAIZ/frontend"
node scripts/config-desde-terraform.mjs >/dev/null
npm ci --no-audit --no-fund
npm run build

TMP_DIR=$(mktemp -d)
trap 'rm -r "$TMP_DIR"' EXIT
# Los archivos van en la raiz del zip (index.html, assets/...), no dentro de dist/.
(cd dist && "$PY" -m zipfile -c "$TMP_DIR/sitio.zip" ./*)

# Amplify acepta un solo despliegue a la vez: si quedo uno a medias (por
# ejemplo, de una ejecucion cortada), se cancela.
for job in $(aws amplify list-jobs --app-id "$APP" --branch-name "$RAMA" \
  --query "jobSummaries[?status=='PENDING' || status=='RUNNING'].jobId" --output text); do
  aws amplify stop-job --app-id "$APP" --branch-name "$RAMA" --job-id "$job" >/dev/null
done

aws amplify create-deployment --app-id "$APP" --branch-name "$RAMA" --output json > "$TMP_DIR/despliegue.json"
JOB=$("$PY" -c 'import json,sys; print(json.load(open(sys.argv[1]))["jobId"])' "$TMP_DIR/despliegue.json")
SUBIDA=$("$PY" -c 'import json,sys; print(json.load(open(sys.argv[1]))["zipUploadUrl"])' "$TMP_DIR/despliegue.json")

curl --silent --show-error --fail --upload-file "$TMP_DIR/sitio.zip" "$SUBIDA"
aws amplify start-deployment --app-id "$APP" --branch-name "$RAMA" --job-id "$JOB" >/dev/null

for _ in $(seq 60); do
  estado=$(aws amplify get-job --app-id "$APP" --branch-name "$RAMA" --job-id "$JOB" --query job.summary.status --output text)
  case "$estado" in
    SUCCEED) echo "Frontend publicado: $URL"; exit 0 ;;
    FAILED | CANCELLED) echo "El despliegue $JOB de Amplify termino en $estado." >&2; exit 1 ;;
  esac
  sleep 5
done
echo "El despliegue $JOB de Amplify no termino en 5 minutos." >&2
exit 1
