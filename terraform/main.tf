terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1" 
}

# 1. Crear el Security Group
resource "aws_security_group" "todo_sg" {
  name        = "todo_api_sg"
  description = "Permitir trafico SSH y acceso al puerto 3000"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Obtener la AMI más reciente de Ubuntu
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # ID oficial de Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# 2. Crear la instancia EC2
resource "aws_instance" "todo_api" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.todo_sg.id]
  
  # IMPORTANTE: Reemplaza "vockey" con el nombre de la llave SSH (Key Pair) que tengas en tu cuenta de AWS.
  key_name               = "vockey" 

  # 3. Script user_data para instalar dependencias, clonar y arrancar la API
  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y git curl
              
              # Instalar Node.js versión 20
              curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
              apt-get install -y nodejs
              
              # Clonar el repositorio
              git clone https://github.com/EmilioMacB/to-do-list-api.git /home/ubuntu/to-do-list-api
              cd /home/ubuntu/to-do-list-api
              
              # Instalar librerías y compilar TypeScript
              npm install
              npm run build
              
              # Ejecutar el servidor en segundo plano
              nohup npm run start > app.log 2>&1 &
              EOF

  tags = {
    Name = "ToDo-API-Server"
  }
}