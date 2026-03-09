# Infrastructure

Infrastructure-as-code for AWS and GCP deployments. Use the deploy scripts from the repo root instead of running these directly.

## Directory Structure

| Directory | Purpose | Deploy Script |
|-----------|---------|---------------|
| `terraform-asg/` | ASG infrastructure (VPC, ALB, ASG) | `./deploy-asg.sh` |
| `terraform-lambda/` | Lambda infrastructure (ECR, Lambda) | `./deploy-lambda.sh` |
| `terraform-cloudrun/` | Cloud Run infrastructure (Artifact Registry, Cloud Run) | `./deploy-cloudrun.sh` |
| `terraform-eks/` | EKS cluster (optional, AWS) | `./deploy-eks.sh` |
| `terraform-gke/` | GKE cluster (optional, GCP) | `./deploy-gke.sh` |
| `terraform-harness/` | Harness entities (services, pipelines) | `./setup-harness.sh` |
| `terraform-bootstrap/` | AWS state backend (S3 + DynamoDB) | Auto-created by `setup-pov.sh` |
| `terraform-bootstrap-gcp/` | GCP state backend (GCS bucket) | Manual (see below) |
| `harness/` | Harness manifest templates | Used by terraform-harness |
| `packer/` | AMI building for ASG | Used by `deploy-asg.sh` |

## Backend Configuration

POV-specific backend configs are managed by symlink:
```
backend.hcl -> backend-<pov-name>.hcl
```

Switch POVs with `./switch-pov.sh <pov-name>`.

## Manual Terraform (if needed)

```bash
# ASG infrastructure
cd terraform-asg
terraform init -backend-config=../backend.hcl
terraform apply

# Lambda infrastructure  
cd terraform-lambda
terraform init -backend-config=../backend.hcl
terraform apply

# Harness entities
cd terraform-harness
terraform init
terraform apply
```

## GCP State Backend Setup

For GCP deployments (Cloud Run, GKE), create a GCS bucket for Terraform state:

```bash
cd infra/terraform-bootstrap-gcp

# Copy and edit the example config
cp terraform.tfvars.example terraform.tfvars
vi terraform.tfvars  # Set your GCP project ID

# Create the state bucket
terraform init
terraform apply

# Note the bucket name from output - use it in Harness pipelines
terraform output state_bucket_name
```

This creates a versioned GCS bucket that:
- Stores Terraform state for Cloud Run/GKE modules
- Enables running Terraform from Harness pipelines (not just locally)
- Makes POV teardown easy (`terraform destroy` from anywhere)

## Cleanup

**AWS:**
```bash
./deploy-asg.sh destroy
./deploy-lambda.sh destroy
```

**GCP:**
```bash
./deploy-cloudrun.sh destroy
./deploy-gke.sh destroy
```

**Full POV teardown (GCP with remote state):**
```bash
# From anywhere with access to the state bucket
cd infra/terraform-cloudrun
terraform init -backend-config="bucket=YOUR_STATE_BUCKET" -backend-config="prefix=terraform/state/cloudrun"
terraform destroy
```
