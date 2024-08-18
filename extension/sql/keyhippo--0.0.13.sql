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
CREATE SCHEMA IF NOT EXISTS keyhippo;

CREATE SCHEMA IF NOT EXISTS keyhippo_internal;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE EXTENSION IF NOT EXISTS pgjwt;

CREATE EXTENSION IF NOT EXISTS pgsodium;

CREATE OR REPLACE FUNCTION keyhippo.setup ()
    RETURNS VOID
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $setup$
BEGIN
    -- Log the start of the setup
    RAISE LOG '[KeyHippo] Starting KeyHippo setup...';
    -- Create jwts table in auth schema
    CREATE TABLE IF NOT EXISTS auth.jwts (
        secret_id uuid PRIMARY KEY,
        user_id uuid,
        CONSTRAINT jwts_secret_id_fkey FOREIGN KEY (secret_id ) REFERENCES vault.secrets (id ) ON DELETE CASCADE
    );
    RAISE LOG '[KeyHippo] Table "auth.jwts" ensured.';
    -- Create user_ids table
    CREATE TABLE IF NOT EXISTS keyhippo.user_ids (
        id uuid PRIMARY KEY
    );
    RAISE LOG '[KeyHippo] Table "keyhippo.user_ids" ensured.';
    -- Create API key related tables
    CREATE TABLE IF NOT EXISTS keyhippo.api_key_id_owner_id (
        api_key_id uuid PRIMARY KEY,
        user_id uuid NOT NULL,
        owner_id uuid,
        CONSTRAINT api_key_id_owner_id_user_id_fkey FOREIGN KEY (user_id ) REFERENCES keyhippo.user_ids (id ) ON DELETE CASCADE,
        CONSTRAINT api_key_id_owner_id_api_key_id_owner_id_key UNIQUE (api_key_id, owner_id )
    );
    RAISE LOG '[KeyHippo] Table "keyhippo.api_key_id_owner_id" ensured.';
    CREATE TABLE IF NOT EXISTS keyhippo.api_key_id_name (
        api_key_id uuid PRIMARY KEY,
        name text NOT NULL,
        owner_id uuid,
        CONSTRAINT api_key_id_name_api_key_id_fkey FOREIGN KEY (api_key_id ) REFERENCES keyhippo.api_key_id_owner_id (api_key_id ) ON DELETE CASCADE,
        CONSTRAINT api_key_id_name_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id ) REFERENCES keyhippo.api_key_id_owner_id (api_key_id, owner_id )
    );
    RAISE LOG '[KeyHippo] Table "keyhippo.api_key_id_name" ensured.';
    CREATE TABLE IF NOT EXISTS keyhippo.api_key_id_permission (
        api_key_id uuid PRIMARY KEY,
        permission text NOT NULL,
        owner_id uuid,
        CONSTRAINT api_key_id_permission_api_key_id_fkey FOREIGN KEY (api_key_id ) REFERENCES keyhippo.api_key_id_owner_id (api_key_id ) ON DELETE CASCADE,
        CONSTRAINT api_key_id_permission_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id ) REFERENCES keyhippo.api_key_id_owner_id (api_key_id, owner_id )
    );
    RAISE LOG '[KeyHippo] Table "keyhippo.api_key_id_permission" ensured.';
    CREATE TABLE IF NOT EXISTS keyhippo.api_key_id_created (
        api_key_id uuid PRIMARY KEY,
        created timestamptz NOT NULL,
        owner_id uuid,
        CONSTRAINT api_key_id_created_api_key_id_fkey FOREIGN KEY (api_key_id ) REFERENCES keyhippo.api_key_id_owner_id (api_key_id ) ON DELETE CASCADE,
        CONSTRAINT api_key_id_created_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id ) REFERENCES keyhippo.api_key_id_owner_id (api_key_id, owner_id )
    );
    RAISE LOG '[KeyHippo] Table "keyhippo.api_key_id_created" ensured.';
    CREATE TABLE IF NOT EXISTS keyhippo.api_key_id_last_used (
        api_key_id uuid PRIMARY KEY,
        last_used timestamptz,
        owner_id uuid,
        CONSTRAINT api_key_id_last_used_api_key_id_fkey FOREIGN KEY (api_key_id ) REFERENCES keyhippo.api_key_id_owner_id (api_key_id ) ON DELETE CASCADE,
        CONSTRAINT api_key_id_last_used_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id ) REFERENCES keyhippo.api_key_id_owner_id (api_key_id, owner_id )
    );
    RAISE LOG '[KeyHippo] Table "keyhippo.api_key_id_last_used" ensured.';
    CREATE TABLE IF NOT EXISTS keyhippo.api_key_id_total_use (
        api_key_id uuid PRIMARY KEY,
        total_uses bigint DEFAULT 0 NOT NULL,
        owner_id uuid,
        CONSTRAINT api_key_id_total_use_api_key_id_fkey FOREIGN KEY (api_key_id ) REFERENCES keyhippo.api_key_id_owner_id (api_key_id ) ON DELETE CASCADE,
        CONSTRAINT api_key_id_total_use_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id ) REFERENCES keyhippo.api_key_id_owner_id (api_key_id, owner_id )
    );
    RAISE LOG '[KeyHippo] Table "keyhippo.api_key_id_total_use" ensured.';
    CREATE TABLE IF NOT EXISTS keyhippo.api_key_id_success_rate (
        api_key_id uuid PRIMARY KEY,
        success_rate numeric(5, 2 ) NOT NULL,
        owner_id uuid,
        CONSTRAINT api_key_id_success_rate_api_key_id_fkey FOREIGN KEY (api_key_id ) REFERENCES keyhippo.api_key_id_owner_id (api_key_id ) ON DELETE CASCADE,
        CONSTRAINT api_key_id_success_rate_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id ) REFERENCES keyhippo.api_key_id_owner_id (api_key_id, owner_id ),
        CONSTRAINT api_key_reference_success_rate_success_rate_check CHECK ((success_rate >= 0 AND success_rate <= 100 ) )
    );
    RAISE LOG '[KeyHippo] Table "keyhippo.api_key_id_success_rate" ensured.';
    CREATE TABLE IF NOT EXISTS keyhippo.api_key_id_total_cost (
        api_key_id uuid PRIMARY KEY,
        total_cost numeric(12, 2 ) DEFAULT 0 NOT NULL,
        owner_id uuid,
        CONSTRAINT api_key_id_total_cost_api_key_id_fkey FOREIGN KEY (api_key_id ) REFERENCES keyhippo.api_key_id_owner_id (api_key_id ) ON DELETE CASCADE,
        CONSTRAINT api_key_id_total_cost_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id ) REFERENCES keyhippo.api_key_id_owner_id (api_key_id, owner_id )
    );
    RAISE LOG '[KeyHippo] Table "keyhippo.api_key_id_total_cost" ensured.';
    CREATE TABLE IF NOT EXISTS keyhippo.api_key_id_revoked (
        api_key_id uuid PRIMARY KEY,
        revoked_at timestamptz DEFAULT now( ) NOT NULL,
        owner_id uuid,
        CONSTRAINT api_key_id_revoked_api_key_id_fkey FOREIGN KEY (api_key_id ) REFERENCES keyhippo.api_key_id_owner_id (api_key_id ) ON DELETE CASCADE,
        CONSTRAINT api_key_id_revoked_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id ) REFERENCES keyhippo.api_key_id_owner_id (api_key_id, owner_id )
    );
    RAISE LOG '[KeyHippo] Table "keyhippo.api_key_id_revoked" ensured.';
    -- Function to set up project_api_key_secret
    CREATE OR REPLACE FUNCTION keyhippo.setup_project_api_key_secret ( )
        RETURNS VOID
        LANGUAGE plpgsql
        SECURITY DEFINER AS $$
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
    -- Function to set up project_jwt_secret
    CREATE OR REPLACE FUNCTION keyhippo.setup_project_jwt_secret ( )
        RETURNS VOID
        LANGUAGE plpgsql
        SECURITY DEFINER AS $$
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
    CREATE OR REPLACE FUNCTION keyhippo.setup_vault_secrets ( )
        RETURNS VOID
        LANGUAGE plpgsql
        SECURITY DEFINER AS $$
        BEGIN
            PERFORM
                keyhippo.setup_project_api_key_secret ();
            PERFORM
                keyhippo.setup_project_jwt_secret ();
            RAISE LOG '[KeyHippo] KeyHippo vault secrets setup complete';
