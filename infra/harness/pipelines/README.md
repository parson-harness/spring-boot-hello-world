# Harness Pipeline Templates

Ready-to-import pipeline YAML files for deployment and infrastructure provisioning.

## How to Import

1. Go to **Harness → Pipelines → Create Pipeline**
2. Click **YAML** tab (top right)
3. Copy/paste the pipeline YAML
4. Replace `<+input>` placeholders with your values
5. Save and run

## Available Pipelines

### Deployment Pipelines

| File | Deployment Type | Strategy |
|------|-----------------|----------|
| `asg-blue-green.yaml` | AWS ASG | Blue-Green with traffic shifting |
| `lambda-canary.yaml` | AWS Lambda | Canary (10% → 50% → 100%) |
| `cloudrun-canary.yaml` | GCP Cloud Run | Canary (10% → 50% → 100%) |
| `k8s-canary.yaml` | Kubernetes | Canary with rolling deployment |

### Infrastructure Provisioning Pipelines (Terraform)

| File | Cloud | What It Creates |
|------|-------|-----------------|
| `terraform-provision-gke.yaml` | GCP | GKE cluster, Artifact Registry, VPC |
| `terraform-provision-lambda.yaml` | AWS | Lambda function, ECR, IAM roles |
| `terraform-provision-cloudrun.yaml` | GCP | Cloud Run service, Artifact Registry |

## Required Inputs

### ASG Blue-Green
| Input | Description |
|-------|-------------|
| `serviceRef` | Your ASG service identifier |
| `environmentRef` | Target environment (e.g., `dev`) |
| `infrastructureDefinitions` | Your ASG infrastructure |
| `loadBalancer` | ALB name |
| `prodListener` | Production listener ARN |
| `prodListenerRuleArn` | Production listener rule ARN |
| `stageListener` | Stage listener ARN |
| `stageListenerRuleArn` | Stage listener rule ARN |
| `version` | AMI version to deploy |

### Lambda Canary
| Input | Description |
|-------|-------------|
| `serviceRef` | Your Lambda service identifier |
| `environmentRef` | Target environment |
| `infrastructureDefinitions` | Your Lambda infrastructure |
| `tag` | ECR image tag to deploy |

### K8s Canary
| Input | Description |
|-------|-------------|
| `serviceRef` | Your K8s service identifier |
| `environmentRef` | Target environment |
| `infrastructureDefinitions` | Your K8s infrastructure |
| `tag` | ECR image tag to deploy |

## Pipeline Flow

### ASG Blue-Green
```
Deploy New ASG → Verify → Approval → Swap Traffic → Done
                                ↓ (reject)
                            Rollback
```

### Lambda Canary
```
Deploy → 10% Traffic → Verify → 50% Traffic → Approval → 100% Traffic → Done
                                                    ↓ (reject)
                                                Rollback
```

### K8s Canary
```
Deploy Canary Pod → Verify → Approval → Delete Canary → Rolling Deploy → Done
                                   ↓ (reject)
                               Rollback
```

## Customization

- **Add more canary steps**: Duplicate traffic shift steps with different percentages
- **Add verification**: Replace ShellScript steps with Harness CV (Continuous Verification)
- **Add notifications**: Add Slack/Email steps after approval or completion
- **Multi-environment**: Add additional stages for staging/prod

---

## Terraform Provisioning Pipelines

These pipelines let you provision cloud infrastructure using Terraform directly from Harness.

### Prerequisites

1. **Cloud Connector** configured in Harness (GCP or AWS)
2. **Delegate** with cloud access (Workload Identity/IRSA recommended, or SA Key/Access Key)
3. **Terraform state backend**:
   - GCP: GCS bucket
   - AWS: S3 bucket + DynamoDB table

### GKE Provisioning (`terraform-provision-gke.yaml`)

**Pipeline Variables:**

| Variable | Required | Description |
|----------|----------|-------------|
| `gcp_project` | Yes | GCP Project ID |
| `gcp_region` | Yes | GCP Region (default: us-central1) |
| `tf_state_bucket` | Yes | GCS bucket for Terraform state |
| `project_name` | Yes | Name for cluster and resources |
| `environment` | Yes | Environment name (dev/staging/prod) |
| `owner` | Yes | Owner for resource tagging |
| `machine_type` | No | Node machine type (default: e2-medium) |
| `node_count` | No | Initial node count (default: 1) |
| `preemptible` | No | Use spot VMs (default: true) |

**What it creates:**
- GKE cluster with Workload Identity enabled
- VPC and subnet with pod/service CIDRs
- Node pool with autoscaling
- Artifact Registry for container images
- Service account with proper IAM bindings

### Lambda Provisioning (`terraform-provision-lambda.yaml`)

**Pipeline Variables:**

| Variable | Required | Description |
|----------|----------|-------------|
| `aws_region` | Yes | AWS Region (default: us-east-1) |
| `tf_state_bucket` | Yes | S3 bucket for Terraform state |
| `tf_lock_table` | Yes | DynamoDB table for state locking |
| `project_name` | Yes | Name for Lambda and resources |
| `environment` | Yes | Environment name (dev/staging/prod) |
| `owner` | Yes | Owner for resource tagging |

**What it creates:**
- ECR repository for container images
- Lambda function with Function URL
- IAM roles and policies
- CloudWatch log group

### Pipeline Flow (Both)

```
Terraform Init → Terraform Plan → Approval → Terraform Apply → Output Values
```

### Using with Your Own Terraform

You can modify these pipelines to point to different Terraform directories:

1. Change `cd infra/terraform-gke` to your Terraform path
2. Update the tfvars generation to match your variables
3. Adjust outputs as needed

### State Backend Setup

**GCP (GCS):**
```bash
# Create bucket for state
gsutil mb -l us-central1 gs://my-terraform-state-bucket
gsutil versioning set on gs://my-terraform-state-bucket
```

**AWS (S3 + DynamoDB):**
```bash
# Create S3 bucket
aws s3 mb s3://my-terraform-state-bucket --region us-east-1
aws s3api put-bucket-versioning --bucket my-terraform-state-bucket --versioning-configuration Status=Enabled

# Create DynamoDB table for locking
aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```
