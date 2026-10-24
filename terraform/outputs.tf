output "queue_url_parameter" {
  description = "Parameter Store name holding the queue URL."
  value       = aws_ssm_parameter.queue_url.name
}

output "output_bucket_parameter" {
  description = "Parameter Store name holding the output bucket."
  value       = aws_ssm_parameter.output_bucket.name
}

output "db_secret_name" {
  description = "Secrets Manager secret holding the database credentials."
  value       = aws_secretsmanager_secret.db.name
}

output "eso_role_arn" {
  description = "IAM role the External Secrets Operator uses through Pod Identity."
  value       = aws_iam_role.eso.arn
}

output "transcoder_role_arn" {
  description = "IAM role the transcoder uses through Pod Identity."
  value       = aws_iam_role.transcoder.arn
}
