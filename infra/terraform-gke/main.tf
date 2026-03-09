# GKE Infrastructure
# Creates a GKE cluster for deploying the Spring Boot app

terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Backend configuration - use backend.hcl for POV-specific state
  # terraform init -backend-config=../backend-gke.hcl
  backend "gcs" {}
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# =============================================================================
# VPC Network
# =============================================================================
resource "google_compute_network" "vpc" {
  name                    = "${var.project_name}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${var.project_name}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.gcp_region
  network       = google_compute_network.vpc.id

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }
}

# =============================================================================
# GKE Cluster
# =============================================================================
resource "google_container_cluster" "primary" {
  name     = var.project_name
  location = var.gcp_zone != "" ? var.gcp_zone : var.gcp_region

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Enable Workload Identity for secure pod authentication
  workload_identity_config {
    workload_pool = "${var.gcp_project_id}.svc.id.goog"
  }

  # Logging and monitoring
  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  resource_labels = {
    project     = var.project_name
    environment = var.environment
    owner       = var.owner
    managed-by  = "terraform"
  }
}

# =============================================================================
# Node Pool
# =============================================================================
resource "google_container_node_pool" "primary_nodes" {
  name       = "${var.project_name}-node-pool"
  location   = var.gcp_zone != "" ? var.gcp_zone : var.gcp_region
  cluster    = google_container_cluster.primary.name
  node_count = var.node_count

  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }

  node_config {
    preemptible  = var.preemptible
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb

    # Google recommends custom service accounts with minimal permissions
    service_account = google_service_account.gke_nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      project     = var.project_name
      environment = var.environment
      owner       = var.owner
    }

    tags = ["gke-node", var.project_name]

    # Enable Workload Identity on nodes
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }
}

# =============================================================================
# Service Account for GKE Nodes
# =============================================================================
resource "google_service_account" "gke_nodes" {
  account_id   = "${var.project_name}-gke-nodes"
  display_name = "GKE Nodes Service Account for ${var.project_name}"
}

# Grant necessary permissions to node service account
resource "google_project_iam_member" "gke_nodes_log_writer" {
  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_metric_writer" {
  project = var.gcp_project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_artifact_reader" {
  project = var.gcp_project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
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
  }
}
