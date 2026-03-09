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
NAMESPACE="${NAMESPACE:-default}"
IMAGE_TAG="${1:-latest}"

# Show usage
usage() {
    echo "Usage: $0 [image_tag] [command]"
    echo ""
    echo "Builds and deploys the Spring Boot app to GKE."
    echo ""
    echo "Arguments:"
    echo "  image_tag    Tag for the container image (default: latest)"
    echo ""
    echo "Commands:"
    echo "  (none)       Full deployment: build JAR, build image, push to Artifact Registry, deploy to GKE"
    echo "  build        Build and push image only (no deploy)"
    echo "  deploy       Deploy to GKE only (image must exist)"
    echo "  infra        Create GKE cluster infrastructure only"
    echo "  destroy      Remove deployment from GKE (keeps cluster)"
    echo "  destroy-all  Destroy GKE cluster and all resources"
    echo "  help         Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_NAME   Unique name for your project (default: spring-boot-hello-world)"
    echo "  OWNER          Your last name - used for labels (default: unknown)"
    echo "  GCP_PROJECT    GCP project ID (required)"
    echo "  GCP_REGION     GCP region (default: us-central1)"
    echo "  NAMESPACE      Kubernetes namespace (default: default)"
    echo ""
    echo "Examples:"
    echo "  GCP_PROJECT=my-project $0                    # Deploy with 'latest' tag"
    echo "  GCP_PROJECT=my-project $0 v1.0-blue          # Deploy with specific tag"
    echo "  GCP_PROJECT=my-project $0 infra              # Create GKE cluster only"
    echo "  $0 destroy                                   # Remove from GKE"
}

# Check prerequisites
check_prereqs() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    local missing=()
    command -v java &> /dev/null || missing+=("java")
    command -v mvn &> /dev/null || missing+=("maven")
    command -v docker &> /dev/null || missing+=("docker")
    command -v gcloud &> /dev/null || missing+=("gcloud")
    command -v kubectl &> /dev/null || missing+=("kubectl")
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

# Check kubectl is connected to GKE
check_kubectl() {
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${YELLOW}kubectl not connected. Configuring for GKE cluster...${NC}"
        gcloud container clusters get-credentials "$PROJECT_NAME" --region "$GCP_REGION" --project "$GCP_PROJECT" 2>/dev/null || {
            echo -e "${RED}Failed to connect to GKE cluster. Run './deploy-gke.sh infra' first to create the cluster.${NC}"
            exit 1
        }
    fi
    echo -e "${GREEN}✓ Connected to GKE cluster${NC}"
}

# Deploy GKE infrastructure
deploy_infrastructure() {
    echo -e "${YELLOW}Deploying GKE infrastructure...${NC}"
    cd "$SCRIPT_DIR/infra/terraform-gke"
    
    # Copy example tfvars if not exists
    if [ ! -f "terraform.tfvars" ]; then
        if [ -f "terraform.tfvars.example" ]; then
            cp terraform.tfvars.example terraform.tfvars
            echo -e "${BLUE}  Created terraform.tfvars from example${NC}"
            echo -e "${YELLOW}  Please edit terraform.tfvars with your GCP project ID${NC}"
        fi
    fi
    
    # Update tfvars with current values
    sed -i.bak "s/gcp_project_id = .*/gcp_project_id = \"$GCP_PROJECT\"/" terraform.tfvars
    sed -i.bak "s/gcp_region = .*/gcp_region = \"$GCP_REGION\"/" terraform.tfvars
    sed -i.bak "s/project_name = .*/project_name = \"$PROJECT_NAME\"/" terraform.tfvars
    sed -i.bak "s/owner = .*/owner = \"$OWNER\"/" terraform.tfvars
    rm -f terraform.tfvars.bak
    
    terraform init -input=false
    terraform apply -auto-approve -input=false
    
    # Configure kubectl
    echo -e "${YELLOW}Configuring kubectl...${NC}"
    eval "$(terraform output -raw kubeconfig_command)"
    
    echo -e "${GREEN}✓ GKE infrastructure deployed${NC}"
    echo ""
}

# Get Artifact Registry URL
get_registry_url() {
    REGISTRY_URL="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT}/${PROJECT_NAME}"
}

