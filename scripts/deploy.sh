#!/bin/bash
# ShazaPiano - Deployment Script
# Deploys backend to production

set -e

echo "🚀 ShazaPiano Deployment Script"
echo "================================"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
BACKEND_DIR="backend"
APP_DIR="app"
DEPLOY_TARGET=${1:-"fly"}  # Default to Fly.io

# Functions
deploy_to_fly() {
    echo -e "${CYAN}Deploying backend to Fly.io...${NC}"
    
    cd $BACKEND_DIR
    
    if ! command -v flyctl &> /dev/null; then
        echo -e "${RED}❌ flyctl not installed${NC}"
        echo "Install: https://fly.io/docs/hands-on/install-flyctl/"
        exit 1
    fi
    
    # Check if fly.toml exists
    if [ ! -f "fly.toml" ]; then
        echo -e "${YELLOW}Creating fly.toml...${NC}"
        flyctl launch --no-deploy
    fi
    
    echo -e "${GREEN}Deploying to Fly.io...${NC}"
    flyctl deploy
    
    echo -e "${GREEN}✅ Backend deployed!${NC}"
    flyctl status
    
    cd ..
}

deploy_to_railway() {
    echo -e "${CYAN}Deploying backend to Railway...${NC}"
    
    cd $BACKEND_DIR
    
    if ! command -v railway &> /dev/null; then
        echo -e "${RED}❌ railway CLI not installed${NC}"
        echo "Install: npm install -g @railway/cli"
        exit 1
    fi
    
    echo -e "${GREEN}Deploying to Railway...${NC}"
    railway up
    
    echo -e "${GREEN}✅ Backend deployed!${NC}"
    railway status
    
    cd ..
}

deploy_docker() {
    echo -e "${CYAN}Building and pushing Docker image...${NC}"
    
    # Check for Docker registry
    REGISTRY=${DOCKER_REGISTRY:-"ghcr.io/sky1241"}
    IMAGE_NAME="shazapiano-backend"
    TAG=${DOCKER_TAG:-"latest"}
    
    cd $BACKEND_DIR
    
    echo -e "${GREEN}Building Docker image...${NC}"
    docker build -t $REGISTRY/$IMAGE_NAME:$TAG .
    
    echo -e "${GREEN}Pushing to registry...${NC}"
    docker push $REGISTRY/$IMAGE_NAME:$TAG
    
    echo -e "${GREEN}✅ Docker image pushed!${NC}"
    echo "Image: $REGISTRY/$IMAGE_NAME:$TAG"
    
    cd ..
}

build_flutter_release() {
    echo -e "${CYAN}Building Flutter release...${NC}"
    
    cd $APP_DIR
    
    # Check for signing config
    if [ ! -f "android/key.properties" ]; then
        echo -e "${YELLOW}⚠️  No signing config found${NC}"
        echo "Building unsigned APK..."
        flutter build apk --release
    else
        echo -e "${GREEN}Building signed App Bundle...${NC}"
        flutter build appbundle --release
    fi
    
    echo -e "${GREEN}✅ Flutter build complete!${NC}"
    
    if [ -f "build/app/outputs/bundle/release/app-release.aab" ]; then
        echo "AAB: build/app/outputs/bundle/release/app-release.aab"
    elif [ -f "build/app/outputs/flutter-apk/app-release.apk" ]; then
        echo "APK: build/app/outputs/flutter-apk/app-release.apk"
    fi
    
    cd ..
}

# Pre-deployment checks
echo ""
echo -e "${CYAN}Pre-deployment checks...${NC}"
echo "------------------------"

# Run tests
echo "Running tests..."
if [ -f "scripts/test.sh" ]; then
    chmod +x scripts/test.sh
    ./scripts/test.sh || {
        echo -e "${RED}❌ Tests failed!${NC}"
        exit 1
    }
else
    echo -e "${YELLOW}⚠️  No test script found${NC}"
fi

# Check git status
if [ -n "$(git status --porcelain)" ]; then
    echo -e "${YELLOW}⚠️  You have uncommitted changes${NC}"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Deployment
echo ""
echo -e "${CYAN}Starting deployment...${NC}"
echo "----------------------"

case $DEPLOY_TARGET in
    fly)
        deploy_to_fly
        ;;
    railway)
        deploy_to_railway
        ;;
    docker)
        deploy_docker
        ;;
    flutter)
        build_flutter_release
        ;;
    all)
        deploy_to_fly
        build_flutter_release
        ;;
    *)
        echo -e "${RED}Unknown target: $DEPLOY_TARGET${NC}"
        echo "Usage: ./deploy.sh [fly|railway|docker|flutter|all]"
        exit 1
        ;;
esac

# Summary
echo ""
echo "================================"
echo -e "${GREEN}🎉 Deployment Complete!${NC}"
echo "================================"
echo ""
echo "Next steps:"
echo "  - Verify deployment at your production URL"
echo "  - Run smoke tests"
echo "  - Monitor logs for errors"
echo "  - Update DNS if needed"
echo ""


