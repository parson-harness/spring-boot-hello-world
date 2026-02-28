variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
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

variable "delegate_name" {
  description = "Name of the Harness delegate"
  type        = string
  default     = "harness-delegate"
}

variable "delegate_namespace" {
  description = "Kubernetes namespace where delegate runs (for IRSA)"
  type        = string
  default     = "harness-delegate-ng"
}

variable "delegate_service_account" {
  description = "Kubernetes service account name for delegate (for IRSA)"
  type        = string
  default     = "harness-delegate-sa"
}

# =============================================================================
# EKS Configuration (optional - for IRSA)
# =============================================================================

variable "eks_cluster_name" {
  description = "EKS cluster name where delegate runs. Leave empty if not using EKS."
  type        = string
  default     = ""
}

# =============================================================================
# EC2 Configuration (optional - for Docker delegate on EC2)
# =============================================================================

variable "enable_ec2_assume" {
  description = "Enable EC2 instance profile for Docker delegate on EC2"
  type        = bool
  default     = false
}

# =============================================================================
# Deployment Type Permissions (enable based on what you're deploying)
# =============================================================================

variable "enable_asg_permissions" {
  description = "Enable IAM permissions for ASG deployments"
  type        = bool
  default     = true
}

variable "enable_lambda_permissions" {
  description = "Enable IAM permissions for Lambda deployments"
  type        = bool
  default     = true
}

variable "enable_eks_permissions" {
  description = "Enable IAM permissions for EKS deployments"
  type        = bool
  default     = true
}

variable "enable_s3_permissions" {
  description = "Enable IAM permissions for S3 artifact access"
  type        = bool
  default     = true
}
