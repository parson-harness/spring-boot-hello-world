# Harness Delegate IAM Roles

> **Reference Module**: This documents the IAM permissions required for Harness deployments. If you manage your delegate infrastructure separately (e.g., in a `harness-automation` repo), use this as a reference for what permissions to add to your existing delegate IAM role.

This Terraform module creates IAM roles and policies for a Harness delegate to perform deployments to various AWS services.

## Supported Deployment Types

| Type | Permission Flag | What It Enables |
|------|-----------------|-----------------|
| **ASG** | `enable_asg_permissions` | Auto Scaling Groups, Launch Templates, EC2, ALB Target Groups |
| **Lambda** | `enable_lambda_permissions` | Lambda functions, ECR, aliases for blue-green/canary |
| **EKS** | `enable_eks_permissions` | EKS cluster describe (for K8s connector) |
| **S3** | `enable_s3_permissions` | S3 artifact bucket access |

## Usage

### For EKS-hosted Delegate (IRSA)

```hcl
module "delegate_iam" {
  source = "./infra/terraform-delegate"

  delegate_name            = "harness-delegate"
  eks_cluster_name         = "my-eks-cluster"
  delegate_namespace       = "harness-delegate-ng"
  delegate_service_account = "harness-delegate-sa"

  enable_asg_permissions    = true
  enable_lambda_permissions = true
  enable_eks_permissions    = true
  enable_s3_permissions     = true

  owner = "parson"
}
```

Then annotate your delegate ServiceAccount:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: harness-delegate-sa
  namespace: harness-delegate-ng
  annotations:
    eks.amazonaws.com/role-arn: <delegate_role_arn output>
```

### For Docker Delegate on EC2

```hcl
module "delegate_iam" {
  source = "./infra/terraform-delegate"

  delegate_name     = "harness-delegate"
  enable_ec2_assume = true

  enable_asg_permissions    = true
  enable_lambda_permissions = true

  owner = "parson"
}
```

Attach the instance profile to your EC2 instance running the delegate.

## Outputs

| Output | Description |
|--------|-------------|
| `delegate_role_arn` | IAM Role ARN to use in Harness AWS Connector |
| `delegate_role_name` | IAM Role name |
| `instance_profile_name` | EC2 Instance Profile (if `enable_ec2_assume = true`) |

## Integrating with Existing Delegate Repo

If you manage your delegate in a separate repo, you can:

1. **Copy this module** to your delegate repo
2. **Use as a remote module**:
   ```hcl
   module "delegate_iam" {
     source = "git::https://github.com/your-org/spring-boot-hello-world.git//infra/terraform-delegate"
     # ... variables
   }
   ```
3. **Import the role ARN** into your delegate Terraform and reference it

## Permissions Summary

### ASG Deployments
- `autoscaling:*` - Create/update/delete ASGs
- `ec2:*LaunchTemplate*` - Manage launch templates
- `ec2:RunInstances` - Launch EC2 instances
- `elasticloadbalancing:*` - Manage ALB target groups and listeners
- `iam:PassRole` - Pass roles to EC2/ASG

### Lambda Deployments
- `lambda:*` - Full Lambda management
- `ecr:*` - Pull/push container images
- `iam:PassRole` - Pass execution role to Lambda

### EKS Deployments
- `eks:DescribeCluster` - Get cluster endpoint for K8s connector
