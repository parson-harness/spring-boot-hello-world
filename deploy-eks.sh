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
NAMESPACE="${NAMESPACE:-default}"
IMAGE_TAG="${1:-latest}"

# Show usage
usage() {
    echo "Usage: $0 [image_tag] [command]"
    echo ""
    echo "Builds and deploys the Spring Boot app to EKS."
    echo ""
    echo "Arguments:"
    echo "  image_tag    Tag for the container image (default: latest)"
    echo ""
    echo "Commands:"
    echo "  (none)       Full deployment: build JAR, build image, push to ECR, deploy to EKS"
    echo "  build        Build and push image only (no deploy)"
    echo "  deploy       Deploy to EKS only (image must exist)"
    echo "  destroy      Remove deployment from EKS"
    echo "  help         Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_NAME   Unique name for your project (default: spring-boot-hello-world)"
    echo "  OWNER          Your last name - used for labels (default: unknown)"
    echo "  AWS_REGION     AWS region for ECR (default: us-east-1)"
    echo "  NAMESPACE      Kubernetes namespace (default: default)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Deploy with 'latest' tag"
    echo "  $0 v1.0-blue                          # Deploy with specific tag"
    echo "  PROJECT_NAME=acme-demo $0 v1.0.0      # Deploy with custom project name"
    echo "  $0 build v1.0-blue                    # Build and push only"
    echo "  $0 destroy                            # Remove from EKS"
}

# Check prerequisites
check_prereqs() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    local missing=()
    command -v java &> /dev/null || missing+=("java")
    command -v mvn &> /dev/null || missing+=("maven")
    command -v docker &> /dev/null || missing+=("docker")
    command -v aws &> /dev/null || missing+=("aws-cli")
    command -v kubectl &> /dev/null || missing+=("kubectl")
    
    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${RED}Missing prerequisites: ${missing[*]}${NC}"
        exit 1
    fi
    
    # Check Docker is running
    if ! docker info &> /dev/null; then
        echo -e "${RED}Docker is not running. Please start Docker.${NC}"
        exit 1
    fi
    
    # Check kubectl context
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}kubectl not connected to a cluster. Configure your kubeconfig.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ All prerequisites met${NC}"
    echo ""
}

# Get or create ECR repository
ensure_ecr_repo() {
    echo -e "${YELLOW}Ensuring ECR repository exists...${NC}"
    
    # Check if repo exists
    if aws ecr describe-repositories --repository-names "$PROJECT_NAME" --region "$AWS_REGION" &> /dev/null; then
        echo -e "${GREEN}✓ ECR repository exists${NC}"
    else
        echo -e "${BLUE}  Creating ECR repository...${NC}"
        aws ecr create-repository \
            --repository-name "$PROJECT_NAME" \
            --region "$AWS_REGION" \
            --image-scanning-configuration scanOnPush=true \
            --tags Key=Project,Value="$PROJECT_NAME" Key=Owner,Value="$OWNER" > /dev/null
        echo -e "${GREEN}✓ ECR repository created${NC}"
    fi
    
    # Get repository URL
    ECR_REPO=$(aws ecr describe-repositories \
        --repository-names "$PROJECT_NAME" \
        --region "$AWS_REGION" \
        --query 'repositories[0].repositoryUri' \
        --output text)
    
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
    
    # Login to ECR
    aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REPO"
    
    # Build image (x86_64 for EKS)
    echo -e "${BLUE}  Building Docker image (linux/amd64)...${NC}"
    docker build --platform linux/amd64 -t "$PROJECT_NAME:$IMAGE_TAG" .
    
    # Tag and push
    docker tag "$PROJECT_NAME:$IMAGE_TAG" "$ECR_REPO:$IMAGE_TAG"
    echo -e "${BLUE}  Pushing to ECR...${NC}"
    docker push "$ECR_REPO:$IMAGE_TAG"
    
    echo -e "${GREEN}✓ Image pushed: $ECR_REPO:$IMAGE_TAG${NC}"
    echo ""
}