END;
    $$;
    -- Create function to generate and store API key
    CREATE OR REPLACE FUNCTION keyhippo.create_api_key (id_of_user text, key_description text )
        RETURNS text
        LANGUAGE plpgsql
        SECURITY DEFINER AS $$
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
    RAISE LOG '[KeyHippo] Function "create_api_key" created.';
    -- Create internal function to get secret uuid for API key
    CREATE OR REPLACE FUNCTION keyhippo_internal._get_secret_uuid_for_api_key (user_api_key text )
        RETURNS uuid
        LANGUAGE plpgsql
        STRICT
        SECURITY DEFINER
        SET search_path = extensions,
        vault,
        keyhippo,
        keyhippo_internal,
        pg_temp AS $$
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
    -- Create function to validate API key
    CREATE OR REPLACE FUNCTION keyhippo.key_uid ( )
        RETURNS uuid
        LANGUAGE plpgsql
        SECURITY DEFINER
        SET search_path = keyhippo,
        keyhippo_internal,
        pg_temp AS $$
DECLARE
    user_api_key text;
    secret_uuid uuid;
    result_user_id uuid;
BEGIN
    SELECT
        current_setting('request.headers', TRUE)::json ->> 'authorization' INTO user_api_key;
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
    RAISE LOG '[KeyHippo] Function "key_uid" created.';
    -- Create function to revoke API key
    CREATE OR REPLACE FUNCTION keyhippo.revoke_api_key (id_of_user text, secret_id text )
        RETURNS VOID
        LANGUAGE plpgsql
        SECURITY DEFINER AS $$
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
    RAISE LOG '[KeyHippo] Function "revoke_api_key" created.';
    -- Create function to get API key metadata
    CREATE OR REPLACE FUNCTION keyhippo.get_api_key_metadata (id_of_user uuid )
        RETURNS TABLE (
            api_key_id uuid,
            name text,
            permission text,
            last_used timestamptz,
            created timestamptz,
            total_uses bigint,
            success_rate double precision,
            total_cost double precision,
            revoked timestamptz )
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
                COALESCE(s.success_rate, 0.0)::double PRECISION AS success_rate,
                COALESCE(tc.total_cost, 0.0)::double PRECISION AS total_cost,
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
    RAISE LOG '[KeyHippo] Function "get_api_key_metadata" created.';
    -- Create helper function for RLS
    CREATE OR REPLACE FUNCTION auth.keyhippo_check (owner_id uuid )
        RETURNS boolean
        LANGUAGE sql
        SECURITY DEFINER AS $$
        SELECT
            (
                auth.uid ( ) = owner_id )
            OR (
                keyhippo.key_uid ( ) = owner_id
            );
    $$;
    RAISE LOG '[KeyHippo] Function "keyhippo_check" created.';
    -- Function to get user ID from API key
    CREATE OR REPLACE FUNCTION keyhippo.get_uid_for_key (user_api_key text )
        RETURNS uuid
        LANGUAGE plpgsql
        SECURITY DEFINER
        SET search_path = keyhippo,
        keyhippo_internal,
        pg_temp AS $$
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
    RAISE LOG '[KeyHippo] Function "get_uid_for_key" created.';
    -- Enable Row Level Security on all tables
    ALTER TABLE keyhippo.api_key_id_created ENABLE ROW LEVEL SECURITY;
    RAISE LOG '[KeyHippo] Row Level Security enabled on table "api_key_id_created".';
    ALTER TABLE keyhippo.api_key_id_last_used ENABLE ROW LEVEL SECURITY;
    RAISE LOG '[KeyHippo] Row Level Security enabled on table "api_key_id_last_used".';
    ALTER TABLE keyhippo.api_key_id_name ENABLE ROW LEVEL SECURITY;
    RAISE LOG '[KeyHippo] Row Level Security enabled on table "api_key_id_name".';
    ALTER TABLE keyhippo.api_key_id_owner_id ENABLE ROW LEVEL SECURITY;
    RAISE LOG '[KeyHippo] Row Level Security enabled on table "api_key_id_owner_id".';
    ALTER TABLE keyhippo.api_key_id_permission ENABLE ROW LEVEL SECURITY;
    RAISE LOG '[KeyHippo] Row Level Security enabled on table "api_key_id_permission".';
    ALTER TABLE keyhippo.api_key_id_revoked ENABLE ROW LEVEL SECURITY;
    RAISE LOG '[KeyHippo] Row Level Security enabled on table "api_key_id_revoked".';
    ALTER TABLE keyhippo.api_key_id_success_rate ENABLE ROW LEVEL SECURITY;
    RAISE LOG '[KeyHippo] Row Level Security enabled on table "api_key_id_success_rate".';
    ALTER TABLE keyhippo.api_key_id_total_cost ENABLE ROW LEVEL SECURITY;
    RAISE LOG '[KeyHippo] Row Level Security enabled on table "api_key_id_total_cost".';
    ALTER TABLE keyhippo.api_key_id_total_use ENABLE ROW LEVEL SECURITY;
    RAISE LOG '[KeyHippo] Row Level Security enabled on table "api_key_id_total_use".';
    ALTER TABLE keyhippo.user_ids ENABLE ROW LEVEL SECURITY;
    RAISE LOG '[KeyHippo] Row Level Security enabled on table "user_ids".';
    -- Create RLS policies for each table
    CREATE POLICY "select_policy_api_key_id_created" ON keyhippo.api_key_id_created
        USING (auth.uid ( ) = owner_id );
    RAISE LOG '[KeyHippo] Policy "select_policy_api_key_id_created" created.';
    CREATE POLICY "select_policy_api_key_id_last_used" ON keyhippo.api_key_id_last_used
        USING (auth.uid ( ) = owner_id );
    RAISE LOG '[KeyHippo] Policy "select_policy_api_key_id_last_used" created.';
    CREATE POLICY "select_policy_api_key_id_name" ON keyhippo.api_key_id_name
        USING (auth.uid ( ) = owner_id );
    RAISE LOG '[KeyHippo] Policy "select_policy_api_key_id_name" created.';
    CREATE POLICY "select_policy_api_key_id_owner_id" ON keyhippo.api_key_id_owner_id
        USING (auth.uid ( ) = owner_id );
    RAISE LOG '[KeyHippo] Policy "select_policy_api_key_id_owner_id" created.';
    CREATE POLICY "select_policy_api_key_id_permission" ON keyhippo.api_key_id_permission
        USING (auth.uid ( ) = owner_id );
    RAISE LOG '[KeyHippo] Policy "select_policy_api_key_id_permission" created.';
    CREATE POLICY "select_policy_api_key_id_revoked" ON keyhippo.api_key_id_revoked
        USING (auth.uid ( ) = owner_id );
    RAISE LOG '[KeyHippo] Policy "select_policy_api_key_id_revoked" created.';
    CREATE POLICY "select_policy_api_key_id_success_rate" ON keyhippo.api_key_id_success_rate
        USING (auth.uid ( ) = owner_id );
    RAISE LOG '[KeyHippo] Policy "select_policy_api_key_id_success_rate" created.';
    CREATE POLICY "select_policy_api_key_id_total_cost" ON keyhippo.api_key_id_total_cost
        USING (auth.uid ( ) = owner_id );
    RAISE LOG '[KeyHippo] Policy "select_policy_api_key_id_total_cost" created.';
    CREATE POLICY "select_policy_api_key_id_total_use" ON keyhippo.api_key_id_total_use
        USING (auth.uid ( ) = owner_id );
    RAISE LOG '[KeyHippo] Policy "select_policy_api_key_id_total_use" created.';
    -- Create triggers for user management
    CREATE OR REPLACE FUNCTION keyhippo.handle_new_user ( )
        RETURNS TRIGGER
        LANGUAGE plpgsql
        SECURITY DEFINER
        SET search_path = '' AS $$
        BEGIN
            INSERT INTO keyhippo.user_ids (id)
                VALUES (NEW.id);
            RETURN NEW;
