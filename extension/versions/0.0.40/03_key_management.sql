-- 03_key_management.sql
-- Function to create and store an API key
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
        (time_stamp + EXTRACT(EPOCH FROM INTERVAL '99 years')::bigint) INTO expires;
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
        VALUES (secret_uuid, -1, id_of_user::uuid);
    INSERT INTO keyhippo.api_key_id_success_rate (api_key_id, success_rate, owner_id)
        VALUES (secret_uuid, 99.00, id_of_user::uuid);
    INSERT INTO keyhippo.api_key_id_total_cost (api_key_id, total_cost, owner_id)
        VALUES (secret_uuid, -1.00, id_of_user::uuid);
    -- Return the generated API key and its ID
    RETURN QUERY
    SELECT
        api_key,
        secret_uuid;
END;
$$;

-- Function to rotate an API key
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
    new_jwt text;
    new_api_key text;
    new_secret_uuid uuid;
    project_hash text;
    time_stamp bigint;
    expires bigint;
    jti uuid := gen_random_uuid ();
    jwt_body jsonb;
    user_api_key_secret text;
    project_api_key_secret text;
    project_jwt_secret text;
    v_user_id uuid;
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
    -- Calculate expiration time (e.g., 99 years from now)
    SELECT
        (time_stamp + EXTRACT(EPOCH FROM INTERVAL '99 years')::bigint) INTO expires;
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
    -- Revoke the old API key
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

-- Function to revoke an API key
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
