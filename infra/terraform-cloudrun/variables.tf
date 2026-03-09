# =============================================================================
# GCP Configuration
# =============================================================================
variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region for Cloud Run"
  type        = string
  default     = "us-central1"
}

# =============================================================================
# Project Configuration
# =============================================================================
variable "project_name" {
  description = "Project name (used for service name, registry, tags)"
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
# Cloud Run Configuration
# =============================================================================
variable "create_service" {
  description = "Whether to create the Cloud Run service (set false on first run before image exists)"
  type        = bool
  default     = false
}

variable "image_tag" {
  description = "Container image tag to deploy"
  type        = string
  default     = "latest"
}

variable "cpu" {
  description = "CPU allocation (e.g., '1' or '2')"
  type        = string
  default     = "1"
}

variable "memory" {
  description = "Memory allocation (e.g., '512Mi' or '1Gi')"
  type        = string
  default     = "512Mi"
}

variable "min_instances" {
  description = "Minimum number of instances (0 allows scale to zero)"
  type        = number
  default     = 0
}

variable "max_instances" {
  description = "Maximum number of instances"
  type        = number
  default     = 10
}

variable "allow_unauthenticated" {
  description = "Allow unauthenticated access to the service (for POV/demo)"
  type        = bool
  default     = true
}
