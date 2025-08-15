#!/bin/bash

# APISphere WAF Installation Script for Mac/Linux
# Uses Docker volumes for persistent PLATFORM_ID storage

echo "🔧 APISphere WAF Installation Starting..."

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check arguments
if [[ $# -lt 2 ]]; then
  echo -e "${RED}❌ Usage: ./install.sh PLATFORM_ID BACKEND_PORT [WAF_PORT]${NC}"
  echo ""
  echo "Examples:"
  echo "  ./install.sh my-project-uuid 8000"
  echo "  ./install.sh my-project-uuid 3000 9080"
  echo "  ./install.sh my-project-uuid 5000 8080"
  echo ""
  echo "Arguments:"
  echo "  ${CYAN}PLATFORM_ID${NC}    - Your project UUID"
  echo "  ${CYAN}BACKEND_PORT${NC}  - Port where your application is running"
  echo "  ${CYAN}WAF_PORT${NC}      - Port for WAF-protected access (default: 8080)"
  echo ""
  echo "Description:"
  echo "  WAF creates a protective layer in front of your application"
  echo "  All traffic should go through WAF_PORT for security protection"
  exit 1
fi

# Read arguments
PLATFORM_ID="$1"
BACKEND_PORT="$2"
WAF_PORT="${3:-8080}"


echo -e "${GREEN}⚙️ Configuration:${NC}"
echo "  Platform ID:   ${CYAN}$PLATFORM_ID${NC}"
echo "  Backend port: ${CYAN}$BACKEND_PORT${NC}"
echo "  WAF port:     ${CYAN}$WAF_PORT${NC}"
echo ""

# Docker availability check
if ! command -v docker >/dev/null 2>&1; then
  echo -e "${RED}❌ Docker is not installed or not available in PATH${NC}"
  echo -e "${YELLOW}Tip: Install Docker Desktop from https://www.docker.com/products/docker-desktop and ensure 'docker' is in your PATH${NC}"
  exit 1
fi

# Docker status check
echo "🐳 Checking Docker status..."
if ! docker info >/dev/null 2>&1; then
  echo -e "${RED}❌ Docker is not running. Please start Docker Desktop and try again${NC}"
  echo -e "${YELLOW}Tip: Ensure Docker is running in your applications folder${NC}"
  exit 1
fi
echo -e "${GREEN}✅ Docker is running${NC}"

# Create config volume
echo "💾 Creating persistent storage for project ID..."
if ! docker volume create apisphere-config-"$PLATFORM_ID" >/dev/null; then
  echo -e "${RED}❌ Failed to create Docker volume${NC}"
  exit 1
fi

# Store in Docker volume with proper permissions
echo "$PLATFORM_ID" > temp_id
docker run --rm -i -v apisphere-config-"$PLATFORM_ID":/config busybox sh -c "cat > /config/PLATFORM_ID && chmod 644 /config/PLATFORM_ID" < temp_id
rm temp_id

# Verify storage
docker run --rm -v apisphere-config-"$PLATFORM_ID":/config busybox sh -c "ls -l /config && cat /config/PLATFORM_ID"

if [ $? -ne 0 ]; then
  echo -e "${RED}❌ Failed to store PLATFORM_ID in Docker volume${NC}"
  exit 1
fi
echo -e "${GREEN}✅ Project ID stored securely in Docker volume${NC}"

# Pull Docker image

# Detect platform and select image tag
ARCH=$(uname -m)
IMAGE_TAG="latest"
if [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
  IMAGE_TAG="arm64"
fi

echo "📦 Downloading APISphere WAF image for $ARCH..."
if ! docker pull -q ezeanacmichael/apisphere-waf:$IMAGE_TAG >/dev/null; then
  echo -e "${RED}❌ Failed to pull Docker image for $ARCH (${IMAGE_TAG})${NC}"
  echo -e "${YELLOW}Possible solutions:"
  echo "  1. Check your internet connection"
  echo "  2. Verify Docker Hub access: docker pull busybox"
  echo "  3. Try with VPN if on corporate network"
  echo "  4. If you are on Apple Silicon (M1/M2), ensure the image supports arm64."
  echo -e "${NC}"
  exit 1
fi
echo -e "${GREEN}✅ Image downloaded successfully for $ARCH (${IMAGE_TAG})${NC}"

# Backend service check
echo "🔍 Verifying backend service on port $BACKEND_PORT..."
if ! lsof -i :"$BACKEND_PORT" >/dev/null 2>&1; then
  echo -e "${RED}❌ No service detected on port $BACKEND_PORT${NC}"
  echo -e "${YELLOW}Please start your backend application first:${NC}"
  echo ""
  echo "Common startup commands:"
  echo "  ${CYAN}Node.js:${NC}    npm start"
  echo "  ${CYAN}Python:${NC}     flask run -p $BACKEND_PORT"
  echo "  ${CYAN}Ruby:${NC}       rails server -p $BACKEND_PORT"
  echo "  ${CYAN}Java:${NC}       mvn spring-boot:run"
  echo ""
  echo -e "${YELLOW}After starting your app, rerun this script${NC}"
  exit 1
fi
echo -e "${GREEN}✅ Backend service confirmed on port $BACKEND_PORT${NC}"

# Stop and remove any container using the target WAF port
existing_container=$(docker ps --format '{{.ID}} {{.Ports}}' | grep ":$WAF_PORT->8080" | awk '{print $1}')
if [ -n "$existing_container" ]; then
  echo "🧹 Stopping container using port $WAF_PORT: $existing_container"
  docker stop "$existing_container" >/dev/null 2>&1
  docker rm "$existing_container" >/dev/null 2>&1
fi

# Cleanup existing containers
echo "🧹 Removing old containers (if any)..."
docker rm -f apisphere-waf-"$PLATFORM_ID" >/dev/null 2>&1


# Start WAF container
echo "🛡️ Starting APISphere WAF protection..."
docker run -d \
  --name apisphere-waf-"$PLATFORM_ID" \
  -v apisphere-config-"$PLATFORM_ID":/app/config:ro \
  -e PLATFORM_ID="$PLATFORM_ID" \
  -e BACKEND_PORT="$BACKEND_PORT" \
  -p "$WAF_PORT":8080 \
  ezeanacmichael/apisphere-waf:latest >/dev/null

# Verify startup
echo "⏳ Waiting for container initialization (5 seconds)..."
sleep 5

# Verify PLATFORM_ID inside the running container
docker exec apisphere-waf-"$PLATFORM_ID" ls -l /app/config
docker exec apisphere-waf-"$PLATFORM_ID" cat /app/config/PLATFORM_ID

if docker ps | grep -q "apisphere-waf-$PLATFORM_ID"; then
  echo -e "${GREEN}✅ WAF started successfully${NC}"
  echo ""
  echo -e "${GREEN}🎉 APISphere WAF Setup Complete!${NC}"
  echo ""
  echo -e "${CYAN}=== Protection Status ========================${NC}"
  echo "  Project ID:       $PLATFORM_ID"
  echo "  Backend URL:      http://localhost:$BACKEND_PORT"
  echo "  Protected URL:    http://localhost:$WAF_PORT"
  echo ""
  echo -e "${CYAN}=== Security Verification ===================${NC}"
  echo "  Test safe request:"
  echo "    curl -I http://localhost:$WAF_PORT/"
  echo ""
  echo "  Test blocked request:"
  echo "    curl 'http://localhost:$WAF_PORT/?exec=/bin/bash'"
  echo ""
  echo -e "${CYAN}=== Management Commands =====================${NC}"
  echo "  View logs:        docker logs apisphere-waf-$PLATFORM_ID"
  echo "  Stop WAF:         docker stop apisphere-waf-$PLATFORM_ID"
  echo "  Restart WAF:      docker start apisphere-waf-$PLATFORM_ID"
  echo "  Remove WAF:       docker rm -f apisphere-waf-$PLATFORM_ID"
  echo "  Remove volume:    docker volume rm apisphere-config-$PLATFORM_ID"
  echo ""
  echo -e "${CYAN}=== Persistence Info ========================${NC}"
  echo "  PLATFORM_ID is stored in Docker volume:"
  echo "    apisphere-config-$PLATFORM_ID"
  echo ""
  echo -e "${GREEN}All traffic should now go through the protected port!${NC}"
else
  echo -e "${RED}❌ WAF failed to start${NC}"
  echo "Troubleshooting steps:"
  echo "  1. Check container logs:"
  echo "     ${CYAN}docker logs apisphere-waf-$PLATFORM_ID${NC}"
  echo "  2. Verify port availability:"
  echo "     ${CYAN}lsof -i :$WAF_PORT${NC}"
  echo "  3. Check Docker resource allocation"
  echo "  4. Ensure backend is still running"
  exit 1
fi