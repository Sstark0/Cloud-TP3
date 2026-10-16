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

