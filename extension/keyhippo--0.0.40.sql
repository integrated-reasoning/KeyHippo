/*
 * Copyright (c) 2024 Integrated Reasoning, Inc.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 *
 * ██╗  ██╗███████╗██╗   ██╗██╗  ██╗██╗██████╗ ██████╗  ██████╗
 * ██║ ██╔╝██╔════╝╚██╗ ██╔╝██║  ██║██║██╔══██╗██╔══██╗██╔═══██╗
 * █████╔╝ █████╗   ╚████╔╝ ███████║██║██████╔╝██████╔╝██║   ██║
 * ██╔═██╗ ██╔══╝    ╚██╔╝  ██╔══██║██║██╔═══╝ ██╔═══╝ ██║   ██║
 * ██║  ██╗███████╗   ██║   ██║  ██║██║██║     ██║     ╚██████╔╝
 * ╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝     ╚═╝      ╚═════╝
 */
-- Create the necessary schemas
CREATE SCHEMA IF NOT EXISTS keyhippo;

CREATE SCHEMA IF NOT EXISTS keyhippo_internal;

-- Ensure required extensions are installed
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE EXTENSION IF NOT EXISTS pgjwt;

-- Create required tables in the auth and keyhippo schemas
CREATE TABLE IF NOT EXISTS auth.jwts (
    secret_id uuid PRIMARY KEY,
    user_id uuid,
    CONSTRAINT jwts_secret_id_fkey FOREIGN KEY (secret_id) REFERENCES vault.secrets (id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS keyhippo.user_ids (
    id uuid PRIMARY KEY
);

CREATE TABLE IF NOT EXISTS keyhippo.api_key_id_owner_id (
    api_key_id uuid PRIMARY KEY,
    user_id uuid NOT NULL,
    owner_id uuid,
    CONSTRAINT api_key_id_owner_id_user_id_fkey FOREIGN KEY (user_id) REFERENCES keyhippo.user_ids (id) ON DELETE CASCADE,
    CONSTRAINT api_key_id_owner_id_api_key_id_owner_id_key UNIQUE (api_key_id, owner_id)
);

-- Additional tables with appropriate foreign key constraints
CREATE TABLE IF NOT EXISTS keyhippo.api_key_id_name (
    api_key_id uuid PRIMARY KEY,
    name text NOT NULL,
    owner_id uuid,
    CONSTRAINT api_key_id_name_api_key_id_fkey FOREIGN KEY (api_key_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id) ON DELETE CASCADE,
    CONSTRAINT api_key_id_name_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id, owner_id)
);

CREATE TABLE IF NOT EXISTS keyhippo.api_key_id_permission (
    api_key_id uuid PRIMARY KEY,
    permission text NOT NULL,
    owner_id uuid,
    CONSTRAINT api_key_id_permission_api_key_id_fkey FOREIGN KEY (api_key_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id) ON DELETE CASCADE,
    CONSTRAINT api_key_id_permission_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id, owner_id)
);

CREATE TABLE IF NOT EXISTS keyhippo.api_key_id_created (
    api_key_id uuid PRIMARY KEY,
    created timestamptz NOT NULL,
    owner_id uuid,
    CONSTRAINT api_key_id_created_api_key_id_fkey FOREIGN KEY (api_key_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id) ON DELETE CASCADE,
    CONSTRAINT api_key_id_created_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id, owner_id)
);

CREATE TABLE IF NOT EXISTS keyhippo.api_key_id_last_used (
    api_key_id uuid PRIMARY KEY,
    last_used timestamptz,
    owner_id uuid,
    CONSTRAINT api_key_id_last_used_api_key_id_fkey FOREIGN KEY (api_key_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id) ON DELETE CASCADE,
    CONSTRAINT api_key_id_last_used_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id, owner_id)
);

CREATE TABLE IF NOT EXISTS keyhippo.api_key_id_total_use (
    api_key_id uuid PRIMARY KEY,
    total_uses bigint DEFAULT 0 NOT NULL,
    owner_id uuid,
    CONSTRAINT api_key_id_total_use_api_key_id_fkey FOREIGN KEY (api_key_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id) ON DELETE CASCADE,
    CONSTRAINT api_key_id_total_use_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id, owner_id)
);

CREATE TABLE IF NOT EXISTS keyhippo.api_key_id_success_rate (
    api_key_id uuid PRIMARY KEY,
    success_rate numeric(5, 2) NOT NULL,
    owner_id uuid,
    CONSTRAINT api_key_id_success_rate_api_key_id_fkey FOREIGN KEY (api_key_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id) ON DELETE CASCADE,
    CONSTRAINT api_key_id_success_rate_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id, owner_id),
    CONSTRAINT api_key_reference_success_rate_success_rate_check CHECK ((success_rate >= 0 AND success_rate <= 100))
);

CREATE TABLE IF NOT EXISTS keyhippo.api_key_id_total_cost (
    api_key_id uuid PRIMARY KEY,
    total_cost numeric(12, 2) DEFAULT 0 NOT NULL,
    owner_id uuid,
    CONSTRAINT api_key_id_total_cost_api_key_id_fkey FOREIGN KEY (api_key_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id) ON DELETE CASCADE,
    CONSTRAINT api_key_id_total_cost_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id, owner_id)
);

CREATE TABLE IF NOT EXISTS keyhippo.api_key_id_revoked (
    api_key_id uuid PRIMARY KEY,
    revoked_at timestamptz DEFAULT now() NOT NULL,
    owner_id uuid,
    CONSTRAINT api_key_id_revoked_api_key_id_fkey FOREIGN KEY (api_key_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id) ON DELETE CASCADE,
    CONSTRAINT api_key_id_revoked_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id, owner_id)
);

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
    -- Check if the secret already exists
    SELECT
        EXISTS (
            SELECT
                1
            FROM
                vault.secrets
            WHERE
                name = 'project_api_key_secret') INTO secret_exists;
    -- If the secret doesn't exist, create it
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
    -- Check if the secret already exists
    SELECT
        EXISTS (
            SELECT
                1
            FROM
                vault.secrets
            WHERE
                name = 'project_jwt_secret') INTO secret_exists;
    -- If the secret doesn't exist, create it
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

-- Function to load API key info
CREATE OR REPLACE FUNCTION keyhippo.load_api_key_info (id_of_user text)
    RETURNS jsonb
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = extensions, pg_temp
    AS $$
DECLARE
    key_info jsonb := '[]'::jsonb;
    jwt_record RECORD;
    vault_record RECORD;
    jwt_count int;
BEGIN
    RAISE LOG '[KeyHippo] Starting load_api_key_info for user: %', id_of_user;
    -- Check if the function is being executed as the correct user
    IF auth.uid () != id_of_user::uuid THEN
        RAISE LOG '[KeyHippo] Unauthorized access attempt for user: %. Current auth.uid(): %', id_of_user, auth.uid ();
        RETURN NULL;
    END IF;
    -- Log the number of JWT records found
    SELECT
        COUNT(*) INTO jwt_count
    FROM
        auth.jwts
    WHERE
        user_id = id_of_user::uuid;
    RAISE LOG '[KeyHippo] Found % JWT records for user: %', jwt_count, id_of_user;
    FOR jwt_record IN
    SELECT
        secret_id
    FROM
        auth.jwts
    WHERE
        user_id = id_of_user::uuid LOOP
            RAISE LOG '[KeyHippo] Processing secret_id: %', jwt_record.secret_id;
            BEGIN
                SELECT
                    description INTO STRICT vault_record
                FROM
                    vault.decrypted_secrets
                WHERE
                    id = jwt_record.secret_id;
                RAISE LOG '[KeyHippo] Found description: %', vault_record.description;
                key_info := key_info || jsonb_build_object('id', jwt_record.secret_id, 'description', vault_record.description);
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    RAISE LOG '[KeyHippo] No data found in vault.decrypted_secrets for secret_id: %', jwt_record.secret_id;
                WHEN OTHERS THEN
                    RAISE LOG '[KeyHippo] Error processing secret_id %: %', jwt_record.secret_id, SQLERRM;
            END;
    END LOOP;
    RAISE LOG '[KeyHippo] Completed load_api_key_info. Total keys: %', jsonb_array_length(key_info);
    RETURN key_info;