# Ensure Artifact Registry exists
ensure_registry() {
    echo -e "${YELLOW}Ensuring Artifact Registry exists...${NC}"
    
    # Check if registry exists
    if gcloud artifacts repositories describe "$PROJECT_NAME" --location="$GCP_REGION" --project="$GCP_PROJECT" &> /dev/null; then
        echo -e "${GREEN}✓ Artifact Registry exists${NC}"
    else
        echo -e "${BLUE}  Creating Artifact Registry...${NC}"
        gcloud artifacts repositories create "$PROJECT_NAME" \
            --repository-format=docker \
            --location="$GCP_REGION" \
            --project="$GCP_PROJECT" \
            --description="Docker repository for $PROJECT_NAME"
        echo -e "${GREEN}✓ Artifact Registry created${NC}"
    fi
    
    get_registry_url
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

# Build and push Docker image
build_and_push_image() {
    echo -e "${YELLOW}Step 2: Building and pushing container image...${NC}"
    cd "$SCRIPT_DIR"
    
    # Configure Docker for Artifact Registry
    gcloud auth configure-docker "${GCP_REGION}-docker.pkg.dev" --quiet
    
    # Build image (x86_64 for GKE)
    echo -e "${BLUE}  Building Docker image (linux/amd64)...${NC}"
    docker build --platform linux/amd64 -t "$PROJECT_NAME:$IMAGE_TAG" .
    
    # Tag and push
    docker tag "$PROJECT_NAME:$IMAGE_TAG" "$REGISTRY_URL/$PROJECT_NAME:$IMAGE_TAG"
    echo -e "${BLUE}  Pushing to Artifact Registry...${NC}"
    docker push "$REGISTRY_URL/$PROJECT_NAME:$IMAGE_TAG"
    
    echo -e "${GREEN}✓ Image pushed: $REGISTRY_URL/$PROJECT_NAME:$IMAGE_TAG${NC}"
    echo ""
}

# Deploy to GKE
deploy_to_gke() {
    echo -e "${YELLOW}Step 3: Deploying to GKE...${NC}"
    cd "$SCRIPT_DIR"
    
    # Create namespace if it doesn't exist
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1
    
    local IMAGE="$REGISTRY_URL/$PROJECT_NAME:$IMAGE_TAG"
    
    # Create deployment
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${PROJECT_NAME}-deployment
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT_NAME}
    owner: ${OWNER}
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ${PROJECT_NAME}
  template:
    metadata:
      labels:
        app: ${PROJECT_NAME}
        owner: ${OWNER}
    spec:
      containers:
        - name: ${PROJECT_NAME}
          image: ${IMAGE}
          imagePullPolicy: Always
          ports:
            - name: http
              containerPort: 8080
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
          readinessProbe:
            httpGet:
              path: /actuator/health
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /actuator/health
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
          env:
            - name: JAVA_OPTS
              value: "-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
EOF

    # Create service
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: ${PROJECT_NAME}-service
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT_NAME}
spec:
  type: LoadBalancer
  selector:
    app: ${PROJECT_NAME}
  ports:
    - name: http
      port: 80
      targetPort: 8080
EOF

    echo -e "${GREEN}✓ Deployed to GKE${NC}"
    echo ""
}

