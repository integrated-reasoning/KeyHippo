-- 04_key_validation.sql
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

-- Function to validate API key and return user ID
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

-- Function to check if the request contains a valid API key
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

-- Set the check_request function as a pre-request check for PostgREST
ALTER ROLE authenticator SET pgrst.db_pre_request = 'keyhippo.check_request';

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
