# =============================================================================
# GCP Configuration
# =============================================================================
variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "GCP zone (optional - if set, creates a zonal cluster instead of regional)"
  type        = string
  default     = ""
}

# =============================================================================
# Project Configuration
# =============================================================================
variable "project_name" {
  description = "Project name (used for cluster name, registry, tags)"
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
# Network Configuration
# =============================================================================
variable "subnet_cidr" {
  description = "CIDR range for the subnet"
  type        = string
  default     = "10.0.0.0/24"
}

variable "pods_cidr" {
  description = "Secondary CIDR range for pods"
  type        = string
  default     = "10.1.0.0/16"
}

variable "services_cidr" {
  description = "Secondary CIDR range for services"
  type        = string
  default     = "10.2.0.0/20"
}

# =============================================================================
# GKE Cluster Configuration
# =============================================================================
variable "machine_type" {
  description = "Machine type for GKE nodes"
  type        = string
  default     = "e2-medium"
}

variable "node_count" {
  description = "Initial number of nodes per zone"
  type        = number
  default     = 1
}

variable "min_node_count" {
  description = "Minimum number of nodes per zone (autoscaling)"
  type        = number
  default     = 1
}

variable "max_node_count" {
  description = "Maximum number of nodes per zone (autoscaling)"
  type        = number
  default     = 3
}

variable "disk_size_gb" {
  description = "Disk size for nodes in GB"
  type        = number
  default     = 50
}

variable "preemptible" {
  description = "Use preemptible (spot) VMs for cost savings"
  type        = bool
  default     = true
}
