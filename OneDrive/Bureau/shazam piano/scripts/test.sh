#!/bin/bash
# ShazaPiano - Test Script
# Runs all tests

set -e

echo "🧪 ShazaPiano Test Suite"
echo "========================"

# Backend Tests
echo ""
echo "📦 Backend Tests..."
echo "------------------"

cd backend

if [ ! -d ".venv" ]; then
    echo "❌ Virtual environment not found. Run ./scripts/setup.sh first"
    exit 1
fi

source .venv/bin/activate

echo "Running pytest..."
pytest --cov=. --cov-report=term --cov-report=html -v

echo "✅ Backend tests passed!"

cd ..

# Flutter Tests
echo ""
echo "📱 Flutter Tests..."
echo "------------------"

cd app

echo "Running flutter test..."
flutter test --coverage

echo "✅ Flutter tests passed!"

cd ..

# Summary
echo ""
echo "================================"
echo "🎉 All Tests Passed!"
echo "================================"
echo ""
echo "Coverage reports:"
echo "  - Backend: backend/htmlcov/index.html"
echo "  - Flutter: app/coverage/lcov.info"


