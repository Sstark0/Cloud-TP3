# Historial y panel analitico (funcionalidad 5 del TP1).
#
# - Posiciones: ya se archivan de forma continua (Kinesis -> archivar-posiciones
#   -> S3 historico/posiciones/).
# - Eventos de pedidos: cada cambio de estado ya se publica en el topic
#   estado_pedido. Una cola SQS suscrita lo junta en lotes y archivar-eventos lo
#   completa con datos del pedido y lo escribe en historico/pedidos/.
# - Glue Data Catalog describe esos archivos como tablas, y Athena las consulta
#   con SQL. Las consultas guardadas son el panel.
#
# Todo historico/ comparte el lifecycle a Standard-IA y Glacier Instant
# Retrieval: Athena puede leer Glacier IR, asi que lo mas viejo sigue siendo
# consultable (Glacier Flexible Retrieval o Deep Archive no lo serian).

locals {
  base_analitica = "${replace(var.proyecto, "-", "_")}_analitica"

  # Formato comun: un JSON por linea, particionado por fecha=AAAA-MM-DD.
  # Partition projection: Athena deduce las particiones del nombre de la
  # carpeta, asi que no hace falta un crawler de Glue (ni su rol, ni su costo).
  tablas_analitica = {
    posiciones = {
      prefijo = "historico/posiciones"
      columnas = {
        repartidor_id = "string"
        lat           = "double"
        lng           = "double"
        ts            = "string"
      }
    }
    eventos_pedido = {
      prefijo = "historico/pedidos"
      columnas = {
        pedido_id     = "string"
        estado        = "string"
        ts            = "string"
        cliente_id    = "string"
        comercio_id   = "bigint"
        comercio      = "string"
        repartidor_id = "string"
        total         = "bigint"
        entrega_lat   = "double"
        entrega_lng   = "double"
        mensaje_id    = "string"
      }
    }
  }

  consultas_analitica = {
    tiempos_entrega        = "Minutos hasta asignar y hasta entregar, por comercio y hora (ultimos 30 dias)"
    curva_demanda          = "Pedidos por dia de la semana y hora (ultimos 30 dias)"
    cobertura              = "Repartidores por celda de ~500 m y hora (ultimos 7 dias)"
    desempeno_repartidores = "Entregas, minutos medios y km recorridos por repartidor (ultimos 30 dias)"
    rechazos_cancelaciones = "Pedidos rechazados y cancelados por comercio (ultimos 30 dias)"
  }
}

# ------------------------------------------------------ eventos de pedidos

resource "aws_sqs_queue" "eventos_fallidos" {
  name                      = "${var.proyecto}-eventos-fallidos"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "eventos_pedido" {
  name                       = "${var.proyecto}-eventos-pedido"
  message_retention_seconds  = 345600
  visibility_timeout_seconds = 180 # 6 veces el timeout de archivar-eventos
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.eventos_fallidos.arn
    maxReceiveCount     = 5
  })
}

data "aws_iam_policy_document" "eventos_pedido" {
  statement {
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.eventos_pedido.arn]

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.estado_pedido.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "eventos_pedido" {
  queue_url = aws_sqs_queue.eventos_pedido.id
  policy    = data.aws_iam_policy_document.eventos_pedido.json
}

# Sin raw delivery: el sobre de SNS trae la hora de publicacion del evento.
resource "aws_sns_topic_subscription" "eventos_pedido" {
  topic_arn = aws_sns_topic.estado_pedido.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.eventos_pedido.arn

  depends_on = [aws_sqs_queue_policy.eventos_pedido]
}

# Dentro de la VPC porque lee RDS; escribe en S3 por el endpoint gateway
# (su politica permite PutObject solo en historico/pedidos/).
module "archivar_eventos" {
  source = "../modules/lambda_function"

  nombre     = "${var.proyecto}-archivar-eventos"
  source_dir = "${path.module}/lambdas/archivar-eventos"
  role_arn   = data.aws_iam_role.lab.arn
  timeout    = 30
  layers     = local.capas_db
  vpc_config = local.vpc_lambda

  environment = merge(local.entorno_db, {
    BUCKET = local.bucket_archivos
  })
}

resource "aws_lambda_event_source_mapping" "eventos_pedido" {
  event_source_arn                   = aws_sqs_queue.eventos_pedido.arn
  function_name                      = module.archivar_eventos.arn
  batch_size                         = 100
  maximum_batching_window_in_seconds = var.archivo_ventana_segundos

  depends_on = [aws_lambda_invocation.migrar_esquema]
}

# ---------------------------------------------------------------- catalogo

resource "aws_glue_catalog_database" "analitica" {
  name        = local.base_analitica
  description = "Historico del delivery en S3 (posiciones y eventos de pedidos)."
}

resource "aws_glue_catalog_table" "analitica" {
  for_each = local.tablas_analitica

  name          = each.key
  database_name = aws_glue_catalog_database.analitica.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    classification                   = "json"
    "projection.enabled"             = "true"
    "projection.fecha.type"          = "date"
    "projection.fecha.format"        = "yyyy-MM-dd"
    "projection.fecha.range"         = "2026-01-01,NOW"
    "projection.fecha.interval"      = "1"
    "projection.fecha.interval.unit" = "DAYS"
    "storage.location.template"      = "s3://${local.bucket_archivos}/${each.value.prefijo}/fecha=$${fecha}/"
  }

  partition_keys {
    name = "fecha"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${local.bucket_archivos}/${each.value.prefijo}/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
      parameters            = { "ignore.malformed.json" = "true" }
    }

    dynamic "columns" {
      for_each = each.value.columnas
      content {
        name = columns.key
        type = columns.value
      }
    }
  }
}

# ---------------------------------------------------------------- consultas

# Resultados en el bucket del proyecto (athena/, con su propio lifecycle) y un
# tope de datos escaneados por consulta: una consulta mal escrita no puede
# recorrer todo el historico.
resource "aws_athena_workgroup" "analitica" {
  name          = "${var.proyecto}-analitica"
  force_destroy = true

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = var.athena_limite_escaneo_mb * 1024 * 1024

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }

    result_configuration {
      output_location = "s3://${local.bucket_archivos}/athena/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }
}

resource "aws_athena_named_query" "analitica" {
  for_each = local.consultas_analitica

  name        = each.key
  description = each.value
  workgroup   = aws_athena_workgroup.analitica.id
  database    = aws_glue_catalog_database.analitica.name
  query       = file("${path.module}/consultas/${each.key}.sql")
}
