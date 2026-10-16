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
