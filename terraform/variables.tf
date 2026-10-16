variable "region" {
  type    = string
  default = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-west-2"], var.region)
    error_message = "Elegir entre us-east-1 o us-west-2."
  }
}

variable "proyecto" {
  type    = string
  default = "delivery"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.proyecto))
    error_message = "Solo minusculas, numeros y guiones, entre 3 y 21 caracteres, empezando con letra."
  }
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr tiene que ser un CIDR IPv4 valido."
  }

  validation {
    condition     = endswith(var.vpc_cidr, "/16")
    error_message = "vpc_cidr tiene que ser /16 (las subredes /24 se calculan sumando 8 bits)."
  }
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}
