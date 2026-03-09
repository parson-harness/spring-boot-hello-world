# Cloud Run Infrastructure
# Creates the necessary GCP resources for deploying the Spring Boot app to Cloud Run

terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Backend configuration - use GCS for state
  # terraform init -backend-config="bucket=your-state-bucket" -backend-config="prefix=terraform/cloudrun"
  backend "gcs" {}
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# Enable required APIs
resource "google_project_service" "run" {
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "artifactregistry" {
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudbuild" {
  service            = "cloudbuild.googleapis.com"
  disable_on_destroy = false
}

# =============================================================================
# Artifact Registry (GCP's container registry)
# =============================================================================
resource "google_artifact_registry_repository" "app" {
  location      = var.gcp_region
  repository_id = var.project_name
  description   = "Docker repository for ${var.project_name}"
  format        = "DOCKER"

  labels = {
    project     = var.project_name
    environment = var.environment
    owner       = var.owner
    managed-by  = "terraform"
  }

  depends_on = [google_project_service.artifactregistry]
}

# =============================================================================
# Service Account for Cloud Run
# =============================================================================
resource "google_service_account" "cloudrun" {
  account_id   = "${var.project_name}-cloudrun"
  display_name = "Cloud Run Service Account for ${var.project_name}"
}

# Grant the service account permission to pull from Artifact Registry
resource "google_project_iam_member" "cloudrun_artifactregistry" {
  project = var.gcp_project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.cloudrun.email}"
}

# Grant Cloud Run invoker permission for public access (if enabled)
resource "google_project_iam_member" "cloudrun_invoker" {
  count   = var.allow_unauthenticated ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/run.invoker"
  member  = "allUsers"
}

# =============================================================================
# Cloud Run Service
# =============================================================================
resource "google_cloud_run_v2_service" "app" {
  count    = var.create_service ? 1 : 0
  name     = var.project_name
  location = var.gcp_region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.cloudrun.email

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    containers {
      image = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.app.repository_id}/${var.project_name}:${var.image_tag}"

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
      }

      env {
        name  = "SPRING_PROFILES_ACTIVE"
        value = var.environment
      }

      # Health check / startup probe
      startup_probe {
        http_get {
          path = "/actuator/health"
          port = 8080
        }
        initial_delay_seconds = 10
        period_seconds        = 10
        failure_threshold     = 3
      }

      liveness_probe {
        http_get {
          path = "/actuator/health"
          port = 8080
        }
        period_seconds = 30
      }
    }

    # Traffic management labels for Harness
    labels = {
      project     = var.project_name
      environment = var.environment
      owner       = var.owner
    }
  }

  # Traffic splitting for canary deployments
  # Harness will manage this during deployments
  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  labels = {
    project     = var.project_name
    environment = var.environment
    owner       = var.owner
    managed-by  = "terraform"
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      traffic
    ]
  }

  depends_on = [
    google_project_service.run,
    google_artifact_registry_repository.app
  ]
}

# =============================================================================
# IAM - Allow unauthenticated access (for POV/demo)
# =============================================================================
resource "google_cloud_run_v2_service_iam_member" "public" {
  count    = var.create_service && var.allow_unauthenticated ? 1 : 0
  location = google_cloud_run_v2_service.app[0].location
  name     = google_cloud_run_v2_service.app[0].name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
