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
  # Sanitize environment name for Harness identifiers (no hyphens allowed)
  env_id     = replace(var.environment, "-", "_")
}

# =============================================================================
# AWS Cloud Provider Connector
# =============================================================================
resource "harness_platform_connector_aws" "aws" {
  identifier  = "aws_${local.env_id}"
  name        = "AWS Lambda"
  description = "AWS connector for ${var.environment} deployments"
  org_id      = var.org_identifier
  project_id  = local.project_id
  tags        = ["${var.environment}:", "pov:"]

  # Use IRSA if delegate is in EKS, otherwise use IAM role
  dynamic "irsa" {
    for_each = var.aws_connector_type == "irsa" ? [1] : []
    content {
      delegate_selectors = var.delegate_selectors
      region             = var.aws_region
    }
  }

  dynamic "inherit_from_delegate" {
    for_each = var.aws_connector_type == "inherit" ? [1] : []
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
  identifier  = "eks_${local.env_id}"
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
  identifier  = local.env_id
  name        = title(var.environment)
  org_id      = var.org_identifier
  project_id  = local.project_id
  description = "${title(var.environment)} environment for POV"
  type        = var.environment == "prod" ? "Production" : "PreProduction"
  tags        = ["pov", var.environment]

  yaml = <<-EOT
    environment:
      name: ${title(var.environment)}
      identifier: ${local.env_id}
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
  identifier        = "asg_${local.env_id}"
  name              = "ASG ${title(var.environment)}"
  org_id            = var.org_identifier
  project_id        = local.project_id
  env_id            = harness_platform_environment.env.identifier
  type              = "Asg"
  deployment_type   = "Asg"
  
  yaml = <<-EOT
    infrastructureDefinition:
      name: ASG ${title(var.environment)}
      identifier: asg_${local.env_id}
      orgIdentifier: ${var.org_identifier}
      projectIdentifier: ${local.project_id}
      environmentRef: ${local.env_id}
      type: Asg
      spec:
        connectorRef: ${harness_platform_connector_aws.aws.identifier}
        region: ${var.aws_region}
  EOT
}

# Lambda Infrastructure
resource "harness_platform_infrastructure" "lambda" {
  count             = var.enable_lambda ? 1 : 0
  identifier        = "lambda_${local.env_id}"
  name              = "Lambda-${title(var.environment)}"
  org_id            = var.org_identifier
  project_id        = local.project_id
  env_id            = harness_platform_environment.env.identifier
  type              = "AwsLambda"
  deployment_type   = "AwsLambda"
  
  yaml = <<-EOT
    infrastructureDefinition:
      name: Lambda-${title(var.environment)}
      identifier: lambda_${local.env_id}
      orgIdentifier: ${var.org_identifier}
      projectIdentifier: ${local.project_id}
      environmentRef: ${local.env_id}
      deploymentType: AwsLambda
      type: AwsLambda
      spec:
        connectorRef: ${harness_platform_connector_aws.aws.identifier}
        region: ${var.aws_region}
      allowSimultaneousDeployments: false
  EOT
}

# Kubernetes Infrastructure
resource "harness_platform_infrastructure" "k8s" {
  count             = var.enable_eks ? 1 : 0
  identifier        = "k8s_${local.env_id}"
  name              = "K8s-${title(var.environment)}"
  org_id            = var.org_identifier
  project_id        = local.project_id
  env_id            = harness_platform_environment.env.identifier
  type              = "KubernetesDirect"
  deployment_type   = "Kubernetes"
  
  yaml = <<-EOT
    infrastructureDefinition:
      name: K8s-${title(var.environment)}
      identifier: k8s_${local.env_id}
      orgIdentifier: ${var.org_identifier}
      projectIdentifier: ${local.project_id}
      environmentRef: ${local.env_id}
      deploymentType: Kubernetes
      type: KubernetesDirect
      spec:
        connectorRef: ${harness_platform_connector_kubernetes.eks[0].identifier}
        namespace: ${var.k8s_namespace}
        releaseName: release-<+INFRA_KEY_SHORT_ID>
      allowSimultaneousDeployments: false
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
                      gitFetchType: Branch
                      repoName: ${var.github_repo}
                      branch: main
                      paths:
                        - infra/harness/lambda/function-definition.json
            - manifest:
                identifier: aliasDefinition
                type: AwsLambdaFunctionAliasDefinition
                spec:
                  store:
                    type: Github
                    spec:
                      connectorRef: ${var.github_connector_ref}
                      gitFetchType: Branch
                      repoName: ${var.github_repo}
                      branch: main
                      paths:
                        - infra/harness/lambda/alias-definition.json
          artifacts:
            primary:
              primaryArtifactRef: <+input>
              sources:
                - spec:
                    connectorRef: ${harness_platform_connector_aws.aws.identifier}
                    imagePath: ${var.project_name}
                    tag: <+input>
                    region: ${var.aws_region}
                  identifier: ${replace(var.project_name, "-", "_")}
                  type: Ecr
  EOT
}

# =============================================================================
# Pipelines
# =============================================================================

# Lambda Canary Pipeline
resource "harness_platform_pipeline" "lambda" {
  count       = var.enable_lambda ? 1 : 0
  identifier  = "lambda_canary_deploy"
  name        = "Lambda Canary Deploy"
  org_id      = var.org_identifier
  project_id  = local.project_id

  yaml = <<-EOT
    pipeline:
      name: Lambda Canary Deploy
      identifier: lambda_canary_deploy
      projectIdentifier: ${local.project_id}
      orgIdentifier: ${var.org_identifier}
      description: |
        Deploys Spring Boot app to AWS Lambda using Canary strategy.
        - Deploys new Lambda version
        - Shifts traffic gradually via alias (10% -> 50% -> 100%)
        - Supports instant rollback
      stages:
        - stage:
            name: Deploy to Dev
            identifier: deploy_to_dev
            description: Canary deployment to Lambda
            type: Deployment
            spec:
              deploymentType: AwsLambda
              service:
                serviceRef: ${harness_platform_service.lambda[0].identifier}
                serviceInputs:
                  serviceDefinition:
                    type: AwsLambda
                    spec:
                      artifacts:
                        primary:
                          primaryArtifactRef: <+input>
                          sources: <+input>
              environment:
                environmentRef: ${harness_platform_environment.env.identifier}
                deployToAll: false
                infrastructureDefinitions:
                  - identifier: ${harness_platform_infrastructure.lambda[0].identifier}
              execution:
                steps:
                  - step:
                      name: Lambda Deploy
                      identifier: lambda_deploy
                      type: AwsLambdaDeploy
                      timeout: 10m
                      spec: {}
                  - step:
                      name: Shift Traffic 10
                      identifier: shift_traffic_10
                      type: AwsLambdaTrafficShift
                      timeout: 5m
                      spec:
                        trafficPercent: 10
                        trafficPercentage: 10
                  - step:
                      name: Verify 10
                      identifier: verify_10
                      type: ShellScript
                      timeout: 5m
                      spec:
                        shell: Bash
                        source:
                          type: Inline
                          spec:
                            script: |
                              echo "Verifying canary at 10 percent..."
                              sleep 30
                              echo "Canary looks healthy!"
                        executionTarget: {}
                        environmentVariables: []
                        outputVariables: []
                  - step:
                      name: Shift Traffic 50
                      identifier: shift_traffic_50
                      type: AwsLambdaTrafficShift
                      timeout: 5m
                      spec:
                        trafficPercent: 50
                        trafficPercentage: 50
                  - step:
                      name: Approval
                      identifier: approval
                      type: HarnessApproval
                      timeout: 1d
                      spec:
                        approvalMessage: |
                          Lambda canary deployment at 50 percent traffic.
                          Review metrics and logs before proceeding to 100 percent.
                          Approve to shift all traffic to new version.
                        includePipelineExecutionHistory: true
                        approvers:
                          userGroups:
                            - _project_all_users
                          minimumCount: 1
                          disallowPipelineExecutor: false
                  - step:
                      name: Shift Traffic 100
                      identifier: shift_traffic_100
                      type: AwsLambdaTrafficShift
                      timeout: 5m
                      spec:
                        trafficPercent: 100
                        trafficPercentage: 100
                rollbackSteps:
                  - step:
                      name: Lambda Rollback
                      identifier: lambda_rollback
                      type: AwsLambdaRollback
                      timeout: 10m
                      spec: {}
            tags: {}
            failureStrategies:
              - onFailure:
                  errors:
                    - AllErrors
                  action:
                    type: StageRollback
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
                      gitFetchType: Branch
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
                - spec:
                    connectorRef: ${harness_platform_connector_aws.aws.identifier}
                    imagePath: ${var.project_name}
                    tag: <+input>
                    region: ${var.aws_region}
                  identifier: ${replace(var.project_name, "-", "_")}
                  type: Ecr
  EOT
}

# Kubernetes Canary Pipeline
resource "harness_platform_pipeline" "k8s" {
  count       = var.enable_eks ? 1 : 0
  identifier  = "k8s_canary_deploy"
  name        = "K8s Canary Deploy"
  org_id      = var.org_identifier
  project_id  = local.project_id

  yaml = <<-EOT
    pipeline:
      name: K8s Canary Deploy
      identifier: k8s_canary_deploy
      projectIdentifier: ${local.project_id}
      orgIdentifier: ${var.org_identifier}
      description: |
        Deploys Spring Boot app to Kubernetes using Canary strategy.
        - Deploys canary pods
        - Shifts traffic gradually
        - Supports rollback
      tags:
        deployment-type: kubernetes
        strategy: canary
      stages:
        - stage:
            name: Deploy to Dev
            identifier: deploy_to_dev
            description: Canary deployment to Kubernetes
            type: Deployment
            spec:
              deploymentType: Kubernetes
              service:
                serviceRef: ${harness_platform_service.k8s[0].identifier}
                serviceInputs:
                  serviceDefinition:
                    type: Kubernetes
                    spec:
                      artifacts:
                        primary:
                          primaryArtifactRef: <+input>
                          sources: <+input>
              environment:
                environmentRef: ${harness_platform_environment.env.identifier}
                deployToAll: false
                infrastructureDefinitions:
                  - identifier: ${harness_platform_infrastructure.k8s[0].identifier}
              execution:
                steps:
                  - stepGroup:
                      name: Canary Deployment
                      identifier: canary_deployment
                      steps:
                        - step:
                            name: Canary Deployment
                            identifier: canary_deploy
                            type: K8sCanaryDeploy
                            timeout: 10m
                            spec:
                              instanceSelection:
                                type: Count
                                spec:
                                  count: 1
                              skipDryRun: false
                        - step:
                            name: Verify Canary
                            identifier: verify_canary
                            type: ShellScript
                            timeout: 5m
                            spec:
                              shell: Bash
                              source:
                                type: Inline
                                spec:
                                  script: |
                                    echo "Verifying canary pod..."
                                    echo "Canary looks healthy!"
                              executionTarget: {}
                              environmentVariables: []
                              outputVariables: []
                        - step:
                            name: Approval
                            identifier: approval
                            type: HarnessApproval
                            timeout: 1d
                            spec:
                              approvalMessage: |
                                Canary pod is running.
                                Review pod logs and metrics before proceeding.
                                Approve to roll out to all pods.
                              includePipelineExecutionHistory: true
                              approvers:
                                userGroups:
                                  - _project_all_users
                                minimumCount: 1
                                disallowPipelineExecutor: false
                  - stepGroup:
                      name: Primary Deployment
                      identifier: primary_deployment
                      steps:
                        - step:
                            name: Canary Delete
                            identifier: canary_delete
                            type: K8sCanaryDelete
                            timeout: 10m
                            spec: {}
                        - step:
                            name: Rolling Deployment
                            identifier: rolling_deploy
                            type: K8sRollingDeploy
                            timeout: 10m
                            spec:
                              skipDryRun: false
                rollbackSteps:
                  - step:
                      name: Canary Delete
                      identifier: rollback_canary_delete
                      type: K8sCanaryDelete
                      timeout: 10m
                      spec: {}
                  - step:
                      name: Rolling Rollback
                      identifier: rolling_rollback
                      type: K8sRollingRollback
                      timeout: 10m
                      spec: {}
            tags: {}
            failureStrategies:
              - onFailure:
                  errors:
                    - AllErrors
                  action:
                    type: StageRollback
  EOT
}
