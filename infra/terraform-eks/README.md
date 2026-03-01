# EKS Infrastructure (Optional)

This Terraform configuration creates an EKS cluster by referencing the `harness-automation` repo's EKS module.

> **Note**: This is optional. If you already have an EKS cluster (e.g., from `harness-automation`), skip this and use `deploy-eks.sh` directly.

## When to Use This

| Scenario | Use This? |
|----------|-----------|
| You have an existing EKS cluster | No - just run `./deploy-eks.sh` |
| You need a dedicated cluster for this POV | Yes |
| You want a self-contained demo | Yes |

## Prerequisites

- Access to the `harness-automation` repo (for the EKS module)
- AWS credentials with EKS permissions

## Usage

```bash
cd infra/terraform-eks

# Initialize (downloads the remote module)
terraform init

# Deploy EKS cluster + ECR repo
terraform apply \
  -var "project_name=acme-demo" \
  -var "owner=yourname"

# Configure kubectl
$(terraform output -raw kubeconfig_command)

# Now deploy the app
cd ../..
./deploy-eks.sh v1.0-blue
```

## Module Source Options

The `main.tf` references the EKS module via Git URL:

```hcl
source = "git::https://github.com/parson-harness/harness-automation.git//aws/modules/eks?ref=main"
```

If you have `harness-automation` cloned locally, you can use a local path instead:

```hcl
source = "../../../harness-automation/aws/modules/eks"
```

## What Gets Created

- EKS cluster with managed node group
- VPC with public/private subnets
- IAM roles for nodes and IRSA
- ECR repository for this app
- OIDC provider for delegate IRSA

## Cleanup

```bash
# First remove K8s resources
./deploy-eks.sh destroy

# Then destroy EKS cluster
cd infra/terraform-eks
terraform destroy -var "project_name=acme-demo" -var "owner=yourname"
```

## Relationship to harness-automation

| Repo | Purpose |
|------|---------|
| `harness-automation` | Shared infrastructure (EKS, delegate, Grafana, etc.) for multiple POVs |
| `spring-boot-hello-world` | Sample app + optional dedicated EKS for self-contained demos |

For most POVs, use the shared EKS from `harness-automation`. Use this only when you need isolation or a customer-specific cluster.
