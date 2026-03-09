#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to list available POVs
list_povs() {
    echo -e "${BLUE}Available POVs:${NC}"
    for f in "$SCRIPT_DIR"/infra/backend-*.hcl; do
        if [ -f "$f" ]; then
            pov_name=$(basename "$f" | sed 's/backend-//' | sed 's/\.hcl//')
            # Check if this is the active POV
            if [ -L "$SCRIPT_DIR/infra/backend.hcl" ]; then
                current=$(readlink "$SCRIPT_DIR/infra/backend.hcl" | sed 's/backend-//' | sed 's/\.hcl//')
                if [ "$pov_name" = "$current" ]; then
                    echo -e "  ${GREEN}* $pov_name (active)${NC}"
                else
                    echo -e "    $pov_name"
                fi
            else
                echo -e "    $pov_name"
            fi
        fi
    done
}

# Function to switch POV
switch_pov() {
    local POV_NAME="$1"
    
    # Check if backend file exists
    if [ ! -f "$SCRIPT_DIR/infra/backend-${POV_NAME}.hcl" ]; then
        echo -e "${RED}Error: POV '$POV_NAME' not found.${NC}"
        echo -e "${YELLOW}Run ./setup-pov.sh to create a new POV.${NC}"
        list_povs
        exit 1
    fi
    
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║              Switching POV: ${POV_NAME}                          ${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Step 1: Switch backend.hcl symlink
    echo -e "${YELLOW}Switching backend config...${NC}"
    ln -sf "backend-${POV_NAME}.hcl" "$SCRIPT_DIR/infra/backend.hcl"
    echo -e "${GREEN}✓ Linked: infra/backend.hcl -> backend-${POV_NAME}.hcl${NC}"
    
    # Step 2: Switch terraform.tfvars for Harness
    if [ -f "$SCRIPT_DIR/infra/terraform-harness/terraform.tfvars.${POV_NAME}" ]; then
        echo -e "${YELLOW}Switching Harness tfvars...${NC}"
        cp "$SCRIPT_DIR/infra/terraform-harness/terraform.tfvars.${POV_NAME}" "$SCRIPT_DIR/infra/terraform-harness/terraform.tfvars"
        echo -e "${GREEN}✓ Copied: terraform.tfvars.${POV_NAME} -> terraform.tfvars${NC}"
    else
        echo -e "${YELLOW}⚠ No Harness tfvars found for ${POV_NAME}${NC}"
    fi
    
    # Step 3: Clear local Terraform state to prevent cross-POV contamination
    echo -e "${YELLOW}Clearing local Terraform state...${NC}"
    rm -rf "$SCRIPT_DIR/infra/terraform-lambda/.terraform" 2>/dev/null || true
    rm -rf "$SCRIPT_DIR/infra/terraform-asg/.terraform" 2>/dev/null || true
    rm -rf "$SCRIPT_DIR/infra/terraform-eks/.terraform" 2>/dev/null || true
    rm -rf "$SCRIPT_DIR/infra/terraform-harness/.terraform" 2>/dev/null || true
    echo -e "${GREEN}✓ Local .terraform directories cleared${NC}"
    
    echo ""
    echo -e "${GREEN}POV switched to: ${POV_NAME}${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo -e "1. Source environment: ${BLUE}source .env.${POV_NAME}${NC}"
    echo -e "2. Verify AWS account: ${BLUE}aws sts get-caller-identity${NC}"
    echo -e "3. Run deploy scripts as needed"
    echo ""
    echo -e "${YELLOW}Tip: Add this to your shell to auto-source:${NC}"
    echo -e "   ${BLUE}source .env.${POV_NAME}${NC}"
}

# Main
if [ "$1" = "list" ] || [ "$1" = "-l" ]; then
    list_povs
    exit 0
fi

if [ -z "$1" ]; then
    echo -e "${BLUE}Usage:${NC}"
    echo -e "  ./switch-pov.sh <pov-name>   Switch to a POV"
    echo -e "  ./switch-pov.sh list         List available POVs"
    echo ""
    list_povs
    exit 0
fi

switch_pov "$1"
