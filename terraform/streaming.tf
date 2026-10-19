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
