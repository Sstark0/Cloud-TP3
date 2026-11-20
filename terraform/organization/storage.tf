# Los buckets los crea recursos-base (ver recursos-base.tf). Aca va su
# configuracion. Las claves son fijas para que for_each se conozca en el plan;
# los nombres llegan del resultado de la invocacion.
locals {
  claves_buckets = toset(["comprobantes", "historico"])
}

resource "aws_s3_bucket_public_access_block" "bucket" {
  for_each = local.claves_buckets
  bucket   = local.buckets[each.key].nombre

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "bucket" {
  for_each = local.claves_buckets
  bucket   = local.buckets[each.key].nombre

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bucket" {
  for_each = local.claves_buckets
  bucket   = local.buckets[each.key].nombre

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "bucket" {
  for_each = local.claves_buckets

  statement {
    sid       = "SoloTLS"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [local.buckets[each.key].arn, "${local.buckets[each.key].arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "bucket" {
  for_each = local.claves_buckets
  bucket   = local.buckets[each.key].nombre
  policy   = data.aws_iam_policy_document.bucket[each.key].json

  depends_on = [aws_s3_bucket_public_access_block.bucket]
}

# ------------------------------------------------------------ comprobantes

resource "aws_s3_bucket_lifecycle_configuration" "comprobantes" {
  bucket = local.bucket_comprobantes

  rule {
    id     = "multipart-incompletos"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# El frontend sube el comprobante directo a S3 con el POST firmado que devuelve
# url-comprobante. Solo POST: el bucket no se lee ni se lista desde el navegador.
resource "aws_s3_bucket_cors_configuration" "comprobantes" {
  bucket = local.bucket_comprobantes

  cors_rule {
    allowed_methods = ["POST"]
    allowed_origins = local.cors_origenes
    allowed_headers = ["content-type"]
    max_age_seconds = 3600
  }
}

# --------------------------------------------------------------- historico

resource "aws_s3_bucket_lifecycle_configuration" "historico" {
  bucket = local.bucket_historico

  # Un rule por tabla del historico (posiciones/ y pedidos/), con las mismas
  # transiciones. athena/ queda afuera: tiene su propia expiracion.
  dynamic "rule" {
    for_each = local.tablas_analitica
    content {
      id     = "historico-${rule.key}"
      status = "Enabled"

      filter {
        prefix = "${rule.value.prefijo}/"
      }

      transition {
        days          = var.historico_lifecycle.dias_standard_ia
        storage_class = "STANDARD_IA"
      }

      transition {
        days          = var.historico_lifecycle.dias_glacier_ir
        storage_class = "GLACIER_IR"
      }

      expiration {
        days = var.historico_lifecycle.dias_expiracion
      }

      noncurrent_version_expiration {
        noncurrent_days = 7
      }
    }
  }

  # Resultados de Athena: son descartables (se regeneran corriendo la consulta).
  rule {
    id     = "resultados-athena"
    status = "Enabled"

    filter {
      prefix = "athena/"
    }

    expiration {
      days = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }

  rule {
    id     = "multipart-incompletos"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Las reglas sobre versiones no actuales necesitan el versionado ya activo.
  depends_on = [aws_s3_bucket_versioning.bucket]
}
