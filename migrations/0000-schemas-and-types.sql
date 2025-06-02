BEGIN;

-- Create KeyHippo schemas
CREATE SCHEMA IF NOT EXISTS keyhippo;
CREATE SCHEMA IF NOT EXISTS keyhippo_internal;
CREATE SCHEMA IF NOT EXISTS keyhippo_rbac;
CREATE SCHEMA IF NOT EXISTS keyhippo_impersonation;

-- Ensure required extensions are installed
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Try to create pg_net extension if available (optional for HTTP functionality)
DO $$
BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_net;
    RAISE NOTICE 'pg_net extension loaded - HTTP notifications will be available';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'pg_net extension not available - HTTP notifications will be disabled';
END $$;

-- Try to create pg_cron extension if available (optional for scheduled tasks)
DO $$
BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_cron;
    RAISE NOTICE 'pg_cron extension loaded - scheduled tasks will be available';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'pg_cron extension not available - scheduled tasks will be disabled';
END $$;

-- Create custom types (drop and recreate to handle changes)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'app_permission') THEN
        CREATE TYPE keyhippo.app_permission AS ENUM (
            'manage_groups',
            'manage_roles',
            'manage_permissions',
            'manage_scopes',
            'manage_user_attributes',
            'manage_api_keys'
        );
    END IF;
END$$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'app_role') THEN
        CREATE TYPE keyhippo.app_role AS ENUM (
            'admin',
            'user'
        );
    END IF;
END$$;

COMMIT;