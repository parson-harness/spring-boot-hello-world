# =============================================================================
# Harness Platform Configuration
# =============================================================================

variable "harness_endpoint" {
  description = "Harness Platform API endpoint"
  type        = string
  default     = "https://app.harness.io/gateway"
}

variable "harness_account_id" {
  description = "Harness Account ID"
  type        = string
}

variable "harness_api_key" {
  description = "Harness Platform API Key (PAT or SAT)"
  type        = string
  sensitive   = true
}

variable "org_identifier" {
  description = "Harness Organization identifier"
  type        = string
  default     = "default"
}

variable "project_identifier" {
  description = "Harness Project identifier (used if create_project is false)"
  type        = string
  default     = "spring_boot_pov"
}

variable "project_name" {
  description = "Harness Project name and AWS resource prefix"
  type        = string
  default     = "spring-boot-hello-world"
}

variable "create_project" {
  description = "Whether to create a new Harness project"
  type        = bool
  default     = false
}

# =============================================================================
# Environment Configuration
# =============================================================================

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region for deployments"
  type        = string
  default     = "us-east-1"
}

variable "k8s_namespace" {
  description = "Kubernetes namespace for deployments"
  type        = string
  default     = "default"
}

# =============================================================================
# Deployment Type Toggles
# =============================================================================

variable "enable_asg" {
  description = "Enable ASG deployment resources"
  type        = bool
  default     = true
}

variable "enable_lambda" {
  description = "Enable Lambda deployment resources"
  type        = bool
  default     = true
}

variable "enable_eks" {
  description = "Enable EKS/Kubernetes deployment resources"
  type        = bool
  default     = true
}

# =============================================================================
# AWS Connector Configuration
# =============================================================================

variable "aws_connector_type" {
  description = "AWS connector credential type: 'irsa' (inherit from delegate) or 'manual' (access keys)"
  type        = string
  default     = "irsa"
  validation {
    condition     = contains(["irsa", "manual"], var.aws_connector_type)
    error_message = "aws_connector_type must be 'irsa' or 'manual'"
  }
}

variable "delegate_selectors" {
  description = "Delegate selectors for connectors"
  type        = list(string)
  default     = ["harness-delegate"]
}

variable "aws_access_key_secret_ref" {
  description = "Harness secret reference for AWS access key (only for manual connector type)"
  type        = string
  default     = ""
}

variable "aws_secret_key_secret_ref" {
  description = "Harness secret reference for AWS secret key (only for manual connector type)"
  type        = string
  default     = ""
}

# =============================================================================
# GitHub Configuration (for manifest storage)
# =============================================================================

variable "github_connector_ref" {
  description = "Harness GitHub connector reference for manifest storage"
  type        = string
  default     = "account.github"
}

variable "github_repo" {
  description = "GitHub repository name (org/repo format)"
  type        = string
  default     = "parson-harness/spring-boot-hello-world"
}
