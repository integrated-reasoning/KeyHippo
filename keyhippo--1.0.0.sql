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
CREATE OR REPLACE FUNCTION public.setup_keyhippo ()
    RETURNS VOID
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $$
BEGIN
    -- Create necessary schemas
    CREATE SCHEMA IF NOT EXISTS auth;
    CREATE SCHEMA IF NOT EXISTS vault;
    -- Create jwts table in auth schema
    CREATE TABLE IF NOT EXISTS auth.jwts (
        secret_id uuid PRIMARY KEY,
        user_id uuid,
        CONSTRAINT jwts_secret_id_fkey FOREIGN KEY (secret_id ) REFERENCES vault.secrets (id ) ON DELETE CASCADE
    );
    -- Create user_ids table
    CREATE TABLE IF NOT EXISTS public.user_ids (
        id uuid PRIMARY KEY
    );
    -- Create API key related tables
    CREATE TABLE IF NOT EXISTS public.api_key_id_owner_id (
        api_key_id uuid PRIMARY KEY,
        user_id uuid NOT NULL,
        owner_id uuid,
        CONSTRAINT api_key_id_owner_id_user_id_fkey FOREIGN KEY (user_id ) REFERENCES public.user_ids (id ) ON DELETE CASCADE,
        CONSTRAINT api_key_id_owner_id_api_key_id_owner_id_key UNIQUE (api_key_id, owner_id )
    );
    CREATE TABLE IF NOT EXISTS public.api_key_id_name (
        api_key_id uuid PRIMARY KEY,
        name text NOT NULL,
        owner_id uuid,
        CONSTRAINT api_key_id_name_api_key_id_fkey FOREIGN KEY (api_key_id ) REFERENCES public.api_key_id_owner_id (api_key_id ) ON DELETE CASCADE,
        CONSTRAINT api_key_id_name_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id ) REFERENCES public.api_key_id_owner_id (api_key_id, owner_id )
    );
    CREATE TABLE IF NOT EXISTS public.api_key_id_permission (
        api_key_id uuid PRIMARY KEY,
        permission text NOT NULL,
        owner_id uuid,
        CONSTRAINT api_key_id_permission_api_key_id_fkey FOREIGN KEY (api_key_id ) REFERENCES public.api_key_id_owner_id (api_key_id ) ON DELETE CASCADE,
        CONSTRAINT api_key_id_permission_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id ) REFERENCES public.api_key_id_owner_id (api_key_id, owner_id )
    );
    CREATE TABLE IF NOT EXISTS public.api_key_id_created (
        api_key_id uuid PRIMARY KEY,
        created timestamptz NOT NULL,
        owner_id uuid,
        CONSTRAINT api_key_id_created_api_key_id_fkey FOREIGN KEY (api_key_id ) REFERENCES public.api_key_id_owner_id (api_key_id ) ON DELETE CASCADE,
        CONSTRAINT api_key_id_created_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id ) REFERENCES public.api_key_id_owner_id (api_key_id, owner_id )
    );
    CREATE TABLE IF NOT EXISTS public.api_key_id_last_used (
        api_key_id uuid PRIMARY KEY,
        last_used timestamptz,
        owner_id uuid,
        CONSTRAINT api_key_id_last_used_api_key_id_fkey FOREIGN KEY (api_key_id ) REFERENCES public.api_key_id_owner_id (api_key_id ) ON DELETE CASCADE,
        CONSTRAINT api_key_id_last_used_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id ) REFERENCES public.api_key_id_owner_id (api_key_id, owner_id )
    );
    CREATE TABLE IF NOT EXISTS public.api_key_id_total_use (
        api_key_id uuid PRIMARY KEY,
        total_uses bigint DEFAULT 0 NOT NULL,
        owner_id uuid,
        CONSTRAINT api_key_id_total_use_api_key_id_fkey FOREIGN KEY (api_key_id ) REFERENCES public.api_key_id_owner_id (api_key_id ) ON DELETE CASCADE,
        CONSTRAINT api_key_id_total_use_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id ) REFERENCES public.api_key_id_owner_id (api_key_id, owner_id )
    );
    CREATE TABLE IF NOT EXISTS public.api_key_id_success_rate (
        api_key_id uuid PRIMARY KEY,
        success_rate numeric(5, 2 ) NOT NULL,
        owner_id uuid,
        CONSTRAINT api_key_id_success_rate_api_key_id_fkey FOREIGN KEY (api_key_id ) REFERENCES public.api_key_id_owner_id (api_key_id ) ON DELETE CASCADE,
        CONSTRAINT api_key_id_success_rate_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id ) REFERENCES public.api_key_id_owner_id (api_key_id, owner_id ),
        CONSTRAINT api_key_reference_success_rate_success_rate_check CHECK ((success_rate >= 0 AND success_rate <= 100 ) )
    );
    CREATE TABLE IF NOT EXISTS public.api_key_id_total_cost (
        api_key_id uuid PRIMARY KEY,
        total_cost numeric(12, 2 ) DEFAULT 0 NOT NULL,
        owner_id uuid,
        CONSTRAINT api_key_id_total_cost_api_key_id_fkey FOREIGN KEY (api_key_id ) REFERENCES public.api_key_id_owner_id (api_key_id ) ON DELETE CASCADE,
        CONSTRAINT api_key_id_total_cost_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id ) REFERENCES public.api_key_id_owner_id (api_key_id, owner_id )
    );
    CREATE TABLE IF NOT EXISTS public.api_key_id_revoked (
        api_key_id uuid PRIMARY KEY,
        revoked_at timestamptz DEFAULT now( ) NOT NULL,
        owner_id uuid,
        CONSTRAINT api_key_id_revoked_api_key_id_fkey FOREIGN KEY (api_key_id ) REFERENCES public.api_key_id_owner_id (api_key_id ) ON DELETE CASCADE,
        CONSTRAINT api_key_id_revoked_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id ) REFERENCES public.api_key_id_owner_id (api_key_id, owner_id )
    );
    -- Function to set up project_api_key_secret
    CREATE OR REPLACE FUNCTION keyhippo_setup_project_api_key_secret ( )
        RETURNS VOID
        LANGUAGE plpgsql
        SECURITY DEFINER AS
