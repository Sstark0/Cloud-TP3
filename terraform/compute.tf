locals {
  capas_db   = [aws_lambda_layer_version.db.arn, aws_lambda_layer_version.rds_ca.arn]
  entorno_db = { DB_SECRET_ARN = aws_secretsmanager_secret.db.arn }
  vpc_lambda = {
    subnet_ids         = module.vpc.private_subnets
    security_group_ids = [aws_security_group.lambda.id]
  }
}

data "archive_file" "layer_db" {
  type        = "zip"
  source_dir  = "${path.module}/layers/db"
  output_path = "${path.module}/.build/layer-db.zip"
  excludes    = ["**/__pycache__/**"]
}

resource "aws_lambda_layer_version" "db" {
  layer_name          = "${var.proyecto}-db"
  filename            = data.archive_file.layer_db.output_path
  source_code_hash    = data.archive_file.layer_db.output_base64sha256
  compatible_runtimes = ["python3.12"]
}

data "http" "rds_ca" {
  url = "https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem"

  lifecycle {
    postcondition {
      condition     = self.status_code == 200 && strcontains(self.response_body, "BEGIN CERTIFICATE")
      error_message = "No se pudo descargar el bundle de CA de RDS."
    }
  }
}

data "archive_file" "layer_rds_ca" {
  type        = "zip"
  output_path = "${path.module}/.build/layer-rds-ca.zip"

  source {
    content  = data.http.rds_ca.response_body
    filename = "rds-ca/global-bundle.pem"
  }
}

resource "aws_lambda_layer_version" "rds_ca" {
  layer_name          = "${var.proyecto}-rds-ca"
  filename            = data.archive_file.layer_rds_ca.output_path
  source_code_hash    = data.archive_file.layer_rds_ca.output_base64sha256
  compatible_runtimes = ["python3.12"]
}

module "migrar_esquema" {
  source = "./modules/lambda_function"

  nombre      = "${var.proyecto}-migrar-esquema"
  source_dir  = "${path.module}/lambdas/migrar-esquema"
  role_arn    = data.aws_iam_role.lab.arn
  timeout     = 60
  layers      = local.capas_db
  environment = local.entorno_db
  vpc_config  = local.vpc_lambda
}

module "api_comercios" {
  source = "./modules/lambda_function"

  nombre      = "${var.proyecto}-api-comercios"
  source_dir  = "${path.module}/lambdas/api-comercios"
  role_arn    = data.aws_iam_role.lab.arn
  layers      = local.capas_db
  environment = local.entorno_db
  vpc_config  = local.vpc_lambda
}

module "recibir_pedido" {
  source = "./modules/lambda_function"

  nombre     = "${var.proyecto}-recibir-pedido"
  source_dir = "${path.module}/lambdas/recibir-pedido"
  role_arn   = data.aws_iam_role.lab.arn

  environment = {
    QUEUE_URL = aws_sqs_queue.pedidos.url
  }
}

module "crear_pedido" {
  source = "./modules/lambda_function"

  nombre      = "${var.proyecto}-crear-pedido"
  source_dir  = "${path.module}/lambdas/crear-pedido"
  role_arn    = data.aws_iam_role.lab.arn
  timeout     = 15
  layers      = local.capas_db
  environment = local.entorno_db
  vpc_config  = local.vpc_lambda
}

resource "aws_lambda_invocation" "migrar_esquema" {
  function_name = module.migrar_esquema.function_name
  input         = jsonencode({})

  triggers = {
    schema = filesha256("${path.module}/lambdas/migrar-esquema/schema.sql")
  }

  depends_on = [
    aws_db_instance.main,
    aws_secretsmanager_secret_version.db,
    aws_vpc_endpoint.secretsmanager,
    aws_vpc_security_group_egress_rule.lambda_a_rds,
    aws_vpc_security_group_ingress_rule.rds_desde_lambda,
    aws_vpc_security_group_egress_rule.lambda_a_vpce,
    aws_vpc_security_group_ingress_rule.vpce_desde_lambda,
  ]
}
