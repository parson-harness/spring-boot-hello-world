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
GCP_PROJECT="${GCP_PROJECT:-}"
GCP_REGION="${GCP_REGION:-us-central1}"
IMAGE_TAG="${1:-latest}"

# Show usage
usage() {
    echo "Usage: $0 [image_tag] [command]"
    echo ""
    echo "Builds and deploys the Spring Boot app to Google Cloud Run."
    echo ""
    echo "Arguments:"
    echo "  image_tag    Tag for the container image (default: latest)"
    echo ""
    echo "Commands:"
    echo "  (none)       Full deployment: build JAR, build image, push to Artifact Registry, deploy to Cloud Run"
    echo "  infra        Create Cloud Run infrastructure only (Artifact Registry, IAM)"
    echo "  build        Build and push image only (no deploy)"
    echo "  deploy       Deploy to Cloud Run only (image must exist)"
    echo "  destroy      Destroy all Cloud Run resources"
    echo "  help         Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_NAME   Unique name for your project (default: spring-boot-hello-world)"
    echo "  OWNER          Your last name - used for labels (default: unknown)"
    echo "  GCP_PROJECT    GCP project ID (required)"
    echo "  GCP_REGION     GCP region (default: us-central1)"
    echo ""
    echo "Examples:"
    echo "  GCP_PROJECT=my-project $0                    # Full deploy with 'latest' tag"
    echo "  GCP_PROJECT=my-project $0 v1.0-blue          # Deploy with specific tag"
    echo "  GCP_PROJECT=my-project $0 infra              # Create infrastructure only"
    echo "  $0 build v2.0                                # Build and push only"
    echo "  $0 destroy                                   # Destroy all resources"
}

# Check prerequisites
check_prereqs() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    local missing=()
    command -v java &> /dev/null || missing+=("java")
    command -v mvn &> /dev/null || missing+=("maven")
    command -v docker &> /dev/null || missing+=("docker")
    command -v gcloud &> /dev/null || missing+=("gcloud")
    command -v terraform &> /dev/null || missing+=("terraform")
    
    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${RED}Missing prerequisites: ${missing[*]}${NC}"
        exit 1
    fi
    
    # Check Docker is running
    if ! docker info &> /dev/null; then
        echo -e "${RED}Docker is not running. Please start Docker.${NC}"
        exit 1
    fi
    
    # Check GCP project is set
    if [ -z "$GCP_PROJECT" ]; then
        # Try to get from gcloud config
        GCP_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
        if [ -z "$GCP_PROJECT" ]; then
            echo -e "${RED}GCP_PROJECT not set. Set it with: export GCP_PROJECT=your-project-id${NC}"
            exit 1
        fi
        echo -e "${BLUE}  Using GCP project from gcloud config: $GCP_PROJECT${NC}"
    fi
    
    echo -e "${GREEN}✓ All prerequisites met${NC}"
    echo ""
}

# Deploy infrastructure (Artifact Registry, IAM)
deploy_infrastructure() {
    echo -e "${YELLOW}Deploying Cloud Run infrastructure...${NC}"
    cd "$SCRIPT_DIR/infra/terraform-cloudrun"
    
    # Copy example tfvars if not exists
    if [ ! -f "terraform.tfvars" ]; then
        if [ -f "terraform.tfvars.example" ]; then
            cp terraform.tfvars.example terraform.tfvars
            echo -e "${BLUE}  Created terraform.tfvars from example${NC}"
        fi
    fi
    
    # Update tfvars with current values
    sed -i.bak "s/gcp_project_id = .*/gcp_project_id = \"$GCP_PROJECT\"/" terraform.tfvars
    sed -i.bak "s/gcp_region = .*/gcp_region = \"$GCP_REGION\"/" terraform.tfvars
    sed -i.bak "s/project_name = .*/project_name = \"$PROJECT_NAME\"/" terraform.tfvars
    sed -i.bak "s/owner = .*/owner = \"$OWNER\"/" terraform.tfvars
    sed -i.bak "s/create_service = .*/create_service = false/" terraform.tfvars
    rm -f terraform.tfvars.bak
    
    terraform init -input=false
    terraform apply -auto-approve -input=false
    
    # Get registry URL
    REGISTRY_URL=$(terraform output -raw artifact_registry_url)
    
    echo -e "${GREEN}✓ Infrastructure deployed${NC}"
    echo ""
}

