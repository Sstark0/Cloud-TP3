output "migracion" {
  value = jsondecode(aws_lambda_invocation.migrar_esquema.result)
}
