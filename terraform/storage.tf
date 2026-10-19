resource "aws_s3_bucket" "archivos" {
  bucket_prefix = "${var.proyecto}-archivos-"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "archivos" {
  bucket = aws_s3_bucket.archivos.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "archivos" {
  bucket = aws_s3_bucket.archivos.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "archivos" {
  bucket = aws_s3_bucket.archivos.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "archivos" {
  bucket = aws_s3_bucket.archivos.id

  rule {
    id     = "historico"
    status = "Enabled"

    filter {
      prefix = "historico/"
    }

    expiration {
      days = 180
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

data "aws_iam_policy_document" "archivos" {
  statement {
    sid       = "SoloTLS"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.archivos.arn, "${aws_s3_bucket.archivos.arn}/*"]

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

resource "aws_s3_bucket_policy" "archivos" {
  bucket = aws_s3_bucket.archivos.id
  policy = data.aws_iam_policy_document.archivos.json

  depends_on = [aws_s3_bucket_public_access_block.archivos]
}