END
$$;

-- Function to create and store an API key
CREATE OR REPLACE FUNCTION keyhippo.create_api_key (id_of_user text, key_description text)
    RETURNS text
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    api_key text;
    expires bigint;
    jti uuid := extensions.gen_random_uuid ();
    jwt text;
    jwt_body jsonb;
    project_hash text;
    project_jwt_secret text;
    project_api_key_secret text;
    secret_uuid uuid;
    time_stamp bigint;
    user_api_key_secret text;
BEGIN
    -- Ensure the user is authorized
    IF auth.uid () IS NULL OR auth.uid () != id_of_user::uuid THEN
        RAISE EXCEPTION '[KeyHippo] Unauthorized: Invalid user ID';
    END IF;
    -- Ensure the user exists in the user_ids table
    INSERT INTO keyhippo.user_ids (id)
        VALUES (id_of_user::uuid)
    ON CONFLICT (id)
        DO NOTHING;
    -- Get current timestamp
    SELECT
        EXTRACT(EPOCH FROM now())::bigint INTO time_stamp;
    -- Calculate expiration time
    SELECT
        (time_stamp + EXTRACT(EPOCH FROM INTERVAL '100 years')::bigint) INTO expires;
    -- Build JWT body
    jwt_body := jsonb_build_object('role', 'authenticated', 'aud', 'authenticated', 'iss', 'supabase', 'sub', to_jsonb (id_of_user), 'iat', to_jsonb (time_stamp), 'exp', to_jsonb (expires), 'jti', to_jsonb (jti));
    -- Retrieve user API key secret
    SELECT
        decrypted_secret INTO user_api_key_secret
    FROM
        vault.decrypted_secrets
    WHERE
        name = id_of_user;
    -- Retrieve project API key secret
    SELECT
        decrypted_secret INTO project_api_key_secret
    FROM
        vault.decrypted_secrets
    WHERE
        name = 'project_api_key_secret';
    -- Retrieve project JWT secret
    SELECT
        decrypted_secret INTO project_jwt_secret
    FROM
        vault.decrypted_secrets
    WHERE
        name = 'project_jwt_secret';
    -- Generate JWT
    SELECT
        extensions.sign(jwt_body::json, project_jwt_secret) INTO jwt;
    -- Generate API key and project hash
    api_key := encode(extensions.hmac(jwt, user_api_key_secret, 'sha512'), 'hex');
    project_hash := encode(extensions.hmac(api_key, project_api_key_secret, 'sha512'), 'hex');
    -- Insert the generated secrets into the vault
    INSERT INTO vault.secrets (secret, name, description)
        VALUES (jwt, project_hash, key_description)
    RETURNING
        id INTO secret_uuid;
    -- Insert the JWT and related data into the auth tables
    INSERT INTO auth.jwts (secret_id, user_id)
        VALUES (secret_uuid, id_of_user::uuid);
    -- Insert the API key metadata into keyhippo tables
    INSERT INTO keyhippo.api_key_id_owner_id (api_key_id, user_id, owner_id)
        VALUES (secret_uuid, id_of_user::uuid, id_of_user::uuid);
    INSERT INTO keyhippo.api_key_id_name (api_key_id, name, owner_id)
        VALUES (secret_uuid, key_description, id_of_user::uuid);
    INSERT INTO keyhippo.api_key_id_permission (api_key_id, permission, owner_id)
        VALUES (secret_uuid, 'readOnly', id_of_user::uuid);
    INSERT INTO keyhippo.api_key_id_created (api_key_id, created, owner_id)
        VALUES (secret_uuid, now(), id_of_user::uuid);
    -- Initialize other tables with default values
    INSERT INTO keyhippo.api_key_id_total_use (api_key_id, total_uses, owner_id)
        VALUES (secret_uuid, 0, id_of_user::uuid);
    INSERT INTO keyhippo.api_key_id_success_rate (api_key_id, success_rate, owner_id)
        VALUES (secret_uuid, 100.00, id_of_user::uuid);
    INSERT INTO keyhippo.api_key_id_total_cost (api_key_id, total_cost, owner_id)
        VALUES (secret_uuid, 0.00, id_of_user::uuid);
    -- Return the generated API key
    RETURN api_key;
END;
$$;

-- Internal function to get secret UUID for API key
CREATE OR REPLACE FUNCTION keyhippo_internal._get_secret_uuid_for_api_key (user_api_key text)
    RETURNS uuid
    LANGUAGE plpgsql
    STRICT
    SECURITY DEFINER
    SET search_path = extensions, vault, keyhippo, keyhippo_internal, pg_temp
    AS $$
DECLARE
    project_api_key_secret text;
    project_hash text;
    secret_uuid uuid;
BEGIN
    SELECT
        decrypted_secret INTO project_api_key_secret
    FROM
        vault.decrypted_secrets
    WHERE
        name = 'project_api_key_secret';
    project_hash := encode(extensions.hmac(user_api_key, project_api_key_secret, 'sha512'), 'hex');
    SELECT
        id INTO secret_uuid
    FROM
        vault.secrets
    WHERE
        name = project_hash;
    RETURN secret_uuid;
END;
$$;

-- Set permissions for the internal function
REVOKE ALL ON FUNCTION keyhippo_internal._get_secret_uuid_for_api_key (text) FROM PUBLIC;

-- Function to validate API key
CREATE OR REPLACE FUNCTION keyhippo.key_uid ()
    RETURNS uuid
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = keyhippo, keyhippo_internal, pg_temp
    AS $$
DECLARE
    user_api_key text;
    secret_uuid uuid;
    result_user_id uuid;
BEGIN
    SELECT
        current_setting('request.headers', TRUE)::json ->> 'x-kh-api-key' INTO user_api_key;
    secret_uuid := keyhippo_internal._get_secret_uuid_for_api_key (user_api_key);
    IF secret_uuid IS NOT NULL THEN
        SELECT
            user_id INTO result_user_id
        FROM
            auth.jwts
        WHERE
            secret_id = secret_uuid;
    END IF;
    RETURN result_user_id;
END;
$$;

-- Function to revoke API key
CREATE OR REPLACE FUNCTION keyhippo.revoke_api_key (id_of_user text, secret_id text)
    RETURNS VOID
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    owner_id uuid;
BEGIN
    IF auth.uid () = id_of_user::uuid THEN
        -- Get the owner_id
        SELECT
            user_id INTO owner_id
        FROM
            keyhippo.api_key_id_owner_id
        WHERE
            api_key_id = secret_id::uuid;
        -- Check if the api_key_id exists in api_key_id_owner_id
        IF NOT FOUND THEN
            RAISE EXCEPTION '[KeyHippo] API key not found: %', secret_id;
        END IF;
        -- Insert into api_key_id_revoked table
        INSERT INTO keyhippo.api_key_id_revoked (api_key_id, owner_id)
            VALUES (secret_id::uuid, owner_id);
        -- Delete from vault.secrets
        DELETE FROM vault.secrets
        WHERE id = secret_id::uuid;
    ELSE
        RAISE EXCEPTION '[KeyHippo] Unauthorized: Invalid user ID';
    END IF;
END;
$$;

