variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name (used for cluster name, ECR repo, tags)"
  type        = string
  default     = "spring-boot-hello-world"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Owner of the resources (SE last name)"
  type        = string
  default     = "unknown"
}

# =============================================================================
# EKS Configuration
# =============================================================================

variable "instance_type" {
  description = "EC2 instance type for EKS nodes"
  type        = string
  default     = "t3.large"
}

variable "min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 0
}

variable "desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 3
}

variable "delegate_namespace" {
  description = "Kubernetes namespace for Harness delegate"
  type        = string
  default     = "harness-delegate-ng"
}

variable "delegate_service_account" {
  description = "Kubernetes service account for Harness delegate"
  type        = string
  default     = "harness-delegate"
}
