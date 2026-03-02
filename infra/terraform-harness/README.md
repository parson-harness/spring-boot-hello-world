# Harness Entity Provisioning

Terraform module to create all Harness entities needed for the POV demo.

## What Gets Created

| Resource | Description |
|----------|-------------|
| **AWS Connector** | Connects Harness to AWS for deployments |
| **K8s Connector** | Connects Harness to EKS cluster (optional) |
| **Environment** | Dev/staging/prod environment |
| **ASG Infrastructure** | Infrastructure definition for ASG deployments |
| **Lambda Infrastructure** | Infrastructure definition for Lambda deployments |
| **K8s Infrastructure** | Infrastructure definition for K8s deployments |
| **ASG Service** | Service with AMI artifact and ASG manifests |
| **Lambda Service** | Service with ECR artifact and Lambda manifests |
| **K8s Service** | Service with ECR artifact and K8s manifests |

## Prerequisites

1. **Harness API Key**: Create a Personal Access Token (PAT) or Service Account Token (SAT)
   - Go to Account Settings → Access Control → Service Accounts or your profile
   - Create token with admin permissions

2. **GitHub Connector**: An existing GitHub connector in Harness for manifest storage
   - Default: `account.github` (account-level connector)

3. **Delegate**: A running Harness delegate with AWS access

## Usage

### Recommended: Use POV Scripts

```bash
# 1. Setup POV (creates backend config, tfvars template, .env file)
./setup-pov.sh
# Enter POV name when prompted

# 2. Edit Harness config
vi infra/terraform-harness/terraform.tfvars.<pov-name>

# 3. Deploy AWS infrastructure
./deploy-asg.sh deploy    # For ASG Blue-Green
./deploy-lambda.sh deploy # For Lambda Canary

# 4. Auto-populate AWS values into tfvars
./update-harness-tfvars.sh <pov-name>

# 5. Switch to POV and apply
./switch-pov.sh <pov-name>
cd infra/terraform-harness
terraform init && terraform apply
```

### Manual Setup

```bash
cd infra/terraform-harness

# Create terraform.tfvars from example
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
vi terraform.tfvars

# Initialize and apply
terraform init
terraform apply
```

## Variables

### Required

| Variable | Description |
|----------|-------------|
| `harness_account_id` | Your Harness account ID |
| `harness_api_key` | API key (PAT or SAT) |

### Optional

| Variable | Default | Description |
|----------|---------|-------------|
| `org_identifier` | `default` | Harness org |
| `project_identifier` | `spring_boot_pov` | Harness project |
| `create_project` | `false` | Create new project |
| `environment` | `dev` | Environment name |
| `aws_region` | `us-east-1` | AWS region |
| `enable_asg` | `true` | Create ASG resources |
| `enable_lambda` | `true` | Create Lambda resources |
| `enable_eks` | `true` | Create K8s resources |
| `aws_connector_type` | `irsa` | `irsa` or `manual` |
| `delegate_selectors` | `["harness-delegate"]` | Delegate tags |

### ASG Infrastructure Values (Auto-populated by `update-harness-tfvars.sh`)

| Variable | Description |
|----------|-------------|
| `asg_security_group_id` | Security group for ASG instances |
| `asg_subnet_ids` | Comma-separated subnet IDs |
| `alb_name` | ALB name for Blue-Green |
| `prod_listener_arn` | Production listener ARN |
| `prod_listener_rule_arn` | Production listener rule ARN |
| `stage_listener_arn` | Stage listener ARN |
| `stage_listener_rule_arn` | Stage listener rule ARN |

## After Provisioning

Pipelines are created automatically by Terraform. No manual import needed.

**Run pipelines** in Harness:
- `asg_blue_green_deploy` - ASG Blue-Green deployment
- `lambda_canary_deploy` - Lambda Canary deployment

**Build new artifacts** using deploy scripts:
```bash
./deploy-asg.sh deploy      # Builds new AMI
./deploy-lambda.sh push     # Builds and pushes Lambda image
```

## Cleanup

```bash
terraform destroy
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| API key invalid | Regenerate token, ensure admin permissions |
| Connector test fails | Check delegate is running and has AWS access |
| Project not found | Set `create_project = true` or use existing project |
| GitHub connector not found | Create account-level GitHub connector first |
