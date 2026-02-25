# Infrastructure

This directory contains all infrastructure-as-code for deploying the Spring Boot Hello World application to AWS with Harness Blue-Green deployment support.

---

## Directory Structure

```
infra/
├─ terraform-bootstrap/    # Terraform state backend (run first)
│  ├─ main.tf              # S3 bucket + DynamoDB table for state locking
│  ├─ variables.tf
│  └─ outputs.tf
├─ terraform/              # Main AWS infrastructure
│  ├─ main.tf              # Provider config, AMI data source
│  ├─ variables.tf         # Configurable inputs
│  ├─ vpc.tf               # VPC, subnets, internet gateway
│  ├─ security_groups.tf   # ALB and app security groups
│  ├─ alb.tf               # ALB with Blue-Green target groups
│  ├─ asg.tf               # Auto Scaling Group + launch template
│  ├─ iam.tf               # EC2 role with S3 access
│  ├─ s3.tf                # Artifacts bucket
│  ├─ user_data.sh.tpl     # EC2 bootstrap script
│  └─ outputs.tf           # Resource ARNs for Harness config
├─ packer/                 # AMI building (required for Harness ASG)
│  ├─ spring-boot-ami.pkr.hcl    # Packer template
│  └─ variables.pkrvars.hcl.example
├─ harness/
│  ├─ asg/                 # Harness ASG Blue-Green deployment
│  │  ├─ launch-template.json
│  │  ├─ asg-config.json
│  │  ├─ user-data.sh
│  │  ├─ scaling-policy.json
│  │  ├─ service.yaml
│  │  ├─ environment.yaml
│  │  ├─ infrastructure.yaml
│  │  └─ pipeline-blue-green.yaml
│  └─ service/             # Harness Kubernetes service (legacy)
└─ kubernetes/             # Kubernetes manifests
```

---

## Prerequisites

- **Terraform** >= 1.0
- **Packer** >= 1.8 (for building AMIs)
- **AWS CLI** configured with credentials that have permissions for:
  - EC2, VPC, ALB, ASG, S3, DynamoDB, IAM, CloudWatch
- **Harness account** (for Blue-Green deployments)

---

## Quick Start

From the repo root:

```bash
./setup.sh
```

Or manually:

```bash
# 1. Build the application
mvn clean package -DskipTests

# 2. Deploy state backend
cd infra/terraform-bootstrap
terraform init
terraform apply -auto-approve

# 3. Deploy main infrastructure
cd ../terraform
terraform init
terraform apply -auto-approve

# 4. Build AMI with Packer
cd ../packer
packer init spring-boot-ami.pkr.hcl
packer build -var "jar_path=../../target/spring-boot-hello-world-1.0-SNAPSHOT.jar" spring-boot-ami.pkr.hcl

# 5. Get the AMI ID and app URL
aws ec2 describe-images --owners self \
  --filters "Name=tag:Application,Values=spring-boot-hello-world" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text

cd ../terraform
terraform output alb_dns_name
```

---

## Terraform Configuration

### Variables

Edit `infra/terraform/terraform.tfvars` (copy from `terraform.tfvars.example`):

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-east-1` | AWS region |
| `app_name` | `spring-boot-hello-world` | Application name (used in resource naming) |
| `environment` | `dev` | Environment (dev/staging/prod) |
| `instance_type` | `t3.micro` | EC2 instance type |
| `min_size` | `1` | ASG minimum instances |
| `max_size` | `3` | ASG maximum instances |
| `desired_capacity` | `2` | ASG desired instances |
| `app_port` | `8080` | Application port |

### Outputs

After `terraform apply`, these outputs are available:

| Output | Description |
|--------|-------------|
| `alb_dns_name` | Application URL |
| `s3_bucket_name` | Artifacts bucket for JAR uploads |
| `prod_listener_arn` | ALB listener ARN (for Harness) |
| `weighted_listener_rule_arn` | Listener rule ARN (for Harness traffic shifting) |
| `prod_target_group_arn` | Production target group ARN |
| `stage_target_group_arn` | Stage target group ARN |

---

## AWS Architecture

```
                    ┌─────────────────────────────────────────────────────┐
                    │                      VPC                            │
                    │  ┌─────────────────────────────────────────────┐   │
