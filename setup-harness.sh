#!/bin/bash
# Sets up Harness entities (services, pipelines, infrastructure) via Terraform
# Validates that tfvars has been properly configured before applying
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get POV name from argument or detect from backend symlink
POV_NAME="${1:-}"
if [ -z "$POV_NAME" ]; then
    if [ -L "$SCRIPT_DIR/infra/backend.hcl" ]; then
        POV_NAME=$(readlink "$SCRIPT_DIR/infra/backend.hcl" | sed 's/backend-//' | sed 's/\.hcl//')
    else
        echo -e "${RED}Error: No POV specified and no active backend.hcl symlink${NC}"
        echo "Usage: ./setup-harness.sh <pov-name>"
        exit 1
    fi
fi

TFVARS_FILE="$SCRIPT_DIR/infra/terraform-harness/terraform.tfvars.${POV_NAME}"
HARNESS_DIR="$SCRIPT_DIR/infra/terraform-harness"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              Harness Entity Setup                          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}POV: ${POV_NAME}${NC}"
echo ""

# Check if tfvars file exists
if [ ! -f "$TFVARS_FILE" ]; then
    echo -e "${RED}Error: $TFVARS_FILE not found${NC}"
    echo "Run ./setup-pov.sh first to create the POV"
    exit 1
fi

# Validate tfvars has been configured (not using example/placeholder values)
echo -e "${YELLOW}Validating Harness configuration...${NC}"
echo ""

ERRORS=0

# Check for placeholder account ID
ACCOUNT_ID=$(grep 'harness_account_id' "$TFVARS_FILE" | grep -v '#' | sed 's/.*= *"//' | sed 's/".*//')
if [ "$ACCOUNT_ID" = "your-account-id" ] || [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}✗ harness_account_id is not set (still has placeholder value)${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ harness_account_id: ${ACCOUNT_ID:0:8}...${NC}"
fi

# Check for placeholder API key
API_KEY=$(grep 'harness_api_key' "$TFVARS_FILE" | grep -v '#' | sed 's/.*= *"//' | sed 's/".*//')
if [ "$API_KEY" = "pat.your-api-key-here" ] || [ -z "$API_KEY" ]; then
    echo -e "${RED}✗ harness_api_key is not set (still has placeholder value)${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ harness_api_key: ${API_KEY:0:20}...${NC}"
fi

# Check org identifier
ORG_ID=$(grep 'org_identifier' "$TFVARS_FILE" | grep -v '#' | sed 's/.*= *"//' | sed 's/".*//')
if [ -z "$ORG_ID" ]; then
    echo -e "${RED}✗ org_identifier is not set${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ org_identifier: ${ORG_ID}${NC}"
fi

# Check project identifier
PROJECT_ID=$(grep 'project_identifier' "$TFVARS_FILE" | grep -v '#' | sed 's/.*= *"//' | sed 's/".*//')
if [ "$PROJECT_ID" = "spring_boot_pov" ] || [ -z "$PROJECT_ID" ]; then
    echo -e "${YELLOW}⚠ project_identifier: ${PROJECT_ID:-not set} (using example value - is this correct?)${NC}"
else
    echo -e "${GREEN}✓ project_identifier: ${PROJECT_ID}${NC}"
fi

# Check delegate selectors
DELEGATE=$(grep 'delegate_selectors' "$TFVARS_FILE" | grep -v '#' | sed 's/.*\["//' | sed 's/".*//')
if [ "$DELEGATE" = "harness-delegate" ]; then
    echo -e "${YELLOW}⚠ delegate_selectors: ${DELEGATE} (using example value - is this correct?)${NC}"
elif [ -z "$DELEGATE" ]; then
    echo -e "${RED}✗ delegate_selectors is not set${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ delegate_selectors: ${DELEGATE}${NC}"
fi

# Check GitHub repo
GITHUB_REPO=$(grep 'github_repo' "$TFVARS_FILE" | grep -v '#' | sed 's/.*= *"//' | sed 's/".*//')
if [ "$GITHUB_REPO" = "your-org/spring-boot-hello-world" ] || [ -z "$GITHUB_REPO" ]; then
    echo -e "${RED}✗ github_repo is not set (still has placeholder value)${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ github_repo: ${GITHUB_REPO}${NC}"
fi

echo ""

# If there are errors, stop and ask user to fix
if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  Configuration errors found! Please fix before continuing  ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Edit your configuration file:${NC}"
    echo -e "   ${BLUE}vi $TFVARS_FILE${NC}"
    echo ""
    echo -e "${YELLOW}Then run this script again:${NC}"
    echo -e "   ${BLUE}./setup-harness.sh ${POV_NAME}${NC}"
    exit 1
fi

# Ask for confirmation
echo -e "${YELLOW}The above configuration will be used to create Harness entities.${NC}"
read -p "Continue? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo -e "${YELLOW}Aborted. Edit your config and try again.${NC}"
    exit 0
fi

# Copy tfvars to active file
echo ""
echo -e "${YELLOW}Copying configuration...${NC}"
cp "$TFVARS_FILE" "$HARNESS_DIR/terraform.tfvars"
echo -e "${GREEN}✓ Copied terraform.tfvars.${POV_NAME} -> terraform.tfvars${NC}"

# Run update-harness-tfvars.sh to populate AWS values if AWS infra exists
if [ -f "$SCRIPT_DIR/update-harness-tfvars.sh" ]; then
    echo ""
    echo -e "${YELLOW}Checking for AWS infrastructure values...${NC}"
    "$SCRIPT_DIR/update-harness-tfvars.sh" "$POV_NAME" 2>/dev/null || true
fi

# Initialize and apply Terraform
echo ""
echo -e "${YELLOW}Initializing Terraform...${NC}"
cd "$HARNESS_DIR"
terraform init -input=false

echo ""
echo -e "${YELLOW}Planning Harness entity creation...${NC}"
terraform plan -out=tfplan

echo ""
read -p "Apply this plan? (y/n): " APPLY_CONFIRM
if [ "$APPLY_CONFIRM" != "y" ] && [ "$APPLY_CONFIRM" != "Y" ]; then
    echo -e "${YELLOW}Aborted. Run 'terraform apply' manually when ready.${NC}"
    rm -f tfplan
    exit 0
fi

echo ""
echo -e "${YELLOW}Applying Terraform...${NC}"
terraform apply tfplan
rm -f tfplan

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              Harness Setup Complete!                       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Harness entities created in:${NC}"
echo -e "   Org:     ${BLUE}${ORG_ID}${NC}"
echo -e "   Project: ${BLUE}${PROJECT_ID}${NC}"
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo -e "1. Go to Harness UI and run your pipeline:"
echo -e "   - ${BLUE}lambda_canary_deploy${NC} (for Lambda)"
echo -e "   - ${BLUE}asg_blue_green_deploy${NC} (for ASG)"
echo ""
