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
 */
-- Create the necessary schemas
CREATE SCHEMA IF NOT EXISTS keyhippo;

CREATE SCHEMA IF NOT EXISTS keyhippo_internal;

-- Ensure required extensions are installed
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE EXTENSION IF NOT EXISTS pgjwt;

CREATE EXTENSION IF NOT EXISTS pgsodium;

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
    SET search_path = extensions
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
    SET search_path = ''
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
    SET search_path = extensions
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
    SET search_path = keyhippo
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
    SET search_path = extensions
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

GRANT SELECT ON auth.jwts TO authenticated;

GRANT SELECT ON auth.jwts TO service_role;

GRANT SELECT ON vault.decrypted_secrets TO authenticated;

GRANT SELECT ON vault.decrypted_secrets TO service_role;

GRANT USAGE ON SCHEMA auth TO authenticated;

GRANT USAGE ON SCHEMA auth TO service_role;

GRANT USAGE ON SCHEMA keyhippo TO authenticated, service_role, anon;

GRANT USAGE ON SCHEMA vault TO authenticated;

GRANT USAGE ON SCHEMA vault TO service_role;

-- Set up vault secrets
SELECT
    keyhippo.setup_vault_secrets ();

COMMENT ON FUNCTION keyhippo.setup_vault_secrets () IS 'Run this function to set up or update KeyHippo vault secrets';

-- Cleanup setup functions
DROP FUNCTION keyhippo.setup_vault_secrets ();

DROP FUNCTION keyhippo.setup_project_jwt_secret ();

DROP FUNCTION keyhippo.setup_project_api_key_secret ();

NOTIFY pgrst,
'reload config';
