terraform {
  required_providers {
    harness = {
      source  = "harness/harness"
      version = ">= 0.33.0"
    }
  }
}

provider "harness" {
  # Reads from env:
  # HARNESS_ACCOUNT_ID, HARNESS_ORG_ID, HARNESS_PROJECT_ID (optional),
  # HARNESS_PLATFORM_API_KEY
  endpoint = "https://app.harness.io/gateway"
}

resource "harness_platform_service" "svc" {
  org_id      = var.org_id
  project_id  = var.project_id
  identifier  = var.service_id
  name        = var.service_name
  description = var.description

  yaml = <<-YAML
    service:
      name: ${var.service_name}
      identifier: ${var.service_id}
      orgIdentifier: ${var.org_id}
      projectIdentifier: ${var.project_id}
      serviceDefinition:
        type: Kubernetes
        spec:
          artifacts:
            primary:
              primaryArtifactRef: <+input>
              sources:
                - spec:
                    connectorRef: ${var.docker_connector_ref}
                    imagePath: ${var.image_repo}/${var.image_name}
                    tag: ${var.image_tag}
                    digest: ""
                  identifier: ${var.service_id}
                  type: DockerRegistry
          manifests:
            - manifest:
                identifier: manifest
                type: K8sManifest
                spec:
                  store:
                    type: Github
                    spec:
                      connectorRef: ${var.connector_ref}
                      gitFetchType: Branch
                      paths:
                        - infra/kubernetes/deployment.yml
                        - infra/kubernetes/service.yml
                        - infra/kubernetes/servicemonitor.yml
                      repoName: ${var.repo_name}
                      branch: main
                  valuesPaths:
                    - infra/kubernetes/values.yml
                  skipResourceVersioning: false
                  enableDeclarativeRollback: false
                  optionalValuesYaml: false
      gitOpsEnabled: false
  YAML
}