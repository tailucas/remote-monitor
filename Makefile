.DELETE_ON_ERROR:
.DEFAULT_GOAL := help

DOCKER_URL := https://docs.docker.com/engine/install
DEVCLI_URL := https://code.visualstudio.com/docs/devcontainers/devcontainer-cli
CHECK_USER := vscode

.PHONY: help check dev dev-build dev-up python

# ---------- Dev container (host only) ----------

check:
	@if [ "${USER}" = "$(CHECK_USER)" ]; then \
	  echo "Running as user ${USER}; dev container targets are host-only."; \
	  echo "Inside the dev container, use: make python"; \
	  exit 1; \
	fi
	@which docker > /dev/null || (echo "Needs Docker, see $(DOCKER_URL)"; exit 1)
	@which devcontainer > /dev/null || (echo "Needs Dev Container CLI; see $(DEVCLI_URL)"; exit 1)

dev-build: check ## Build the dev container
	devcontainer build --workspace-folder .

dev-up: dev-build ## Start the dev container
	devcontainer up --workspace-folder .

dev: dev-up ## Open a shell in the dev container
	devcontainer exec --workspace-folder . bash

# ---------- Development (inside the dev container) ----------

.venv: pyproject.toml uv.lock ## Create/sync the Python virtual environment
	@uv -V
	uv python install
	uv sync
	@touch .venv

python: .venv ## Set up the Python virtual environment (alias)

help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "}; /^[a-zA-Z0-9_\/.-]+:.*## / {printf "\033[36m%-12s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

lint:
	uv run ruff check app/
	uv run ruff format --check app/
	uv run mypy app/
