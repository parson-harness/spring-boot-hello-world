# GCP Bootstrap - Creates GCS bucket for Terraform state
# This is the GCP equivalent of terraform-bootstrap (which creates S3/DynamoDB for AWS)

terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Bootstrap uses local state - this is the only module that does
  # All other modules will use the GCS bucket created here
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# Enable required APIs
resource "google_project_service" "storage" {
  service            = "storage.googleapis.com"
  disable_on_destroy = false
}

# =============================================================================
# GCS Bucket for Terraform State
# =============================================================================
resource "google_storage_bucket" "terraform_state" {
  name     = "${var.gcp_project_id}-${var.project_name}-tfstate"
  location = var.gcp_region

  # Prevent accidental deletion
  force_destroy = false

  # Enable versioning for state history
  versioning {
    enabled = true
  }

  # Lifecycle rule to clean up old versions (optional, keeps costs down)
  lifecycle_rule {
    condition {
      num_newer_versions = 5
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  # Uniform bucket-level access (recommended)
  uniform_bucket_level_access = true

  labels = {
    project     = var.project_name
    environment = var.environment
    purpose     = "terraform-state"
    managed-by  = "terraform"
  }

  depends_on = [google_project_service.storage]
}

# =============================================================================
# IAM - Grant access to the state bucket
# =============================================================================
# If you want to grant specific service accounts access to the state bucket,
# uncomment and modify the following:

# resource "google_storage_bucket_iam_member" "terraform_state_admin" {
#   bucket = google_storage_bucket.terraform_state.name
#   role   = "roles/storage.objectAdmin"
#   member = "serviceAccount:${var.terraform_service_account}"
# }
