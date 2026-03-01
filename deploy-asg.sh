#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# PROJECT CONFIGURATION - Change this for your POV
# =============================================================================
PROJECT_NAME="${PROJECT_NAME:-spring-boot-hello-world}"
OWNER="${OWNER:-unknown}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ENVIRONMENT="${ENVIRONMENT:-dev}"

# Install Packer (macOS via Homebrew, Linux via apt/yum)
install_packer() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            brew tap hashicorp/tap 2>/dev/null || true
            brew install hashicorp/tap/packer
        else
            echo -e "${RED}Homebrew not found. Please install Homebrew first: https://brew.sh${NC}"
            exit 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        if command -v apt-get &> /dev/null; then
            # Debian/Ubuntu
            curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
            sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
            sudo apt-get update && sudo apt-get install -y packer
        elif command -v yum &> /dev/null; then
            # RHEL/CentOS
            sudo yum install -y yum-utils
            sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
            sudo yum -y install packer
        else
            echo -e "${RED}Unsupported Linux distribution. Please install Packer manually.${NC}"
            exit 1
        fi
    else
        echo -e "${RED}Unsupported OS. Please install Packer manually: https://developer.hashicorp.com/packer/downloads${NC}"
        exit 1
    fi
}

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Spring Boot Hello World - AWS ASG Setup Script         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
check_prereqs() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    local missing=0
    
    if ! command -v java &> /dev/null; then
        echo -e "${RED}✗ Java not found. Please install JDK 11+${NC}"
        missing=1
    else
        echo -e "${GREEN}✓ Java found: $(java -version 2>&1 | head -n 1)${NC}"
    fi
    
    if ! command -v mvn &> /dev/null; then
        echo -e "${RED}✗ Maven not found. Please install Maven 3.8+${NC}"
        missing=1
    else
        echo -e "${GREEN}✓ Maven found: $(mvn -version 2>&1 | head -n 1)${NC}"
    fi
    
    if ! command -v terraform &> /dev/null; then
        echo -e "${RED}✗ Terraform not found. Please install Terraform 1.0+${NC}"
        missing=1
    else
        echo -e "${GREEN}✓ Terraform found: $(terraform version 2>&1 | head -n 1)${NC}"
    fi
    
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}✗ AWS CLI not found. Please install and configure AWS CLI${NC}"
        missing=1
    else
        echo -e "${GREEN}✓ AWS CLI found: $(aws --version 2>&1)${NC}"
    fi
    
    if ! command -v packer &> /dev/null; then
        echo -e "${YELLOW}Packer not found. Installing...${NC}"
        install_packer
    fi
    echo -e "${GREEN}✓ Packer found: $(packer version 2>&1 | head -n 1)${NC}"
    
    if [ $missing -eq 1 ]; then
        echo -e "${RED}Please install missing prerequisites and try again.${NC}"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${RED}✗ AWS credentials not configured or invalid${NC}"
        echo -e "${YELLOW}Run 'aws configure' to set up your credentials${NC}"
        exit 1
    else
        echo -e "${GREEN}✓ AWS credentials configured${NC}"
    fi
    
    echo ""
}

# Build the application
build_app() {
    echo -e "${YELLOW}Step 1: Building application...${NC}"
    cd "$SCRIPT_DIR"
    mvn clean package -DskipTests -q
    
    if [ -f "target/spring-boot-hello-world-1.0-SNAPSHOT.jar" ]; then
        echo -e "${GREEN}✓ Application built successfully${NC}"
    else
        echo -e "${RED}✗ Build failed - JAR not found${NC}"
        exit 1
    fi
    echo ""
}

# Deploy Terraform state backend
deploy_bootstrap() {
    echo -e "${YELLOW}Step 2: Deploying Terraform state backend...${NC}"
    cd "$SCRIPT_DIR/infra/terraform-bootstrap"
    
    terraform init -input=false > /dev/null
    terraform apply -auto-approve -input=false
    
    echo -e "${GREEN}✓ State backend deployed${NC}"
    echo ""
}

# Deploy main infrastructure
deploy_infrastructure() {
    echo -e "${YELLOW}Step 3: Deploying AWS infrastructure...${NC}"
    cd "$SCRIPT_DIR/infra/terraform"
    
    # Copy example tfvars if not exists
    if [ ! -f "terraform.tfvars" ]; then
        if [ -f "terraform.tfvars.example" ]; then
            cp terraform.tfvars.example terraform.tfvars
            echo -e "${BLUE}  Created terraform.tfvars from example${NC}"
        fi
    fi
    
    terraform init -input=false > /dev/null
    terraform apply -auto-approve -input=false -var "app_name=$PROJECT_NAME" -var "environment=$ENVIRONMENT" -var "aws_region=$AWS_REGION" -var "owner=$OWNER"
    
    echo -e "${GREEN}✓ Infrastructure deployed${NC}"
    echo ""
}