END;
    $$;
    RAISE LOG '[KeyHippo] Function "handle_new_user" created.';
    CREATE TRIGGER on_auth_user_created
        AFTER INSERT ON auth.users
        FOR EACH ROW
        EXECUTE FUNCTION keyhippo.handle_new_user ( );
    RAISE LOG '[KeyHippo] Trigger "on_auth_user_created" created.';
    CREATE OR REPLACE FUNCTION keyhippo.create_user_api_key_secret ( )
        RETURNS TRIGGER
        LANGUAGE plpgsql
        SECURITY DEFINER
        SET search_path = extensions AS $$
DECLARE
    rand_bytes bytea := extensions.gen_random_bytes(32);
    user_api_key_secret text := encode(extensions.digest(rand_bytes, 'sha512'), 'hex');
BEGIN
    INSERT INTO vault.secrets (secret, name)
        VALUES (user_api_key_secret, NEW.id);
    RETURN NEW;
END;
    $$;
    RAISE LOG '[KeyHippo] Function "create_user_api_key_secret" created.';
    CREATE TRIGGER on_user_created__create_user_api_key_secret
        AFTER INSERT ON auth.users
        FOR EACH ROW
        EXECUTE FUNCTION keyhippo.create_user_api_key_secret ( );
    RAISE LOG '[KeyHippo] Trigger "on_user_created__create_user_api_key_secret" created.';
    CREATE OR REPLACE FUNCTION keyhippo.remove_user_vault_secrets ( )
        RETURNS TRIGGER
        LANGUAGE plpgsql
        SECURITY DEFINER
        SET search_path = keyhippo AS $$
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
    RAISE LOG '[KeyHippo] Function "remove_user_vault_secrets" created.';
    CREATE TRIGGER on_auth_user_deleted
        AFTER DELETE ON auth.users
        FOR EACH ROW
        EXECUTE FUNCTION keyhippo.remove_user_vault_secrets ( );
    RAISE LOG '[KeyHippo] Trigger "on_auth_user_deleted" created.';
    -- Create additional utility functions
    CREATE OR REPLACE FUNCTION keyhippo.get_api_key (id_of_user text, secret_id text )
        RETURNS text
        LANGUAGE plpgsql
        SECURITY DEFINER
        SET search_path = extensions AS $$
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
    RAISE LOG '[KeyHippo] Function "get_api_key" created.';
    CREATE OR REPLACE FUNCTION keyhippo.load_api_key_info (id_of_user text )
        RETURNS text[]
        LANGUAGE plpgsql
        SECURITY DEFINER
        SET search_path = extensions AS $$