# Get Artifact Registry URL
get_registry_url() {
    REGISTRY_URL="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT}/${PROJECT_NAME}"
}

# Build JAR
build_app() {
    echo -e "${YELLOW}Step 1: Building application JAR...${NC}"
    cd "$SCRIPT_DIR"
    mvn clean package -DskipTests -q
    echo -e "${GREEN}✓ JAR built successfully${NC}"
    echo ""
}

# Build and push Docker image
build_and_push_image() {
    echo -e "${YELLOW}Step 2: Building and pushing container image...${NC}"
    cd "$SCRIPT_DIR"
    
    # Configure Docker for Artifact Registry
    gcloud auth configure-docker "${GCP_REGION}-docker.pkg.dev" --quiet
    
    # Build image (x86_64 for Cloud Run)
    echo -e "${BLUE}  Building Docker image (linux/amd64)...${NC}"
    docker build --platform linux/amd64 -t "$PROJECT_NAME:$IMAGE_TAG" .
    
    # Tag and push
    docker tag "$PROJECT_NAME:$IMAGE_TAG" "$REGISTRY_URL/$PROJECT_NAME:$IMAGE_TAG"
    echo -e "${BLUE}  Pushing to Artifact Registry...${NC}"
    docker push "$REGISTRY_URL/$PROJECT_NAME:$IMAGE_TAG"
    
    echo -e "${GREEN}✓ Image pushed: $REGISTRY_URL/$PROJECT_NAME:$IMAGE_TAG${NC}"
    echo ""
}

# Deploy to Cloud Run
deploy_to_cloudrun() {
    echo -e "${YELLOW}Step 3: Deploying to Cloud Run...${NC}"
    cd "$SCRIPT_DIR/infra/terraform-cloudrun"
    
    # Update tfvars to create service
    sed -i.bak "s/create_service = .*/create_service = true/" terraform.tfvars
    sed -i.bak "s/image_tag = .*/image_tag = \"$IMAGE_TAG\"/" terraform.tfvars
    rm -f terraform.tfvars.bak
    
    terraform apply -auto-approve -input=false
    
    echo -e "${GREEN}✓ Deployed to Cloud Run${NC}"
    echo ""
}

# Deploy using gcloud directly (faster for updates)
deploy_with_gcloud() {
    echo -e "${YELLOW}Step 3: Deploying to Cloud Run...${NC}"
    
    gcloud run deploy "$PROJECT_NAME" \
        --image "$REGISTRY_URL/$PROJECT_NAME:$IMAGE_TAG" \
        --region "$GCP_REGION" \
        --platform managed \
        --allow-unauthenticated \
        --port 8080 \
        --memory 512Mi \
        --cpu 1 \
        --min-instances 0 \
        --max-instances 10 \
        --set-env-vars "SPRING_PROFILES_ACTIVE=dev" \
        --project "$GCP_PROJECT" \
        --quiet
    
    echo -e "${GREEN}✓ Deployed to Cloud Run${NC}"
    echo ""
}

# Print outputs
print_outputs() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║              Cloud Run Deployment Complete                 ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Get service URL
    SERVICE_URL=$(gcloud run services describe "$PROJECT_NAME" \
        --region "$GCP_REGION" \
        --project "$GCP_PROJECT" \
        --format 'value(status.url)' 2>/dev/null || echo "pending...")
    
    echo -e "${GREEN}GCP Project:${NC}     $GCP_PROJECT"
    echo -e "${GREEN}Region:${NC}          $GCP_REGION"
    echo -e "${GREEN}Service:${NC}         $PROJECT_NAME"
    echo -e "${GREEN}Image Tag:${NC}       $IMAGE_TAG"
    echo ""
    echo -e "${GREEN}Service URL:${NC}     $SERVICE_URL"
    echo ""
    echo -e "${YELLOW}Test the deployment:${NC}"
    echo "  curl $SERVICE_URL/api"
    echo ""
    echo -e "${YELLOW}Harness Configuration:${NC}"
    echo "  GCP Connector Project: $GCP_PROJECT"
    echo "  Region: $GCP_REGION"
    echo "  Service Name: $PROJECT_NAME"
    echo "  Artifact Registry: $REGISTRY_URL"
    echo ""
    echo -e "${YELLOW}Useful commands:${NC}"
    echo "  gcloud run services describe $PROJECT_NAME --region $GCP_REGION"
    echo "  gcloud run revisions list --service $PROJECT_NAME --region $GCP_REGION"
    echo "  gcloud logging read \"resource.type=cloud_run_revision AND resource.labels.service_name=$PROJECT_NAME\" --limit 50"
    echo ""
    
    # Get POV name from backend symlink
    POV_NAME=""
    if [ -L "$SCRIPT_DIR/infra/backend.hcl" ]; then
        POV_NAME=$(readlink "$SCRIPT_DIR/infra/backend.hcl" | sed 's/backend-//' | sed 's/\.hcl//')
    fi
    
    echo -e "${YELLOW}Next step - Setup Harness entities:${NC}"
    if [ -n "$POV_NAME" ]; then
        echo "  ./setup-harness.sh $POV_NAME"
    else
        echo "  ./setup-harness.sh <pov-name>"
    fi
    echo ""
}

