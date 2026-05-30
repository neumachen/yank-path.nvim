.PHONY: test lint format check install-deps clean help

# Default target
help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

test: ## Run tests
	@echo "Running tests..."
	nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua', sequential = true}"

lint: ## Run luacheck linter
	@echo "Running luacheck..."
	luacheck lua/ tests/ --config .luacheckrc

format: ## Format code with stylua
	@echo "Formatting code with stylua..."
	stylua lua/ tests/ --config-path stylua.toml

format-check: ## Check if code is formatted correctly
	@echo "Checking code formatting..."
	stylua --check lua/ tests/ --config-path stylua.toml

check: lint format-check test ## Run all checks (lint, format-check, test)

install-deps: ## Install development dependencies
	@echo "Installing development dependencies..."
	@echo "Please install the following tools manually:"
	@echo "  - luacheck: luarocks install luacheck"
	@echo "  - stylua: cargo install stylua"
	@echo "  - plenary.nvim: Install via your plugin manager"

clean: ## Clean temporary files
	@echo "Cleaning temporary files..."
	find . -name "*.tmp" -delete
	find . -name ".DS_Store" -delete

# Development workflow targets
dev-setup: install-deps ## Set up development environment
	@echo "Development environment setup complete!"
	@echo "Run 'make check' to verify everything works."

ci: check ## Run CI checks (same as check)

watch-test: ## Watch for changes and run tests (requires entr)
	@echo "Watching for changes... (requires 'entr' to be installed)"
	find lua tests -name "*.lua" | entr -c make test
