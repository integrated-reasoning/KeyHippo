# Directory paths
SRC_DIR := src
TEST_DIR := tests
BUILD_DIR := dist

# Default goal
.DEFAULT_GOAL := help

# Help target
.PHONY: help
help:
	@echo "Available targets:"
	@echo "  clean       - Clean up project directories"
	@echo "  install     - Install dependencies using pnpm"
	@echo "  build       - Build the TypeScript project"
	@echo "  test        - Run tests with coverage"

# Clean target
.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)
	rm -f tsconfig.tsbuildinfo
	pnpm store prune

# Install dependencies
.PHONY: install
install:
	pnpm install

# Build the project
.PHONY: build
build: install
	pnpm run build

# Run tests with coverage
.PHONY: test
test: install
	pnpm run test --coverage

# Set up Supabase
.PHONY: setup-supabase
setup-supabase:
	@echo "Setting up Supabase..."
	@pnpx supabase start
	@eval $$(pnpx supabase status -o env); \
	echo "SUPABASE_URL=$$API_URL" > .env.test; \
	echo "SUPABASE_ANON_KEY=$$ANON_KEY" >> .env.test; \
	echo "CREATE EXTENSION IF NOT EXISTS pgcrypto;" > create_schema.sql; \
	echo "CREATE EXTENSION IF NOT EXISTS pgjwt;" >> create_schema.sql; \
	echo "CREATE SCHEMA IF NOT EXISTS keyhippo;" >> create_schema.sql; \

# Run tests locally
.PHONY: local-test
test: install setup-supabase
	@echo "Running tests..."
	@if [ -f .env.test ]; then \
		export $$(cat .env.test | xargs) && pnpm run test --coverage; \
	else \
		echo "Error: .env.test file not found. Make sure setup-supabase completed successfully."; \
		exit 1; \
	fi
