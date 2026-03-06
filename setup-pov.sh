#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              POV Environment Setup                         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Prompt for POV name
read -p "Enter POV name (e.g., acme, tr, customer-name): " POV_NAME
if [ -z "$POV_NAME" ]; then
    echo -e "${RED}POV name is required${NC}"
    exit 1
fi

# Sanitize POV name (lowercase, replace spaces with dashes)
POV_NAME=$(echo "$POV_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo -e "${RED}Could not get AWS Account ID. Make sure AWS CLI is configured.${NC}"
    exit 1
fi
echo -e "${GREEN}Using AWS Account: ${AWS_ACCOUNT_ID}${NC}"

echo ""
echo -e "${YELLOW}Setting up POV: ${POV_NAME}${NC}"
echo ""

# Step 1: Create backend config
BACKEND_FILE="$SCRIPT_DIR/infra/backend-${POV_NAME}.hcl"
if [ -f "$BACKEND_FILE" ]; then
    echo -e "${GREEN}✓ Backend config already exists: backend-${POV_NAME}.hcl${NC}"
else
    echo -e "${YELLOW}Creating backend config...${NC}"
    cat > "$BACKEND_FILE" << EOF
# Terraform Backend Configuration for ${POV_NAME} POV
bucket         = "${POV_NAME}-spring-boot-hello-world-terraform-state-dev"
region         = "us-east-1"
dynamodb_table = "${POV_NAME}-spring-boot-hello-world-terraform-locks-dev"
encrypt        = true
EOF
    echo -e "${GREEN}✓ Created: infra/backend-${POV_NAME}.hcl${NC}"
fi

# Step 2: Symlink as active backend
echo -e "${YELLOW}Setting as active backend...${NC}"
ln -sf "backend-${POV_NAME}.hcl" "$SCRIPT_DIR/infra/backend.hcl"
echo -e "${GREEN}✓ Linked: infra/backend.hcl -> backend-${POV_NAME}.hcl${NC}"

# Step 3: Create Harness tfvars
TFVARS_FILE="$SCRIPT_DIR/infra/terraform-harness/terraform.tfvars.${POV_NAME}"
if [ -f "$TFVARS_FILE" ]; then
    echo -e "${GREEN}✓ Harness tfvars already exists: terraform.tfvars.${POV_NAME}${NC}"
else
    echo -e "${YELLOW}Creating Harness tfvars...${NC}"
    cp "$SCRIPT_DIR/infra/terraform-harness/terraform.tfvars.example" "$TFVARS_FILE"
    # Update with detected values
    sed -i.bak "s/aws_account_id = \"123456789012\"/aws_account_id = \"${AWS_ACCOUNT_ID}\"/" "$TFVARS_FILE"
    sed -i.bak "s/project_name   = \"tr-hello-world\"/project_name   = \"${POV_NAME}-hello-world\"/" "$TFVARS_FILE"
    rm -f "$TFVARS_FILE.bak"
    echo -e "${GREEN}✓ Created: infra/terraform-harness/terraform.tfvars.${POV_NAME}${NC}"
    echo -e "${BLUE}  → Edit this file with your Harness account details${NC}"
fi

# Step 4: Create .env file for this POV
ENV_FILE="$SCRIPT_DIR/.env.${POV_NAME}"
if [ -f "$ENV_FILE" ]; then
    echo -e "${GREEN}✓ Environment file already exists: .env.${POV_NAME}${NC}"
else
    cat > "$ENV_FILE" << EOF
# Environment variables for ${POV_NAME} POV
# Source this file before running deploy scripts:
#   source .env.${POV_NAME}

export PROJECT_NAME="${POV_NAME}-hello-world"
export ENVIRONMENT="dev"
export AWS_REGION="us-east-1"
export OWNER="${POV_NAME}"

# Uncomment and set if using AWS SSO profile
# export AWS_PROFILE="${POV_NAME}-profile"
EOF
    echo -e "${GREEN}✓ Created: .env.${POV_NAME}${NC}"
fi

# Step 5: Create S3 state bucket
echo ""
echo -e "${YELLOW}Creating Terraform state backend (S3 + DynamoDB)...${NC}"

BUCKET_NAME="${POV_NAME}-spring-boot-hello-world-terraform-state-dev"
DYNAMO_TABLE="${POV_NAME}-spring-boot-hello-world-terraform-locks-dev"

# Check if bucket exists
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    echo -e "${GREEN}✓ S3 bucket already exists: ${BUCKET_NAME}${NC}"
else
    aws s3api create-bucket --bucket "$BUCKET_NAME" --region us-east-1 > /dev/null
    aws s3api put-bucket-versioning --bucket "$BUCKET_NAME" --versioning-configuration Status=Enabled
    echo -e "${GREEN}✓ Created S3 bucket: ${BUCKET_NAME}${NC}"
fi

# Check if DynamoDB table exists
if aws dynamodb describe-table --table-name "$DYNAMO_TABLE" --region us-east-1 > /dev/null 2>&1; then
    echo -e "${GREEN}✓ DynamoDB table already exists: ${DYNAMO_TABLE}${NC}"
else
    aws dynamodb create-table \
        --table-name "$DYNAMO_TABLE" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region us-east-1 > /dev/null
    echo -e "${GREEN}✓ Created DynamoDB table: ${DYNAMO_TABLE}${NC}"
fi

# Step 6: Clear any existing Terraform state (for fresh POV)
echo ""
echo -e "${YELLOW}Clearing local Terraform state for fresh POV...${NC}"
rm -rf "$SCRIPT_DIR/infra/terraform-lambda/.terraform" "$SCRIPT_DIR/infra/terraform-lambda/terraform.tfstate"* 2>/dev/null || true
rm -rf "$SCRIPT_DIR/infra/terraform/.terraform" "$SCRIPT_DIR/infra/terraform/terraform.tfstate"* 2>/dev/null || true
rm -rf "$SCRIPT_DIR/infra/terraform-eks/.terraform" "$SCRIPT_DIR/infra/terraform-eks/terraform.tfstate"* 2>/dev/null || true
rm -rf "$SCRIPT_DIR/infra/terraform-harness/.terraform" "$SCRIPT_DIR/infra/terraform-harness/terraform.tfstate"* 2>/dev/null || true
echo -e "${GREEN}✓ Local state cleared${NC}"

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              POV Setup Complete!                           ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║  IMPORTANT: Update your Harness account details NOW!       ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Edit this file with YOUR Harness account info:${NC}"
echo -e "   ${BLUE}vi infra/terraform-harness/terraform.tfvars.${POV_NAME}${NC}"
echo ""
echo -e "${YELLOW}Required values to update:${NC}"
echo -e "   - ${GREEN}harness_account_id${NC}    = Your Harness account ID"
echo -e "   - ${GREEN}harness_api_key${NC}       = Your PAT or SAT token"
echo -e "   - ${GREEN}org_identifier${NC}        = Your Harness org (e.g., 'default', 'sandbox')"
echo -e "   - ${GREEN}project_identifier${NC}    = Your Harness project name"
echo -e "   - ${GREEN}delegate_selectors${NC}    = Your delegate tag(s)"
echo -e "   - ${GREEN}github_connector_ref${NC}  = Your GitHub connector (e.g., 'account.github')"
echo -e "   - ${GREEN}github_repo${NC}           = Your forked repo (e.g., 'your-org/spring-boot-hello-world')"
echo ""
echo -e "${GREEN}Next steps after editing:${NC}"
echo ""
echo -e "1. ${YELLOW}Source environment variables:${NC}"
echo -e "   source .env.${POV_NAME}"
echo ""
echo -e "2. ${YELLOW}Deploy AWS infrastructure (choose one):${NC}"
echo -e "   ./deploy-lambda.sh deploy   ${BLUE}# Fast: ~2-3 min${NC}"
echo -e "   ./deploy-asg.sh deploy      ${BLUE}# Full: ~8-12 min${NC}"
echo ""
echo -e "3. ${YELLOW}Setup Harness entities:${NC}"
echo -e "   ./setup-harness.sh ${POV_NAME}"
echo ""
echo -e "4. ${YELLOW}Run pipeline in Harness UI${NC}"
echo ""
