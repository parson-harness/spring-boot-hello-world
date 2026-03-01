# Harness Entity Provisioning
# Creates all Harness resources needed for the POV demo

terraform {
  required_version = ">= 1.0"

  required_providers {
    harness = {
      source  = "harness/harness"
      version = "~> 0.30"
    }
  }
}

# =============================================================================
# Provider Configuration
# =============================================================================
provider "harness" {
  endpoint         = var.harness_endpoint
  account_id       = var.harness_account_id
  platform_api_key = var.harness_api_key
}

# =============================================================================
# Project (optional - use existing or create new)
# =============================================================================
resource "harness_platform_project" "demo" {
  count       = var.create_project ? 1 : 0
  identifier  = var.project_identifier
  name        = var.project_name
  org_id      = var.org_identifier
  description = "Spring Boot Hello World POV Demo"
  color       = "#0063F7"
}

locals {
  project_id = var.create_project ? harness_platform_project.demo[0].identifier : var.project_identifier
}

# =============================================================================
# AWS Cloud Provider Connector
# =============================================================================
resource "harness_platform_connector_aws" "aws" {
  identifier  = "aws_${var.environment}"
  name        = "AWS ${title(var.environment)}"
  description = "AWS connector for ${var.environment} deployments"
  org_id      = var.org_identifier
  project_id  = local.project_id
  tags        = ["pov", var.environment]

  # Use IRSA if delegate is in EKS, otherwise use IAM role
  dynamic "inherit_from_delegate" {
    for_each = var.aws_connector_type == "irsa" ? [1] : []
    content {
      delegate_selectors = var.delegate_selectors
    }
  }

  dynamic "manual" {
    for_each = var.aws_connector_type == "manual" ? [1] : []
    content {
      access_key_ref     = var.aws_access_key_secret_ref
      secret_key_ref     = var.aws_secret_key_secret_ref
      delegate_selectors = var.delegate_selectors
    }
  }
}

# =============================================================================
# Kubernetes Connector (for EKS deployments)
# =============================================================================
resource "harness_platform_connector_kubernetes" "eks" {
  count       = var.enable_eks ? 1 : 0
  identifier  = "eks_${var.environment}"
  name        = "EKS ${title(var.environment)}"
  description = "EKS cluster for ${var.environment} deployments"
  org_id      = var.org_identifier
  project_id  = local.project_id
  tags        = ["pov", var.environment, "eks"]

  inherit_from_delegate {
    delegate_selectors = var.delegate_selectors
  }
}

# =============================================================================
# Environment
# =============================================================================
resource "harness_platform_environment" "env" {
  identifier  = var.environment
  name        = title(var.environment)
  org_id      = var.org_identifier
  project_id  = local.project_id
  description = "${title(var.environment)} environment for POV"
  type        = var.environment == "prod" ? "Production" : "PreProduction"
  tags        = ["pov", var.environment]

  yaml = <<-EOT
    environment:
      name: ${title(var.environment)}
      identifier: ${var.environment}
      type: ${var.environment == "prod" ? "Production" : "PreProduction"}
      orgIdentifier: ${var.org_identifier}
      projectIdentifier: ${local.project_id}
  EOT
}

# =============================================================================
# Infrastructure Definitions
# =============================================================================

# ASG Infrastructure
resource "harness_platform_infrastructure" "asg" {
  count             = var.enable_asg ? 1 : 0
  identifier        = "asg_${var.environment}"
  name              = "ASG ${title(var.environment)}"
  org_id            = var.org_identifier
  project_id        = local.project_id
  env_id            = harness_platform_environment.env.identifier
  type              = "Asg"
  deployment_type   = "Asg"
  
  yaml = <<-EOT
    infrastructureDefinition:
      name: ASG ${title(var.environment)}
      identifier: asg_${var.environment}
      orgIdentifier: ${var.org_identifier}
      projectIdentifier: ${local.project_id}
      environmentRef: ${var.environment}
      type: Asg
      spec:
        connectorRef: ${harness_platform_connector_aws.aws.identifier}
        region: ${var.aws_region}
  EOT
}

# Lambda Infrastructure
resource "harness_platform_infrastructure" "lambda" {
  count             = var.enable_lambda ? 1 : 0
  identifier        = "lambda_${var.environment}"
  name              = "Lambda ${title(var.environment)}"
  org_id            = var.org_identifier
  project_id        = local.project_id
  env_id            = harness_platform_environment.env.identifier
  type              = "AwsLambda"
  deployment_type   = "AwsLambda"
  
  yaml = <<-EOT
    infrastructureDefinition:
      name: Lambda ${title(var.environment)}
      identifier: lambda_${var.environment}
      orgIdentifier: ${var.org_identifier}
      projectIdentifier: ${local.project_id}
      environmentRef: ${var.environment}
      type: AwsLambda
      spec:
        connectorRef: ${harness_platform_connector_aws.aws.identifier}
        region: ${var.aws_region}
  EOT
}

