#!/bin/bash
# Updates terraform.tfvars for Harness with values from AWS infrastructure
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get POV name from argument or current backend
POV_NAME="${1:-}"
if [ -z "$POV_NAME" ]; then
    if [ -L "$SCRIPT_DIR/infra/backend.hcl" ]; then
        POV_NAME=$(readlink "$SCRIPT_DIR/infra/backend.hcl" | sed 's/backend-//' | sed 's/\.hcl//')
    else
        echo -e "${RED}Error: No POV specified and no active backend.hcl symlink${NC}"
        echo "Usage: ./update-harness-tfvars.sh <pov-name>"
        exit 1
    fi
fi

TFVARS_FILE="$SCRIPT_DIR/infra/terraform-harness/terraform.tfvars.${POV_NAME}"

if [ ! -f "$TFVARS_FILE" ]; then
    echo -e "${RED}Error: $TFVARS_FILE not found${NC}"
    echo "Run ./setup-pov.sh first to create the POV"
    exit 1
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Updating Harness tfvars from AWS Infrastructure        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Get values from AWS Terraform
cd "$SCRIPT_DIR/infra/terraform"

# Initialize if needed
if [ ! -d ".terraform" ]; then
    echo -e "${YELLOW}Initializing Terraform...${NC}"
    terraform init -backend-config=../backend.hcl > /dev/null 2>&1
fi

echo -e "${YELLOW}Extracting values from AWS infrastructure...${NC}"

# Get security group ID
SECURITY_GROUP=$(terraform output -raw app_security_group_id 2>/dev/null || echo "")
if [ -z "$SECURITY_GROUP" ]; then
    echo -e "${YELLOW}Warning: Could not get security group ID${NC}"
fi

# Get subnet IDs (public subnets for ASG)
SUBNET_IDS=$(terraform output -json subnet_ids 2>/dev/null | jq -r 'join(",")' 2>/dev/null || echo "")
if [ -z "$SUBNET_IDS" ]; then
    echo -e "${YELLOW}Warning: Could not get subnet IDs${NC}"
fi

# Get ALB name
ALB_NAME=$(terraform output -raw alb_dns_name 2>/dev/null | sed 's/-.*//' 2>/dev/null || echo "")
# Actually get the ALB name from the ARN or directly
ALB_ARN=$(terraform output -raw alb_arn 2>/dev/null || echo "")
if [ -n "$ALB_ARN" ]; then
    ALB_NAME=$(echo "$ALB_ARN" | sed 's/.*:loadbalancer\/app\///' | cut -d'/' -f1)
fi

# Get listener ARNs
PROD_LISTENER_ARN=$(terraform output -raw prod_listener_arn 2>/dev/null || echo "")
PROD_LISTENER_RULE_ARN=$(terraform output -raw weighted_listener_rule_arn 2>/dev/null || echo "")

# For single-listener setup, stage listener is same as prod
STAGE_LISTENER_ARN="$PROD_LISTENER_ARN"
STAGE_LISTENER_RULE_ARN="$PROD_LISTENER_RULE_ARN"

cd "$SCRIPT_DIR"

echo ""
echo -e "${GREEN}Values extracted:${NC}"
echo -e "  Security Group:        ${BLUE}${SECURITY_GROUP:-N/A}${NC}"
echo -e "  Subnet IDs:            ${BLUE}${SUBNET_IDS:-N/A}${NC}"
echo -e "  ALB Name:              ${BLUE}${ALB_NAME:-N/A}${NC}"
echo -e "  Prod Listener ARN:     ${BLUE}${PROD_LISTENER_ARN:-N/A}${NC}"
echo -e "  Prod Listener Rule:    ${BLUE}${PROD_LISTENER_RULE_ARN:-N/A}${NC}"
echo ""

# Update tfvars file
if [ -n "$SECURITY_GROUP" ]; then
    if grep -q "^asg_security_group_id" "$TFVARS_FILE"; then
        sed -i.bak "s|^asg_security_group_id.*|asg_security_group_id = \"$SECURITY_GROUP\"|" "$TFVARS_FILE"
    else
        echo "" >> "$TFVARS_FILE"
        echo "# ASG Infrastructure Values (auto-populated)" >> "$TFVARS_FILE"
        echo "asg_security_group_id = \"$SECURITY_GROUP\"" >> "$TFVARS_FILE"
    fi
    echo -e "${GREEN}✓ Updated asg_security_group_id${NC}"
