output "migracion" {
  value = jsondecode(aws_lambda_invocation.migrar_esquema.result)
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_client_ids" {
  value = { for rol, cliente in aws_cognito_user_pool_client.app : rol => cliente.id }
}

output "api_url" {
  value = aws_apigatewayv2_api.main.api_endpoint
}

output "cola_posiciones_fallidas" {
  value = aws_sqs_queue.posiciones_fallidas.url
}
