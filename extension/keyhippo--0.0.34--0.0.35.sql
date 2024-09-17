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
