-- KeyHippo Database Reset Script
-- Drop schemas
DROP TABLE IF EXISTS public.test_accounts CASCADE;

DROP SCHEMA IF EXISTS keyhippo CASCADE;

DROP SCHEMA IF EXISTS keyhippo_internal CASCADE;

DROP SCHEMA IF EXISTS keyhippo_rbac CASCADE;

DROP SCHEMA IF EXISTS keyhippo_impersonation CASCADE;

-- Drop custom types
DROP TYPE IF EXISTS keyhippo.app_permission CASCADE;

DROP TYPE IF EXISTS keyhippo.app_role CASCADE;

-- Delete all rows from auth.users
DELETE FROM auth.users;

-- Drop the trigger on auth.users
DROP TRIGGER IF EXISTS assign_default_role_trigger ON auth.users;

-- Notify PostgREST to reload configuration
NOTIFY pgrst,
'reload config';
