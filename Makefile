# Directory paths
SRC_DIR := src
TEST_DIR := tests
BUILD_DIR := dist
PG_HOST := localhost
PG_PORT := 54322
PG_USER := postgres
PG_DB := postgres
PG_PASSWORD := postgres

# Default goal
.DEFAULT_GOAL := help

# Help target
.PHONY: help
help:
	@echo "Available targets:"
	@echo "  setup-supabase - Set up Supabase for testing"
	@echo "  test        - Run tests"
	@echo "  pg_tap      - Run pg_tap tests"

# Set up Supabase
.PHONY: setup-supabase
setup-supabase:
	@echo "Setting up Supabase..."
	@cd tests && \
		supabase start && \
		eval $$(supabase status -o env) && \
		echo "SUPABASE_URL=$$API_URL" > .env.test && \
		echo "SUPABASE_ANON_KEY=$$ANON_KEY" >> .env.test && \
		echo "SUPABASE_SERVICE_ROLE_KEY=$$SERVICE_ROLE_KEY" >> .env.test
	@echo "CREATE EXTENSION IF NOT EXISTS pgcrypto;" > create_schema.sql
	@echo "CREATE EXTENSION IF NOT EXISTS pgjwt;" >> create_schema.sql
	@echo "CREATE SCHEMA IF NOT EXISTS keyhippo;" >> create_schema.sql
	PGPASSWORD=$(PG_PASSWORD) psql -h $(PG_HOST) -p $(PG_PORT) -U $(PG_USER) -d $(PG_DB) -v ON_ERROR_STOP=1 -f create_schema.sql
	@for file in $$(find extension/ -type f -name "keyhippo*--*.sql" | sort -V); do \
		echo "Applying migration: $$file" ; \
		PGPASSWORD=$(PG_PASSWORD) psql -h $(PG_HOST) -p $(PG_PORT) -U $(PG_USER) -d $(PG_DB) -v ON_ERROR_STOP=1 -f "$$file"; \
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
	@echo "    USING ((COALESCE(auth.uid (), (SELECT user_id FROM keyhippo.current_user_context ())) = user_id));" >> create_test_accounts.sql
	@echo "" >> create_test_accounts.sql
	@echo "GRANT SELECT ON public.test_accounts TO anon, authenticated;" >> create_test_accounts.sql
	@echo "GRANT INSERT, UPDATE, DELETE ON public.test_accounts TO authenticated;" >> create_test_accounts.sql
	PGPASSWORD=$(PG_PASSWORD) psql -h $(PG_HOST) -p $(PG_PORT) -U $(PG_USER) -d $(PG_DB) -v ON_ERROR_STOP=1 -f create_test_accounts.sql

# Run pg_tap tests
.PHONY: pg_tap
pg_tap:
	@echo "Running pg_tap tests..."
	PGPASSWORD=$(PG_PASSWORD) psql -h $(PG_HOST) -p $(PG_PORT) -U $(PG_USER) -d $(PG_DB) -v ON_ERROR_STOP=1 -f $(TEST_DIR)/tests.sql

# Run benchmark
.PHONY: benchmark
benchmark:
	@echo "Running benchmark..."
	PGPASSWORD=$(PG_PASSWORD) psql -h $(PG_HOST) -p $(PG_PORT) -U $(PG_USER) -d $(PG_DB) -v ON_ERROR_STOP=1 -f $(TEST_DIR)/bench.sql

# Run tests with coverage (including Supabase setup and migrations)
.PHONY: test
test: setup-supabase apply-integration-test-migrations pg_tap
	@echo "Running tests..."