# Deploy to EKS
deploy_to_eks() {
    echo -e "${YELLOW}Step 3: Deploying to EKS...${NC}"
    cd "$SCRIPT_DIR"
    
    # Create namespace if it doesn't exist
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1
    
    # Generate plain K8s manifests from templates (simple variable substitution)
    local IMAGE="$ECR_REPO:$IMAGE_TAG"
    
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

    echo -e "${GREEN}✓ Deployed to EKS${NC}"
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
    local lb_hostname=""
    
    while [ $attempts -lt $max_attempts ]; do
        lb_hostname=$(kubectl get svc ${PROJECT_NAME}-service -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
        
        if [ -n "$lb_hostname" ]; then
            break
        fi
        
        attempts=$((attempts + 1))
        sleep 5
    done
    
    if [ -z "$lb_hostname" ]; then
        echo -e "${YELLOW}LoadBalancer not ready yet. Check with: kubectl get svc ${PROJECT_NAME}-service -n $NAMESPACE${NC}"
    else
        echo -e "${GREEN}✓ LoadBalancer ready${NC}"
        echo ""
        echo -e "${GREEN}Application URL:${NC} http://$lb_hostname/"
        echo -e "${GREEN}API Endpoint:${NC}   http://$lb_hostname/api"
    fi
}

# Print outputs
print_outputs() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                 EKS Deployment Complete                    ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${GREEN}ECR Repository:${NC}  $ECR_REPO"
    echo -e "${GREEN}Image Tag:${NC}       $IMAGE_TAG"
    echo -e "${GREEN}Namespace:${NC}       $NAMESPACE"
    echo ""
    
    local lb_hostname=$(kubectl get svc ${PROJECT_NAME}-service -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending...")
    
    echo -e "${GREEN}LoadBalancer:${NC}    $lb_hostname"
    echo ""
    echo -e "${YELLOW}Test the deployment:${NC}"
    echo "  curl http://$lb_hostname/api"
    echo ""
    echo -e "${YELLOW}Harness Configuration:${NC}"
    echo "  ECR Connector Region: $AWS_REGION"
    echo "  Image Path: $PROJECT_NAME"
    echo "  Namespace: $NAMESPACE"
    echo ""
    echo -e "${YELLOW}Useful commands:${NC}"
    echo "  kubectl get pods -n $NAMESPACE -l app=$PROJECT_NAME"
    echo "  kubectl logs -n $NAMESPACE -l app=$PROJECT_NAME --tail=50"
    echo ""
}

# Destroy deployment
destroy() {
    echo -e "${YELLOW}Removing EKS deployment...${NC}"
    
    kubectl delete deployment ${PROJECT_NAME}-deployment -n "$NAMESPACE" --ignore-not-found
    kubectl delete service ${PROJECT_NAME}-service -n "$NAMESPACE" --ignore-not-found
    
    echo -e "${GREEN}✓ EKS deployment removed${NC}"
    echo ""
    echo -e "${YELLOW}Note: ECR repository not deleted. To delete:${NC}"
    echo "  aws ecr delete-repository --repository-name $PROJECT_NAME --region $AWS_REGION --force"
}

# Main
case "${1:-}" in
    help|-h|--help)
        usage
        ;;
    destroy)
        destroy
        ;;
    build)
        IMAGE_TAG="${2:-latest}"
        echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║                 EKS Build Script                           ║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${GREEN}Project:${NC}     $PROJECT_NAME"
        echo -e "${GREEN}Image Tag:${NC}   $IMAGE_TAG"
        echo ""
        
        check_prereqs
        ensure_ecr_repo
        build_app
        build_and_push_image
        
        echo -e "${GREEN}✓ Image ready: $ECR_REPO:$IMAGE_TAG${NC}"
        ;;
    deploy)
        IMAGE_TAG="${2:-latest}"
        echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║                 EKS Deploy Script                          ║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${GREEN}Project:${NC}     $PROJECT_NAME"
        echo -e "${GREEN}Namespace:${NC}   $NAMESPACE"
        echo -e "${GREEN}Image Tag:${NC}   $IMAGE_TAG"
        echo ""
        
        check_prereqs
        ensure_ecr_repo
        deploy_to_eks
        wait_for_deployment
        print_outputs
        ;;
    *)
        echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║                 EKS Deployment Script                      ║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${GREEN}Project:${NC}     $PROJECT_NAME"
        echo -e "${GREEN}Owner:${NC}       $OWNER"
        echo -e "${GREEN}Region:${NC}      $AWS_REGION"
        echo -e "${GREEN}Namespace:${NC}   $NAMESPACE"
        echo -e "${GREEN}Image Tag:${NC}   $IMAGE_TAG"
        echo ""
        
        check_prereqs
        ensure_ecr_repo
        build_app
        build_and_push_image
        deploy_to_eks
        wait_for_deployment
        print_outputs
        ;;
esac
