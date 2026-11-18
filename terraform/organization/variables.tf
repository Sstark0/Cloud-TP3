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

variable "archivo_ventana_segundos" {
  description = "Segundos que archivar-posiciones junta posiciones antes de escribir un objeto en S3."
  type        = number
  default     = 60

  validation {
    condition     = var.archivo_ventana_segundos >= 1 && var.archivo_ventana_segundos <= 300
    error_message = "Kinesis admite una ventana de 1 a 300 segundos."
  }
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "historico_lifecycle" {
  description = "Dias hasta pasar historico/ a Standard-IA, a Glacier Instant Retrieval y hasta borrarlo."
  type = object({
    dias_standard_ia = number
    dias_glacier_ir  = number
    dias_expiracion  = number
  })
  default = {
    dias_standard_ia = 30
    dias_glacier_ir  = 90
    dias_expiracion  = 180
  }

  validation {
    condition     = var.historico_lifecycle.dias_standard_ia >= 30
    error_message = "S3 no permite pasar a Standard-IA antes de los 30 dias."
  }

  validation {
    condition = (
      var.historico_lifecycle.dias_standard_ia < var.historico_lifecycle.dias_glacier_ir &&
      var.historico_lifecycle.dias_glacier_ir < var.historico_lifecycle.dias_expiracion
    )
    error_message = "Los dias van en orden: Standard-IA < Glacier IR < expiracion."
  }
}

variable "db_dias_backup" {
  description = "Dias de retencion de los backups automaticos de RDS. Define hasta cuando se puede restaurar a un punto en el tiempo."
  type        = number
  default     = 7

  validation {
    condition     = var.db_dias_backup >= 1 && var.db_dias_backup <= 35
    error_message = "RDS admite entre 1 y 35 dias de retencion."
  }
}

variable "db_multi_az" {
  description = "RDS con standby sincronico en otra AZ y failover automatico. Duplica el costo de la instancia."
  type        = bool
  default     = false
}

variable "backup_rds" {
  description = "Plan de AWS Backup para RDS: si se crea, cuando corre (cron en UTC) y cuantos dias se guarda cada copia."
  type = object({
    habilitado     = bool
    cron           = string
    dias_retencion = number
  })
  default = {
    habilitado     = true
    cron           = "cron(0 6 * * ? *)" # 03:00 en Buenos Aires
    dias_retencion = 7
  }

  validation {
    condition     = var.backup_rds.dias_retencion >= 1
    error_message = "La retencion tiene que ser de al menos 1 dia."
  }

  validation {
    condition     = startswith(var.backup_rds.cron, "cron(")
    error_message = "El cron tiene que tener el formato de AWS: cron(min hora dia mes dia-semana anio)."
  }
}

variable "presupuesto_mensual_usd" {
  description = "Presupuesto mensual de la cuenta en USD, con alertas al topic de alertas al 80 % pronosticado y al 100 % real. 0 lo desactiva."
  type        = number
  default     = 50

  validation {
    condition     = var.presupuesto_mensual_usd >= 0
    error_message = "El presupuesto no puede ser negativo."
  }
}

variable "endpoint_una_az" {
  description = "Endpoint de Secrets Manager en una sola AZ (mas barato). En false hay una interfaz por AZ y las Lambdas de la VPC no dependen de una sola zona para leer la clave de la base."
  type        = bool
  default     = true
}

variable "asignacion_max_intentos" {
  type    = number
  default = 3

  validation {
    condition     = var.asignacion_max_intentos >= 1 && var.asignacion_max_intentos <= 10
    error_message = "asignacion_max_intentos tiene que estar entre 1 y 10."
  }
}

variable "asignacion_radio_metros" {
  type    = number
  default = 5000
}

variable "asignacion_velocidad_kmh" {
  description = "Velocidad media del repartidor en ciudad, para estimar cuando llega al comercio y compararlo con el tiempo de preparacion."
  type        = number
  default     = 20

  validation {
    condition     = var.asignacion_velocidad_kmh >= 5 && var.asignacion_velocidad_kmh <= 80
    error_message = "asignacion_velocidad_kmh tiene que estar entre 5 y 80."
  }
}

variable "asignacion_timeout_segundos" {
  type    = number
  default = 60
}

variable "asignacion_espera_segundos" {
  description = "Segundos que se sigue buscando repartidor cuando no hay ninguno cerca, antes de cancelar el pedido."
  type        = number
  default     = 300

  validation {
    condition     = var.asignacion_espera_segundos >= 0 && var.asignacion_espera_segundos <= 1800
    error_message = "asignacion_espera_segundos tiene que estar entre 0 y 1800."
  }
}

variable "alerta_email" {
  description = "Email que recibe las alarmas. Vacio = sin suscripcion."
  type        = string
  default     = ""

  validation {
    condition     = var.alerta_email == "" || can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alerta_email))
    error_message = "alerta_email tiene que ser un email valido o quedar vacio."
  }
}


