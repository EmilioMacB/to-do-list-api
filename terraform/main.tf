terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Backend remoto: el tfstate vive en S3, nunca en el repo.
  # El nombre del bucket NO va aquí (depende del Account ID del lab); se pasa en init:
  #   terraform init -backend-config="bucket=<tu-bucket>"
  backend "s3" {
    key          = "todo-list-api/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true # Lock nativo de S3 (Terraform >= 1.10), evita applies simultáneos
  }
}

provider "aws" {
  region = var.aws_region

  # Etiquetas automáticas en todos los recursos (útil para identificar/filtrar)
  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}

# ---------------------------------------------------------------------------
# Datos de apoyo
# ---------------------------------------------------------------------------

# AMI más reciente de Ubuntu 24.04 LTS (trae Python 3.12 y el agente SSM)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

# ---------------------------------------------------------------------------
# Key Pair (generado por Terraform)
# ---------------------------------------------------------------------------

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "todo_key" {
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.ssh.public_key_openssh
}

# ---------------------------------------------------------------------------
# Credenciales de la base de datos -> Secrets Manager
# ---------------------------------------------------------------------------

# Password aleatorio: nunca se escribe en el código.
# RDS no acepta '/', '@', '"' ni espacios, por eso limitamos los especiales.
resource "random_password" "db" {
  length           = 24
  special          = true
  override_special = "!#$%^&*()-_=+"
}

resource "aws_secretsmanager_secret" "db" {
  name        = var.db_secret_name
  description = "Credenciales de RDS para ${var.project_name}"

  # 0 = borrado inmediato al hacer destroy. Sin esto, el nombre queda "reservado"
  # 7-30 días y el siguiente apply fallaría (pasa seguido en el Learner Lab).
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    host     = aws_db_instance.todo_db.address
    port     = aws_db_instance.todo_db.port
    dbname   = var.db_name
  })
}

# ---------------------------------------------------------------------------
# Security Groups
# ---------------------------------------------------------------------------

resource "aws_security_group" "api_sg" {
  name        = "${var.project_name}-api-sg"
  description = "Trafico HTTP a la API y SSH de emergencia"

  ingress {
    description = "API"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH (solo depuracion; el despliegue no lo usa)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "PostgreSQL solo desde la EC2 de la API"

  ingress {
    description     = "PostgreSQL desde la API"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.api_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------------------------------------------------------------------
# RDS PostgreSQL
# ---------------------------------------------------------------------------

resource "aws_db_instance" "todo_db" {
  identifier             = "${var.project_name}-db"
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = var.db_instance_class
  allocated_storage      = 20
  db_name                = var.db_name
  username               = var.db_username
  password               = random_password.db.result
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
  deletion_protection    = false
  apply_immediately      = true
}

# ---------------------------------------------------------------------------
# EC2 de la API
# ---------------------------------------------------------------------------

resource "aws_instance" "todo_api" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.todo_key.key_name
  vpc_security_group_ids = [aws_security_group.api_sg.id]

  # Learner Lab no permite crear roles IAM: usamos el perfil que ya existe.
  # Le da permisos a la app para leer Secrets Manager y publicar métricas en CloudWatch.
  iam_instance_profile = var.instance_profile_name

  # El script recibe solo el NOMBRE del secret, nunca el password.
  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    repo_url    = var.repo_url
    app_port    = var.app_port
    aws_region  = var.aws_region
    secret_name = aws_secretsmanager_secret.db.name
  })

  # Si cambia el script, recrear la instancia para que se vuelva a ejecutar
  user_data_replace_on_change = true

  # Sin depends_on hacia RDS: la EC2 se crea en paralelo (apply más rápido).
  # La app lee el secret de forma perezosa y reintenta; /health dará FAIL
  # hasta que RDS esté lista, y systemd la reinicia si se cae.

  tags = {
    Name = "${var.project_name}-server"
  }
}
