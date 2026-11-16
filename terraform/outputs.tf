output "instance_id" {
  description = "ID de la EC2 (lo usa el workflow de deploy vía SSM)"
  value       = aws_instance.todo_api.id
}

output "public_ip" {
  description = "IP pública de la EC2"
  value       = aws_instance.todo_api.public_ip
}

output "api_url" {
  description = "URL base de la API"
  value       = "http://${aws_instance.todo_api.public_ip}:${var.app_port}"
}

output "rds_endpoint" {
  description = "Endpoint de RDS (privado, solo accesible desde la EC2)"
  value       = aws_db_instance.todo_db.address
}

output "rds_identifier" {
  description = "Identificador de RDS (para métricas nativas y para detenerla en pruebas)"
  value       = aws_db_instance.todo_db.identifier
}

output "db_secret_name" {
  description = "Nombre del secret con las credenciales"
  value       = aws_secretsmanager_secret.db.name
}

output "ssh_private_key" {
  description = "Llave privada para SSH de emergencia: terraform output -raw ssh_private_key > key.pem"
  value       = tls_private_key.ssh.private_key_pem
  sensitive   = true
}
