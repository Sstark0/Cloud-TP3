resource "random_id" "bucket" {
  byte_length = 4
}

data "aws_default_tags" "actual" {}

module "recursos_base" {
  source = "../modules/lambda_function"

  nombre     = "${var.proyecto}-recursos-base"
  source_dir = "${path.module}/lambdas/recursos-base"
  role_arn   = data.aws_iam_role.lab.arn
  timeout    = 600
}

# Dos buckets con usos distintos:
# - comprobantes: fotos de entrega, subidas desde el navegador con un POST
#   firmado. Datos operativos, leidos por marcar-entregado.
# - historico: posiciones y eventos de pedidos para Athena, con lifecycle a
#   Standard-IA y Glacier IR, mas los resultados de las consultas.
resource "aws_lambda_invocation" "recursos_base" {
  function_name   = module.recursos_base.function_name
  lifecycle_scope = "CRUD"

  input = jsonencode({
    buckets = {
      comprobantes = "${var.proyecto}-comprobantes-${random_id.bucket.hex}"
      historico    = "${var.proyecto}-historico-${random_id.bucket.hex}"
    }
    stream  = "${var.proyecto}-posiciones"
    shards  = var.escalado.shards_minimo
    kms_key = "alias/aws/kinesis"
    tags    = data.aws_default_tags.actual.tags
  })
}

locals {
  recursos_base = jsondecode(aws_lambda_invocation.recursos_base.result)

  # {comprobantes = {nombre, arn}, historico = {nombre, arn}}
  buckets = local.recursos_base.buckets

  bucket_comprobantes     = local.buckets.comprobantes.nombre
  bucket_comprobantes_arn = local.buckets.comprobantes.arn
  bucket_historico        = local.buckets.historico.nombre
  bucket_historico_arn    = local.buckets.historico.arn
  stream_posiciones       = local.recursos_base.stream
  stream_posiciones_arn   = local.recursos_base.stream_arn
}