DECLARE
    current_set jsonb;
    jwt_record RECORD;
    key_info jsonb[];
    vault_record RECORD;
BEGIN
    IF auth.uid () = id_of_user::uuid THEN
        FOR jwt_record IN
        SELECT
            secret_id
        FROM
            auth.jwts
        WHERE
            user_id = id_of_user::uuid LOOP
                SELECT
                    description INTO vault_record
                FROM
                    vault.decrypted_secrets
                WHERE
                    id = jwt_record.secret_id;
                current_set := jsonb_build_object('description', TO_JSONB (vault_record.description), 'id', TO_JSONB (jwt_record.secret_id));
                SELECT
                    INTO key_info array_append(key_info, current_set);
            END LOOP;
    END IF;
    RETURN key_info;
END;
    $$;
    RAISE LOG '[KeyHippo] Function "load_api_key_info" created.';
    -- Grant necessary permissions
    GRANT USAGE ON SCHEMA keyhippo TO authenticated;
    GRANT USAGE ON SCHEMA keyhippo TO anon;
    GRANT ALL ON FUNCTION keyhippo.create_api_key (TEXT, TEXT) TO authenticated;
    GRANT ALL ON FUNCTION keyhippo.revoke_api_key (TEXT, TEXT) TO authenticated;
    GRANT ALL ON FUNCTION keyhippo.get_api_key_metadata (UUID) TO authenticated;
    GRANT ALL ON FUNCTION keyhippo.get_api_key (TEXT, TEXT) TO authenticated;
    GRANT ALL ON FUNCTION keyhippo.load_api_key_info (TEXT) TO authenticated;
    GRANT ALL ON FUNCTION keyhippo.get_uid_for_key (TEXT) TO authenticated;
    GRANT ALL ON FUNCTION keyhippo.get_uid_for_key (TEXT) TO anon;
    GRANT SELECT ON ALL TABLES IN SCHEMA keyhippo TO authenticated;
    -- Set up vault secrets
    PERFORM
        keyhippo.setup_vault_secrets ();
    COMMENT ON FUNCTION keyhippo.setup_vault_secrets () IS 'Run this function to set up or update KeyHippo vault secrets';
    RAISE LOG '[KeyHippo] KeyHippo setup completed successfully.';
