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
# CONFIGURATION
# =============================================================================
PROJECT_NAME="${PROJECT_NAME:-spring-boot-hello-world}"
OWNER="${OWNER:-unknown}"
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_PROFILE="${AWS_PROFILE:-default}"
export AWS_PROFILE
ENVIRONMENT="${ENVIRONMENT:-dev}"
IMAGE_TAG="${1:-latest}"

# Show usage
usage() {
    echo "Usage: $0 [image_tag] [command]"
    echo ""
    echo "Deploys the Spring Boot app as an AWS Lambda function."
    echo ""
    echo "Arguments:"
    echo "  image_tag    Tag for the container image (default: latest)"
    echo ""
    echo "Commands:"
    echo "  (none)       Full deployment: build JAR, build image, push to ECR, deploy infra"
    echo "  destroy      Tear down Lambda infrastructure"
    echo "  help         Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_NAME   Unique name for your project (default: spring-boot-hello-world)"
    echo "  OWNER          Your last name - used as AWS resource tag (default: unknown)"
    echo "  AWS_REGION     AWS region to deploy to (default: us-east-1)"
    echo "  ENVIRONMENT    Environment name (default: dev)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Deploy with 'latest' tag"
    echo "  $0 v1.0-blue                          # Deploy with specific tag"
    echo "  PROJECT_NAME=acme-demo OWNER=smith $0 v1.0.0"
    echo "  $0 destroy                            # Tear down infrastructure"
}

# Check prerequisites
check_prereqs() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    local missing=()
    command -v java &> /dev/null || missing+=("java")
    command -v mvn &> /dev/null || missing+=("maven")
    command -v docker &> /dev/null || missing+=("docker")
    command -v terraform &> /dev/null || missing+=("terraform")
    command -v aws &> /dev/null || missing+=("aws-cli")
    
    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${RED}Missing prerequisites: ${missing[*]}${NC}"
        exit 1
    fi
    
    # Check Docker is running
    if ! docker info &> /dev/null; then
        echo -e "${RED}Docker is not running. Please start Docker.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ All prerequisites met${NC}"
    echo ""
}

# Build JAR
build_app() {
    echo -e "${YELLOW}Step 1: Building application JAR...${NC}"
    cd "$SCRIPT_DIR"
    mvn clean package -DskipTests -q
    echo -e "${GREEN}✓ JAR built successfully${NC}"
    echo ""
}

# Deploy ECR repository (phase 1 - before image push)
deploy_ecr() {
    echo -e "${YELLOW}Step 2: Creating ECR repository...${NC}"
    cd "$SCRIPT_DIR/infra/terraform-lambda"
    
    terraform init -input=false > /dev/null
    terraform apply -auto-approve -input=false \
        -var "app_name=$PROJECT_NAME" \
        -var "environment=$ENVIRONMENT" \
        -var "aws_region=$AWS_REGION" \
        -var "owner=$OWNER" \
        -var "create_lambda=false"
    
    echo -e "${GREEN}✓ ECR repository created${NC}"
    echo ""
}

# Deploy Lambda function (phase 2 - after image push)
deploy_lambda() {
    echo -e "${YELLOW}Step 4: Creating Lambda function...${NC}"
    cd "$SCRIPT_DIR/infra/terraform-lambda"
    
    terraform apply -auto-approve -input=false \
        -var "app_name=$PROJECT_NAME" \
        -var "environment=$ENVIRONMENT" \
        -var "aws_region=$AWS_REGION" \
        -var "owner=$OWNER" \
        -var "create_lambda=true" \
        -var "image_tag=$IMAGE_TAG"
    
    echo -e "${GREEN}✓ Lambda function created${NC}"
    echo ""
}

# Build and push Docker image to ECR
build_and_push_image() {
    echo -e "${YELLOW}Step 3: Building and pushing container image...${NC}"
    cd "$SCRIPT_DIR"
    
    # Get ECR repository URL from Terraform
    cd "$SCRIPT_DIR/infra/terraform-lambda"
    ECR_REPO=$(terraform output -raw ecr_repository_url)
    
    cd "$SCRIPT_DIR"
    
    # Login to ECR
    aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REPO"
    
    # Build image (must be x86_64 for Lambda)
    echo -e "${BLUE}  Building Docker image (linux/amd64)...${NC}"
    docker build --platform linux/amd64 -f Dockerfile.lambda -t "$PROJECT_NAME:$IMAGE_TAG" .
    
    # Tag and push
    docker tag "$PROJECT_NAME:$IMAGE_TAG" "$ECR_REPO:$IMAGE_TAG"
    echo -e "${BLUE}  Pushing to ECR...${NC}"
    docker push "$ECR_REPO:$IMAGE_TAG"
    
    echo -e "${GREEN}✓ Image pushed: $ECR_REPO:$IMAGE_TAG${NC}"
    echo ""
}

