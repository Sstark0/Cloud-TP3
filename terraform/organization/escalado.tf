# Escalado del stream de posiciones segun la curva de demanda.
#
# - Programado: EventBridge Scheduler sube a shards_pico al empezar cada franja
#   (almuerzo, cena) y baja hacia shards_minimo al terminar.
# - Reactivo: una alarma sobre escrituras rechazadas por Kinesis duplica los
#   shards hasta shards_maximo.
# - Todo pasa por la Lambda escalar-capacidad, con concurrencia reservada 1:
#   dos cambios simultaneos sobre el mismo stream fallarian.
#
# Lambda y Step Functions ya escalan solos. En el Learner Lab no hay
# concurrencia aprovisionada (deny explicito) ni Application Auto Scaling para
# Lambda (no se puede crear su rol vinculado al servicio).

locals {
  escalado        = var.escalado.habilitado ? 1 : 0
  alarma_escalado = "${var.proyecto}-posiciones-escrituras-rechazadas"

  # Un schedule por franja y extremo: almuerzo-inicio, almuerzo-fin, ...
  schedules_escalado = var.escalado.habilitado ? merge([
    for franja, h in var.escalado.franjas : {
      "${franja}-inicio" = { cron = h.inicio, accion = "pico", franja = franja }
      "${franja}-fin"    = { cron = h.fin, accion = "base", franja = franja }
    }
  ]...) : {}
}

module "escalar_capacidad" {
  source = "../modules/lambda_function"
  count  = local.escalado

  nombre                 = "${var.proyecto}-escalar-capacidad"
  source_dir             = "${path.module}/lambdas/escalar-capacidad"
  role_arn               = data.aws_iam_role.lab.arn
  concurrencia_reservada = 1

  environment = {
    STREAM_NAME        = local.stream_posiciones
    SHARDS_MINIMO      = tostring(var.escalado.shards_minimo)
    SHARDS_PICO        = tostring(var.escalado.shards_pico)
    SHARDS_MAXIMO      = tostring(var.escalado.shards_maximo)
    TOPIC_ALERTAS      = aws_sns_topic.alertas.arn
    NAMESPACE_METRICAS = "${var.proyecto}/Escalado"
    # Nombre fijo y no una referencia: la alarma ya depende de esta Lambda.
    ALARMA = local.alarma_escalado
  }
}

# ---------------------------------------------------------------- programado

resource "aws_scheduler_schedule_group" "escalado" {
  count = local.escalado

  name = "${var.proyecto}-escalado"
}

# Scheduler invoca la Lambda asumiendo LabRole (scheduler.amazonaws.com esta en
# su trust policy). A diferencia de una regla de EventBridge, acepta zona
# horaria: los cron se escriben en hora de Buenos Aires.
resource "aws_scheduler_schedule" "escalado" {
  for_each = local.schedules_escalado

  name                         = "${var.proyecto}-${each.key}"
  group_name                   = aws_scheduler_schedule_group.escalado[0].name
  schedule_expression          = each.value.cron
  schedule_expression_timezone = var.escalado.zona_horaria

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = module.escalar_capacidad[0].arn
    role_arn = data.aws_iam_role.lab.arn
    input    = jsonencode({ accion = each.value.accion, origen = "schedule:${each.key}" })

    # Si el stream esta cambiando de tamano la Lambda falla y se reintenta.
    retry_policy {
      maximum_retry_attempts       = 5
      maximum_event_age_in_seconds = 1800
    }
  }
}

# ------------------------------------------------------------------ reactivo

resource "aws_cloudwatch_metric_alarm" "escrituras_rechazadas" {
  count = local.escalado

  alarm_name          = local.alarma_escalado
  alarm_description   = "Kinesis rechaza escrituras por falta de capacidad: se duplican los shards de ${local.stream_posiciones}."
  namespace           = "AWS/Kinesis"
  metric_name         = "WriteProvisionedThroughputExceeded"
  dimensions          = { StreamName = local.stream_posiciones }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  # La accion Lambda se dispara al entrar en ALARM. Despues de escalar, la
  # Lambda devuelve la alarma a OK para que pueda volver a dispararse si la
  # capacidad nueva tampoco alcanza (con 5 min de enfriamiento). Por eso no hay
  # acciones SNS aca: mandarian un mail por minuto; avisa la Lambda cuando
  # cambia los shards.
  alarm_actions = [module.escalar_capacidad[0].arn]
}

# ------------------------------------------------------- techo de capacidad

# Avisa cuando el ingreso se acerca a lo que soportan shards_maximo shards,
# sin importar cuantos haya abiertos en este momento: es el aviso de que el
# escalado reactivo se esta quedando sin margen. Compara contra los dos limites
# de escritura por shard (1000 registros/s y 1 MiB/s) y se queda con el mayor.
#
# No usa WriteProvisionedThroughputExceeded: esa metrica tambien sube con 1 o 2
# shards, cuando el escalado reactivo todavia tiene margen, y avisaria de mas.
# El caso "ya en el maximo y con rechazos" (por ejemplo, un shard caliente que
# el promedio no muestra) lo avisa la Lambda de escalado.
locals {
  capacidad_maxima_registros_s = 1000 * var.escalado.shards_maximo
  capacidad_maxima_bytes_s     = 1048576 * var.escalado.shards_maximo
}

resource "aws_cloudwatch_metric_alarm" "capacidad_maxima" {
  count = local.escalado

  alarm_name          = "${var.proyecto}-posiciones-capacidad-maxima"
  alarm_description   = "El ingreso a ${local.stream_posiciones} supera el 80 % de lo que soportan ${var.escalado.shards_maximo} shards (shards_maximo): el escalado ya no tiene margen."
  comparison_operator = "GreaterThanThreshold"
  threshold           = 80
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alertas.arn]
  ok_actions          = [aws_sns_topic.alertas.arn]

  metric_query {
    id = "registros"
    metric {
      namespace   = "AWS/Kinesis"
      metric_name = "IncomingRecords"
      dimensions  = { StreamName = local.stream_posiciones }
      period      = 60
      stat        = "Sum"
    }
  }

  metric_query {
    id = "bytes"
    metric {
      namespace   = "AWS/Kinesis"
      metric_name = "IncomingBytes"
      dimensions  = { StreamName = local.stream_posiciones }
      period      = 60
      stat        = "Sum"
    }
  }

  metric_query {
    id          = "uso"
    label       = "Uso de la capacidad de shards_maximo (%)"
    return_data = true
    expression  = "100 * MAX([registros / 60 / ${local.capacidad_maxima_registros_s}, bytes / 60 / ${local.capacidad_maxima_bytes_s}])"
  }
}

resource "aws_lambda_permission" "alarma_escalado" {
  count = local.escalado

  statement_id  = "AllowCloudWatchAlarm"
  action        = "lambda:InvokeFunction"
  function_name = module.escalar_capacidad[0].function_name
  principal     = "lambda.alarms.cloudwatch.amazonaws.com"
  source_arn    = aws_cloudwatch_metric_alarm.escrituras_rechazadas[0].arn
}
