# MakanLah developer entrypoints.
# Windows users: run from Git Bash with GNU make (choco install make).

ifeq ($(OS),Windows_NT)
VENV_BIN := .venv/Scripts
else
VENV_BIN := .venv/bin
endif

.PHONY: up-local down-local logs test test-menu test-order test-worker demo-order audit nuke

up-local: ## build and start the full local stack
	docker compose up -d --build
	@echo ""
	@echo "menu-service   http://localhost:8081/docs"
	@echo "order-service  http://localhost:8082/healthz"
	@echo "elasticmq ui   http://localhost:9325"
	@echo "try:           make demo-order"

down-local: ## stop the local stack and remove volumes
	docker compose down -v

logs:
	docker compose logs -f --tail=50

test: test-menu test-order test-worker ## run every service's test suite

test-menu:
	cd services/menu-service && $(VENV_BIN)/python -m pytest

test-order:
	cd services/order-service && npx jest --coverage

test-worker:
	cd services/notify-worker && $(VENV_BIN)/python -m pytest

demo-order: ## place an order end-to-end against the local stack
	bash scripts/demo-order.sh

audit: ## verify the AWS account has no idle-billable resources
	bash scripts/aws-audit.sh

nuke: down-local ## tear down EVERYTHING that costs money (local + cloud dev env)
	cd infra/envs/dev && terraform destroy -auto-approve
	@echo "dev environment destroyed. run 'make audit' to verify the account is at zero."