# Update Lambda function with new image
update_lambda() {
    echo -e "${YELLOW}Step 4: Updating Lambda function...${NC}"
    
    cd "$SCRIPT_DIR/infra/terraform-lambda"
    ECR_REPO=$(terraform output -raw ecr_repository_url)
    FUNCTION_NAME=$(terraform output -raw lambda_function_name)
    
    # Update function code
    aws lambda update-function-code \
        --function-name "$FUNCTION_NAME" \
        --image-uri "$ECR_REPO:$IMAGE_TAG" \
        --region "$AWS_REGION" > /dev/null
    
    # Wait for update to complete
    echo -e "${BLUE}  Waiting for Lambda update...${NC}"
    aws lambda wait function-updated --function-name "$FUNCTION_NAME" --region "$AWS_REGION"
    
    # Publish new version
    VERSION=$(aws lambda publish-version \
        --function-name "$FUNCTION_NAME" \
        --description "Deployed $IMAGE_TAG" \
        --region "$AWS_REGION" \
        --query 'Version' --output text)
    
    echo -e "${GREEN}✓ Lambda updated to version $VERSION${NC}"
    echo ""
}

# Print outputs
print_outputs() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                Lambda Deployment Complete                  ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    cd "$SCRIPT_DIR/infra/terraform-lambda"
    
    FUNCTION_URL=$(terraform output -raw lambda_function_url 2>/dev/null || echo "")
    FUNCTION_NAME=$(terraform output -raw lambda_function_name 2>/dev/null || echo "")
    ECR_REPO=$(terraform output -raw ecr_repository_url 2>/dev/null || echo "")
    
    echo -e "${GREEN}Lambda Function:${NC} $FUNCTION_NAME"
    echo -e "${GREEN}ECR Repository:${NC}  $ECR_REPO"
    echo -e "${GREEN}Image Tag:${NC}       $IMAGE_TAG"
    echo -e "${GREEN}Function URL:${NC}    $FUNCTION_URL"
    echo ""
    echo -e "${YELLOW}Test the deployment:${NC}"
    echo "  curl $FUNCTION_URL"
    echo "  curl ${FUNCTION_URL}api"
    echo ""
    echo -e "${YELLOW}Harness Configuration:${NC}"
    echo "  ECR Connector Region: $AWS_REGION"
    echo "  Image Path: $PROJECT_NAME"
    echo "  Function Name: $FUNCTION_NAME"
    echo "  Alias: live"
    echo ""
}

# Destroy infrastructure
destroy() {
    echo -e "${YELLOW}Destroying Lambda infrastructure...${NC}"
    
    cd "$SCRIPT_DIR/infra/terraform-lambda"
    
    if [ -f "terraform.tfstate" ]; then
        # Delete all images from ECR first
        ECR_REPO=$(terraform output -raw ecr_repository_name 2>/dev/null || echo "")
        if [ -n "$ECR_REPO" ]; then
            echo -e "${BLUE}  Deleting ECR images...${NC}"
            aws ecr batch-delete-image \
                --repository-name "$ECR_REPO" \
                --image-ids "$(aws ecr list-images --repository-name "$ECR_REPO" --query 'imageIds[*]' --output json)" \
                --region "$AWS_REGION" 2>/dev/null || true
        fi
        
        terraform destroy -auto-approve -input=false \
            -var "app_name=$PROJECT_NAME" \
            -var "environment=$ENVIRONMENT" \
            -var "aws_region=$AWS_REGION" \
            -var "owner=$OWNER"
        
        echo -e "${GREEN}✓ Lambda infrastructure destroyed${NC}"
    else
        echo -e "${YELLOW}No Terraform state found. Nothing to destroy.${NC}"
    fi
}

# Main
case "${1:-}" in
    help|-h|--help)
        usage
        ;;
    destroy)
        destroy
        ;;
    *)
        echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║              Lambda Deployment Script                      ║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${GREEN}Project:${NC}     $PROJECT_NAME"
        echo -e "${GREEN}Owner:${NC}       $OWNER"
        echo -e "${GREEN}Region:${NC}      $AWS_REGION"
        echo -e "${GREEN}Environment:${NC} $ENVIRONMENT"
        echo -e "${GREEN}Image Tag:${NC}   $IMAGE_TAG"
        echo ""
        
        check_prereqs
        build_app
        deploy_ecr
        build_and_push_image
        deploy_lambda
        print_outputs
        ;;
esac
