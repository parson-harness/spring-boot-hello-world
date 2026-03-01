# EKS Infrastructure (optional)
# References the EKS module from harness-automation repo
# Use this if you need to create a new EKS cluster for your POV
# Otherwise, use an existing cluster and skip this

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Owner       = var.owner
      ManagedBy   = "terraform"
    }
  }
}

# =============================================================================
# EKS Cluster from harness-automation module
# =============================================================================
# To use this, you need the harness-automation repo cloned locally or
# reference it via Git URL (requires repo access)

module "eks" {
  # Option 1: Local path (if harness-automation is cloned alongside this repo)
  # source = "../../../harness-automation/aws/modules/eks"

  # Option 2: Git URL (requires access to the repo)
  source = "git::https://github.com/parson-harness/harness-automation.git//aws/modules/eks?ref=main"

  cluster                  = var.project_name
  tag_owner                = var.owner
  instance_type            = var.instance_type
  min_size                 = var.min_size
  desired_size             = var.desired_size
  max_size                 = var.max_size
  delegate_namespace       = var.delegate_namespace
  delegate_service_account = var.delegate_service_account
  ecr_repo_prefix          = var.project_name
}

# =============================================================================
# ECR Repository for this app
# =============================================================================
resource "aws_ecr_repository" "app" {
  name                 = var.project_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}