-- Function to get API key metadata
CREATE OR REPLACE FUNCTION keyhippo.get_api_key_metadata (id_of_user uuid)
    RETURNS TABLE (
        api_key_id uuid,
        name text,
        permission text,
        last_used timestamptz,
        created timestamptz,
        total_uses bigint,
        success_rate double precision,
        total_cost double precision,
        revoked timestamptz)
    LANGUAGE plpgsql
    SECURITY INVOKER
    SET search_path = pg_temp
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        u.api_key_id,
        n.name,
        p.permission,
        l.last_used,
        c.created,
        COALESCE(t.total_uses, 0) AS total_uses,
        COALESCE(s.success_rate, 0.0)::double precision AS success_rate,
        COALESCE(tc.total_cost, 0.0)::double precision AS total_cost,
        r.revoked_at AS revoked
    FROM
        keyhippo.api_key_id_owner_id u
    LEFT JOIN keyhippo.api_key_id_name n ON u.api_key_id = n.api_key_id
    LEFT JOIN keyhippo.api_key_id_permission p ON u.api_key_id = p.api_key_id
    LEFT JOIN keyhippo.api_key_id_last_used l ON u.api_key_id = l.api_key_id
    LEFT JOIN keyhippo.api_key_id_created c ON u.api_key_id = c.api_key_id
    LEFT JOIN keyhippo.api_key_id_total_use t ON u.api_key_id = t.api_key_id
    LEFT JOIN keyhippo.api_key_id_success_rate s ON u.api_key_id = s.api_key_id
    LEFT JOIN keyhippo.api_key_id_total_cost tc ON u.api_key_id = tc.api_key_id
    LEFT JOIN keyhippo.api_key_id_revoked r ON u.api_key_id = r.api_key_id
WHERE
    u.user_id = id_of_user;
END;
$$;

-- Helper function for RLS
CREATE OR REPLACE FUNCTION auth.keyhippo_check (owner_id uuid)
    RETURNS boolean
    LANGUAGE sql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
    SELECT
        (auth.uid () = owner_id)
        OR (keyhippo.key_uid () = owner_id);
$$;

-- Function to get user ID from API key
CREATE OR REPLACE FUNCTION keyhippo.get_uid_for_key (user_api_key text)
    RETURNS uuid
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = keyhippo, keyhippo_internal, pg_temp
    AS $$
DECLARE
    secret_uuid uuid;
    result_user_id uuid;
BEGIN
    secret_uuid := keyhippo_internal._get_secret_uuid_for_api_key (user_api_key);
    IF secret_uuid IS NOT NULL THEN
        SELECT
            user_id INTO result_user_id
        FROM
            auth.jwts
        WHERE
            secret_id = secret_uuid;
    END IF;
    RETURN result_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION keyhippo.check_request ()
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    req_app_api_key text := current_setting('request.headers', TRUE)::json ->> 'x-app-api-key';
    result_user_id uuid;
BEGIN
    IF CURRENT_ROLE <> 'anon' THEN
        -- If not using the anon role, allow the request to pass
        RETURN;
    END IF;
    -- Check if the provided API key is valid
    result_user_id := keyhippo.get_uid_for_key (req_app_api_key);
    IF result_user_id IS NULL THEN
        -- No valid API key found, raise an error
        RAISE EXCEPTION 'No registered API key found in x-app-api-key header.';
    END IF;
END;
$$;

ALTER ROLE authenticator SET pgrst.db_pre_request = 'keyhippo.check_request';

-- Enable Row Level Security on all tables
ALTER TABLE keyhippo.api_key_id_created ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo.api_key_id_last_used ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo.api_key_id_name ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo.api_key_id_owner_id ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo.api_key_id_permission ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo.api_key_id_revoked ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo.api_key_id_success_rate ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo.api_key_id_total_cost ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo.api_key_id_total_use ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo.user_ids ENABLE ROW LEVEL SECURITY;

-- Create RLS policies for each table
CREATE POLICY "select_policy_api_key_id_created" ON keyhippo.api_key_id_created
    USING (auth.uid () = owner_id);

CREATE POLICY "select_policy_api_key_id_last_used" ON keyhippo.api_key_id_last_used
    USING (auth.uid () = owner_id);

CREATE POLICY "select_policy_api_key_id_name" ON keyhippo.api_key_id_name
    USING (auth.uid () = owner_id);

CREATE POLICY "select_policy_api_key_id_owner_id" ON keyhippo.api_key_id_owner_id
    USING (auth.uid () = owner_id);

CREATE POLICY "select_policy_api_key_id_permission" ON keyhippo.api_key_id_permission
    USING (auth.uid () = owner_id);

CREATE POLICY "select_policy_api_key_id_revoked" ON keyhippo.api_key_id_revoked
    USING (auth.uid () = owner_id);

CREATE POLICY "select_policy_api_key_id_success_rate" ON keyhippo.api_key_id_success_rate
    USING (auth.uid () = owner_id);

CREATE POLICY "select_policy_api_key_id_total_cost" ON keyhippo.api_key_id_total_cost
    USING (auth.uid () = owner_id);

CREATE POLICY "select_policy_api_key_id_total_use" ON keyhippo.api_key_id_total_use
    USING (auth.uid () = owner_id);

-- Create triggers for user management
CREATE OR REPLACE FUNCTION keyhippo.handle_new_user ()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
BEGIN
    INSERT INTO keyhippo.user_ids (id)
        VALUES (NEW.id);
    RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION keyhippo.handle_new_user ();

CREATE OR REPLACE FUNCTION keyhippo.create_user_api_key_secret ()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = extensions, pg_temp
    AS $$
DECLARE
    rand_bytes bytea := extensions.gen_random_bytes(32);
    user_api_key_secret text := encode(extensions.digest(rand_bytes, 'sha512'), 'hex');
BEGIN
    INSERT INTO vault.secrets (secret, name)
        VALUES (user_api_key_secret, NEW.id);
    RETURN NEW;
END;
$$;

CREATE TRIGGER on_user_created__create_user_api_key_secret
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION keyhippo.create_user_api_key_secret ();

CREATE OR REPLACE FUNCTION keyhippo.remove_user_vault_secrets ()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = keyhippo, pg_temp
    AS $$
DECLARE
    jwt_record RECORD;
BEGIN
    DELETE FROM vault.secrets
    WHERE name = OLD.id::text;
    FOR jwt_record IN
    SELECT
        secret_id
    FROM
        auth.jwts
    WHERE
        user_id = OLD.id LOOP
            DELETE FROM vault.secrets
            WHERE id = jwt_record.secret_id;
        END LOOP;
    RETURN OLD;
END;
$$;

CREATE TRIGGER on_auth_user_deleted
    AFTER DELETE ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION keyhippo.remove_user_vault_secrets ();

-- Create additional utility functions
CREATE OR REPLACE FUNCTION keyhippo.get_api_key (id_of_user text, secret_id text)
    RETURNS text
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = extensions, pg_temp
    AS $$
DECLARE
    jwt text;
    key TEXT;
    user_api_key_secret text;
BEGIN
    IF auth.uid () = id_of_user::uuid THEN
        SELECT
            decrypted_secret INTO user_api_key_secret
        FROM
            vault.decrypted_secrets
        WHERE
            name = id_of_user;
        SELECT
            decrypted_secret INTO jwt
        FROM
            vault.decrypted_secrets
        WHERE
            id = secret_id::uuid;
        key := encode(extensions.hmac(jwt, user_api_key_secret, 'sha512'), 'hex');
    END IF;
    RETURN key;
END;
$$;

-- Grant necessary permissions
GRANT ALL ON FUNCTION keyhippo.create_api_key (TEXT, TEXT) TO authenticated;

GRANT ALL ON FUNCTION keyhippo.get_api_key (TEXT, TEXT) TO authenticated;

