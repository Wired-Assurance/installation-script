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
  echo -e "${YELLOW}🔧 Attempting to install Docker...${NC}"
  
  # Detect OS and install Docker accordingly
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    echo "📥 Installing Docker Desktop for macOS..."
    if command -v brew >/dev/null 2>&1; then
      echo "🍺 Using Homebrew to install Docker Desktop..."
      brew install --cask docker
      if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Docker Desktop installed via Homebrew${NC}"
        echo -e "${YELLOW}⚠️  Please start Docker Desktop from Applications and rerun this script${NC}"
        exit 0
      fi
    fi
    
    # Fallback: Direct download for macOS
    echo "📦 Downloading Docker Desktop for macOS..."
    ARCH=$(uname -m)
    if [[ "$ARCH" == "arm64" ]]; then
      DOCKER_URL="https://desktop.docker.com/mac/main/arm64/Docker.dmg"
    else
      DOCKER_URL="https://desktop.docker.com/mac/main/amd64/Docker.dmg"
    fi
    
    curl -L "$DOCKER_URL" -o Docker.dmg
    if [ $? -eq 0 ]; then
      echo "💿 Mounting and installing Docker Desktop..."
      hdiutil attach Docker.dmg
      cp -R "/Volumes/Docker/Docker.app" /Applications/
      hdiutil detach "/Volumes/Docker"
      rm Docker.dmg
      echo -e "${GREEN}✅ Docker Desktop installed${NC}"
      echo -e "${YELLOW}⚠️  Please start Docker Desktop from Applications and rerun this script${NC}"
      exit 0
    fi
    
  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    echo "🐧 Installing Docker for Linux..."
    
    # Try package manager based installation
    if command -v apt-get >/dev/null 2>&1; then
      # Ubuntu/Debian
      echo "📦 Installing Docker via apt..."
      sudo apt-get update
      sudo apt-get install -y ca-certificates curl gnupg lsb-release
      sudo mkdir -p /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
      sudo apt-get update
      sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
      sudo systemctl start docker
      sudo systemctl enable docker
      sudo usermod -aG docker $USER
      echo -e "${GREEN}✅ Docker installed${NC}"
      echo -e "${YELLOW}⚠️  Please log out and log back in, then rerun this script${NC}"
      exit 0
      
    elif command -v yum >/dev/null 2>&1; then
      # CentOS/RHEL
      echo "📦 Installing Docker via yum..."
      sudo yum install -y yum-utils
      sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
      sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
      sudo systemctl start docker
      sudo systemctl enable docker
      sudo usermod -aG docker $USER
      echo -e "${GREEN}✅ Docker installed${NC}"
      echo -e "${YELLOW}⚠️  Please log out and log back in, then rerun this script${NC}"
      exit 0
      
    elif command -v pacman >/dev/null 2>&1; then
      # Arch Linux
      echo "📦 Installing Docker via pacman..."
      sudo pacman -S --noconfirm docker docker-compose
      sudo systemctl start docker
      sudo systemctl enable docker
      sudo usermod -aG docker $USER
      echo -e "${GREEN}✅ Docker installed${NC}"
      echo -e "${YELLOW}⚠️  Please log out and log back in, then rerun this script${NC}"
      exit 0
    fi
  fi
  
  # If automatic installation failed
  echo -e "${RED}❌ Automatic Docker installation failed${NC}"
  echo -e "${YELLOW}Please install Docker manually:${NC}"
  echo "  📖 macOS: https://docs.docker.com/desktop/install/mac-install/"
  echo "  📖 Linux: https://docs.docker.com/engine/install/"
  echo "  📖 Windows: https://docs.docker.com/desktop/install/windows-install/"
  exit 1
fi
echo -e "${GREEN}✅ Docker is available${NC}"

# Docker status check
echo "🐳 Checking Docker status..."
if ! docker info >/dev/null 2>&1; then
  echo -e "${YELLOW}⚠️  Docker is installed but not responding. Trying to start it...${NC}"
  sudo systemctl start docker
  sleep 2
  if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}❌ Docker is still not running${NC}"
    echo -e "${YELLOW}Check logs with:${NC} sudo journalctl -u docker -n 50"
    exit 1
  fi
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

# Pull Docker image from Amazon ECR
# Public ECR repository URL format: public.ecr.aws/[registry-alias]/[repository-name]:[tag]
# Private ECR repository URL format: [aws-account-id].dkr.ecr.[region].amazonaws.com/[repository-name]:[tag]