# Build AMI with Packer
build_ami() {
    echo -e "${YELLOW}Step 4: Building AMI with Packer...${NC}"
    cd "$SCRIPT_DIR/infra/packer"
    
    # Initialize Packer plugins
    packer init spring-boot-ami.pkr.hcl > /dev/null 2>&1 || true
    
    # Build the AMI
    packer build \
        -var "jar_path=$SCRIPT_DIR/target/spring-boot-hello-world-1.0-SNAPSHOT.jar" \
        -var "ami_name_prefix=$PROJECT_NAME" \
        -var "aws_region=$AWS_REGION" \
        spring-boot-ami.pkr.hcl
    
    # Get the AMI ID from the manifest or output
    AMI_ID=$(aws ec2 describe-images \
        --owners self \
        --filters "Name=tag:Application,Values=$PROJECT_NAME" \
        --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
        --output text)
    
    echo -e "${GREEN}✓ AMI built: $AMI_ID${NC}"
    echo ""
    
    # Export for use in outputs
    export BUILT_AMI_ID=$AMI_ID
}

# Print outputs
print_outputs() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                    Deployment Complete!                    ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    cd "$SCRIPT_DIR/infra/terraform"
    
    ALB_DNS=$(terraform output -raw alb_dns_name)
    S3_BUCKET=$(terraform output -raw s3_bucket_name)
    PROD_LISTENER=$(terraform output -raw prod_listener_arn)
    LISTENER_RULE=$(terraform output -raw weighted_listener_rule_arn)
    
    # Get AMI ID
    AMI_ID=$(aws ec2 describe-images \
        --owners self \
        --filters "Name=tag:Application,Values=spring-boot-hello-world" \
        --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
        --output text)
    
    echo -e "${GREEN}AMI ID (for Harness artifact):${NC}"
    echo -e "  $AMI_ID"
    echo ""
    echo -e "${GREEN}Application URL:${NC}"
    echo -e "  http://$ALB_DNS"
    echo ""
    echo -e "${GREEN}S3 Artifacts Bucket:${NC}"
    echo -e "  $S3_BUCKET"
    echo ""
    echo -e "${GREEN}Harness Configuration Values:${NC}"
    echo -e "  ${YELLOW}AMI ID:${NC}"
    echo -e "    $AMI_ID"
    echo ""
    echo -e "  ${YELLOW}Prod Listener ARN:${NC}"
    echo -e "    $PROD_LISTENER"
    echo ""
    echo -e "  ${YELLOW}Weighted Listener Rule ARN:${NC}"
    echo -e "    $LISTENER_RULE"
    echo ""
    echo -e "${BLUE}Note: The AMI contains the Spring Boot app. Use this AMI ID in Harness.${NC}"
    echo ""
    
    # Save Harness config to file
    save_harness_config "$AMI_ID" "$ALB_DNS" "$S3_BUCKET" "$PROD_LISTENER" "$LISTENER_RULE"
    
    # Update Harness manifests with infrastructure values
    update_harness_manifests
}

# Update Harness ASG manifests with actual values from Terraform
update_harness_manifests() {
    echo -e "${YELLOW}Updating Harness manifests with infrastructure values...${NC}"
    
    cd "$SCRIPT_DIR/infra/terraform"
    
    # Get values from Terraform output
    SUBNET_IDS=$(terraform output -json private_subnet_ids 2>/dev/null | jq -r 'join(",")' || echo "")
    SECURITY_GROUP=$(terraform output -raw app_security_group_id 2>/dev/null || echo "")
    
    if [ -z "$SUBNET_IDS" ]; then
        echo -e "${YELLOW}Warning: Could not get subnet IDs from Terraform${NC}"
    fi
    
    if [ -z "$SECURITY_GROUP" ]; then
        echo -e "${YELLOW}Warning: Could not get security group from Terraform${NC}"
    fi
    
    # Update ASG config with subnet IDs
    local asg_config="$SCRIPT_DIR/infra/harness/asg/asg-config.json"
    if [ -n "$SUBNET_IDS" ]; then
        jq --arg subnets "$SUBNET_IDS" --arg name "$PROJECT_NAME-asg" \
            '.VPCZoneIdentifier = $subnets | .AutoScalingGroupName = $name' \
            "$asg_config" > "$asg_config.tmp" && mv "$asg_config.tmp" "$asg_config"
        echo -e "${GREEN}✓ ASG config updated with subnet IDs${NC}"
    fi
    
    # Update launch template with security group
    local launch_template="$SCRIPT_DIR/infra/harness/asg/launch-template.json"
    if [ -n "$SECURITY_GROUP" ]; then
        jq --arg sg "$SECURITY_GROUP" --arg name "$PROJECT_NAME" \
            '.LaunchTemplateData.SecurityGroupIds = [$sg] | .LaunchTemplateData.TagSpecifications[0].Tags[0].Value = $name | .LaunchTemplateData.TagSpecifications[0].Tags[1].Value = $name' \
            "$launch_template" > "$launch_template.tmp" && mv "$launch_template.tmp" "$launch_template"
        echo -e "${GREEN}✓ Launch template updated with security group${NC}"
    fi
    
    echo ""
}

