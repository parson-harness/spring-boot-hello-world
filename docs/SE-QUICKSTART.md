# SE Quick Start Guide

This repo contains a Spring Boot sample app with infrastructure for multiple deployment models. Fork it, deploy it, and demo Harness CD.

---

## Quick Start (New POV)

```bash
# 1. Run the setup script
./setup-pov.sh
# Enter POV name when prompted (e.g., "acme", "tr")

# 2. Source environment variables
source .env.<pov-name>

# 3. Edit Harness config with your account details
vi infra/terraform-harness/terraform.tfvars.<pov-name>

# 4. Deploy AWS infrastructure (choose one or both)
./deploy-lambda.sh deploy   # Lambda: ECR + Lambda function
./deploy-asg.sh deploy      # ASG: VPC + ALB + AMI

# 5. Auto-populate Harness tfvars with AWS values
./update-harness-tfvars.sh <pov-name>

# 6. Switch to POV and create Harness entities
./switch-pov.sh <pov-name>
cd infra/terraform-harness && terraform init && terraform apply

# 7. Run pipeline in Harness UI
```

### Switching Between POVs

```bash
# Switch to a different POV (updates backend.hcl symlink and copies tfvars)
./switch-pov.sh <pov-name>
source .env.<pov-name>
```

---

## Prerequisites

- AWS account with PowerUser access
- Harness account with CD module
- AWS CLI configured (`aws sso login`)
- Docker running
- Terraform, Maven, Packer installed

---

## CI Options

| Option | When to Use |
|--------|-------------|
| **Harness CI** | Full Harness demo (CI + CD) |
| **GitHub Actions** | Quick setup, GitHub-native |
| **Local scripts** | Fast iteration, no CI needed |

### GitHub Actions (Optional)
Workflows are disabled by default. To enable:
```bash
mv .github/workflows/build-ami.yml.disabled .github/workflows/build-ami.yml
```
See `.github/workflows/README.md` for setup instructions.

### Harness CI
Use the deploy scripts as reference for build steps, or import pipeline YAML from `infra/harness/pipelines/`.

### Automated Harness Setup (Optional)
Provision all Harness entities with Terraform:
```bash
cd infra/terraform-harness
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Harness account details
terraform init && terraform apply
```
See `infra/terraform-harness/README.md` for details.

### Remote State (Default)
Terraform state is stored in S3 for easy teardown after POV. The `setup-pov.sh` script creates all backend configs automatically.

**Running Multiple POVs:**
Use the POV management scripts to run multiple POVs from the same repo:
```bash
# Setup a new POV (creates backend config, tfvars, .env file)
./setup-pov.sh
# Enter: acme

# Switch between POVs
./switch-pov.sh acme    # Switch to customer POV
./switch-pov.sh sandbox # Switch to your sandbox

# After switching, source the environment
source .env.<pov-name>
```

---

## Deployment Models

| Model | Best For | Cold Start | Cost Model |
|-------|----------|------------|------------|
| **ASG Blue-Green** | Traditional EC2 workloads | None (always running) | Pay for instances 24/7 |
| **Lambda** | Event-driven, variable traffic | 5-15 seconds | Pay per invocation |
| **EKS/Kubernetes** | Container workloads, microservices | None (pods always running) | Pay for nodes 24/7 |

---

# Option 1: ASG Blue-Green Deployment

## What You Get
- VPC, ALB, Auto Scaling Group
- Two target groups for blue-green traffic shifting
- AMI-based deployments with Packer

## Step 1: Deploy Infrastructure

```bash
# Clone and configure
git clone <your-fork>
cd spring-boot-hello-world

# Deploy with your name (used for AWS resource tags)
PROJECT_NAME=acme-demo OWNER=yourname ./deploy-asg.sh
```

This creates:
- VPC with public/private subnets
- ALB with weighted listener rules
- S3 bucket for artifacts
- Outputs saved to `harness-config.txt`

## Step 2: Build First AMI

```bash
./build-ami.sh v1.0-blue
```

## Step 3: Configure Harness (Automated)

The Harness Terraform module creates all entities automatically:

```bash
# Auto-populate tfvars with AWS infrastructure values
./update-harness-tfvars.sh <pov-name>

# Switch to POV and apply
./switch-pov.sh <pov-name>
cd infra/terraform-harness
terraform init && terraform apply
```

This creates:
- AWS Connector (IRSA-based)
- ASG Service with manifests and AMI artifact
- ASG Infrastructure Definition
- ASG Blue-Green Pipeline (with ALB values pre-configured)

### Manual Setup (Alternative)

<details>
<summary>Click to expand manual Harness setup steps</summary>