# Kubernetes Infrastructure
resource "harness_platform_infrastructure" "k8s" {
  count             = var.enable_eks ? 1 : 0
  identifier        = "k8s_${var.environment}"
  name              = "K8s ${title(var.environment)}"
  org_id            = var.org_identifier
  project_id        = local.project_id
  env_id            = harness_platform_environment.env.identifier
  type              = "KubernetesDirect"
  deployment_type   = "Kubernetes"
  
  yaml = <<-EOT
    infrastructureDefinition:
      name: K8s ${title(var.environment)}
      identifier: k8s_${var.environment}
      orgIdentifier: ${var.org_identifier}
      projectIdentifier: ${local.project_id}
      environmentRef: ${var.environment}
      type: KubernetesDirect
      spec:
        connectorRef: ${harness_platform_connector_kubernetes.eks[0].identifier}
        namespace: ${var.k8s_namespace}
        releaseName: release-<+INFRA_KEY_SHORT_ID>
  EOT
}

# =============================================================================
# Services
# =============================================================================

# ASG Service
resource "harness_platform_service" "asg" {
  count       = var.enable_asg ? 1 : 0
  identifier  = "spring_boot_asg"
  name        = "Spring Boot ASG"
  org_id      = var.org_identifier
  project_id  = local.project_id
  description = "Spring Boot app deployed to ASG"

  yaml = <<-EOT
    service:
      name: Spring Boot ASG
      identifier: spring_boot_asg
      serviceDefinition:
        type: Asg
        spec:
          manifests:
            - manifest:
                identifier: launchTemplate
                type: AsgLaunchTemplate
                spec:
                  store:
                    type: Github
                    spec:
                      connectorRef: ${var.github_connector_ref}
                      repoName: ${var.github_repo}
                      branch: main
                      paths:
                        - infra/harness/asg/launch-template.json
            - manifest:
                identifier: asgConfig
                type: AsgConfiguration
                spec:
                  store:
                    type: Github
                    spec:
                      connectorRef: ${var.github_connector_ref}
                      repoName: ${var.github_repo}
                      branch: main
                      paths:
                        - infra/harness/asg/asg-config.json
            - manifest:
                identifier: userData
                type: AsgUserData
                spec:
                  store:
                    type: Github
                    spec:
                      connectorRef: ${var.github_connector_ref}
                      repoName: ${var.github_repo}
                      branch: main
                      paths:
                        - infra/harness/asg/user-data.sh
          artifacts:
            primary:
              primaryArtifactRef: <+input>
              sources:
                - identifier: ami
                  type: AmazonMachineImage
                  spec:
                    connectorRef: ${harness_platform_connector_aws.aws.identifier}
                    region: ${var.aws_region}
                    tags:
                      Application: ${var.project_name}
                    version: <+input>
  EOT
}

# Lambda Service
resource "harness_platform_service" "lambda" {
  count       = var.enable_lambda ? 1 : 0
  identifier  = "spring_boot_lambda"
  name        = "Spring Boot Lambda"
  org_id      = var.org_identifier
  project_id  = local.project_id
  description = "Spring Boot app deployed to Lambda"

  yaml = <<-EOT
    service:
      name: Spring Boot Lambda
      identifier: spring_boot_lambda
      serviceDefinition:
        type: AwsLambda
        spec:
          manifests:
            - manifest:
                identifier: functionDefinition
                type: AwsLambdaFunctionDefinition
                spec:
                  store:
                    type: Github
                    spec:
                      connectorRef: ${var.github_connector_ref}
                      repoName: ${var.github_repo}
                      branch: main
                      paths:
                        - infra/harness/lambda/function-definition.yaml
            - manifest:
                identifier: aliasDefinition
                type: AwsLambdaFunctionAliasDefinition
                spec:
                  store:
                    type: Github
                    spec:
                      connectorRef: ${var.github_connector_ref}
                      repoName: ${var.github_repo}
                      branch: main
                      paths:
                        - infra/harness/lambda/alias-definition.yaml
          artifacts:
            primary:
              primaryArtifactRef: <+input>
              sources:
                - identifier: ecr
                  type: Ecr
                  spec:
                    connectorRef: ${harness_platform_connector_aws.aws.identifier}
                    region: ${var.aws_region}
                    imagePath: ${var.project_name}
                    tag: <+input>
  EOT
}

# Kubernetes Service
resource "harness_platform_service" "k8s" {
  count       = var.enable_eks ? 1 : 0
  identifier  = "spring_boot_k8s"
  name        = "Spring Boot K8s"
  org_id      = var.org_identifier
  project_id  = local.project_id
  description = "Spring Boot app deployed to Kubernetes"

  yaml = <<-EOT
    service:
      name: Spring Boot K8s
      identifier: spring_boot_k8s
      serviceDefinition:
        type: Kubernetes
        spec:
          manifests:
            - manifest:
                identifier: k8sManifests
                type: K8sManifest
                spec:
                  store:
                    type: Github
                    spec:
                      connectorRef: ${var.github_connector_ref}
                      repoName: ${var.github_repo}
                      branch: main
                      paths:
                        - infra/kubernetes/
                  valuesPaths:
                    - infra/kubernetes/values.yml
          artifacts:
            primary:
              primaryArtifactRef: <+input>
              sources:
                - identifier: ecr
                  type: Ecr
                  spec:
                    connectorRef: ${harness_platform_connector_aws.aws.identifier}
                    region: ${var.aws_region}
                    imagePath: ${var.project_name}
                    tag: <+input>
  EOT
}