variable "cors_origenes" {
  description = "Origenes del frontend que pueden llamar a la API y subir comprobantes a S3."
  type        = list(string)
  default     = ["http://localhost:5173"]

  validation {
    condition     = alltrue([for o in var.cors_origenes : can(regex("^https?://[^/*]+$", o))])
    error_message = "Cada origen es esquema + host (+ puerto), sin comodines ni barra final. Ej: http://localhost:5173."
  }
}

variable "cargar_datos_demo" {
  description = "Carga comercios y productos de prueba en la migracion."
  type        = bool
  default     = true
}

variable "usuarios_demo" {
  description = "Usuarios de prueba (email => grupo) que se crean ya confirmados y con contrasena permanente."
  type        = map(string)
  default = {
    "cliente.demo@example.com"     = "cliente"
    "repartidor.demo@example.com"  = "repartidor"
    "repartidor2.demo@example.com" = "repartidor"
  }

  validation {
    condition     = alltrue([for g in values(var.usuarios_demo) : contains(["cliente", "repartidor"], g)])
    error_message = "El grupo tiene que ser cliente o repartidor."
  }
}

variable "escalado" {
  description = <<-EOT
    Escalado del stream de posiciones. Cada franja tiene un cron de inicio (sube a
    shards_pico) y uno de fin (baja un paso hacia shards_minimo; conviene que se
    dispare varias veces, porque Kinesis solo divide a la mitad por llamada).
    Los cron se interpretan en zona_horaria. La alarma de escrituras rechazadas
    duplica los shards hasta shards_maximo.
  EOT
  type = object({
    habilitado    = bool
    zona_horaria  = string
    shards_minimo = number
    shards_pico   = number
    shards_maximo = number
    franjas = map(object({
      inicio = string
      fin    = string
    }))
  })
  default = {
    habilitado    = true
    zona_horaria  = "America/Argentina/Buenos_Aires"
    shards_minimo = 1
    shards_pico   = 2
    shards_maximo = 4
    franjas = {
      almuerzo = {
        inicio = "cron(30 11 * * ? *)"
        fin    = "cron(30 14-16 * * ? *)" # 14:30, 15:30 y 16:30
      }
      cena = {
        inicio = "cron(30 19 * * ? *)"
        fin    = "cron(0 23,0,1 * * ? *)" # 23:00, 00:00 y 01:00
      }
    }
  }

  validation {
    condition = (
      var.escalado.shards_minimo >= 1 &&
      var.escalado.shards_minimo <= var.escalado.shards_pico &&
      var.escalado.shards_pico <= var.escalado.shards_maximo
    )
    error_message = "Los shards van en orden: 1 <= shards_minimo <= shards_pico <= shards_maximo."
  }

  validation {
    condition     = var.escalado.shards_pico <= 2 * var.escalado.shards_minimo
    error_message = "Kinesis solo duplica por llamada: shards_pico no puede superar 2 * shards_minimo."
  }

  validation {
    condition     = var.escalado.shards_maximo <= 2 * var.escalado.shards_pico
    error_message = "shards_maximo no puede superar 2 * shards_pico: con mas pasos se agota el cupo de 10 cambios diarios de Kinesis."
  }

  validation {
    condition = alltrue(flatten([for f in values(var.escalado.franjas) :
    [startswith(f.inicio, "cron("), startswith(f.fin, "cron(")]]))
    error_message = "Los horarios tienen el formato de AWS: cron(min hora dia mes dia-semana anio)."
  }
}

variable "athena_limite_escaneo_mb" {
  description = "Tope de datos que puede escanear una consulta del workgroup de Athena (MB). Control de costo: Athena cobra por dato leido."
  type        = number
  default     = 1024

  validation {
    condition     = var.athena_limite_escaneo_mb >= 10
    error_message = "Athena exige un tope de al menos 10 MB."
  }
}
