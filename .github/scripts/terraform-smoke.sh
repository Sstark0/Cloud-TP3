#!/usr/bin/env bash
set -euo pipefail

api_url=$(terraform output -raw api_url)
pool=$(terraform output -raw cognito_user_pool_id)
client_id=$(terraform output -json cognito_client_ids | jq -er .cliente)
response_file=$(mktemp)
trap 'rm -f "$response_file"' EXIT

status=$(curl --silent --show-error --connect-timeout 10 --max-time 30 \
  --output "$response_file" --write-out '%{http_code}' "$api_url/comercios")
[[ "$status" == 401 ]] || { echo "::error::GET /comercios sin token devolvio $status; se esperaba 401."; exit 1; }

# Los secretos de usuarios demo se usan en memoria y no se publican como outputs.
password=$(terraform output -json usuarios_demo | jq -er '."cliente.demo@example.com"')
printf '::add-mask::%s\n' "$password"
token=$(aws cognito-idp admin-initiate-auth --user-pool-id "$pool" --client-id "$client_id" \
  --auth-flow ADMIN_USER_PASSWORD_AUTH \
  --auth-parameters "USERNAME=cliente.demo@example.com,PASSWORD=$password" \
  --query AuthenticationResult.IdToken --output text)
[[ -n "$token" && "$token" != None ]] || { echo '::error::Cognito no devolvio un IdToken.'; exit 1; }
printf '::add-mask::%s\n' "$token"
unset password

# La primera invocacion puede esperar el arranque de Lambda y la conexion TLS
# al proxy, y el target del proxy puede tardar un poco mas en estar disponible.
for attempt in 1 2 3 4 5 6; do
  status=$(curl --silent --show-error --connect-timeout 10 --max-time 40 \
    --header "Authorization: Bearer $token" --output "$response_file" \
    --write-out '%{http_code}' "$api_url/comercios")
  [[ "$status" == 200 ]] && break
  [[ "$attempt" == 6 ]] || sleep 10
done
[[ "$status" == 200 ]] || { echo "::error::GET /comercios autenticado devolvio $status."; exit 1; }
jq -e 'type == "array" and length > 0' "$response_file" >/dev/null
comercio=$(jq -er '.[0].id' "$response_file")
count=$(jq 'length' "$response_file")
status=$(curl --silent --show-error --connect-timeout 10 --max-time 40 \
  --header "Authorization: Bearer $token" --output "$response_file" \
  --write-out '%{http_code}' "$api_url/comercios/$comercio/productos")
unset token
[[ "$status" == 200 ]] || { echo "::error::GET productos devolvio $status."; exit 1; }
jq -e 'type == "array" and length > 0' "$response_file" >/dev/null
printf 'API lista: acceso anonimo rechazado, login de Cognito valido, %s comercios y productos disponibles desde RDS (via RDS Proxy).\n' "$count"

# El frontend publicado en Amplify responde por HTTPS, tambien en una ruta de la SPA.
frontend_url=$(terraform output -raw frontend_url)
for ruta in / /cliente; do
  status=$(curl --silent --connect-timeout 10 --max-time 30 --output /dev/null \
    --write-out '%{http_code}' "$frontend_url$ruta")
  [[ "$status" == 200 ]] || { echo "::error::El frontend devolvio $status en $ruta."; exit 1; }
done
printf 'Frontend publicado: %s\n' "$frontend_url"