GRANT ALL ON FUNCTION keyhippo.get_api_key_metadata (UUID) TO authenticated;

GRANT ALL ON FUNCTION keyhippo.check_request () TO authenticated, service_role, anon;

GRANT ALL ON FUNCTION keyhippo.key_uid () TO authenticated, service_role, anon;

GRANT ALL ON FUNCTION keyhippo.get_uid_for_key (TEXT) TO authenticated, service_role, anon;

GRANT ALL ON FUNCTION keyhippo.load_api_key_info (TEXT) TO authenticated, service_role, anon;

GRANT ALL ON FUNCTION keyhippo.revoke_api_key (TEXT, TEXT) TO authenticated;

GRANT SELECT ON ALL TABLES IN SCHEMA keyhippo TO authenticated;

GRANT SELECT ON auth.jwts TO authenticated, service_role;

GRANT USAGE ON SCHEMA keyhippo TO authenticated, service_role, anon;

-- Set up vault secrets
SELECT
    keyhippo.setup_vault_secrets ();

-- Cleanup setup functions
DROP FUNCTION keyhippo.setup_vault_secrets ();

DROP FUNCTION keyhippo.setup_project_jwt_secret ();

DROP FUNCTION keyhippo.setup_project_api_key_secret ();

-- Create temporary schema
CREATE SCHEMA IF NOT EXISTS keyhippo_temp;

-- 1. Create temporary function to handle existing users
CREATE OR REPLACE FUNCTION keyhippo_temp.handle_existing_users ()
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = extensions, pg_temp
    AS $$
DECLARE
    user_record RECORD;
BEGIN
    FOR user_record IN
    SELECT
        id
    FROM
        auth.users LOOP
            -- Insert into keyhippo.user_ids if not exists
            INSERT INTO keyhippo.user_ids (id)
                VALUES (user_record.id)
            ON CONFLICT (id)
                DO NOTHING;
            -- Create user API key secret if not exists
            IF NOT EXISTS (
                SELECT
                    1
                FROM
                    vault.secrets
                WHERE
                    name = user_record.id::text) THEN
            INSERT INTO vault.secrets (secret, name)
                VALUES (encode(digest(gen_random_bytes(32), 'sha512'), 'hex'), user_record.id::text);
        END IF;
END LOOP;
END;
$$;

-- 2. Execute the function to handle existing users
SELECT
    keyhippo_temp.handle_existing_users ();

-- 3. Create a function to update policies with elevated privileges
CREATE OR REPLACE FUNCTION keyhippo_temp.update_policies ()
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = keyhippo, pg_temp
    AS $$
DECLARE
    tbl_name text;
