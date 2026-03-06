.DEFAULT_GOAL := help

.PHONY: help setup dev test format

help:          ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

setup:         ## Install all dependencies and configure the project
	brew bundle
	localias start
	mise install
	npm install
	lefthook install
	mix setup
	@echo ""
	@echo "If mise-managed tools are not active, add this to your shell config (~/.zshrc or ~/.bashrc):"
	@echo "  eval \"\$$(mise activate zsh)\"   # zsh"
	@echo "  eval \"\$$(mise activate bash)\"  # bash"
	@echo "Then open a new terminal or run: eval \"\$$(mise activate zsh)\""

dev:           ## Start the dev server
	mix phx.server

test:          ## Run the test suite
	mix test

format:        ## Format Elixir source files
	mix format
