# ShazaPiano Makefile
# Shortcuts for common development tasks

.PHONY: help setup test clean backend-run flutter-run docker-up lint format

# Colors
CYAN := \033[0;36m
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m # No Color

help: ## Show this help message
	@echo "$(CYAN)ShazaPiano - Development Commands$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}'

setup: ## Setup development environment
	@echo "$(CYAN)Setting up development environment...$(NC)"
	@chmod +x scripts/setup.sh
	@./scripts/setup.sh

test: ## Run all tests
	@echo "$(CYAN)Running all tests...$(NC)"
	@chmod +x scripts/test.sh
	@./scripts/test.sh

clean: ## Clean build artifacts
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	@rm -rf backend/.venv
	@rm -rf backend/__pycache__
	@rm -rf backend/**/__pycache__
	@rm -rf backend/.pytest_cache
	@rm -rf backend/htmlcov
	@rm -rf app/build
	@rm -rf app/.dart_tool
	@echo "$(GREEN)✓ Cleaned!$(NC)"

backend-run: ## Run backend server
	@echo "$(CYAN)Starting backend server...$(NC)"
	@cd backend && source .venv/bin/activate && uvicorn app:app --reload --host 0.0.0.0 --port 8000

backend-test: ## Run backend tests only
	@echo "$(CYAN)Running backend tests...$(NC)"
	@cd backend && source .venv/bin/activate && pytest --cov=. --cov-report=term -v

backend-lint: ## Lint backend code
	@echo "$(CYAN)Linting backend...$(NC)"
	@cd backend && source .venv/bin/activate && black --check . && flake8 .

backend-format: ## Format backend code
	@echo "$(CYAN)Formatting backend...$(NC)"
	@cd backend && source .venv/bin/activate && black .

flutter-run: ## Run Flutter app
	@echo "$(CYAN)Starting Flutter app...$(NC)"
	@cd app && flutter run

flutter-test: ## Run Flutter tests only
	@echo "$(CYAN)Running Flutter tests...$(NC)"
	@cd app && flutter test --coverage

flutter-analyze: ## Analyze Flutter code
	@echo "$(CYAN)Analyzing Flutter code...$(NC)"
	@cd app && flutter analyze

flutter-format: ## Format Flutter code
	@echo "$(CYAN)Formatting Flutter code...$(NC)"
	@cd app && dart format .

flutter-build-apk: ## Build Android APK
	@echo "$(CYAN)Building Android APK...$(NC)"
	@cd app && flutter build apk --release

flutter-build-aab: ## Build Android App Bundle
	@echo "$(CYAN)Building Android App Bundle...$(NC)"
	@cd app && flutter build appbundle --release

docker-up: ## Start Docker containers
	@echo "$(CYAN)Starting Docker containers...$(NC)"
	@cd infra && docker-compose up -d

docker-down: ## Stop Docker containers
	@echo "$(CYAN)Stopping Docker containers...$(NC)"
	@cd infra && docker-compose down

docker-logs: ## View Docker logs
	@cd infra && docker-compose logs -f

docker-build: ## Build Docker images
	@echo "$(CYAN)Building Docker images...$(NC)"
	@cd infra && docker-compose build

lint: backend-lint flutter-analyze ## Lint all code

format: backend-format flutter-format ## Format all code

install-backend: ## Install backend dependencies
	@echo "$(CYAN)Installing backend dependencies...$(NC)"
	@cd backend && python -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt

install-flutter: ## Install Flutter dependencies
	@echo "$(CYAN)Installing Flutter dependencies...$(NC)"
	@cd app && flutter pub get

commit: ## Quick commit with message
	@read -p "Commit message: " msg; \
	git add .; \
	git commit -m "$$msg"; \
	git push

status: ## Show git status
	@git status

pull: ## Pull latest changes
	@git pull origin main

# Development shortcuts
dev-backend: install-backend backend-run ## Install deps and run backend
dev-flutter: install-flutter flutter-run ## Install deps and run Flutter

# CI/CD simulation
ci-backend: backend-lint backend-test ## Run backend CI checks
ci-flutter: flutter-analyze flutter-test ## Run Flutter CI checks
ci-all: ci-backend ci-flutter ## Run all CI checks

# Documentation
docs: ## Open documentation
	@echo "$(CYAN)Documentation:$(NC)"
	@echo "  - README.md"
	@echo "  - docs/ARCHITECTURE.md"
	@echo "  - docs/UI_SPEC.md"
	@echo "  - docs/ROADMAP.md"
	@echo "  - docs/SETUP_FIREBASE.md"
	@echo "  - docs/meta/legacy/STATUS.md"
	@echo "  - docs/meta/legacy/FINAL_SUMMARY.md"

# Project info
info: ## Show project information
	@echo "$(CYAN)ShazaPiano - Project Information$(NC)"
	@echo ""
	@echo "$(GREEN)Backend:$(NC)"
	@cd backend && python --version 2>/dev/null || echo "  Python not installed"
	@echo ""
	@echo "$(GREEN)Flutter:$(NC)"
	@cd app && flutter --version 2>/dev/null | head -n 1 || echo "  Flutter not installed"
	@echo ""
	@echo "$(GREEN)Docker:$(NC)"
	@docker --version 2>/dev/null || echo "  Docker not installed"
	@echo ""
	@echo "$(GREEN)Git:$(NC)"
	@git log --oneline -1


