output "rds_endpoint" {
  value = aws_db_instance.main.address
}

output "rds_secret_arn" {
  value = aws_secretsmanager_secret.rds.arn
}

output "db_name" {
  value = aws_db_instance.main.db_name
}