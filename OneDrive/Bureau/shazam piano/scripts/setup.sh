#!/bin/bash
# ShazaPiano - Setup Script
# Sets up development environment

set -e

echo "🎹 ShazaPiano Setup Script"
echo "=========================="

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Backend Setup
echo ""
echo "📦 Setting up Backend..."
echo "------------------------"

if ! command_exists python3; then
    echo -e "${RED}❌ Python 3 not found. Please install Python 3.10+${NC}"
    exit 1
fi

echo "✓ Python found: $(python3 --version)"

if ! command_exists ffmpeg; then
    echo -e "${YELLOW}⚠️  FFmpeg not found. Installing...${NC}"
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo apt-get update
        sudo apt-get install -y ffmpeg
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        brew install ffmpeg
    else
        echo -e "${RED}❌ Please install FFmpeg manually${NC}"
        exit 1
    fi
fi

echo "✓ FFmpeg found: $(ffmpeg -version | head -n 1)"

cd backend

if [ ! -d ".venv" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv .venv
fi

echo "Activating virtual environment..."
source .venv/bin/activate

echo "Installing Python dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

echo -e "${GREEN}✅ Backend setup complete!${NC}"

cd ..

# Flutter Setup
echo ""
echo "📱 Setting up Flutter App..."
echo "----------------------------"

if ! command_exists flutter; then
    echo -e "${RED}❌ Flutter not found. Please install Flutter SDK${NC}"
    echo "   Visit: https://docs.flutter.dev/get-started/install"
    exit 1
fi

echo "✓ Flutter found: $(flutter --version | head -n 1)"

cd app

echo "Getting Flutter dependencies..."
flutter pub get

echo "Running code generation..."
flutter pub run build_runner build --delete-conflicting-outputs

echo -e "${GREEN}✅ Flutter setup complete!${NC}"

cd ..

# Docker Setup
echo ""
echo "🐳 Checking Docker..."
echo "--------------------"

if command_exists docker; then
    echo "✓ Docker found: $(docker --version)"
    echo "✓ Docker Compose found: $(docker compose version)"
else
    echo -e "${YELLOW}⚠️  Docker not found (optional)${NC}"
fi

# Firebase Setup
echo ""
echo "🔥 Firebase Setup"
echo "----------------"

if [ -f "app/android/app/google-services.json" ]; then
    echo -e "${GREEN}✓ google-services.json found${NC}"
else
    echo -e "${YELLOW}⚠️  google-services.json not found${NC}"
    echo "   1. Create Firebase project"
    echo "   2. Download google-services.json"
    echo "   3. Place in app/android/app/"
    echo "   See: docs/SETUP_FIREBASE.md"
fi

# Summary
echo ""
echo "================================"
echo -e "${GREEN}🎉 Setup Complete!${NC}"
echo "================================"
echo ""
echo "Next steps:"
echo "  1. Backend: cd backend && uvicorn app:app --reload"
echo "  2. Flutter: cd app && flutter run"
echo "  3. Docker:  cd infra && docker-compose up"
echo ""
echo "Documentation:"
echo "  - README.md"
echo "  - STATUS.md"
echo "  - docs/SETUP_FIREBASE.md"
echo ""
echo "Happy coding! 🎹"

