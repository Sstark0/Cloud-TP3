resource "aws_kinesis_stream" "posiciones" {
  name             = "${var.proyecto}-posiciones"
  shard_count      = 1
  retention_period = 24
  encryption_type  = "KMS"
  kms_key_id       = "alias/aws/kinesis"

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }
}

locals {
  consumidores_posiciones = {
    actualizar-posicion = module.actualizar_posicion.arn
    archivar-posiciones = module.archivar_posiciones.arn
  }
}

resource "aws_lambda_event_source_mapping" "posiciones" {
  for_each = local.consumidores_posiciones

  event_source_arn                   = aws_kinesis_stream.posiciones.arn
  function_name                      = each.value
  starting_position                  = "LATEST"
  batch_size                         = 100
  maximum_batching_window_in_seconds = 5
  bisect_batch_on_function_error     = true
  maximum_retry_attempts             = 3
}
