variable "nombre" {
  type = string
}

variable "source_dir" {
  type = string
}

variable "role_arn" {
  type = string
}

variable "timeout" {
  type    = number
  default = 10
}

variable "environment" {
  type    = map(string)
  default = {}
}

variable "vpc_config" {
  type = object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
  default = null
}

variable "layers" {
  type    = list(string)
  default = []

  validation {
    condition     = length(var.layers) <= 5
    error_message = "Lambda admite hasta 5 layers por funcion."
  }
}

variable "concurrencia_reservada" {
  description = "Ejecuciones concurrentes reservadas. null = sin reserva (usa la concurrencia libre de la cuenta)."
  type        = number
  default     = null

  validation {
    condition     = var.concurrencia_reservada == null ? true : var.concurrencia_reservada >= 0
    error_message = "La concurrencia reservada no puede ser negativa."
  }
}
