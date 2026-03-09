# Spring Boot Hello World

A sample Spring Boot app for demonstrating Harness CD deployments (ASG Blue-Green, Lambda Canary, EKS, GKE, Cloud Run).

---

## Quick Start

```bash
# 1. Setup your POV
./setup-pov.sh
# Enter POV name (e.g., "acme", "customer-name")

# 2. Edit Harness config with YOUR account details
vi infra/terraform-harness/terraform.tfvars.<pov-name>

# 3. Source environment and deploy AWS infrastructure
source .env.<pov-name>
./deploy-lambda.sh deploy   # Fast: ~2-3 min (recommended for demos)
# OR
./deploy-asg.sh deploy      # Full: ~8-12 min

# 4. Setup Harness entities
./setup-harness.sh <pov-name>

# 5. Run pipeline in Harness UI
```

---

## Deployment Options

| Option | Script | Time | Best For |
|--------|--------|------|----------|
| **Lambda Canary** | `./deploy-lambda.sh deploy` | ~3 min | Quick demos, serverless (AWS) |
| **Cloud Run** | `./deploy-cloudrun.sh deploy` | ~3 min | Quick demos, serverless (GCP) |
| **ASG Blue-Green** | `./deploy-asg.sh deploy` | ~10 min | EC2 workloads, ALB traffic shifting (AWS) |
| **EKS Kubernetes** | `./deploy-eks.sh deploy` | ~5 min | Container workloads (AWS, requires cluster) |
| **GKE Kubernetes** | `./deploy-gke.sh deploy` | ~5 min | Container workloads (GCP, requires cluster) |

---

## Prerequisites

**Tools:**
- AWS CLI configured (`aws sso login`) - for AWS deployments
- GCP CLI configured (`gcloud auth login`) - for GCP deployments (GKE, Cloud Run)
- Docker, Terraform, Maven installed
- Packer (for ASG only)

**Harness Account Info** (collect before starting):

| Item | Where to Find | Example |
|------|---------------|---------|
| **Account ID** | URL: `app.harness.io/ng/account/<ACCOUNT_ID>/...` | `EeRjnXTnS4GrLG5VNNJZUw` |
| **API Key (PAT)** | My Profile → API Keys → Create Token | `pat.xxx.xxx.xxx` |
| **Org Identifier** | Organization Settings → Overview | `default` or `sandbox` |
| **Project Identifier** | Project Settings → Overview | `my_project` |
| **Delegate Selector** | Project Settings → Delegates → Tags column | `my-delegate` |
| **GitHub Connector** | Project/Account Settings → Connectors | `account.github` |
| **GitHub Repo** | Your fork of this repo | `your-org/spring-boot-hello-world` |

---

## Switching POVs

```bash
./switch-pov.sh <pov-name>
source .env.<pov-name>
```

---

## Cleanup

```bash
./deploy-lambda.sh destroy
./deploy-asg.sh destroy
./deploy-eks.sh destroy
```

---

<details>
<summary><b>About the Application</b></summary>

### Endpoints
- `GET /` → Landing page
- `GET /api` → Sample JSON response
- `GET /health` → Health check
- `GET /swagger-ui.html` → API docs

### Run Locally
```bash
mvn clean package -DskipTests
java -jar target/spring-boot-hello-world-1.0-SNAPSHOT.jar
open http://localhost:8080/
```

### Tech Stack
- Spring Boot 2.7.x (Java 11)
- Maven build
- Docker container support

</details>

<details>
<summary><b>Project Structure</b></summary>

```
spring-boot-hello-world/
├── src/                          # Application source
├── infra/
│   ├── terraform/                # ASG infrastructure (VPC, ALB, ASG)
│   ├── terraform-lambda/         # Lambda infrastructure (ECR, Lambda)
│   ├── terraform-harness/        # Harness entities (services, pipelines)
│   └── harness/                  # Harness manifest templates
├── setup-pov.sh                  # Initialize new POV
├── setup-harness.sh              # Apply Harness Terraform
├── deploy-lambda.sh              # Lambda deployment
├── deploy-asg.sh                 # ASG deployment
└── deploy-eks.sh                 # EKS deployment
```

</details>

<details>
<summary><b>Manual Harness Setup (Alternative to Terraform)</b></summary>

If you prefer to configure Harness manually instead of using `setup-harness.sh`:

### Lambda
1. **Connector**: AWS connector with ECR access
2. **Service**: AWS Lambda type, ECR artifact
3. **Infrastructure**: Lambda, your region
4. **Pipeline**: Canary deployment strategy

### ASG
1. **Connector**: AWS connector with EC2/ASG/ALB access
2. **Service**: ASG type, AMI artifact
3. **Infrastructure**: ASG, your region
4. **Pipeline**: Blue-Green with traffic shifting

See `infra/terraform-harness/` for the Terraform that automates this.

</details>

<details>
<summary><b>Troubleshooting</b></summary>

| Issue | Solution |
|-------|----------|
| AWS credentials expired | `aws sso login` |
| Harness config not set | Edit `terraform.tfvars.<pov-name>` with your account details |
| Lambda cold start slow | First invocation takes 5-15s, subsequent calls are fast |
| ASG instances unhealthy | Check security group allows ALB → port 8080 |
| AMI not found in Harness | Verify `Application` tag matches your `PROJECT_NAME` |

</details>

<details>
<summary><b>Demo Flow Examples</b></summary>

### Lambda Canary Demo (~5 min)
1. Show app at Function URL
2. Make code change, push new image: `./deploy-lambda.sh v2.0 push`
3. Run Harness pipeline → watch canary traffic shift
4. Show instant rollback capability

### ASG Blue-Green Demo (~10 min)
1. Show app at ALB URL
2. Build new AMI: `./build-ami.sh v2.0`
3. Run Harness pipeline → watch traffic shift 10% → 50% → 100%
4. Show ALB target groups in AWS console

</details>

---

**Questions?** See `infra/terraform-harness/README.md` for Harness Terraform details.