BEGIN
    FOR tbl_name IN
    SELECT
        table_name
    FROM
        information_schema.tables
    WHERE
        table_schema = 'keyhippo'
        AND table_name LIKE 'api_key_id_%' LOOP
            EXECUTE format('
            DROP POLICY IF EXISTS "select_policy_%1$s" ON keyhippo.%1$I;
            CREATE POLICY "select_policy_%1$s" ON keyhippo.%1$I
                FOR SELECT TO anon, authenticated
                USING ((SELECT auth.uid() = owner_id) OR
                    (SELECT keyhippo.key_uid() = owner_id)
                );
            GRANT SELECT ON TABLE keyhippo.%1$I TO anon, authenticated;
        ', tbl_name);
        END LOOP;
END;
$$;

-- 4. Execute the policy update function
SELECT
    keyhippo_temp.update_policies ();

-- 5. Drop all temporary functions
DROP FUNCTION IF EXISTS keyhippo_temp.handle_existing_users ();

DROP FUNCTION IF EXISTS keyhippo_temp.update_policies ();

-- Drop temporary schema
DROP SCHEMA IF EXISTS keyhippo_temp CASCADE;

-- Drop the existing function
DROP FUNCTION IF EXISTS keyhippo.create_api_key (text, text);

-- Create the updated function
CREATE OR REPLACE FUNCTION keyhippo.create_api_key (id_of_user text, key_description text)
    RETURNS TABLE (
        api_key text,
        api_key_id uuid)
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    api_key text;
    expires bigint;
    jti uuid := extensions.gen_random_uuid ();
    jwt text;
    jwt_body jsonb;
    project_hash text;
    project_jwt_secret text;
    project_api_key_secret text;
    secret_uuid uuid;
    time_stamp bigint;
    user_api_key_secret text;
BEGIN
    -- Ensure the user is authorized
    IF auth.uid () IS NULL OR auth.uid () != id_of_user::uuid THEN
        RAISE EXCEPTION '[KeyHippo] Unauthorized: Invalid user ID';
    END IF;
    -- Validate key description length and format
    IF LENGTH(key_description) > 255 OR key_description !~ '^[a-zA-Z0-9_ -]*$' THEN
        RAISE EXCEPTION '[KeyHippo] Invalid key description';
    END IF;
    -- Ensure the user exists in the user_ids table
    INSERT INTO keyhippo.user_ids (id)
        VALUES (id_of_user::uuid)
    ON CONFLICT (id)
        DO NOTHING;
    -- Get current timestamp
    SELECT
        EXTRACT(EPOCH FROM now())::bigint INTO time_stamp;
    -- Calculate expiration time
    SELECT
        (time_stamp + EXTRACT(EPOCH FROM INTERVAL '100 years')::bigint) INTO expires;
    -- Build JWT body
    jwt_body := jsonb_build_object('role', 'authenticated', 'aud', 'authenticated', 'iss', 'supabase', 'sub', to_jsonb (id_of_user), 'iat', to_jsonb (time_stamp), 'exp', to_jsonb (expires), 'jti', to_jsonb (jti));
    -- Retrieve user API key secret
    SELECT
        decrypted_secret INTO user_api_key_secret
    FROM
        vault.decrypted_secrets
    WHERE
        name = id_of_user;
    -- Retrieve project API key secret
    SELECT
        decrypted_secret INTO project_api_key_secret
    FROM
        vault.decrypted_secrets
    WHERE
        name = 'project_api_key_secret';
    -- Retrieve project JWT secret
    SELECT
        decrypted_secret INTO project_jwt_secret
    FROM
        vault.decrypted_secrets
    WHERE
        name = 'project_jwt_secret';
    -- Generate JWT
    SELECT
        extensions.sign(jwt_body::json, project_jwt_secret) INTO jwt;
    -- Generate API key and project hash
    api_key := encode(extensions.hmac(jwt, user_api_key_secret, 'sha512'), 'hex');
    project_hash := encode(extensions.hmac(api_key, project_api_key_secret, 'sha512'), 'hex');
    -- Insert the generated secrets into the vault
    INSERT INTO vault.secrets (secret, name, description)
        VALUES (jwt, project_hash, key_description)
    RETURNING
        id INTO secret_uuid;
    -- Insert the JWT and related data into the auth tables
    INSERT INTO auth.jwts (secret_id, user_id)
        VALUES (secret_uuid, id_of_user::uuid);
    -- Insert the API key metadata into keyhippo tables
    INSERT INTO keyhippo.api_key_id_owner_id (api_key_id, user_id, owner_id)
        VALUES (secret_uuid, id_of_user::uuid, id_of_user::uuid);
    INSERT INTO keyhippo.api_key_id_name (api_key_id, name, owner_id)
        VALUES (secret_uuid, key_description, id_of_user::uuid);
    INSERT INTO keyhippo.api_key_id_permission (api_key_id, permission, owner_id)
        VALUES (secret_uuid, 'readOnly', id_of_user::uuid);
    INSERT INTO keyhippo.api_key_id_created (api_key_id, created, owner_id)
        VALUES (secret_uuid, now(), id_of_user::uuid);
    -- Initialize other tables with default values
    INSERT INTO keyhippo.api_key_id_total_use (api_key_id, total_uses, owner_id)
        VALUES (secret_uuid, 0, id_of_user::uuid);
    INSERT INTO keyhippo.api_key_id_success_rate (api_key_id, success_rate, owner_id)
        VALUES (secret_uuid, 100.00, id_of_user::uuid);
    INSERT INTO keyhippo.api_key_id_total_cost (api_key_id, total_cost, owner_id)
        VALUES (secret_uuid, 0.00, id_of_user::uuid);
    -- Return the generated API key and its ID
    RETURN QUERY
    SELECT
        api_key,
        secret_uuid;
END;
$$;

-- Grant necessary permissions
GRANT ALL ON FUNCTION keyhippo.create_api_key (TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION keyhippo.rotate_api_key (p_api_key_id uuid)
    RETURNS TABLE (
        new_api_key text,
        new_api_key_id uuid)
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = keyhippo,
    vault,
    extensions,
    pg_temp
    AS $$
DECLARE
    -- Variables for the new JWT
    new_jwt text;
    new_api_key text;
    new_secret_uuid uuid;
    project_hash text;
    -- Variables for JWT creation
    time_stamp bigint;
    expires bigint;
    jti uuid := gen_random_uuid ();
    jwt_body jsonb;
    -- Variables for secrets
    user_api_key_secret text;
    project_api_key_secret text;
    project_jwt_secret text;
    -- User ID associated with the API key
    v_user_id uuid;
    -- Renamed variable
    key_description text;
BEGIN
    -- Ensure the user owns the API key
    SELECT
        user_id INTO v_user_id
    FROM
        keyhippo.api_key_id_owner_id
    WHERE
        api_key_id = p_api_key_id;
    IF v_user_id IS NULL OR auth.uid () IS NULL OR auth.uid () != v_user_id THEN
        RAISE EXCEPTION '[KeyHippo] Unauthorized: You do not own this API key';
    END IF;
    -- Retrieve the description of the existing API key
    SELECT
        name INTO key_description
    FROM
        keyhippo.api_key_id_name
    WHERE
        api_key_id = p_api_key_id;
    -- Get current timestamp
    SELECT
        EXTRACT(EPOCH FROM now())::bigint INTO time_stamp;
    -- Calculate expiration time (e.g., 100 years from now)
    SELECT
        (time_stamp + EXTRACT(EPOCH FROM INTERVAL '100 years')::bigint) INTO expires;
    -- Build JWT body using the same claims as the original
    jwt_body := jsonb_build_object('role', 'authenticated', 'aud', 'authenticated', 'iss', 'supabase', 'sub', to_jsonb (v_user_id::text), 'iat', to_jsonb (time_stamp), 'exp', to_jsonb (expires), 'jti', to_jsonb (jti));
    -- Retrieve user API key secret
    SELECT
        decrypted_secret INTO user_api_key_secret
    FROM
        vault.decrypted_secrets
    WHERE
        name = v_user_id::text;
    -- Retrieve project API key secret
    SELECT
        decrypted_secret INTO project_api_key_secret
    FROM
        vault.decrypted_secrets
    WHERE
        name = 'project_api_key_secret';
    -- Retrieve project JWT secret
    SELECT
        decrypted_secret INTO project_jwt_secret
    FROM
        vault.decrypted_secrets
    WHERE
        name = 'project_jwt_secret';
    -- Generate new JWT
    SELECT
        sign(jwt_body::json, project_jwt_secret) INTO new_jwt;
    -- Generate new API key and project hash
    new_api_key := encode(hmac(new_jwt, user_api_key_secret, 'sha512'), 'hex');
    project_hash := encode(hmac(new_api_key, project_api_key_secret, 'sha512'), 'hex');
    -- Insert the new secret into the vault
    INSERT INTO vault.secrets (secret, name, description)
        VALUES (new_jwt, project_hash, key_description)
    RETURNING
        id INTO new_secret_uuid;
    -- Insert the new JWT and related data into the auth and keyhippo tables
    INSERT INTO auth.jwts (secret_id, user_id)
        VALUES (new_secret_uuid, v_user_id);
    INSERT INTO keyhippo.api_key_id_owner_id (api_key_id, user_id, owner_id)
        VALUES (new_secret_uuid, v_user_id, v_user_id);
    INSERT INTO keyhippo.api_key_id_name (api_key_id, name, owner_id)
        VALUES (new_secret_uuid, key_description, v_user_id);
    INSERT INTO keyhippo.api_key_id_permission (api_key_id, permission, owner_id)
        VALUES (new_secret_uuid, 'readOnly', v_user_id);
    INSERT INTO keyhippo.api_key_id_created (api_key_id, created, owner_id)
        VALUES (new_secret_uuid, now(), v_user_id);
    -- Initialize other tables with default values
    INSERT INTO keyhippo.api_key_id_total_use (api_key_id, total_uses, owner_id)
        VALUES (new_secret_uuid, 0, v_user_id);
    INSERT INTO keyhippo.api_key_id_success_rate (api_key_id, success_rate, owner_id)
        VALUES (new_secret_uuid, 100.00, v_user_id);
    INSERT INTO keyhippo.api_key_id_total_cost (api_key_id, total_cost, owner_id)
        VALUES (new_secret_uuid, 0.00, v_user_id);
    -- Optionally revoke the old API key
    INSERT INTO keyhippo.api_key_id_revoked (api_key_id, revoked_at, owner_id)
        VALUES (p_api_key_id, now(), v_user_id);
    -- Delete the old secret from the vault
    DELETE FROM vault.secrets
    WHERE id = p_api_key_id;
    -- Return the new API key and its ID
    RETURN QUERY
    SELECT
        new_api_key,
        new_secret_uuid;
END;
$$;

GRANT EXECUTE ON FUNCTION keyhippo.rotate_api_key (uuid) TO authenticated;

-- ================================================================
-- RBAC + ABAC Implementation
-- ================================================================
-- ================================================================
-- 1. Schema Creation
-- ================================================================
-- Create RBAC Schema
CREATE SCHEMA IF NOT EXISTS keyhippo_rbac AUTHORIZATION postgres;

-- Create ABAC Schema
CREATE SCHEMA IF NOT EXISTS keyhippo_abac AUTHORIZATION postgres;

-- ================================================================
-- 2. Table Definitions
-- ================================================================
-- -------------------------------
-- 2.1 RBAC Tables
-- -------------------------------
-- Create Groups Table
CREATE TABLE IF NOT EXISTS keyhippo_rbac.groups (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid (),
    name text UNIQUE NOT NULL,
    description text
);

-- Create Roles Table
CREATE TABLE IF NOT EXISTS keyhippo_rbac.roles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid (),
    name text UNIQUE NOT NULL,
    description text,
    group_id uuid NOT NULL REFERENCES keyhippo_rbac.groups (id) ON DELETE CASCADE,
    parent_role_id uuid REFERENCES keyhippo_rbac.roles (id) ON DELETE SET NULL
);

-- Create Permissions Table
CREATE TABLE IF NOT EXISTS keyhippo_rbac.permissions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid (),
    name text UNIQUE NOT NULL,
    description text
);

