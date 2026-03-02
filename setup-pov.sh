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
echo -e "${GREEN}Next steps:${NC}"
echo ""
echo -e "1. ${YELLOW}Source environment variables:${NC}"
echo -e "   source .env.${POV_NAME}"
echo ""
echo -e "2. ${YELLOW}Edit Harness config:${NC}"
echo -e "   Edit infra/terraform-harness/terraform.tfvars.${POV_NAME}"
echo -e "   Then: cp infra/terraform-harness/terraform.tfvars.${POV_NAME} infra/terraform-harness/terraform.tfvars"
echo ""
echo -e "3. ${YELLOW}Deploy Lambda (example):${NC}"
echo -e "   ./deploy-lambda.sh push"
echo ""
echo -e "4. ${YELLOW}Apply Harness Terraform:${NC}"
echo -e "   cd infra/terraform-harness && terraform init && terraform apply"
echo ""
echo -e "5. ${YELLOW}Run pipeline in Harness UI${NC}"
echo ""
