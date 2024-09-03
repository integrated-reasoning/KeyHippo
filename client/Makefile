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
	@echo "  setup-supabase - Set up Supabase for testing"
	@echo "  test        - Run tests with coverage (includes Supabase setup)"

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

# Set up Supabase
.PHONY: setup-supabase
setup-supabase:
	@echo "Setting up Supabase..."
	@cd tests && \
		pnpx supabase start && \
		eval $$(pnpx supabase status -o env) && \
		echo "SUPABASE_URL=$$API_URL" > ../.env.test && \
		echo "SUPABASE_ANON_KEY=$$ANON_KEY" >> ../.env.test
	@echo "CREATE EXTENSION IF NOT EXISTS pgcrypto;" > create_schema.sql
	@echo "CREATE EXTENSION IF NOT EXISTS pgjwt;" >> create_schema.sql
	@echo "CREATE SCHEMA IF NOT EXISTS keyhippo;" >> create_schema.sql
	PGPASSWORD=postgres psql -h localhost -p 54322 -U postgres -d postgres -f create_schema.sql
	@for file in $$(find ../extension/ -type f -name "keyhippo--*.sql" | sort -V); do \
		PGPASSWORD=postgres psql -h localhost -p 54322 -U postgres -d postgres -f "$$file"; \
	done

# Apply integration test migrations
.PHONY: apply-integration-test-migrations
apply-integration-test-migrations:
	@echo "Applying integration test migrations..."
	@echo "CREATE TABLE public.test_accounts (" > create_test_accounts.sql
	@echo "    id uuid PRIMARY KEY DEFAULT uuid_generate_v4 ()," >> create_test_accounts.sql
	@echo "    user_id uuid NOT NULL," >> create_test_accounts.sql
	@echo "    name text NOT NULL," >> create_test_accounts.sql
	@echo "    email text NOT NULL UNIQUE," >> create_test_accounts.sql
	@echo "    created_at timestamptz DEFAULT now()" >> create_test_accounts.sql
	@echo ");" >> create_test_accounts.sql
	@echo "" >> create_test_accounts.sql
	@echo "ALTER TABLE public.test_accounts ENABLE ROW LEVEL SECURITY;" >> create_test_accounts.sql
	@echo "" >> create_test_accounts.sql
	@echo "CREATE POLICY \"Users can access their own test account\" ON public.test_accounts TO anon, authenticated" >> create_test_accounts.sql
	@echo "    USING ((COALESCE(auth.uid (), keyhippo.key_uid ()) = user_id));" >> create_test_accounts.sql
	@echo "" >> create_test_accounts.sql
	@echo "GRANT SELECT ON public.test_accounts TO anon, authenticated;" >> create_test_accounts.sql
	@echo "GRANT INSERT, UPDATE, DELETE ON public.test_accounts TO authenticated;" >> create_test_accounts.sql

	PGPASSWORD=postgres psql -h localhost -p 54322 -U postgres -d postgres -f create_test_accounts.sql

# Run tests with coverage (including Supabase setup and migrations)
.PHONY: test
test: install setup-supabase apply-integration-test-migrations
	@echo "Running tests..."
	@if [ -f .env.test ]; then \
		export $$(cat .env.test | xargs) && pnpm run test --coverage; \
	else \
		echo "Error: .env.test file not found. Make sure setup-supabase completed successfully."; \
		exit 1; \
	fi