# Wait for deployment and get URL
wait_for_deployment() {
    echo -e "${YELLOW}Waiting for deployment to be ready...${NC}"
    
    kubectl rollout status deployment/${PROJECT_NAME}-deployment -n "$NAMESPACE" --timeout=120s
    
    echo ""
    echo -e "${BLUE}Waiting for LoadBalancer IP...${NC}"
    
    local attempts=0
    local max_attempts=30
    local lb_ip=""
    
    while [ $attempts -lt $max_attempts ]; do
        lb_ip=$(kubectl get svc ${PROJECT_NAME}-service -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        
        if [ -n "$lb_ip" ]; then
            break
        fi
        
        attempts=$((attempts + 1))
        sleep 5
    done
    
    if [ -z "$lb_ip" ]; then
        echo -e "${YELLOW}LoadBalancer not ready yet. Check with: kubectl get svc ${PROJECT_NAME}-service -n $NAMESPACE${NC}"
    else
        echo -e "${GREEN}✓ LoadBalancer ready${NC}"
        echo ""
        echo -e "${GREEN}Application URL:${NC} http://$lb_ip/"
        echo -e "${GREEN}API Endpoint:${NC}   http://$lb_ip/api"
    fi
}

# Print outputs
print_outputs() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                 GKE Deployment Complete                    ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${GREEN}GCP Project:${NC}     $GCP_PROJECT"
    echo -e "${GREEN}Registry:${NC}        $REGISTRY_URL"
    echo -e "${GREEN}Image Tag:${NC}       $IMAGE_TAG"
    echo -e "${GREEN}Namespace:${NC}       $NAMESPACE"
    echo ""
    
    local lb_ip=$(kubectl get svc ${PROJECT_NAME}-service -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending...")
    
    echo -e "${GREEN}LoadBalancer IP:${NC} $lb_ip"
    echo ""
    echo -e "${YELLOW}Test the deployment:${NC}"
    echo "  curl http://$lb_ip/api"
    echo ""
    echo -e "${YELLOW}Harness Configuration:${NC}"
    echo "  GCP Connector Project: $GCP_PROJECT"
    echo "  Artifact Registry: $REGISTRY_URL"
    echo "  Image Path: $PROJECT_NAME"
    echo "  Namespace: $NAMESPACE"
    echo ""
    echo -e "${YELLOW}Useful commands:${NC}"
    echo "  kubectl get pods -n $NAMESPACE -l app=$PROJECT_NAME"
    echo "  kubectl logs -n $NAMESPACE -l app=$PROJECT_NAME --tail=50"
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

# Destroy deployment (keeps cluster)
destroy() {
    echo -e "${YELLOW}Removing GKE deployment...${NC}"
    
    # Try to connect to cluster
    gcloud container clusters get-credentials "$PROJECT_NAME" --region "$GCP_REGION" --project "$GCP_PROJECT" 2>/dev/null || true
    
    kubectl delete deployment ${PROJECT_NAME}-deployment -n "$NAMESPACE" --ignore-not-found
    kubectl delete service ${PROJECT_NAME}-service -n "$NAMESPACE" --ignore-not-found
    
    echo -e "${GREEN}✓ GKE deployment removed${NC}"
    echo ""
    echo -e "${YELLOW}Note: GKE cluster and Artifact Registry not deleted.${NC}"
    echo "To destroy everything: ./deploy-gke.sh destroy-all"
}

# Destroy all infrastructure
destroy_all() {
    echo -e "${YELLOW}Destroying all GKE infrastructure...${NC}"
    
    # Remove K8s resources first
    destroy 2>/dev/null || true
    
    # Destroy Terraform resources
    cd "$SCRIPT_DIR/infra/terraform-gke"
    if [ -d ".terraform" ]; then
        terraform destroy -auto-approve -input=false
    fi
    
    echo -e "${GREEN}✓ All GKE resources destroyed${NC}"
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
    destroy-all)
        check_prereqs
        destroy_all
        ;;
    infra)
        echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║              GKE Infrastructure Setup                      ║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${GREEN}Project:${NC}     $PROJECT_NAME"
        echo -e "${GREEN}GCP Project:${NC} $GCP_PROJECT"
        echo -e "${GREEN}Region:${NC}      $GCP_REGION"
        echo ""
        
        check_prereqs
        deploy_infrastructure
        
        echo -e "${GREEN}✓ GKE cluster ready${NC}"
        echo ""
        echo -e "${YELLOW}Next: Deploy the app with:${NC}"
        echo "  ./deploy-gke.sh deploy"
        ;;
    build)
        IMAGE_TAG="${2:-latest}"
        echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║                 GKE Build Script                           ║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${GREEN}Project:${NC}     $PROJECT_NAME"
        echo -e "${GREEN}Image Tag:${NC}   $IMAGE_TAG"
        echo ""
        
        check_prereqs
        ensure_registry
        build_app
        build_and_push_image
        
        echo -e "${GREEN}✓ Image ready: $REGISTRY_URL/$PROJECT_NAME:$IMAGE_TAG${NC}"
        ;;
    deploy)
        IMAGE_TAG="${2:-latest}"
        echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║                 GKE Deploy Script                          ║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${GREEN}Project:${NC}     $PROJECT_NAME"
        echo -e "${GREEN}Namespace:${NC}   $NAMESPACE"
        echo -e "${GREEN}Image Tag:${NC}   $IMAGE_TAG"
        echo ""
        
        check_prereqs
        check_kubectl
        get_registry_url
        deploy_to_gke
        wait_for_deployment
        print_outputs
        ;;
    *)
        echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║                 GKE Deployment Script                      ║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${GREEN}Project:${NC}     $PROJECT_NAME"
        echo -e "${GREEN}Owner:${NC}       $OWNER"
        echo -e "${GREEN}GCP Project:${NC} $GCP_PROJECT"
        echo -e "${GREEN}Region:${NC}      $GCP_REGION"
        echo -e "${GREEN}Namespace:${NC}   $NAMESPACE"
        echo -e "${GREEN}Image Tag:${NC}   $IMAGE_TAG"
        echo ""
        
        check_prereqs
        check_kubectl
        ensure_registry
        build_app
        build_and_push_image
        deploy_to_gke
        wait_for_deployment
        print_outputs
        ;;
esac