# Save Harness configuration to file
save_harness_config() {
    local ami_id=$1
    local alb_dns=$2
    local s3_bucket=$3
    local prod_listener=$4
    local listener_rule=$5
    
    local config_file="$SCRIPT_DIR/harness-config.txt"
    
    cat > "$config_file" <<EOF
# Harness ASG Blue-Green Configuration
# Generated by deploy-asg.sh on $(date)
# Use these values when configuring Harness pipelines

# =============================================================================
# AMI Artifact
# =============================================================================
AMI_ID=$ami_id
AMI_REGION=us-east-1
AMI_TAG_FILTER=Application=$PROJECT_NAME

# =============================================================================
# ASG Blue Green Deploy Step
# =============================================================================
ASG_NAME=$PROJECT_NAME-asg
LOAD_BALANCER=$PROJECT_NAME-alb
PROD_LISTENER_ARN=$prod_listener
WEIGHTED_LISTENER_RULE_ARN=$listener_rule

# =============================================================================
# Application URL
# =============================================================================
ALB_URL=http://$alb_dns

# =============================================================================
# S3 Artifacts Bucket
# =============================================================================
S3_BUCKET=$s3_bucket

# =============================================================================
# Quick Reference - Harness Setup Steps
# =============================================================================
# 1. AWS Connector: Use IAM role or access keys with EC2, ASG, ALB permissions
# 2. Service: Type=ASG, Artifact=AMI filtered by Application tag
# 3. Environment: Region=us-east-1
# 4. Pipeline: Blue Green strategy with traffic shifting
# 5. ASG Blue Green Deploy Step:
#    - ASG Name: $PROJECT_NAME-asg
#    - Load Balancer: $PROJECT_NAME-alb
#    - Prod Listener ARN: (see above)
#    - Listener Rule ARN: (see above)
#    - Enable "Use Shift Traffic"
EOF
    
    echo -e "${GREEN}✓ Harness config saved to: harness-config.txt${NC}"
    echo ""
}

# Helper function to empty an S3 bucket (including all versions)
empty_s3_bucket() {
    local bucket=$1
    if [ -z "$bucket" ]; then
        return
    fi
    
    echo -e "${YELLOW}Emptying S3 bucket: $bucket${NC}"
    
    # Delete all objects
    aws s3 rm "s3://$bucket" --recursive 2>/dev/null || true
    
    # Delete all versions (for versioned buckets)
    local versions
    versions=$(aws s3api list-object-versions --bucket "$bucket" --query 'Versions[].{Key:Key,VersionId:VersionId}' --output json 2>/dev/null || echo "[]")
    if [ "$versions" != "[]" ] && [ "$versions" != "null" ] && [ -n "$versions" ]; then
        echo "$versions" | jq -c '.[]' 2>/dev/null | while read -r obj; do
            key=$(echo "$obj" | jq -r '.Key')
            vid=$(echo "$obj" | jq -r '.VersionId')
            aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$vid" 2>/dev/null || true
        done
    fi
    
    # Delete all delete markers
    local markers
    markers=$(aws s3api list-object-versions --bucket "$bucket" --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output json 2>/dev/null || echo "[]")
    if [ "$markers" != "[]" ] && [ "$markers" != "null" ] && [ -n "$markers" ]; then
        echo "$markers" | jq -c '.[]' 2>/dev/null | while read -r obj; do
            key=$(echo "$obj" | jq -r '.Key')
            vid=$(echo "$obj" | jq -r '.VersionId')
            aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$vid" 2>/dev/null || true
        done
    fi
}