fi

if [ -n "$SUBNET_IDS" ]; then
    if grep -q "^asg_subnet_ids" "$TFVARS_FILE"; then
        sed -i.bak "s|^asg_subnet_ids.*|asg_subnet_ids = \"$SUBNET_IDS\"|" "$TFVARS_FILE"
    else
        echo "asg_subnet_ids = \"$SUBNET_IDS\"" >> "$TFVARS_FILE"
    fi
    echo -e "${GREEN}✓ Updated asg_subnet_ids${NC}"
fi

# Update ALB values
if [ -n "$ALB_NAME" ]; then
    if grep -q "^alb_name" "$TFVARS_FILE"; then
        sed -i.bak "s|^alb_name.*|alb_name = \"$ALB_NAME\"|" "$TFVARS_FILE"
    else
        echo "" >> "$TFVARS_FILE"
        echo "# ALB Configuration (auto-populated)" >> "$TFVARS_FILE"
        echo "alb_name = \"$ALB_NAME\"" >> "$TFVARS_FILE"
    fi
    echo -e "${GREEN}✓ Updated alb_name${NC}"
fi

if [ -n "$PROD_LISTENER_ARN" ]; then
    if grep -q "^prod_listener_arn" "$TFVARS_FILE"; then
        sed -i.bak "s|^prod_listener_arn.*|prod_listener_arn = \"$PROD_LISTENER_ARN\"|" "$TFVARS_FILE"
    else
        echo "prod_listener_arn = \"$PROD_LISTENER_ARN\"" >> "$TFVARS_FILE"
    fi
    echo -e "${GREEN}✓ Updated prod_listener_arn${NC}"
fi

if [ -n "$PROD_LISTENER_RULE_ARN" ]; then
    if grep -q "^prod_listener_rule_arn" "$TFVARS_FILE"; then
        sed -i.bak "s|^prod_listener_rule_arn.*|prod_listener_rule_arn = \"$PROD_LISTENER_RULE_ARN\"|" "$TFVARS_FILE"
    else
        echo "prod_listener_rule_arn = \"$PROD_LISTENER_RULE_ARN\"" >> "$TFVARS_FILE"
    fi
    echo -e "${GREEN}✓ Updated prod_listener_rule_arn${NC}"
fi

if [ -n "$STAGE_LISTENER_ARN" ]; then
    if grep -q "^stage_listener_arn" "$TFVARS_FILE"; then
        sed -i.bak "s|^stage_listener_arn.*|stage_listener_arn = \"$STAGE_LISTENER_ARN\"|" "$TFVARS_FILE"
    else
        echo "stage_listener_arn = \"$STAGE_LISTENER_ARN\"" >> "$TFVARS_FILE"
    fi
    echo -e "${GREEN}✓ Updated stage_listener_arn${NC}"
fi

if [ -n "$STAGE_LISTENER_RULE_ARN" ]; then
    if grep -q "^stage_listener_rule_arn" "$TFVARS_FILE"; then
        sed -i.bak "s|^stage_listener_rule_arn.*|stage_listener_rule_arn = \"$STAGE_LISTENER_RULE_ARN\"|" "$TFVARS_FILE"
    else
        echo "stage_listener_rule_arn = \"$STAGE_LISTENER_RULE_ARN\"" >> "$TFVARS_FILE"
    fi
    echo -e "${GREEN}✓ Updated stage_listener_rule_arn${NC}"
fi

# Clean up backup files
rm -f "$TFVARS_FILE.bak"

echo ""
echo -e "${GREEN}Updated: $TFVARS_FILE${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "1. Switch to POV:     ${BLUE}./switch-pov.sh $POV_NAME${NC}"
echo -e "2. Apply Harness TF:  ${BLUE}cd infra/terraform-harness && terraform apply${NC}"
