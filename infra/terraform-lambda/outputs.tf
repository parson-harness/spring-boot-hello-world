output "ecr_repository_url" {
  description = "ECR repository URL for Lambda container images"
  value       = aws_ecr_repository.app.repository_url
}

output "ecr_repository_name" {
  description = "ECR repository name"
  value       = aws_ecr_repository.app.name
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = var.create_lambda ? aws_lambda_function.app[0].function_name : null
}

output "lambda_function_arn" {
  description = "Lambda function ARN"
  value       = var.create_lambda ? aws_lambda_function.app[0].arn : null
}

output "lambda_alias_name" {
  description = "Lambda alias name for deployments"
  value       = var.create_lambda ? aws_lambda_alias.live[0].name : null
}

output "lambda_function_url" {
  description = "Lambda function URL (public endpoint)"
  value       = var.create_lambda ? aws_lambda_function_url.app[0].function_url : null
}

output "lambda_role_arn" {
  description = "Lambda execution role ARN"
  value       = aws_iam_role.lambda_role.arn
}