$$ DECLARE secret_exists boolean;

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
        VALUES (encode(digest(gen_random_bytes(32), 'sha512'), 'hex'), 'project_api_key_secret');

RAISE INFO 'Created project_api_key_secret in vault.secrets';

ELSE
    RAISE INFO 'project_api_key_secret already exists in vault.secrets';

END IF;

END;

$$;

-- Function to set up project_jwt_secret
CREATE OR REPLACE FUNCTION keyhippo_setup_project_jwt_secret ()
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
            VALUES (encode(digest(gen_random_bytes(32), 'sha256'), 'hex'), 'project_jwt_secret');
        RAISE INFO 'Created project_jwt_secret in vault.secrets';
    ELSE
        RAISE INFO 'project_jwt_secret already exists in vault.secrets';
    END IF;
END;
$$;

-- Function to set up both secrets
CREATE OR REPLACE FUNCTION keyhippo_setup_vault_secrets ()
    RETURNS VOID
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $$
BEGIN
    PERFORM
        keyhippo_setup_project_api_key_secret ();
    PERFORM
        keyhippo_setup_project_jwt_secret ();
    RAISE INFO 'KeyHippo vault secrets setup complete';
END;
$$;

-- Create function to generate and store API key
CREATE OR REPLACE FUNCTION public.create_api_key (id_of_user text, key_description text)
    RETURNS text
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $$
DECLARE
    api_key text;
    expires bigint;
    jti uuid := gen_random_uuid ();
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
        RAISE EXCEPTION 'Unauthorized: Invalid user ID';
    END IF;
    -- Ensure the user exists in the user_ids table
    INSERT INTO public.user_ids (id)
        VALUES (id_of_user::uuid)
    ON CONFLICT (id)
        DO NOTHING;
    SELECT
        INTO time_stamp EXTRACT(EPOCH FROM now())::bigint;
    SELECT
        INTO expires time_stamp + EXTRACT(EPOCH FROM INTERVAL '100 years')::bigint;
    jwt_body := jsonb_build_object('role', 'authenticated', 'aud', 'authenticated', 'iss', 'supabase', 'sub', to_jsonb (id_of_user), 'iat', to_jsonb (time_stamp), 'exp', to_jsonb (expires), 'jti', to_jsonb (jti));
    SELECT
        decrypted_secret INTO user_api_key_secret
    FROM
        vault.decrypted_secrets
    WHERE
        name = id_of_user;
    SELECT
        decrypted_secret INTO project_api_key_secret
    FROM
        vault.decrypted_secrets
    WHERE
        name = 'project_api_key_secret';
    SELECT
        decrypted_secret INTO project_jwt_secret
    FROM
        vault.decrypted_secrets
    WHERE
        name = 'project_jwt_secret';
    SELECT
        INTO jwt sign(jwt_body::json, project_jwt_secret);
    api_key := encode(hmac(jwt, user_api_key_secret, 'sha512'), 'hex');
    project_hash := encode(hmac(api_key, project_api_key_secret, 'sha512'), 'hex');
    INSERT INTO vault.secrets (secret, name, description)
        VALUES (jwt, project_hash, key_description)
    RETURNING
        id INTO secret_uuid;
    INSERT INTO auth.jwts (secret_id, user_id)
        VALUES (secret_uuid, id_of_user::uuid);
    -- Insert into api_key_id_owner_id
    INSERT INTO public.api_key_id_owner_id (api_key_id, user_id, owner_id)
        VALUES (secret_uuid, id_of_user::uuid, id_of_user::uuid);
    -- Insert into api_key_id_name
    INSERT INTO public.api_key_id_name (api_key_id, name, owner_id)
        VALUES (secret_uuid, key_description, id_of_user::uuid);
    -- Insert into api_key_id_permission (assuming default permission, update as needed)
    INSERT INTO public.api_key_id_permission (api_key_id, permission, owner_id)
        VALUES (secret_uuid, 'readOnly', id_of_user::uuid);
    -- Insert into api_key_id_created
    INSERT INTO public.api_key_id_created (api_key_id, created, owner_id)
        VALUES (secret_uuid, now(), id_of_user::uuid);
    -- Initialize other tables with default values
    INSERT INTO public.api_key_id_total_use (api_key_id, total_uses, owner_id)
        VALUES (secret_uuid, 0, id_of_user::uuid);
    INSERT INTO public.api_key_id_success_rate (api_key_id, success_rate, owner_id)
        VALUES (secret_uuid, 100.00, id_of_user::uuid);
    INSERT INTO public.api_key_id_total_cost (api_key_id, total_cost, owner_id)
        VALUES (secret_uuid, 0.00, id_of_user::uuid);
    RETURN api_key;
