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
