# =============================================================================
# GCP Configuration
# =============================================================================
variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region for the state bucket"
  type        = string
  default     = "us-central1"
}

# =============================================================================
# Project Configuration
# =============================================================================
variable "project_name" {
  description = "Project name (used in bucket naming)"
  type        = string
  default     = "harness-pov"
}

variable "environment" {
  description = "Environment name (used for labeling)"
  type        = string
  default     = "pov"
}
