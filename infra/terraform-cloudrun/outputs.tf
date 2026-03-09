# =============================================================================
# Artifact Registry Outputs
# =============================================================================
output "artifact_registry_url" {
  description = "Artifact Registry URL for Docker images"
  value       = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.app.repository_id}"
}

output "artifact_registry_repository" {
  description = "Artifact Registry repository name"
  value       = google_artifact_registry_repository.app.repository_id
}

output "docker_push_command" {
  description = "Command to push an image to the registry"
  value       = "docker push ${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.app.repository_id}/${var.project_name}:TAG"
}

# =============================================================================
# Cloud Run Outputs
# =============================================================================
output "service_url" {
  description = "Cloud Run service URL"
  value       = var.create_service ? google_cloud_run_v2_service.app[0].uri : "Service not created yet - set create_service=true after pushing an image"
}

output "service_name" {
  description = "Cloud Run service name"
  value       = var.project_name
}

output "service_account_email" {
  description = "Service account used by Cloud Run"
  value       = google_service_account.cloudrun.email
}

# =============================================================================
# Harness Configuration
# =============================================================================
output "harness_config" {
  description = "Configuration values for Harness Cloud Run deployment"
  value = {
    gcp_project     = var.gcp_project_id
    gcp_region      = var.gcp_region
    service_name    = var.project_name
    registry_url    = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.app.repository_id}"
    image_path      = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.app.repository_id}/${var.project_name}"
    service_account = google_service_account.cloudrun.email
  }
}
