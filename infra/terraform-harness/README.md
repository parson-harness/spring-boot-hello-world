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

```bash
cd infra/terraform-harness

# Create terraform.tfvars
cat > terraform.tfvars <<EOF
harness_account_id = "your-account-id"
harness_api_key    = "your-api-key"
org_identifier     = "default"
project_identifier = "spring_boot_pov"
environment        = "dev"
aws_region         = "us-east-1"

# Delegate selector (must match your delegate)
delegate_selectors = ["harness-delegate"]

# GitHub repo for manifests
github_connector_ref = "account.github"
github_repo          = "your-org/spring-boot-hello-world"

# Enable/disable deployment types
enable_asg    = true
enable_lambda = true
enable_eks    = true
EOF

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

## After Provisioning

1. **Import pipelines** from `infra/harness/pipelines/`:
   ```
   asg-blue-green.yaml
   lambda-canary.yaml
   k8s-canary.yaml
   ```

2. **Build artifacts** using deploy scripts:
   ```bash
   ./deploy-asg.sh v1.0-blue      # Builds AMI
   ./deploy-lambda.sh v1.0-blue   # Builds Lambda image
   ./deploy-eks.sh v1.0-blue      # Builds K8s image
   ```

3. **Run pipelines** in Harness with the built artifacts

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
