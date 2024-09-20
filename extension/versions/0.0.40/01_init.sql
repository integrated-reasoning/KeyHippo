-- 01_init.sql
-- Create the necessary schemas
CREATE SCHEMA IF NOT EXISTS keyhippo;

CREATE SCHEMA IF NOT EXISTS keyhippo_internal;

-- Ensure required extensions are installed
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE EXTENSION IF NOT EXISTS pgjwt;

-- Function to set up project_api_key_secret
CREATE OR REPLACE FUNCTION keyhippo.setup_project_api_key_secret ()
    RETURNS VOID
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    secret_exists boolean;
BEGIN
    SELECT
        EXISTS (
            SELECT
                1
            FROM
                vault.secrets
            WHERE
                name = 'project_api_key_secret') INTO secret_exists;
    IF NOT secret_exists THEN
        INSERT INTO vault.secrets (secret, name)
            VALUES (encode(extensions.digest(extensions.gen_random_bytes(32), 'sha512'), 'hex'), 'project_api_key_secret');
        RAISE LOG '[KeyHippo] Created project_api_key_secret in vault.secrets';
    ELSE
        RAISE LOG '[KeyHippo] project_api_key_secret already exists in vault.secrets';
    END IF;
END;
$$;

-- Function to set up project JWT secret
CREATE OR REPLACE FUNCTION keyhippo.setup_project_jwt_secret ()
    RETURNS VOID
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    secret_exists boolean;
BEGIN
    SELECT
        EXISTS (
            SELECT
                1
            FROM
                vault.secrets
            WHERE
                name = 'project_jwt_secret') INTO secret_exists;
    IF NOT secret_exists THEN
        INSERT INTO vault.secrets (secret, name)
            VALUES (encode(extensions.digest(extensions.gen_random_bytes(32), 'sha256'), 'hex'), 'project_jwt_secret');
        RAISE LOG '[KeyHippo] Created project_jwt_secret in vault.secrets';
    ELSE
        RAISE LOG '[KeyHippo] project_jwt_secret already exists in vault.secrets';
    END IF;
END;
$$;

-- Function to set up both secrets
CREATE OR REPLACE FUNCTION keyhippo.setup_vault_secrets ()
    RETURNS VOID
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
BEGIN
    PERFORM
        keyhippo.setup_project_api_key_secret ();
    PERFORM
        keyhippo.setup_project_jwt_secret ();
    RAISE LOG '[KeyHippo] KeyHippo vault secrets setup complete';
END;
$$;

-- Execute the setup function
SELECT
    keyhippo.setup_vault_secrets ();

-- Cleanup setup functions
DROP FUNCTION keyhippo.setup_vault_secrets ();

DROP FUNCTION keyhippo.setup_project_jwt_secret ();

DROP FUNCTION keyhippo.setup_project_api_key_secret ();
