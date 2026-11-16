variable "aws_region" {
  description = "Región de AWS (Learner Lab usa us-east-1)"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefijo para nombrar y etiquetar todos los recursos"
  type        = string
  default     = "todo-api"
}

variable "repo_url" {
  description = "Repositorio que user_data clona al arrancar la EC2"
  type        = string
  default     = "https://github.com/EmilioMacB/to-do-list-api.git"
}

variable "instance_type" {
  description = "Tipo de instancia EC2"
  type        = string
  default     = "t2.micro"
}

variable "instance_profile_name" {
  description = "Instance profile preexistente del Learner Lab (no se pueden crear roles IAM)"
  type        = string
  default     = "LabInstanceProfile"
}

variable "app_port" {
  description = "Puerto en el que escucha la API"
  type        = number
  default     = 8000
}

variable "allowed_ssh_cidr" {
  description = "CIDR con acceso SSH (solo depuración). Ideal: tu IP/32"
  type        = string
  default     = "0.0.0.0/0"
}

variable "db_instance_class" {
  description = "Clase de la instancia RDS"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Nombre de la base de datos"
  type        = string
  default     = "tododb"
}

variable "db_username" {
  description = "Usuario administrador de RDS"
  type        = string
  default     = "todo_admin"
}

variable "db_secret_name" {
  description = "Nombre del secret en Secrets Manager con las credenciales de RDS"
  type        = string
  default     = "todo-api/db-credentials"
}