# Destroy all resources
destroy() {
    echo -e "${YELLOW}Destroying Cloud Run resources...${NC}"
    
    # Delete Cloud Run service first
    gcloud run services delete "$PROJECT_NAME" \
        --region "$GCP_REGION" \
        --project "$GCP_PROJECT" \
        --quiet 2>/dev/null || true
    
    # Destroy Terraform resources
    cd "$SCRIPT_DIR/infra/terraform-cloudrun"
    if [ -d ".terraform" ]; then
        # Set create_service to false to avoid errors
        sed -i.bak "s/create_service = .*/create_service = false/" terraform.tfvars 2>/dev/null || true
        rm -f terraform.tfvars.bak
        terraform destroy -auto-approve -input=false
    fi
    
    echo -e "${GREEN}✓ All Cloud Run resources destroyed${NC}"
}

# Main
case "${1:-}" in
    help|-h|--help)
        usage
        ;;
    destroy)
        check_prereqs
        destroy
        ;;
    infra)
        echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║           Cloud Run Infrastructure Setup                   ║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${GREEN}Project:${NC}     $PROJECT_NAME"
        echo -e "${GREEN}GCP Project:${NC} $GCP_PROJECT"
        echo -e "${GREEN}Region:${NC}      $GCP_REGION"
        echo ""
        
        check_prereqs
        deploy_infrastructure
        
        echo -e "${GREEN}✓ Infrastructure ready${NC}"
        echo ""
        echo -e "${YELLOW}Next steps:${NC}"
        echo "  1. Build and push image: ./deploy-cloudrun.sh build"
        echo "  2. Deploy to Cloud Run:  ./deploy-cloudrun.sh deploy"
        echo "  Or do both:              ./deploy-cloudrun.sh"
        ;;
    build)
        IMAGE_TAG="${2:-latest}"
        echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║              Cloud Run Build Script                        ║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${GREEN}Project:${NC}     $PROJECT_NAME"
        echo -e "${GREEN}Image Tag:${NC}   $IMAGE_TAG"
        echo ""
        
        check_prereqs
        get_registry_url
        build_app
        build_and_push_image
        
        echo -e "${GREEN}✓ Image ready: $REGISTRY_URL/$PROJECT_NAME:$IMAGE_TAG${NC}"
        ;;
    deploy)
        IMAGE_TAG="${2:-latest}"
        echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║              Cloud Run Deploy Script                       ║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${GREEN}Project:${NC}     $PROJECT_NAME"
        echo -e "${GREEN}Image Tag:${NC}   $IMAGE_TAG"
        echo ""
        
        check_prereqs
        get_registry_url
        deploy_with_gcloud
        print_outputs
        ;;
    *)
        IMAGE_TAG="${1:-latest}"
        echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║             Cloud Run Deployment Script                    ║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${GREEN}Project:${NC}     $PROJECT_NAME"
        echo -e "${GREEN}Owner:${NC}       $OWNER"
        echo -e "${GREEN}GCP Project:${NC} $GCP_PROJECT"
        echo -e "${GREEN}Region:${NC}      $GCP_REGION"
        echo -e "${GREEN}Image Tag:${NC}   $IMAGE_TAG"
        echo ""
        
        check_prereqs
        deploy_infrastructure
        get_registry_url
        build_app
        build_and_push_image
        deploy_with_gcloud
        print_outputs
        ;;
esac