Internet ──────────►│  │              Application Load Balancer       │   │
                    │  │  ┌─────────────┐      ┌─────────────┐       │   │
                    │  │  │ Prod TG     │      │ Stage TG    │       │   │
                    │  │  │ (weight:100)│      │ (weight:0)  │       │   │
                    │  │  └──────┬──────┘      └──────┬──────┘       │   │
                    │  └─────────┼────────────────────┼───────────────┘   │
                    │            │                    │                   │
                    │  ┌─────────▼────────┐ ┌────────▼─────────┐        │
                    │  │   ASG (Prod)     │ │   ASG (Stage)    │        │
                    │  │   EC2 instances  │ │   (Blue-Green)   │        │
                    │  └──────────────────┘ └──────────────────┘        │
                    │                                                    │
                    │  ┌──────────────────┐                             │
                    │  │   S3 Bucket      │◄── JAR artifacts            │
                    │  └──────────────────┘                             │
                    └─────────────────────────────────────────────────────┘
```

### Blue-Green Traffic Shifting

The ALB is configured with:
- **Two target groups**: `prod` and `stage`
- **Weighted listener rule**: Supports traffic distribution between target groups
- Harness manages the weights during deployment (e.g., 10% → 50% → 100%)

---

## Harness Setup

### 1. Create AWS Connector

In Harness, create an AWS Cloud Provider connector with:
- Access to EC2, ASG, ALB, S3
- Region: `us-east-1` (or your configured region)

### 2. Create ASG Service

Use the service definition at `infra/harness/asg/service.yaml`:
- Type: `Asg`
- Manifests: Launch template, ASG config, scaling policy, user data
- Artifact: S3 bucket with JAR file

### 3. Create Environment & Infrastructure

- **Environment**: `infra/harness/asg/environment.yaml`
- **Infrastructure**: `infra/harness/asg/infrastructure.yaml`
  - Set the AWS connector reference
  - Region: `us-east-1`

### 4. Create Pipeline

Import or create pipeline from `infra/harness/asg/pipeline-blue-green.yaml`:

**Pipeline Flow:**
1. **ASG Blue Green Deploy** - Creates new ASG with stage target group
2. **Traffic Shift 10%** - Shifts 10% traffic to new ASG
3. **Approval** - Manual gate
4. **Traffic Shift 50%** - Shifts 50% traffic
5. **Approval** - Manual gate
6. **Traffic Shift 100%** - Full cutover, downsize old ASG

**Required Inputs:**
- `prodListener`: Use `prod_listener_arn` from Terraform output
- `prodListenerRuleArn`: Use `weighted_listener_rule_arn` from Terraform output

### 5. Configure Load Balancer in Pipeline

In the ASG Blue Green Deploy step:
- **Load Balancer**: `spring-boot-hello-world-alb`
- **Prod Listener**: ARN from `terraform output prod_listener_arn`
- **Prod Listener Rule ARN**: ARN from `terraform output weighted_listener_rule_arn`
- **Use Traffic Shift**: Enabled

---

## Cleanup

To destroy all resources:

```bash
# Destroy main infrastructure
cd infra/terraform
terraform destroy -auto-approve

# Destroy state backend (optional - contains state files)
cd ../terraform-bootstrap
terraform destroy -auto-approve
```

---

## Troubleshooting

### Instances not healthy
- Check security group allows ALB to reach port 8080
- Verify JAR was uploaded to S3
- Check instance logs: `aws ssm start-session --target <instance-id>`

### Traffic not shifting
- Verify listener rule ARN is correct in Harness
- Check ALB listener has both target groups configured
- Ensure Harness AWS connector has ALB permissions

### Terraform state issues
- Run `terraform init -migrate-state` after enabling S3 backend
- Ensure DynamoDB table exists for state locking
