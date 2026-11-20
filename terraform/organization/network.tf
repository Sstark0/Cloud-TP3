module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  name = var.proyecto
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets       = local.subredes_app
  private_subnet_suffix = "app"

  database_subnets       = local.subredes_datos
  database_subnet_suffix = "datos"

  database_dedicated_network_acl = true

  database_inbound_acl_rules = [
    for i, cidr in local.subredes_app : {
      rule_number = 100 + i
      rule_action = "allow"
      protocol    = "tcp"
      from_port   = 5432
      to_port     = 5432
      cidr_block  = cidr
    }
  ]

  database_outbound_acl_rules = [
    for i, cidr in local.subredes_app : {
      rule_number = 100 + i
      rule_action = "allow"
      protocol    = "tcp"
      from_port   = 1024
      to_port     = 65535
      cidr_block  = cidr
    }
  ]

  create_igw         = false
  enable_nat_gateway = false
}

resource "aws_security_group" "lambda" {
  name_prefix = "${var.proyecto}-lambda-"
  description = "Lambdas dentro de la VPC"
  vpc_id      = module.vpc.vpc_id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "vpce" {
  name_prefix = "${var.proyecto}-vpce-"
  description = "Interface endpoints"
  vpc_id      = module.vpc.vpc_id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "rds_proxy" {
  name_prefix = "${var.proyecto}-rds-proxy-"
  description = "RDS Proxy"
  vpc_id      = module.vpc.vpc_id

  lifecycle {
    create_before_destroy = true
  }
}

# Lambda -> RDS Proxy -> RDS. Las Lambdas no llegan a la instancia directo:
# todas las conexiones pasan por el pool del proxy.
resource "aws_vpc_security_group_egress_rule" "lambda_a_proxy" {
  security_group_id            = aws_security_group.lambda.id
  referenced_security_group_id = aws_security_group.rds_proxy.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_vpc_security_group_ingress_rule" "proxy_desde_lambda" {
  security_group_id            = aws_security_group.rds_proxy.id
  referenced_security_group_id = aws_security_group.lambda.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_vpc_security_group_egress_rule" "proxy_a_rds" {
  security_group_id            = aws_security_group.rds_proxy.id
  referenced_security_group_id = aws_security_group.rds.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_vpc_security_group_ingress_rule" "rds_desde_proxy" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.rds_proxy.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

# El proxy lee usuario y clave del secreto de RDS. La VPC no tiene salida a
# internet: si esa lectura sale desde las interfaces del proxy, pasa por el
# endpoint de Secrets Manager (el proxy esta en las mismas subredes app).
resource "aws_vpc_security_group_egress_rule" "proxy_a_vpce" {
  security_group_id            = aws_security_group.rds_proxy.id
  referenced_security_group_id = aws_security_group.vpce.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_vpc_security_group_ingress_rule" "vpce_desde_proxy" {
  security_group_id            = aws_security_group.vpce.id
  referenced_security_group_id = aws_security_group.rds_proxy.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_vpc_security_group_egress_rule" "lambda_a_vpce" {
  security_group_id            = aws_security_group.lambda.id
  referenced_security_group_id = aws_security_group.vpce.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_vpc_security_group_ingress_rule" "vpce_desde_lambda" {
  security_group_id            = aws_security_group.vpce.id
  referenced_security_group_id = aws_security_group.lambda.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.endpoint_una_az ? [module.vpc.private_subnets[0]] : module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true
}

data "aws_iam_policy_document" "vpce_s3" {
  # marcar-entregado (dentro de la VPC) verifica que exista el comprobante.
  statement {
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      local.bucket_comprobantes_arn,
      "${local.bucket_comprobantes_arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }

  # archivar-eventos (dentro de la VPC) escribe el historico de pedidos. Desde
  # la VPC solo se puede escribir ahi: nada mas de S3 es alcanzable.
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${local.bucket_historico_arn}/pedidos/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids
  policy            = data.aws_iam_policy_document.vpce_s3.json
}

resource "aws_vpc_security_group_egress_rule" "lambda_a_s3" {
  security_group_id = aws_security_group.lambda.id
  prefix_list_id    = aws_vpc_endpoint.s3.prefix_list_id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}