# Replace with your actual ECR repository URL
ECR_REPO="public.ecr.aws/u2u6i4x5/waf-image"
IMAGE_TAG="latest"

echo "📦 Downloading APISphere WAF image ($ARCH $DOCKER_PLATFORM)..."
if ! docker pull -q $DOCKER_PLATFORM $ECR_REPO:$IMAGE_TAG >/dev/null; then
  echo -e "${RED}❌ Failed to pull Docker image from Amazon ECR for $ARCH${NC}"
  echo -e "${YELLOW}Possible solutions:"
  echo "  1. Check your internet connection"
  echo "  2. Verify ECR access: docker pull $ECR_REPO:$IMAGE_TAG"
  echo "  3. Try with VPN if on corporate network"
  echo "  4. If you are on Apple Silicon (M1/M2), try: DOCKER_WAF_PLATFORM=linux/amd64 ./install.sh"
  echo -e "${NC}"
  exit 1
fi
echo -e "${GREEN}✅ Image downloaded successfully from Amazon ECR for $ARCH${NC}"

# Backend service check (improved)
echo "🔍 Verifying backend service on port $BACKEND_PORT..."
BACKEND_PID=$(sudo lsof -ti tcp:"$BACKEND_PORT" 2>/dev/null)
if [ -z "$BACKEND_PID" ]; then
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
else
  # Try to identify backend process type
  BACKEND_CMD=$(ps -p "$BACKEND_PID" -o comm= 2>/dev/null)
  if [[ ! "$BACKEND_CMD" =~ (node|python|java|ruby|gunicorn|uwsgi|dotnet|rails|flask|go|php|nginx|httpd|apache2) ]]; then
    echo -e "${YELLOW}⚠️  Service detected on port $BACKEND_PORT, but not a typical backend process ($BACKEND_CMD)${NC}"
    echo -e "${YELLOW}Proceeding, but please ensure your backend is running as expected.${NC}"
  fi
  echo -e "${GREEN}✅ Backend service confirmed on port $BACKEND_PORT ($BACKEND_CMD)${NC}"
fi

# Port conflict check for WAF_PORT (matches .bat logic)
echo "🔎 Checking if WAF port $WAF_PORT is available..."
WAF_PORT_IN_USE=0

# Check if any process is using the port
if lsof -i tcp:"$WAF_PORT" >/dev/null 2>&1; then
  WAF_PORT_IN_USE=1
fi

# Check if any Docker container is using the port
DOCKER_CONFLICT_CONTAINER_IDS=$(docker ps --format '{{.ID}} {{.Ports}}' | grep ":$WAF_PORT->8080" | awk '{print $1}')
if [ -n "$DOCKER_CONFLICT_CONTAINER_IDS" ]; then
  WAF_PORT_IN_USE=1
fi

if [ "$WAF_PORT_IN_USE" -eq 1 ]; then
  echo -e "${YELLOW}⚠️  Port $WAF_PORT is already in use${NC}"
  # Try to stop conflicting Docker containers
  if [ -n "$DOCKER_CONFLICT_CONTAINER_IDS" ]; then
    for cid in $DOCKER_CONFLICT_CONTAINER_IDS; do
      echo "🧹 Stopping conflicting Docker container: $cid"
      docker stop "$cid" >/dev/null 2>&1
      docker rm "$cid" >/dev/null 2>&1
    done
  fi
  # Check again if port is still in use
  if lsof -i tcp:"$WAF_PORT" >/dev/null 2>&1; then
    echo -e "${RED}❌ Port $WAF_PORT is still in use after Docker cleanup${NC}"
    echo -e "${YELLOW}Tips:${NC}"
    echo "  1. Close any application using port $WAF_PORT"
    echo "  2. Choose a different WAF_PORT"
    echo "  3. Run: lsof -i :$WAF_PORT"
    exit 1
  fi
  echo -e "${GREEN}✅ Port conflict resolved${NC}"
fi

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
  -e BACKEND_HOST=host.docker.internal \
  -e BACKEND_PORT="$BACKEND_PORT" \
  --add-host=host.docker.internal:host-gateway \
  -p "$WAF_PORT":8080 \
  $ECR_REPO:$IMAGE_TAG >/dev/null

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
