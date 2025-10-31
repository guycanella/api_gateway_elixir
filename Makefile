.PHONY: help docker-up docker-down docker-restart docker-logs docker-clean docker-ps db-shell test seed

# Variables
DOCKER_COMPOSE = docker-compose

# Load .env.local if it exists
ifneq (,$(wildcard ./.env.local))
    include .env.local
    export
endif

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

test: ## Run tests (all tests or specific file with FILE=name)
	@if [ -z "$(FILE)" ]; then \
		echo "🧪 Rodando todos os testes..."; \
		mix test; \
	else \
		echo "🔍 Procurando arquivo de teste: $(FILE)..."; \
		EXACT_MATCH=$$(find apps/*/test -type f -name "$(FILE)_test.exs" | head -n 1); \
		if [ -n "$$EXACT_MATCH" ]; then \
			echo "✅ Match exato encontrado: $$EXACT_MATCH"; \
			echo "🧪 Rodando teste..."; \
			mix test $$EXACT_MATCH; \
		else \
			TEST_FILES=$$(find apps/*/test -type f -name "*$(FILE)*_test.exs"); \
			TEST_COUNT=$$(echo "$$TEST_FILES" | grep -c . || echo 0); \
			if [ -z "$$TEST_FILES" ]; then \
				echo "❌ Arquivo de teste não encontrado: $(FILE)"; \
				echo "💡 Dica: use apenas parte do nome (ex: make test FILE=integration)"; \
				exit 1; \
			elif [ $$TEST_COUNT -gt 1 ]; then \
				echo "⚠️  Múltiplos arquivos encontrados:"; \
				echo "$$TEST_FILES" | nl; \
				echo ""; \
				echo "💡 Seja mais específico ou use o nome exato:"; \
				echo "   make test FILE=circuit_breaker           (busca circuit_breaker_test.exs primeiro)"; \
				echo "   make test FILE=circuit_breaker_state     (busca circuit_breaker_state_test.exs)"; \
				exit 1; \
			else \
				echo "✅ Encontrado: $$TEST_FILES"; \
				echo "🧪 Rodando teste..."; \
				mix test $$TEST_FILES; \
			fi \
		fi \
	fi

seed: ## Populate database with test data
	@echo "🌱 Populando banco de dados com dados de teste..."
	@mix run apps/gateway_db/priv/repo/seeds.exs
	@echo "✅ Seeds executados com sucesso!"

# Commands to be added in the future:
# setup: ## Install dependencies and configure the project
# format: ## Format code
# lint: ## Check code quality
# migrate: ## Run database migrations