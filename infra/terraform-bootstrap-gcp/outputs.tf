# =============================================================================
# State Bucket Outputs
# =============================================================================
output "state_bucket_name" {
  description = "GCS bucket name for Terraform state"
  value       = google_storage_bucket.terraform_state.name
}

output "state_bucket_url" {
  description = "GCS bucket URL"
  value       = google_storage_bucket.terraform_state.url
}

# =============================================================================
# Backend Configuration
# =============================================================================
output "backend_config" {
  description = "Backend configuration for other Terraform modules"
  value = {
    bucket = google_storage_bucket.terraform_state.name
    prefix = "terraform/state"
  }
}

output "backend_config_command" {
  description = "Command to initialize other modules with this backend"
  value       = "terraform init -backend-config=\"bucket=${google_storage_bucket.terraform_state.name}\" -backend-config=\"prefix=terraform/state/MODULE_NAME\""
}

# =============================================================================
# Harness Pipeline Variables
# =============================================================================
output "harness_pipeline_vars" {
  description = "Variables to use in Harness IaC pipelines"
  value = {
    tf_state_bucket = google_storage_bucket.terraform_state.name
    gcp_project     = var.gcp_project_id
    gcp_region      = var.gcp_region
  }
}