#### Create AWS Connector
1. **Project Settings → Connectors → New Connector → AWS**
2. Name: `aws-asg`
3. Credentials: **Use IRSA** or **Assume Role** (use delegate's IAM role)
4. Test connection

#### Create Service
1. **Services → New Service**
2. Name: `spring-boot-asg`
3. Deployment Type: **AWS Auto Scaling Group**
4. **Manifests** (from repo):
   - Launch Template: `/infra/harness/asg/launch-template.json`
   - ASG Configuration: `/infra/harness/asg/asg-config.json`
5. **Artifacts**:
   - Type: **Amazon Machine Image**
   - Connector: `aws-asg`
   - Region: `us-east-1`
   - Filters: `Application` = `<PROJECT_NAME>`
   - Version: Runtime Input

#### Create Environment & Infrastructure
1. **Environments → New Environment** → Name: `dev`, Type: **Pre-Production**
2. **New Infrastructure** → Type: **AWS Auto Scaling Group**
3. Connector: `aws-asg`, Region: `us-east-1`

#### Create Pipeline
1. **Pipelines → New Pipeline** → Name: `ASG Blue-Green Deploy`
2. Add Stage: **Deploy → AWS Auto Scaling Group**
3. Deployment Strategy: **Blue Green**
4. Use values from `harness-config.txt` for ALB configuration

</details>

## Step 4: Run Pipeline

1. Select AMI version (e.g., `spring-boot-hello-world-v1.0-blue`)
2. Watch traffic shift from old ASG to new
3. Access app: `http://<ALB_DNS>/`

---

# Option 2: Lambda Deployment

## What You Get
- ECR repository for container images
- Lambda function with Function URL
- Alias-based traffic shifting for blue-green/canary

## Step 1: Deploy Infrastructure

```bash
# Deploy Lambda infra + push first image
PROJECT_NAME=acme-demo OWNER=yourname ./deploy-lambda.sh v1.0-blue
```

This creates:
- ECR repository
- Lambda function with `live` alias
- Public Function URL

## Step 2: Configure Harness (Automated)

The Harness Terraform module creates all entities automatically:

```bash
# Switch to POV and apply (if not already done for ASG)
./switch-pov.sh <pov-name>
cd infra/terraform-harness
terraform init && terraform apply
```

This creates:
- AWS Connector (IRSA-based)
- Lambda Service with manifests and ECR artifact
- Lambda Infrastructure Definition
- Lambda Canary Pipeline

### Manual Setup (Alternative)

<details>
<summary>Click to expand manual Harness setup steps</summary>

#### Create AWS Connector
1. **Project Settings → Connectors → New Connector → AWS**
2. Name: `aws-lambda`
3. Credentials: **Use IRSA** or **Assume Role**
4. Test connection

#### Create Service
1. **Services → New Service**
2. Name: `spring-boot-lambda`
3. Deployment Type: **AWS Lambda**
4. **Manifests** (from repo):
   - Function Definition: `/infra/harness/lambda/function-definition.json`
   - Alias Definition: `/infra/harness/lambda/alias-definition.json`
5. **Artifacts**:
   - Type: **ECR**
   - Connector: `aws-lambda`
   - Region: `us-east-1`
   - Image Path: `<PROJECT_NAME>`
   - Tag: Runtime Input

#### Create Environment & Infrastructure
1. **Environments → New Environment** → Name: `dev`, Type: **Pre-Production**
2. **New Infrastructure** → Type: **AWS Lambda**
3. Connector: `aws-lambda`, Region: `us-east-1`

#### Create Pipeline
1. **Pipelines → New Pipeline** → Name: `Lambda Canary Deploy`
2. Add Stage: **Deploy → AWS Lambda**
3. Deployment Strategy: **Canary**

</details>

### Lambda Canary Steps

| Step | Traffic to New Version |
|------|------------------------|
| Deploy | 0% (new version created) |
| Shift 10% | 10% |
| Approval | Manual gate |
| Shift 100% | 100% |

## Step 3: Run Pipeline

1. Select ECR image tag (e.g., `v1.0-blue`)
2. Watch traffic shift via alias routing
3. Access app: `<FUNCTION_URL>/api`

---

# Option 3: EKS/Kubernetes Deployment

## What You Get
- ECR repository for container images
- Kubernetes Deployment + LoadBalancer Service
- Works with existing EKS cluster (from `harness-automation` repo)

## EKS Cluster Options

| Option | When to Use |
|--------|-------------|
| **Use existing cluster** | You have EKS from `harness-automation` or customer's cluster |
| **Create dedicated cluster** | Need isolation or self-contained demo |

### Option A: Use Existing Cluster (Recommended)
```bash
# Ensure kubectl points to your cluster
aws eks update-kubeconfig --name <cluster-name> --region us-east-1
kubectl cluster-info
```

### Option B: Create Dedicated Cluster
```bash
cd infra/terraform-eks
terraform init
terraform apply -var "project_name=acme-demo" -var "owner=yourname"

# Configure kubectl
$(terraform output -raw kubeconfig_command)
```
> This references the EKS module from `harness-automation` repo via Git.

## Step 1: Deploy to EKS

```bash
# Ensure kubectl is connected to your EKS cluster
kubectl cluster-info

# Deploy with your name
PROJECT_NAME=acme-demo OWNER=yourname ./deploy-eks.sh v1.0-blue
```

This creates:
- ECR repository (if not exists)
- Kubernetes Deployment (2 replicas)
- LoadBalancer Service

## Step 2: Configure Harness

### Create AWS Connector (for ECR)
1. **Project Settings → Connectors → New Connector → AWS**
2. Name: `aws-ecr`
3. Credentials: **Use IRSA** or **Assume Role**
4. Test connection

### Create Kubernetes Connector
1. **Project Settings → Connectors → New Connector → Kubernetes Cluster**
2. Name: `eks-cluster`
3. Credentials: **Use Delegate credentials** (if delegate runs in EKS)
4. Test connection

### Create Service
1. **Services → New Service**
2. Name: `spring-boot-k8s`
3. Deployment Type: **Kubernetes**
4. **Manifests** (from repo):
   - Type: **K8s Manifest**
   - Store: **Git**
   - Path: `/infra/kubernetes/`
   - Values file: `values.yml`
5. **Artifacts**:
   - Type: **ECR**
   - Connector: `aws-ecr`
   - Region: `us-east-1`
   - Image Path: `<PROJECT_NAME>`
   - Tag: Runtime Input

### Create Environment
1. **Environments → New Environment**
2. Name: `dev`
3. Type: **Pre-Production**

### Create Infrastructure Definition
1. In the environment, **New Infrastructure**
2. Name: `eks-infra`
3. Type: **Kubernetes**
4. Connector: `eks-cluster`
5. Namespace: `default` (or your namespace)

### Create Pipeline
1. **Pipelines → New Pipeline**
2. Name: `K8s Canary Deploy`
3. Add Stage: **Deploy → Kubernetes**
4. Deployment Strategy: **Canary**, **Blue Green**, or **Rolling**

### Kubernetes Deployment Strategies

| Strategy | How It Works |
|----------|--------------|
| **Rolling** | Gradually replaces old pods with new |
| **Canary** | Deploy canary pods, shift traffic %, then full rollout |
| **Blue-Green** | Deploy new version, swap service selector |

## Step 3: Run Pipeline

1. Select ECR image tag (e.g., `v1.0-blue`)
2. Watch pods roll out
3. Access app via LoadBalancer URL

---

# Delegate IAM Permissions

Your Harness delegate needs these AWS permissions. See `infra/terraform-delegate/` for a reference Terraform module.

## Required for ASG
- `autoscaling:*`
- `ec2:*LaunchTemplate*`, `ec2:RunInstances`, `ec2:DescribeImages`
- `elasticloadbalancing:*`
- `iam:PassRole`

## Required for Lambda
- `lambda:*`
- `ecr:*`
- `iam:PassRole`

## Required for EKS
- `ecr:*`
- `eks:DescribeCluster` (if using AWS connector for K8s)

---

# Cleanup

```bash
# ASG infrastructure
./deploy-asg.sh destroy

# Lambda infrastructure
./deploy-lambda.sh destroy

# EKS deployment (removes K8s resources, keeps ECR)
./deploy-eks.sh destroy
```

---

# Troubleshooting

| Issue | Solution |
|-------|----------|
| AWS credentials expired | Run `aws sso login` |
| Terraform state locked | Delete `.terraform.lock.hcl` and re-run |
| Lambda cold start timeout | Increase Lambda timeout to 30s |
| ASG instances unhealthy | Check security group allows ALB → port 8080 |
| AMI not found | Verify `Application` tag matches `PROJECT_NAME` |

---

# Demo Flow

## ASG Blue-Green Demo
1. Show app running at ALB URL (version 1.0-blue)
2. Build new AMI: `./build-ami.sh v2.0-green`
3. Run Harness pipeline with new AMI
4. Show 20% traffic shift in ALB console
5. Approve swap → 100% on new version
6. Refresh browser → new version

## Lambda Canary Demo
1. Show app running at Function URL
2. Build new image: `docker build --platform linux/amd64 -f Dockerfile.lambda -t app:v2.0-green .`
3. Push to ECR
4. Run Harness pipeline with new tag
5. Show canary traffic shift (10% → 50% → 100%)
6. Demonstrate instant rollback by pointing alias back

## EKS Kubernetes Demo
1. Show app running at LoadBalancer URL
2. Build new image: `./deploy-eks.sh build v2.0-green`
3. Run Harness pipeline with new tag
4. Show pods rolling out: `kubectl get pods -w`
5. Demonstrate rollback with Harness or `kubectl rollout undo`
