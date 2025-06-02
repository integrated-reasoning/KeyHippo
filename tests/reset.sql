-- KeyHippo Database Reset Script for Vanilla PostgreSQL
BEGIN;

-- Drop test tables
DROP TABLE IF EXISTS public.test_accounts CASCADE;

-- Drop triggers first
DROP TRIGGER IF EXISTS keyhippo_assign_default_role_trigger ON auth.users;

-- Drop schemas (which will cascade to all contained objects)
DROP SCHEMA IF EXISTS keyhippo CASCADE;
DROP SCHEMA IF EXISTS keyhippo_internal CASCADE;
DROP SCHEMA IF EXISTS keyhippo_rbac CASCADE;
DROP SCHEMA IF EXISTS keyhippo_impersonation CASCADE;

-- Clean up any remaining functions that might be in public schema
DROP FUNCTION IF EXISTS public.keyhippo_authorize CASCADE;
DROP FUNCTION IF EXISTS public.keyhippo_current_user_context CASCADE;

-- Reset any configuration that might have been set
RESET ALL;

COMMIT;