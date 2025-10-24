.PHONY: help docker-up docker-down docker-restart docker-logs docker-clean docker-ps db-shell

# Variables
DOCKER_COMPOSE = docker-compose

help: ## Show this help message
	@echo "Comandos disponíveis:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

docker-up: ## Start containers in background
	$(DOCKER_COMPOSE) up -d
	@echo "✅ Containers iniciados!"
	@echo "📊 PostgreSQL disponível em localhost:5432"

docker-down: ## Stop and remove containers
	$(DOCKER_COMPOSE) down
	@echo "🛑 Containers parados e removidos!"

docker-restart: ## Restart containers
	$(DOCKER_COMPOSE) restart
	@echo "🔄 Containers reiniciados!"

docker-logs: ## Show logs of containers
	$(DOCKER_COMPOSE) logs -f

docker-logs-postgres: ## Show only logs of PostgreSQL
	$(DOCKER_COMPOSE) logs -f postgres

docker-clean: ## Stop containers and remove volumes (⚠️  delete database data!)
	$(DOCKER_COMPOSE) down -v
	@echo "🧹 Containers e volumes removidos!"

docker-ps: ## List running containers
	$(DOCKER_COMPOSE) ps

db-shell: ## Open interactive shell in PostgreSQL
	$(DOCKER_COMPOSE) exec postgres psql -U postgres -d api_gateway_dev

# Commands to be added in the future:
# setup: ## Install dependencies and configure the project
# test: ## Run tests
# format: ## Format code
# lint: ## Check code quality
# migrate: ## Run database migrations
# seed: ## Populate database with test data