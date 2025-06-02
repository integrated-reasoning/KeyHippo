# Directory paths
MIGRATIONS_DIR := migrations
TEST_DIR := tests
PG_HOST := localhost
PG_PORT := 5432
PG_USER := postgres
PG_DB := keyhippo
PG_PASSWORD := postgres

# Default goal
.DEFAULT_GOAL := help

# Help target
.PHONY: help
help:
	@echo "Available targets:"
	@echo "  setup      - Start PostgreSQL with Docker and apply migrations"
	@echo "  start      - Start PostgreSQL container"
	@echo "  stop       - Stop PostgreSQL container"
	@echo "  reset      - Reset database (drop and recreate)"
	@echo "  migrate    - Apply all migrations"
	@echo "  test       - Run tests"
	@echo "  benchmark  - Run benchmarks"
	@echo "  clean      - Stop containers and remove volumes"

# Start PostgreSQL container
.PHONY: start
start:
	@echo "Starting PostgreSQL..."
	docker-compose up -d postgres
	@echo "Waiting for PostgreSQL to be ready..."
	@until PGPASSWORD=$(PG_PASSWORD) psql -h $(PG_HOST) -p $(PG_PORT) -U $(PG_USER) -d $(PG_DB) -c '\q' 2>/dev/null; do \
		echo "PostgreSQL is unavailable - sleeping"; \
		sleep 2; \
	done
	@echo "PostgreSQL is ready!"

# Stop PostgreSQL container
.PHONY: stop
stop:
	@echo "Stopping PostgreSQL..."
	docker-compose down

# Clean up containers and volumes
.PHONY: clean
clean:
	@echo "Cleaning up..."
	docker-compose down -v
	docker-compose rm -f

# Apply all migrations
.PHONY: migrate
migrate:
	@echo "Applying migrations..."
	@for file in $$(find $(MIGRATIONS_DIR) -name "*.sql" | sort); do \
		echo "Applying migration: $$file"; \
		PGPASSWORD=$(PG_PASSWORD) psql -h $(PG_HOST) -p $(PG_PORT) -U $(PG_USER) -d $(PG_DB) -v ON_ERROR_STOP=1 -f "$$file"; \
	done
	@echo "Migrations completed!"

# Reset database
.PHONY: reset
reset:
	@echo "Resetting database..."
	PGPASSWORD=$(PG_PASSWORD) psql -h $(PG_HOST) -p $(PG_PORT) -U $(PG_USER) -d $(PG_DB) -v ON_ERROR_STOP=1 -f $(TEST_DIR)/reset.sql

# Set up everything (start + migrate)
.PHONY: setup
setup: start migrate
	@echo "Setup completed!"

# Apply integration test migrations
.PHONY: apply-test-migrations
apply-test-migrations:
	@echo "Applying integration test migrations..."
	@echo "CREATE TABLE IF NOT EXISTS public.test_accounts (" > create_test_accounts.sql
	@echo "    id uuid PRIMARY KEY DEFAULT gen_random_uuid()," >> create_test_accounts.sql
	@echo "    user_id uuid NOT NULL," >> create_test_accounts.sql
	@echo "    name text NOT NULL," >> create_test_accounts.sql
	@echo "    email text NOT NULL UNIQUE," >> create_test_accounts.sql
	@echo "    created_at timestamptz DEFAULT now()" >> create_test_accounts.sql
	@echo ");" >> create_test_accounts.sql
	@echo "" >> create_test_accounts.sql
	@echo "GRANT SELECT ON public.test_accounts TO authenticated;" >> create_test_accounts.sql
	@echo "GRANT INSERT, UPDATE, DELETE ON public.test_accounts TO authenticated;" >> create_test_accounts.sql
	PGPASSWORD=$(PG_PASSWORD) psql -h $(PG_HOST) -p $(PG_PORT) -U $(PG_USER) -d $(PG_DB) -v ON_ERROR_STOP=1 -f create_test_accounts.sql
	@rm -f create_test_accounts.sql

# Run tests
.PHONY: test
test: setup apply-test-migrations
	@echo "Running tests..."
	PGPASSWORD=$(PG_PASSWORD) psql -h $(PG_HOST) -p $(PG_PORT) -U $(PG_USER) -d $(PG_DB) -v ON_ERROR_STOP=1 -f $(TEST_DIR)/tests.sql

# Run benchmark
.PHONY: benchmark
benchmark: setup
	@echo "Running benchmark..."
	PGPASSWORD=$(PG_PASSWORD) psql -h $(PG_HOST) -p $(PG_PORT) -U $(PG_USER) -d $(PG_DB) -v ON_ERROR_STOP=1 -f $(TEST_DIR)/bench.sql

# Check database status
.PHONY: status
status:
	@echo "Database status:"
	@PGPASSWORD=$(PG_PASSWORD) psql -h $(PG_HOST) -p $(PG_PORT) -U $(PG_USER) -d $(PG_DB) -c "SELECT version();" 2>/dev/null && echo "✓ Database is accessible" || echo "✗ Database is not accessible"

# Connect to database
.PHONY: psql
psql:
	PGPASSWORD=$(PG_PASSWORD) psql -h $(PG_HOST) -p $(PG_PORT) -U $(PG_USER) -d $(PG_DB)

# Show logs
.PHONY: logs
logs:
	docker-compose logs -f postgres

# Restart everything
.PHONY: restart
restart: stop start migrate