END;
$setup$;

CREATE OR REPLACE FUNCTION keyhippo.destructive_uninstall_keyhippo_with_cascade ()
    RETURNS VOID
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $uninstall$
BEGIN
    -- Log the start of the uninstallation
    RAISE LOG '[KeyHippo] Starting KeyHippo uninstallation...';
    -- Drop Row Level Security policies from KeyHippo tables
    DROP POLICY IF EXISTS "select_policy_api_key_id_created" ON keyhippo.api_key_id_created;
    DROP POLICY IF EXISTS "select_policy_api_key_id_last_used" ON keyhippo.api_key_id_last_used;
    DROP POLICY IF EXISTS "select_policy_api_key_id_name" ON keyhippo.api_key_id_name;
    DROP POLICY IF EXISTS "select_policy_api_key_id_owner_id" ON keyhippo.api_key_id_owner_id;
    DROP POLICY IF EXISTS "select_policy_api_key_id_permission" ON keyhippo.api_key_id_permission;
    DROP POLICY IF EXISTS "select_policy_api_key_id_revoked" ON keyhippo.api_key_id_revoked;
    DROP POLICY IF EXISTS "select_policy_api_key_id_success_rate" ON keyhippo.api_key_id_success_rate;
    DROP POLICY IF EXISTS "select_policy_api_key_id_total_cost" ON keyhippo.api_key_id_total_cost;
    DROP POLICY IF EXISTS "select_policy_api_key_id_total_use" ON keyhippo.api_key_id_total_use;
    -- Disable Row Level Security on KeyHippo tables
    ALTER TABLE IF EXISTS keyhippo.api_key_id_created DISABLE ROW LEVEL SECURITY;
    ALTER TABLE IF EXISTS keyhippo.api_key_id_last_used DISABLE ROW LEVEL SECURITY;
    ALTER TABLE IF EXISTS keyhippo.api_key_id_name DISABLE ROW LEVEL SECURITY;
    ALTER TABLE IF EXISTS keyhippo.api_key_id_owner_id DISABLE ROW LEVEL SECURITY;
    ALTER TABLE IF EXISTS keyhippo.api_key_id_permission DISABLE ROW LEVEL SECURITY;
    ALTER TABLE IF EXISTS keyhippo.api_key_id_revoked DISABLE ROW LEVEL SECURITY;
    ALTER TABLE IF EXISTS keyhippo.api_key_id_success_rate DISABLE ROW LEVEL SECURITY;
    ALTER TABLE IF EXISTS keyhippo.api_key_id_total_cost DISABLE ROW LEVEL SECURITY;
    ALTER TABLE IF EXISTS keyhippo.api_key_id_total_use DISABLE ROW LEVEL SECURITY;
    ALTER TABLE IF EXISTS keyhippo.user_ids DISABLE ROW LEVEL SECURITY;
    -- Drop triggers specifically created by KeyHippo
    DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
    DROP TRIGGER IF EXISTS on_user_created__create_user_api_key_secret ON auth.users;
    DROP TRIGGER IF EXISTS on_auth_user_deleted ON auth.users;
    -- Drop functions specifically created by KeyHippo
    DROP FUNCTION IF EXISTS keyhippo.handle_new_user ();
    DROP FUNCTION IF EXISTS keyhippo.create_user_api_key_secret ();
    DROP FUNCTION IF EXISTS keyhippo.remove_user_vault_secrets ();
    DROP FUNCTION IF EXISTS keyhippo.create_api_key (TEXT, TEXT);
    DROP FUNCTION IF EXISTS keyhippo.revoke_api_key (TEXT, TEXT);
    DROP FUNCTION IF EXISTS keyhippo.get_api_key_metadata (UUID);
    DROP FUNCTION IF EXISTS keyhippo.get_api_key (TEXT, TEXT);
    DROP FUNCTION IF EXISTS keyhippo.load_api_key_info (TEXT);
    DROP FUNCTION IF EXISTS keyhippo.key_uid ();
    DROP FUNCTION IF EXISTS keyhippo.setup_project_api_key_secret ();
    DROP FUNCTION IF EXISTS keyhippo.setup_project_jwt_secret ();
    DROP FUNCTION IF EXISTS keyhippo.setup_vault_secrets ();
    DROP FUNCTION IF EXISTS auth.keyhippo_check (UUID);
    -- Drop KeyHippo-specific tables
    DROP TABLE IF EXISTS keyhippo.api_key_id_created CASCADE;
    DROP TABLE IF EXISTS keyhippo.api_key_id_last_used CASCADE;
    DROP TABLE IF EXISTS keyhippo.api_key_id_name CASCADE;
    DROP TABLE IF EXISTS keyhippo.api_key_id_owner_id CASCADE;
    DROP TABLE IF EXISTS keyhippo.api_key_id_permission CASCADE;
    DROP TABLE IF EXISTS keyhippo.api_key_id_revoked CASCADE;
    DROP TABLE IF EXISTS keyhippo.api_key_id_success_rate CASCADE;
    DROP TABLE IF EXISTS keyhippo.api_key_id_total_cost CASCADE;
    DROP TABLE IF EXISTS keyhippo.api_key_id_total_use CASCADE;
    DROP TABLE IF EXISTS keyhippo.user_ids CASCADE;
    -- Drop the jwts table in the auth schema
    DROP TABLE IF EXISTS auth.jwts CASCADE;
    -- Drop the keyhippo schema if it exists
    DROP SCHEMA IF EXISTS keyhippo CASCADE;
    -- Drop the keyhippo extension if it exists
    DROP EXTENSION IF EXISTS "keyhippo@keyhippo" CASCADE;
    -- Log the completion of the uninstallation
    RAISE LOG '[KeyHippo] KeyHippo uninstallation completed successfully.';
END;
$uninstall$;

SELECT
    keyhippo.setup ();

DROP FUNCTION keyhippo.setup ();

DROP FUNCTION keyhippo.setup_vault_secrets ();

DROP FUNCTION keyhippo.setup_project_jwt_secret ();

DROP FUNCTION keyhippo.setup_project_api_key_secret ();