END;
$$;

-- Create function to validate API key
CREATE OR REPLACE FUNCTION auth.key_uid ()
    RETURNS uuid
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $$
DECLARE
    project_hash text;
    project_api_key_secret text;
    secret_uuid uuid;
    user_api_key text;
BEGIN
    SELECT
        current_setting('request.headers', TRUE)::json ->> 'authorization' INTO user_api_key;
    SELECT
        decrypted_secret INTO project_api_key_secret
    FROM
        vault.decrypted_secrets
    WHERE
        name = 'project_api_key_secret';
    project_hash := encode(hmac(user_api_key, project_api_key_secret, 'sha512'), 'hex');
    SELECT
        id INTO secret_uuid
    FROM
        vault.secrets
    WHERE
        name = project_hash;
    IF secret_uuid IS NOT NULL THEN
        RETURN (
            SELECT
                user_id
            FROM
                auth.jwts
            WHERE
                secret_id = secret_uuid);
    ELSE
        RETURN NULL;
    END IF;
END;
$$;

-- Create function to revoke API key
CREATE OR REPLACE FUNCTION public.revoke_api_key (id_of_user text, secret_id text)
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
            public.api_key_id_owner_id
        WHERE
            api_key_id = secret_id::uuid;
        -- Check if the api_key_id exists in api_key_id_owner_id
        IF NOT FOUND THEN
            RAISE EXCEPTION 'API key not found: %', secret_id;
        END IF;
        -- Insert into api_key_id_revoked table
        INSERT INTO public.api_key_id_revoked (api_key_id, owner_id)
            VALUES (secret_id::uuid, owner_id);
        -- Delete from vault.secrets
        DELETE FROM vault.secrets
        WHERE id = secret_id::uuid;
    ELSE
        RAISE EXCEPTION 'Unauthorized: Invalid user ID';
    END IF;
END;
$$;

-- Create function to get API key metadata
CREATE OR REPLACE FUNCTION public.get_api_key_metadata (p_user_id uuid)
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
        COALESCE(s.success_rate, 0.0)::double PRECISION AS success_rate,
        COALESCE(tc.total_cost, 0.0)::double PRECISION AS total_cost,
        r.revoked_at AS revoked
    FROM
        public.api_key_id_owner_id u
    LEFT JOIN public.api_key_id_name n ON u.api_key_id = n.api_key_id
    LEFT JOIN public.api_key_id_permission p ON u.api_key_id = p.api_key_id
    LEFT JOIN public.api_key_id_last_used l ON u.api_key_id = l.api_key_id
    LEFT JOIN public.api_key_id_created c ON u.api_key_id = c.api_key_id
    LEFT JOIN public.api_key_id_total_use t ON u.api_key_id = t.api_key_id
    LEFT JOIN public.api_key_id_success_rate s ON u.api_key_id = s.api_key_id
    LEFT JOIN public.api_key_id_total_cost tc ON u.api_key_id = tc.api_key_id
    LEFT JOIN public.api_key_id_revoked r ON u.api_key_id = r.api_key_id
