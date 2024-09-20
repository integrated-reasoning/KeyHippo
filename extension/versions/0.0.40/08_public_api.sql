-- 08_public_api.sql
-- Function to get an API key
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
        key := encode(hmac(jwt, user_api_key_secret, 'sha512'), 'hex');
    END IF;
    RETURN key;
END;
$$;

-- Function to create an API key (public-facing wrapper)
CREATE OR REPLACE FUNCTION keyhippo.create_api_key_public (key_description text)
    RETURNS TABLE (
        api_key text,
        api_key_id uuid)
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    id_of_user uuid;
BEGIN
    id_of_user := auth.uid ();
    IF id_of_user IS NULL THEN
        RAISE EXCEPTION 'User must be authenticated to create an API key';
    END IF;
    RETURN QUERY
    SELECT
        *
    FROM
        keyhippo.create_api_key (id_of_user::text, key_description);
END;
$$;

-- Function to rotate an API key (public-facing wrapper)
CREATE OR REPLACE FUNCTION keyhippo.rotate_api_key_public (p_api_key_id uuid)
    RETURNS TABLE (
        new_api_key text,
        new_api_key_id uuid)
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        *
    FROM
        keyhippo.rotate_api_key (p_api_key_id);
END;
$$;

-- Function to revoke an API key (public-facing wrapper)
CREATE OR REPLACE FUNCTION keyhippo.revoke_api_key_public (secret_id text)
    RETURNS VOID
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    id_of_user uuid;
BEGIN
    id_of_user := auth.uid ();
    IF id_of_user IS NULL THEN
        RAISE EXCEPTION 'User must be authenticated to revoke an API key';
    END IF;
    PERFORM
        keyhippo.revoke_api_key (id_of_user::text, secret_id);
END;
$$;

-- Function to get API key metadata (public-facing wrapper)
CREATE OR REPLACE FUNCTION keyhippo.get_api_key_metadata_public ()
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
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    id_of_user uuid;
BEGIN
    id_of_user := auth.uid ();
    IF id_of_user IS NULL THEN
        RAISE EXCEPTION 'User must be authenticated to get API key metadata';
    END IF;
    RETURN QUERY
    SELECT
        *
    FROM
        keyhippo.get_api_key_metadata (id_of_user);
END;
$$;

-- Function to load API key info (public-facing wrapper)
CREATE OR REPLACE FUNCTION keyhippo.load_api_key_info_public ()
    RETURNS jsonb
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    id_of_user uuid;
BEGIN
    id_of_user := auth.uid ();
    IF id_of_user IS NULL THEN
        RAISE EXCEPTION 'User must be authenticated to load API key info';
    END IF;
    RETURN keyhippo.load_api_key_info (id_of_user::text);
END;
$$;
