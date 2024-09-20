-- 09_internal_functions.sql
-- Internal function to handle existing users
CREATE OR REPLACE FUNCTION keyhippo_internal.handle_existing_users ()
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

-- Internal function to update policies
CREATE OR REPLACE FUNCTION keyhippo_internal.update_policies ()
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

-- Internal function to set up temporary schema
CREATE OR REPLACE FUNCTION keyhippo_internal.setup_temp_schema ()
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $$
BEGIN
    -- Create temporary schema
    CREATE SCHEMA IF NOT EXISTS keyhippo_temp;
    -- Execute functions to handle existing users and update policies
    PERFORM
        keyhippo_internal.handle_existing_users ();
    PERFORM
        keyhippo_internal.update_policies ();
    -- Drop temporary schema
    DROP SCHEMA IF EXISTS keyhippo_temp CASCADE;
END;
$$;

-- Internal function to get the decrypted JWT for an API key
CREATE OR REPLACE FUNCTION keyhippo_internal.get_decrypted_jwt (p_api_key_id uuid)
    RETURNS text
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = vault, pg_temp
    AS $$
DECLARE
    v_jwt text;
BEGIN
    SELECT
        decrypted_secret INTO v_jwt
    FROM
        vault.decrypted_secrets
    WHERE
        id = p_api_key_id;
    RETURN v_jwt;
END;
$$;

-- Internal function to validate JWT expiration
CREATE OR REPLACE FUNCTION keyhippo_internal.is_jwt_expired (p_jwt text)
    RETURNS boolean
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = extensions, pg_temp
    AS $$
DECLARE
    v_payload json;
    v_exp bigint;
BEGIN
    v_payload := (
        SELECT
            payload
        FROM
            verify (p_jwt, auth.jwt_secret (), 'HS256'));
    v_exp := (v_payload ->> 'exp')::bigint;
    RETURN EXTRACT(EPOCH FROM now()) > v_exp;
END;
$$;