WHERE
    u.user_id = p_user_id;
END;
$$;

-- Create helper function for RLS
CREATE OR REPLACE FUNCTION auth.keyhippo_check (owner_id uuid)
    RETURNS boolean
    LANGUAGE sql
    SECURITY DEFINER
    AS $$
    SELECT
        (auth.uid () = owner_id)
        OR (auth.key_uid () = owner_id);
$$;

-- Enable Row Level Security on all tables
ALTER TABLE public.api_key_id_created ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.api_key_id_last_used ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.api_key_id_name ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.api_key_id_owner_id ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.api_key_id_permission ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.api_key_id_revoked ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.api_key_id_success_rate ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.api_key_id_total_cost ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.api_key_id_total_use ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.user_ids ENABLE ROW LEVEL SECURITY;

-- Create RLS policies for each table
CREATE POLICY "select_policy_api_key_id_created" ON public.api_key_id_created
    USING (auth.uid () = owner_id);

CREATE POLICY "select_policy_api_key_id_last_used" ON public.api_key_id_last_used
    USING (auth.uid () = owner_id);

CREATE POLICY "select_policy_api_key_id_name" ON public.api_key_id_name
    USING (auth.uid () = owner_id);

CREATE POLICY "select_policy_api_key_id_owner_id" ON public.api_key_id_owner_id
    USING (auth.uid () = owner_id);

CREATE POLICY "select_policy_api_key_id_permission" ON public.api_key_id_permission
    USING (auth.uid () = owner_id);

CREATE POLICY "select_policy_api_key_id_revoked" ON public.api_key_id_revoked
    USING (auth.uid () = owner_id);

CREATE POLICY "select_policy_api_key_id_success_rate" ON public.api_key_id_success_rate
    USING (auth.uid () = owner_id);

CREATE POLICY "select_policy_api_key_id_total_cost" ON public.api_key_id_total_cost
    USING (auth.uid () = owner_id);

CREATE POLICY "select_policy_api_key_id_total_use" ON public.api_key_id_total_use
    USING (auth.uid () = owner_id);

-- Create triggers for user management
CREATE OR REPLACE FUNCTION public.handle_new_user ()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = ''
    AS $$
BEGIN
    INSERT INTO public.user_ids (id)
        VALUES (NEW.id);
    RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user ();

CREATE OR REPLACE FUNCTION public.create_user_api_key_secret ()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = extensions
    AS $$
DECLARE
    rand_bytes bytea := gen_random_bytes(32);
    user_api_key_secret text := encode(digest(rand_bytes, 'sha512'), 'hex');
BEGIN
    INSERT INTO vault.secrets (secret, name)
        VALUES (user_api_key_secret, NEW.id);
    RETURN NEW;
END;
$$;

CREATE TRIGGER on_user_created__create_user_api_key_secret
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.create_user_api_key_secret ();

CREATE OR REPLACE FUNCTION public.remove_user_vault_secrets ()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
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
    EXECUTE FUNCTION public.remove_user_vault_secrets ();

-- Create additional utility functions
CREATE OR REPLACE FUNCTION public.get_api_key (id_of_user text, secret_id text)
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
        key := encode(hmac(jwt, user_api_key_secret, 'sha512'), 'hex');
    END IF;
    RETURN key;
END;
$$;

CREATE OR REPLACE FUNCTION public.load_api_key_info (id_of_user text)
    RETURNS text[]
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = extensions
    AS $$
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

-- Grant necessary permissions
GRANT USAGE ON SCHEMA public TO authenticated;

GRANT USAGE ON SCHEMA public TO anon;

GRANT ALL ON FUNCTION public.create_api_key (TEXT, TEXT) TO authenticated;

GRANT ALL ON FUNCTION public.revoke_api_key (TEXT, TEXT) TO authenticated;

GRANT ALL ON FUNCTION public.get_api_key_metadata (UUID) TO authenticated;

GRANT ALL ON FUNCTION public.get_api_key (TEXT, TEXT) TO authenticated;

GRANT ALL ON FUNCTION public.load_api_key_info (TEXT) TO authenticated;

GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;

SELECT
    keyhippo_setup_vault_secrets ();

COMMENT ON FUNCTION keyhippo_setup_vault_secrets () IS 'Run this function to set up or update KeyHippo vault secrets';

RAISE INFO 'KeyHippo setup completed successfully.';

END;

$$;

-- To ensure everything worked:
-- SELECT * FROM vault.decrypted_secrets
-- WHERE name IN ('project_api_key_secret', 'project_jwt_secret');
--
-- Also, create a new user manually in supabase and run this query using their role:
-- SELECT create_api_key('uuid-of-new-user', 'Test API Key');
