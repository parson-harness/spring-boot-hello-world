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
APP_VERSION="${1:-}"

# Show usage
usage() {
    echo "Usage: $0 <version>"
    echo ""
    echo "Builds the application JAR and creates a new AMI with Packer."
    echo ""
    echo "Arguments:"
    echo "  version    Version tag for the AMI (e.g., v1.0-blue, v2.0-green)"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_NAME   Project name prefix for AMI (default: spring-boot-hello-world)"
    echo ""
    echo "Examples:"
    echo "  $0 v1.0-blue                           # Build AMI with version v1.0-blue"
    echo "  $0 v2.0-green                          # Build AMI with version v2.0-green"
    echo "  PROJECT_NAME=acme-demo $0 v1.0.0       # Build with custom project name"
    echo ""
    echo "The resulting AMI will be named: \${PROJECT_NAME}-\${version}"
    echo "Example: spring-boot-hello-world-v1.0-blue"
}

# Check if version provided
if [ -z "$APP_VERSION" ]; then
    echo -e "${RED}Error: Version argument required${NC}"
    echo ""
    usage
    exit 1
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    Build AMI Script                        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Project:${NC} $PROJECT_NAME"
echo -e "${GREEN}Version:${NC} $APP_VERSION"
echo -e "${GREEN}AMI Name:${NC} $PROJECT_NAME-$APP_VERSION"
echo ""

# Step 1: Build JAR
echo -e "${YELLOW}Step 1: Building application JAR...${NC}"
cd "$SCRIPT_DIR"
mvn clean package -DskipTests -q
echo -e "${GREEN}✓ JAR built successfully${NC}"
echo ""

# Step 2: Build AMI with Packer
echo -e "${YELLOW}Step 2: Building AMI with Packer...${NC}"
cd "$SCRIPT_DIR/infra/packer"

# Initialize Packer plugins
packer init spring-boot-ami.pkr.hcl > /dev/null 2>&1 || true

# Build the AMI
packer build \
    -var "jar_path=$SCRIPT_DIR/target/spring-boot-hello-world-1.0-SNAPSHOT.jar" \
    -var "ami_name_prefix=$PROJECT_NAME" \
    -var "app_version=$APP_VERSION" \
    spring-boot-ami.pkr.hcl

echo ""
echo -e "${GREEN}✓ AMI built successfully${NC}"
echo ""

# Get the AMI ID
AMI_ID=$(aws ec2 describe-images \
    --owners self \
    --filters "Name=tag:Application,Values=$PROJECT_NAME" "Name=tag:Version,Values=$APP_VERSION" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text)

AMI_NAME=$(aws ec2 describe-images \
    --image-ids "$AMI_ID" \
    --query 'Images[0].Name' \
    --output text)

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    AMI Build Complete                      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}AMI ID:${NC}   $AMI_ID"
echo -e "${GREEN}AMI Name:${NC} $AMI_NAME"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. Run your Harness pipeline"
echo "  2. Enter AMI version: $AMI_NAME"
echo ""
