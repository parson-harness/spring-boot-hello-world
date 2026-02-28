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
      Project     = "harness-delegate"
      Environment = var.environment
      Owner       = var.owner
      ManagedBy   = "terraform"
    }
  }
}

# =============================================================================
# IAM Role for Harness Delegate (IRSA - IAM Roles for Service Accounts)
# =============================================================================

data "aws_caller_identity" "current" {}

# OIDC Provider for EKS (if using EKS-hosted delegate)
data "aws_eks_cluster" "delegate" {
  count = var.eks_cluster_name != "" ? 1 : 0
  name  = var.eks_cluster_name
}

data "aws_iam_openid_connect_provider" "eks" {
  count = var.eks_cluster_name != "" ? 1 : 0
  url   = data.aws_eks_cluster.delegate[0].identity[0].oidc[0].issuer
}

# IAM Role for Delegate
resource "aws_iam_role" "harness_delegate" {
  name = "${var.delegate_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      # For EKS IRSA
      var.eks_cluster_name != "" ? [
        {
          Effect = "Allow"
          Principal = {
            Federated = data.aws_iam_openid_connect_provider.eks[0].arn
          }
          Action = "sts:AssumeRoleWithWebIdentity"
          Condition = {
            StringEquals = {
              "${replace(data.aws_iam_openid_connect_provider.eks[0].url, "https://", "")}:sub" = "system:serviceaccount:${var.delegate_namespace}:${var.delegate_service_account}"
              "${replace(data.aws_iam_openid_connect_provider.eks[0].url, "https://", "")}:aud" = "sts.amazonaws.com"
            }
          }
        }
      ] : [],
      # For EC2 instance profile (Docker delegate on EC2)
      var.enable_ec2_assume ? [
        {
          Effect = "Allow"
          Principal = {
            Service = "ec2.amazonaws.com"
          }
          Action = "sts:AssumeRole"
        }
      ] : []
    )
  })
}

# =============================================================================
# ASG Deployment Permissions
# =============================================================================

resource "aws_iam_role_policy" "asg_deployment" {
  count = var.enable_asg_permissions ? 1 : 0
  name  = "asg-deployment"
  role  = aws_iam_role.harness_delegate.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ASGManagement"
        Effect = "Allow"
        Action = [
          "autoscaling:CreateAutoScalingGroup",
          "autoscaling:UpdateAutoScalingGroup",
          "autoscaling:DeleteAutoScalingGroup",
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
          "autoscaling:AttachLoadBalancerTargetGroups",
          "autoscaling:DetachLoadBalancerTargetGroups",
          "autoscaling:DescribeLoadBalancerTargetGroups"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2LaunchTemplate"
        Effect = "Allow"
        Action = [
          "ec2:CreateLaunchTemplate",
          "ec2:CreateLaunchTemplateVersion",
          "ec2:DeleteLaunchTemplate",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:GetLaunchTemplateData",
          "ec2:ModifyLaunchTemplate"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2Instances"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:CreateTags",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2Networking"
        Effect = "Allow"
        Action = [
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeImages",
          "ec2:DescribeKeyPairs"
        ]
        Resource = "*"
      },
      {
        Sid    = "ELBTargetGroups"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:ModifyRule",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets"
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMPassRole"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = [
              "ec2.amazonaws.com",
              "autoscaling.amazonaws.com"
            ]
          }
        }
      }
    ]
  })
}

# =============================================================================
# Lambda Deployment Permissions
# =============================================================================

resource "aws_iam_role_policy" "lambda_deployment" {
  count = var.enable_lambda_permissions ? 1 : 0
  name  = "lambda-deployment"
  role  = aws_iam_role.harness_delegate.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LambdaManagement"
        Effect = "Allow"
        Action = [
          "lambda:GetFunction",
          "lambda:GetFunctionConfiguration",
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:PublishVersion",
          "lambda:CreateAlias",
          "lambda:UpdateAlias",
          "lambda:DeleteAlias",
          "lambda:GetAlias",
          "lambda:ListVersionsByFunction",
          "lambda:ListAliases",
          "lambda:CreateFunction",
          "lambda:DeleteFunction",
          "lambda:InvokeFunction",
          "lambda:TagResource"
        ]
        Resource = "arn:aws:lambda:*:${data.aws_caller_identity.current.account_id}:function:*"
      },
      {
        Sid    = "ECRAccess"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRRepository"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:DescribeImages",
          "ecr:ListImages",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "arn:aws:ecr:*:${data.aws_caller_identity.current.account_id}:repository/*"
      },
      {
        Sid    = "IAMPassRoleToLambda"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "lambda.amazonaws.com"
          }
        }
      }
    ]
  })
}

# =============================================================================
# EKS Deployment Permissions
# =============================================================================

resource "aws_iam_role_policy" "eks_deployment" {
  count = var.enable_eks_permissions ? 1 : 0
  name  = "eks-deployment"
  role  = aws_iam_role.harness_delegate.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EKSDescribe"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# S3 Artifact Permissions (for JAR uploads, etc.)
# =============================================================================

resource "aws_iam_role_policy" "s3_artifacts" {
  count = var.enable_s3_permissions ? 1 : 0
  name  = "s3-artifacts"
  role  = aws_iam_role.harness_delegate.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ArtifactAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:aws:s3:::*-artifacts*",
          "arn:aws:s3:::*-artifacts*/*"
        ]
      }
    ]
  })
}

# =============================================================================
# EC2 Instance Profile (for Docker delegate on EC2)
# =============================================================================

resource "aws_iam_instance_profile" "harness_delegate" {
  count = var.enable_ec2_assume ? 1 : 0
  name  = "${var.delegate_name}-instance-profile"
  role  = aws_iam_role.harness_delegate.name
}