# Cleanup function
cleanup() {
    echo -e "${YELLOW}Cleaning up AWS resources...${NC}"
    
    # Empty S3 buckets before destroying (Terraform can't delete non-empty buckets)
    cd "$SCRIPT_DIR/infra/terraform"
    if terraform state list &> /dev/null; then
        # Get artifacts bucket name from state directly
        ARTIFACTS_BUCKET=$(terraform state show aws_s3_bucket.artifacts 2>/dev/null | grep "bucket " | head -1 | awk -F'"' '{print $2}' || true)
        if [ -n "$ARTIFACTS_BUCKET" ]; then
            empty_s3_bucket "$ARTIFACTS_BUCKET"
        fi
        terraform destroy -auto-approve -input=false
    fi
    
    cd "$SCRIPT_DIR/infra/terraform-bootstrap"
    if terraform state list &> /dev/null; then
        # Get state bucket name from state directly
        STATE_BUCKET=$(terraform state show aws_s3_bucket.terraform_state 2>/dev/null | grep "bucket " | head -1 | awk -F'"' '{print $2}' || true)
        if [ -n "$STATE_BUCKET" ]; then
            empty_s3_bucket "$STATE_BUCKET"
        fi
        
        # Remove prevent_destroy lifecycle rule temporarily for cleanup
        sed -i.bak 's/prevent_destroy = true/prevent_destroy = false/' main.tf 2>/dev/null || \
            sed -i '' 's/prevent_destroy = true/prevent_destroy = false/' main.tf
        
        terraform destroy -auto-approve -input=false
        
        # Restore the original file
        if [ -f main.tf.bak ]; then
            mv main.tf.bak main.tf
        else
            # Restore prevent_destroy for macOS sed (which uses -i '')
            sed -i '' 's/prevent_destroy = false/prevent_destroy = true/' main.tf
        fi
    fi
    
    echo -e "${GREEN}✓ All resources destroyed${NC}"
}

# Fetch and display Harness config values from existing infrastructure
fetch_config() {
    echo -e "${YELLOW}Fetching Harness configuration values...${NC}"
    echo ""
    
    cd "$SCRIPT_DIR/infra/terraform"
    
    if ! terraform state list &> /dev/null; then
        echo -e "${RED}No Terraform state found. Run './deploy-asg.sh' first to deploy infrastructure.${NC}"
        exit 1
    fi
    
    ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null || echo "N/A")
    S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "N/A")
    PROD_LISTENER=$(terraform output -raw prod_listener_arn 2>/dev/null || echo "N/A")
    LISTENER_RULE=$(terraform output -raw weighted_listener_rule_arn 2>/dev/null || echo "N/A")
    
    AMI_ID=$(aws ec2 describe-images \
        --owners self \
        --filters "Name=tag:Application,Values=$PROJECT_NAME" \
        --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
        --output text 2>/dev/null || echo "N/A")
    
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║              Harness Configuration Values                  ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}Project Name:${NC}"
    echo -e "  $PROJECT_NAME"
    echo ""
    echo -e "${GREEN}AMI ID:${NC}"
    echo -e "  $AMI_ID"
    echo ""
    echo -e "${GREEN}Application URL:${NC}"
    echo -e "  http://$ALB_DNS"
    echo ""
    echo -e "${GREEN}ASG Name:${NC}"
    echo -e "  $PROJECT_NAME-asg"
    echo ""
    echo -e "${GREEN}Load Balancer:${NC}"
    echo -e "  $PROJECT_NAME-alb"
    echo ""
    echo -e "${GREEN}Prod Listener ARN:${NC}"
    echo -e "  $PROD_LISTENER"
    echo ""
    echo -e "${GREEN}Weighted Listener Rule ARN:${NC}"
    echo -e "  $LISTENER_RULE"
    echo ""
    echo -e "${GREEN}S3 Bucket:${NC}"
    echo -e "  $S3_BUCKET"
    echo ""
    
    # Save to file and update manifests
    save_harness_config "$AMI_ID" "$ALB_DNS" "$S3_BUCKET" "$PROD_LISTENER" "$LISTENER_RULE"
    update_harness_manifests
}

# Main execution
main() {
    case "${1:-}" in
        --destroy|destroy)
            cleanup
            ;;
        --config|config)
            fetch_config
            ;;
        --help|help|-h)
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  (none)     Deploy the full stack (build, infra, AMI)"
            echo "  config     Fetch Harness config values from existing infrastructure"
            echo "  destroy    Tear down all AWS resources"
            echo "  help       Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  PROJECT_NAME   Unique name for your project (default: spring-boot-hello-world)"
            echo "  OWNER          Your last name - used as AWS resource tag (default: unknown)"
            echo "  AWS_REGION     AWS region to deploy to (default: us-east-1)"
            echo "  ENVIRONMENT    Environment name (default: dev)"
            echo ""
            echo "Examples:"
            echo "  ./deploy-asg.sh                                    # Full deployment with defaults"
            echo "  PROJECT_NAME=acme-demo OWNER=parson ./deploy-asg.sh # Deploy with custom name and owner"
            echo "  ./deploy-asg.sh config                             # Just get the Harness config values"
            echo "  ./deploy-asg.sh destroy                            # Clean up everything"
            ;;
        *)
            check_prereqs
            build_app
            deploy_bootstrap
            deploy_infrastructure
            build_ami
            print_outputs
            ;;
    esac
}

main "$@"
