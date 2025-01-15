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

-- Drop the trigger on auth.users
DROP TRIGGER IF EXISTS assign_default_role_trigger ON auth.users;

-- Notify PostgREST to reload configuration
NOTIFY pgrst,
'reload config';
