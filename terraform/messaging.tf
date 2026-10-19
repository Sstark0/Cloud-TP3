resource "aws_sqs_queue" "pedidos_dlq" {
  name                      = "${var.proyecto}-pedidos-dlq.fifo"
  fifo_queue                = true
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "pedidos" {
  name                        = "${var.proyecto}-pedidos.fifo"
  fifo_queue                  = true
  content_based_deduplication = false
  sqs_managed_sse_enabled     = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.pedidos_dlq.arn
    maxReceiveCount     = 3
  })
}