-- Create Role-Permissions Mapping Table
CREATE TABLE IF NOT EXISTS keyhippo_rbac.role_permissions (
    role_id uuid NOT NULL REFERENCES keyhippo_rbac.roles (id) ON DELETE CASCADE,
    permission_id uuid NOT NULL REFERENCES keyhippo_rbac.permissions (id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

-- Create User-Group-Roles Mapping Table
CREATE TABLE IF NOT EXISTS keyhippo_rbac.user_group_roles (
    user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
    group_id uuid NOT NULL REFERENCES keyhippo_rbac.groups (id) ON DELETE CASCADE,
    role_id uuid NOT NULL REFERENCES keyhippo_rbac.roles (id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, group_id, role_id)
);

-- Create Claims Cache Table
CREATE TABLE IF NOT EXISTS keyhippo_rbac.claims_cache (
    user_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
    rbac_claims jsonb DEFAULT '{}' ::jsonb
);

-- -------------------------------
-- 2.2 ABAC Tables
-- -------------------------------
-- Create User Attributes Table (ABAC)
CREATE TABLE IF NOT EXISTS keyhippo_abac.user_attributes (
    user_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
    attributes jsonb DEFAULT '{}' ::jsonb
);

-- Create Policies Table (ABAC)
CREATE TABLE IF NOT EXISTS keyhippo_abac.policies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid (),
    name text UNIQUE NOT NULL,
    description text,
    policy JSONB NOT NULL
);

-- ================================================================
-- 3. Function Definitions
-- ================================================================
-- -------------------------------
-- 3.1 RBAC Functions
-- -------------------------------
-- Function: add_user_to_group
CREATE OR REPLACE FUNCTION keyhippo_rbac.add_user_to_group (p_user_id uuid, p_group_id uuid, p_role_name text)
    RETURNS VOID
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $$
DECLARE
    v_role_id uuid;
BEGIN
    -- Fetch the role ID based on role name and group
    SELECT
        id INTO v_role_id
    FROM
        keyhippo_rbac.roles
    WHERE
        name = p_role_name
        AND group_id = p_group_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Role "%" not found in group ID %', p_role_name, p_group_id;
    END IF;
    -- Insert into user_group_roles if not exists
    INSERT INTO keyhippo_rbac.user_group_roles (user_id, group_id, role_id)
        VALUES (p_user_id, p_group_id, v_role_id)
    ON CONFLICT
        DO NOTHING;
    -- Update user claims cache
    PERFORM
        keyhippo_rbac.update_user_claims_cache (p_user_id);
END;
$$;

-- Function: set_parent_role
CREATE OR REPLACE FUNCTION keyhippo_rbac.set_parent_role (p_child_role_id uuid, p_parent_role_id uuid)
    RETURNS VOID
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $$
BEGIN
    -- Prevent setting the role's parent to itself
    IF p_child_role_id = p_parent_role_id THEN
        RAISE EXCEPTION 'A role cannot be its own parent.';
    END IF;
    -- Prevent circular hierarchies by checking ancestry
    IF EXISTS ( WITH RECURSIVE ancestor_roles AS (
            SELECT
                id,
                parent_role_id
            FROM
                keyhippo_rbac.roles
            WHERE
                id = p_parent_role_id
            UNION
            SELECT
                r.id,
                r.parent_role_id
            FROM
                keyhippo_rbac.roles r
                INNER JOIN ancestor_roles ar ON r.id = ar.parent_role_id
)
            SELECT
                1
            FROM
                ancestor_roles
            WHERE
                id = p_child_role_id) THEN
        RAISE EXCEPTION 'Circular role hierarchy detected when assigning parent role.';
END IF;
    -- Update the parent_role_id
    UPDATE
        keyhippo_rbac.roles
    SET
        parent_role_id = p_parent_role_id
    WHERE
        id = p_child_role_id;
    -- Update claims_cache for affected users
    WITH affected_users AS (
        SELECT DISTINCT
            user_id
        FROM
            keyhippo_rbac.user_group_roles
        WHERE
            role_id = p_child_role_id)
    UPDATE
        keyhippo_rbac.claims_cache cc
    SET
        rbac_claims = (
            SELECT
                jsonb_object_agg(g.id::text, array_agg(DISTINCT r.name))
            FROM
                keyhippo_rbac.user_group_roles ugr
                JOIN keyhippo_rbac.roles r ON ugr.role_id = r.id
                JOIN keyhippo_rbac.groups g ON ugr.group_id = g.id
            WHERE
                ugr.user_id = cc.user_id
            GROUP BY
                g.id)
    FROM
        affected_users
    WHERE
        cc.user_id = affected_users.user_id;
END;
$$;

-- Function: update_user_claims_cache (RBAC)
CREATE OR REPLACE FUNCTION keyhippo_rbac.update_user_claims_cache (p_user_id uuid)
    RETURNS VOID
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $$
BEGIN
    -- Aggregate RBAC claims for the user
    WITH user_roles AS (
        SELECT
            r.name AS role_name,
            g.id AS group_id
        FROM
            keyhippo_rbac.user_group_roles ugr
            JOIN keyhippo_rbac.roles r ON ugr.role_id = r.id
            JOIN keyhippo_rbac.groups g ON ugr.group_id = g.id
        WHERE
            ugr.user_id = p_user_id
),
group_roles AS (
    SELECT
        group_id::text,
        jsonb_agg(role_name) AS roles
FROM
    user_roles
GROUP BY
    group_id)
UPDATE
    keyhippo_rbac.claims_cache
SET
    rbac_claims = (
        SELECT
            jsonb_object_agg(group_id, roles)
        FROM
            group_roles)
WHERE
    user_id = p_user_id;
    -- Handle users without roles by ensuring a row exists
    IF NOT FOUND THEN
        INSERT INTO keyhippo_rbac.claims_cache (user_id, rbac_claims)
            VALUES (p_user_id, '{}'::jsonb)
        ON CONFLICT
            DO NOTHING;
    END IF;
END;
$$;

-- Function: assign_role_to_user (RBAC)
CREATE OR REPLACE FUNCTION keyhippo_rbac.assign_role_to_user (p_user_id uuid, p_group_id uuid, p_role_name text)
    RETURNS VOID
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $$
BEGIN
    PERFORM
        keyhippo_rbac.add_user_to_group (p_user_id, p_group_id, p_role_name);
END;
$$;

-- -------------------------------
-- 3.2 ABAC Functions
-- -------------------------------
-- Function: get_user_attribute (ABAC)
CREATE OR REPLACE FUNCTION keyhippo_abac.get_user_attribute (p_user_id uuid, p_attribute text)
    RETURNS jsonb
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $$
DECLARE
    v_attribute jsonb;
BEGIN
    SELECT
        attributes -> p_attribute INTO v_attribute
    FROM
        keyhippo_abac.user_attributes
    WHERE
        user_id = p_user_id;
    RETURN COALESCE(v_attribute, 'null'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION keyhippo_abac.set_user_attribute (p_user_id uuid, p_attribute text, p_value jsonb)
    RETURNS void
    AS $$
BEGIN
    INSERT INTO keyhippo_abac.user_attributes (user_id, attributes)
        VALUES (p_user_id, jsonb_build_object(p_attribute, p_value))
    ON CONFLICT (user_id)
        DO UPDATE SET
            attributes = keyhippo_abac.user_attributes.attributes || jsonb_build_object(p_attribute, p_value);
END;
$$
LANGUAGE plpgsql
SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION keyhippo_abac.set_user_attribute (uuid, text, jsonb) TO authenticated;

-- Function: check_abac_policy (ABAC)
CREATE OR REPLACE FUNCTION keyhippo_abac.check_abac_policy (p_user_id uuid, p_policy jsonb)
    RETURNS boolean
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $$
DECLARE
    v_attribute_value text;
    v_policy_attribute text;
    v_policy_value text;
    v_result boolean;
BEGIN
    -- Get the attribute name from the policy
    v_policy_attribute := p_policy ->> 'attribute';
    -- Retrieve the user's attribute value
    EXECUTE format('SELECT (attributes->>%L)::text FROM keyhippo_abac.user_attributes WHERE user_id = $1', v_policy_attribute) INTO v_attribute_value
    USING p_user_id;
    -- Retrieve the policy's expected value
    v_policy_value := p_policy ->> 'value';
    RAISE NOTICE 'Checking policy: Attribute %, User value: %, Policy value: %', v_policy_attribute, v_attribute_value, v_policy_value;
    -- If the attribute is missing, the policy check should fail
    IF v_attribute_value IS NULL THEN
        v_result := FALSE;
    ELSE
        v_result := (
            CASE WHEN p_policy ->> 'type' = 'attribute_equals' THEN
                v_attribute_value = v_policy_value
            WHEN p_policy ->> 'type' = 'attribute_contains' THEN
                v_attribute_value::jsonb @> v_policy_value::jsonb
            ELSE
                FALSE
            END);
    END IF;
    RAISE NOTICE 'Policy check result: %', v_result;
    RETURN v_result;
END;
$$;

-- Function: update_user_claims_cache (RBAC)
CREATE OR REPLACE FUNCTION keyhippo_rbac.update_user_claims_cache (p_user_id uuid)
    RETURNS VOID
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $$
BEGIN
    -- First, delete existing claims for the user
    DELETE FROM keyhippo_rbac.claims_cache
    WHERE user_id = p_user_id;
    -- Then, insert new claims
    INSERT INTO keyhippo_rbac.claims_cache (user_id, rbac_claims)
    SELECT
        p_user_id,
        jsonb_object_agg(g.id::text, roles)
    FROM (
        SELECT
            ugr.group_id,
            jsonb_agg(DISTINCT r.name) AS roles
        FROM
            keyhippo_rbac.user_group_roles ugr
            JOIN keyhippo_rbac.roles r ON ugr.role_id = r.id
        WHERE
            ugr.user_id = p_user_id
        GROUP BY
            ugr.group_id) AS group_roles
    JOIN keyhippo_rbac.groups g ON g.id = group_roles.group_id;
    -- If no claims were inserted (user has no roles), ensure an empty claims cache entry exists
    INSERT INTO keyhippo_rbac.claims_cache (user_id, rbac_claims)
        VALUES (p_user_id, '{}')
    ON CONFLICT (user_id)
        DO NOTHING;
END;
$$;

-- Function: assign_role_to_user (RBAC)
CREATE OR REPLACE FUNCTION keyhippo_rbac.assign_role_to_user (p_user_id uuid, p_group_id uuid, p_role_name text)
    RETURNS VOID
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $$
BEGIN
    PERFORM
        keyhippo_rbac.add_user_to_group (p_user_id, p_group_id, p_role_name);
END;
$$;

-- Function: create_policy (ABAC)
CREATE OR REPLACE FUNCTION keyhippo_abac.create_policy (p_name text, p_description text, p_policy jsonb)
    RETURNS VOID
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $$
BEGIN
    INSERT INTO keyhippo_abac.policies (name, description, POLICY)
            VALUES (p_name, p_description, p_policy)
        ON CONFLICT (name)
            DO UPDATE SET
                description = EXCLUDED.description, POLICY = EXCLUDED.policy;
END;
$$;

-- Function: evaluate_policies (ABAC)
CREATE OR REPLACE FUNCTION keyhippo_abac.evaluate_policies (p_user_id uuid)
    RETURNS boolean
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $$
DECLARE
    policy_record RECORD;
    policy_result boolean;
    overall_result boolean := TRUE;
BEGIN
    FOR policy_record IN
    SELECT
        *
    FROM
        keyhippo_abac.policies LOOP
            policy_result := keyhippo_abac.check_abac_policy (p_user_id, policy_record.policy);
            RAISE NOTICE 'Policy % evaluation result: %', policy_record.name, policy_result;
            IF policy_result IS NULL OR NOT policy_result THEN
                overall_result := FALSE;
            END IF;
        END LOOP;
    RETURN overall_result;
END;
$$;

-- ================================================================
-- 4. Row-Level Security (RLS) Policies
-- ================================================================
-- -------------------------------
-- 4.1 RBAC RLS Policies
-- -------------------------------
-- Enable RLS on RBAC Tables
ALTER TABLE keyhippo_rbac.groups ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo_rbac.roles ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo_rbac.permissions ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo_rbac.role_permissions ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo_rbac.user_group_roles ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo_rbac.claims_cache ENABLE ROW LEVEL SECURITY;

-- RBAC: Groups Access Policy
CREATE POLICY "rbac_groups_access" ON keyhippo_rbac.groups
    FOR ALL
        USING (auth.uid () = ANY (
            SELECT
                user_id
            FROM
                keyhippo_rbac.user_group_roles
            WHERE
                group_id = keyhippo_rbac.groups.id)
                OR CURRENT_ROLE = 'service_role')
            WITH CHECK (CURRENT_ROLE = 'service_role');

-- RBAC: Roles Access Policy
CREATE POLICY "rbac_roles_access" ON keyhippo_rbac.roles
    FOR ALL
        USING (auth.uid () = ANY (
            SELECT
                user_id
            FROM
                keyhippo_rbac.user_group_roles
            WHERE
                role_id = keyhippo_rbac.roles.id)
                OR CURRENT_ROLE = 'service_role')
            WITH CHECK (CURRENT_ROLE = 'service_role');

-- RBAC: Permissions Access Policy
CREATE POLICY "rbac_permissions_access" ON keyhippo_rbac.permissions
    FOR ALL
        USING (auth.uid () = ANY (
            SELECT
                user_id
            FROM
                keyhippo_rbac.user_group_roles ugr
                JOIN keyhippo_rbac.role_permissions rp ON ugr.role_id = rp.role_id
            WHERE
                rp.permission_id = keyhippo_rbac.permissions.id)
                OR CURRENT_ROLE = 'service_role')
            WITH CHECK (CURRENT_ROLE = 'service_role');

-- RBAC: Role-Permissions Access Policy
CREATE POLICY "rbac_role_permissions_access" ON keyhippo_rbac.role_permissions
    FOR ALL
        USING (auth.uid () = ANY (
            SELECT
                user_id
            FROM
                keyhippo_rbac.user_group_roles
            WHERE
                role_id = keyhippo_rbac.role_permissions.role_id)
                OR CURRENT_ROLE = 'service_role')
            WITH CHECK (CURRENT_ROLE = 'service_role');

-- RBAC: User-Group-Roles Access Policy
CREATE POLICY "rbac_user_group_roles_access" ON keyhippo_rbac.user_group_roles
    FOR ALL
        USING (auth.uid () = user_id
            OR CURRENT_ROLE = 'service_role')
            WITH CHECK (CURRENT_ROLE = 'service_role');

-- RBAC: Claims Cache Access Policy
CREATE POLICY "rbac_claims_cache_access" ON keyhippo_rbac.claims_cache
    FOR SELECT
        USING (auth.uid () = user_id
            OR CURRENT_ROLE = 'service_role');

-- -------------------------------
-- 4.2 ABAC RLS Policies
-- -------------------------------
-- Enable RLS on ABAC Tables
ALTER TABLE keyhippo_abac.user_attributes ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo_abac.policies ENABLE ROW LEVEL SECURITY;

-- ABAC: User Attributes Access Policy
CREATE POLICY "abac_user_attributes_access" ON keyhippo_abac.user_attributes
    FOR ALL
        USING (auth.uid () = user_id
            OR CURRENT_ROLE = 'service_role')
            WITH CHECK (CURRENT_ROLE = 'service_role');

-- ABAC: Policies Access Policy
CREATE POLICY "abac_policies_access" ON keyhippo_abac.policies
    FOR ALL
        USING (CURRENT_ROLE = 'service_role')
        WITH CHECK (CURRENT_ROLE = 'service_role');

-- ================================================================
-- 5. Permissions and Grants
-- ================================================================
-- -------------------------------
-- 5.1 Granting Permissions to 'authenticated' Role
-- -------------------------------
-- Grant USAGE on RBAC and ABAC Schemas to Authenticated Role
GRANT USAGE ON SCHEMA keyhippo_rbac TO authenticated;

GRANT USAGE ON SCHEMA keyhippo_abac TO authenticated;

-- Grant SELECT, INSERT, UPDATE, DELETE on All RBAC Tables to Authenticated Role
GRANT SELECT, INSERT, UPDATE, DELETE ON keyhippo_rbac.groups TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON keyhippo_rbac.roles TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON keyhippo_rbac.permissions TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON keyhippo_rbac.role_permissions TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON keyhippo_rbac.user_group_roles TO authenticated;

GRANT SELECT ON keyhippo_rbac.claims_cache TO authenticated;

-- Grant SELECT, INSERT, UPDATE, DELETE on All ABAC Tables to Authenticated Role
GRANT SELECT, INSERT, UPDATE, DELETE ON keyhippo_abac.user_attributes TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON keyhippo_abac.policies TO authenticated;

-- Grant EXECUTE on RBAC Functions to Authenticated Role
GRANT EXECUTE ON FUNCTION keyhippo_rbac.add_user_to_group (uuid, uuid, text) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo_rbac.set_parent_role (uuid, uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo_rbac.update_user_claims_cache (uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo_rbac.assign_role_to_user (uuid, uuid, text) TO authenticated;

-- Grant EXECUTE on ABAC Functions to Authenticated Role
GRANT EXECUTE ON FUNCTION keyhippo_abac.get_user_attribute (uuid, text) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo_abac.check_abac_policy (uuid, jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo_abac.create_policy (text, text, jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo_abac.evaluate_policies (uuid) TO authenticated;

-- -------------------------------
-- 5.2 Granting Permissions to 'service_role'
-- -------------------------------
-- Grant USAGE on RBAC and ABAC Schemas to Service Role
GRANT USAGE ON SCHEMA keyhippo_rbac TO service_role;

GRANT USAGE ON SCHEMA keyhippo_abac TO service_role;

-- Grant SELECT, INSERT, UPDATE, DELETE on All RBAC Tables to Service Role
GRANT SELECT, INSERT, UPDATE, DELETE ON keyhippo_rbac.groups TO service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON keyhippo_rbac.roles TO service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON keyhippo_rbac.permissions TO service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON keyhippo_rbac.role_permissions TO service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON keyhippo_rbac.user_group_roles TO service_role;

GRANT SELECT ON keyhippo_rbac.claims_cache TO service_role;

-- Grant SELECT, INSERT, UPDATE, DELETE on All ABAC Tables to Service Role
GRANT SELECT, INSERT, UPDATE, DELETE ON keyhippo_abac.user_attributes TO service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON keyhippo_abac.policies TO service_role;

-- Grant EXECUTE on RBAC Functions to Service Role
GRANT EXECUTE ON FUNCTION keyhippo_rbac.add_user_to_group (uuid, uuid, text) TO service_role;

GRANT EXECUTE ON FUNCTION keyhippo_rbac.set_parent_role (uuid, uuid) TO service_role;

GRANT EXECUTE ON FUNCTION keyhippo_rbac.update_user_claims_cache (uuid) TO service_role;

GRANT EXECUTE ON FUNCTION keyhippo_rbac.assign_role_to_user (uuid, uuid, text) TO service_role;

-- Grant EXECUTE on ABAC Functions to Service Role
GRANT EXECUTE ON FUNCTION keyhippo_abac.get_user_attribute (uuid, text) TO service_role;

GRANT EXECUTE ON FUNCTION keyhippo_abac.check_abac_policy (uuid, jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION keyhippo_abac.create_policy (text, text, jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION keyhippo_abac.evaluate_policies (uuid) TO service_role;

-- ================================================================
-- 6. Indexes for Performance
-- ================================================================
-- GIN Index on user_attributes.attributes for Faster ABAC Queries
CREATE INDEX IF NOT EXISTS idx_user_attributes_attributes ON keyhippo_abac.user_attributes USING GIN (attributes);

-- GIN Index on claims_cache.rbac_claims for Efficient Claims Retrieval
CREATE INDEX IF NOT EXISTS idx_claims_cache_rbac_claims ON keyhippo_rbac.claims_cache USING GIN (rbac_claims);

-- Index on role_permissions.permission_id for Faster Permission Checks
CREATE INDEX IF NOT EXISTS idx_role_permissions_permission_id ON keyhippo_rbac.role_permissions (permission_id);

-- Index on user_group_roles.user_id for Faster Role Assignments
CREATE INDEX IF NOT EXISTS idx_user_group_roles_user_id ON keyhippo_rbac.user_group_roles (user_id);

-- ================================================================
-- 7. Default Data Insertion
-- ================================================================
-- Inserting Default Groups
INSERT INTO keyhippo_rbac.groups (name, description)
    VALUES ('Admin Group', 'Group with administrative privileges'),
    ('User Group', 'Group with standard user privileges')
ON CONFLICT (name)
    DO NOTHING;

-- Inserting Default Roles
INSERT INTO keyhippo_rbac.roles (name, description, group_id)
SELECT
    'Admin',
    'Administrator Role',
    id
FROM
    keyhippo_rbac.groups
WHERE
    name = 'Admin Group'
ON CONFLICT (name)
    DO NOTHING;

INSERT INTO keyhippo_rbac.roles (name, description, group_id)
SELECT
    'User',
    'Standard User Role',
    id
FROM
    keyhippo_rbac.groups
WHERE
    name = 'User Group'
ON CONFLICT (name)
    DO NOTHING;

-- Inserting Default Permissions
INSERT INTO keyhippo_rbac.permissions (name, description)
    VALUES ('read', 'Read Permission'),
    ('write', 'Write Permission'),
    ('delete', 'Delete Permission'),
    ('manage_policies', 'Manage ABAC Policies')
ON CONFLICT (name)
    DO NOTHING;

-- Mapping Roles to Permissions
-- Admin Role: All permissions
INSERT INTO keyhippo_rbac.role_permissions (role_id, permission_id)
SELECT
    r.id,
    p.id
FROM
    keyhippo_rbac.roles r
    JOIN keyhippo_rbac.permissions p ON p.name IN ('read', 'write', 'delete', 'manage_policies')
WHERE
    r.name = 'Admin'
ON CONFLICT
    DO NOTHING;

-- User Role: read and write permissions
INSERT INTO keyhippo_rbac.role_permissions (role_id, permission_id)
SELECT
    r.id,
    p.id
FROM
    keyhippo_rbac.roles r
    JOIN keyhippo_rbac.permissions p ON p.name IN ('read', 'write')
WHERE
    r.name = 'User'
ON CONFLICT
    DO NOTHING;

-- ================================================================
-- 8. Triggers for Automatic Claims Cache Updates
-- ================================================================
-- Function: trigger_update_claims_cache
CREATE OR REPLACE FUNCTION keyhippo_rbac.trigger_update_claims_cache ()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $$
BEGIN
    PERFORM
        keyhippo_rbac.update_user_claims_cache (NEW.user_id);
    RETURN NEW;
END;
$$;

-- Trigger: after_insert_update_user_group_roles
CREATE TRIGGER after_insert_update_user_group_roles
    AFTER INSERT OR UPDATE ON keyhippo_rbac.user_group_roles
    FOR EACH ROW
    EXECUTE FUNCTION keyhippo_rbac.trigger_update_claims_cache ();

-- ================================================================
-- 9. Notifications and Final Setup
-- ================================================================
--
-- Notify pgRest to reload configuration if necessary
NOTIFY pgrst,
'reload config';
