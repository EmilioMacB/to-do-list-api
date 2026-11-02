output "public_ip" {
  description = "Dirección IP publica de la instancia EC2"
  value       = aws_instance.todo_api.public_ip
}