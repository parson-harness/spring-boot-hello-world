variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "app_name" {
  description = "Application name"
  type        = string
  default     = "spring-boot-hello-world"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Owner of the resources (SE last name for POVs)"
  type        = string
  default     = "unknown"
}

variable "create_lambda" {
  description = "Whether to create the Lambda function. Set to false on first run to create ECR first, push image, then set to true."
  type        = bool
  default     = true
}

variable "image_tag" {
  description = "Container image tag to deploy"
  type        = string
  default     = "latest"
}
