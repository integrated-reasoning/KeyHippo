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

CREATE SCHEMA IF NOT EXISTS keyhippo_rbac;

CREATE SCHEMA IF NOT EXISTS keyhippo_abac;

-- Ensure required extensions are installed
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Create RBAC tables
CREATE TABLE IF NOT EXISTS keyhippo_rbac.groups (
    id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid (),
    name text UNIQUE NOT NULL,
    description text
);

CREATE TABLE IF NOT EXISTS keyhippo_rbac.roles (
    id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid (),
    name text NOT NULL,
    description text,
    group_id uuid NOT NULL REFERENCES keyhippo_rbac.groups (id) ON DELETE CASCADE,
    parent_role_id uuid REFERENCES keyhippo_rbac.roles (id) ON DELETE SET NULL,
    UNIQUE (name, group_id)
);

CREATE TABLE IF NOT EXISTS keyhippo_rbac.permissions (
    id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid (),
    name text UNIQUE NOT NULL,
    description text
);

CREATE TABLE IF NOT EXISTS keyhippo_rbac.role_permissions (
    role_id uuid NOT NULL REFERENCES keyhippo_rbac.roles (id) ON DELETE CASCADE,
    permission_id uuid NOT NULL REFERENCES keyhippo_rbac.permissions (id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE IF NOT EXISTS keyhippo_rbac.user_group_roles (
    user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
    group_id uuid NOT NULL REFERENCES keyhippo_rbac.groups (id) ON DELETE CASCADE,
    role_id uuid NOT NULL REFERENCES keyhippo_rbac.roles (id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, group_id, role_id)
);

CREATE TABLE IF NOT EXISTS keyhippo_rbac.claims_cache (
    user_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
    rbac_claims jsonb DEFAULT '{}' ::jsonb
);

-- Create ABAC tables
CREATE TABLE IF NOT EXISTS keyhippo_abac.user_attributes (
    user_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
    attributes jsonb DEFAULT '{}' ::jsonb
);

CREATE TABLE IF NOT EXISTS keyhippo_abac.policies (
    id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid (),
    name text UNIQUE NOT NULL,
    description text,
    policy jsonb NOT NULL
);

-- Create KeyHippo tables
CREATE TABLE keyhippo.scopes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid (),
    name text NOT NULL UNIQUE,
    description text
);

CREATE TABLE IF NOT EXISTS keyhippo.scope_permissions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid (),
    scope_id uuid NOT NULL REFERENCES keyhippo.scopes (id),
    permission_id uuid NOT NULL REFERENCES keyhippo_rbac.permissions (id),
    UNIQUE (scope_id, permission_id)
);

CREATE TABLE keyhippo.api_key_metadata (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
    scope_id uuid REFERENCES keyhippo.scopes (id),
    description text,
    prefix text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now(),
    last_used_at timestamptz,
    expires_at timestamptz NOT NULL DEFAULT (now() + interval '100 years'),
    is_revoked boolean NOT NULL DEFAULT FALSE
);

CREATE TABLE keyhippo.group_permissions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid (),
    group_id uuid NOT NULL REFERENCES keyhippo_rbac.groups (id),
    permission_id uuid NOT NULL REFERENCES keyhippo_rbac.permissions (id),
    UNIQUE (group_id, permission_id)
);

CREATE TABLE keyhippo.api_key_secrets (
    key_metadata_id uuid PRIMARY KEY REFERENCES keyhippo.api_key_metadata (id) ON DELETE CASCADE,
    key_hash text NOT NULL
);

-- Create indexes
CREATE INDEX idx_api_key_metadata_user_id ON keyhippo.api_key_metadata (user_id);

CREATE INDEX IF NOT EXISTS idx_user_attributes_gin ON keyhippo_abac.user_attributes USING gin (attributes);

CREATE INDEX IF NOT EXISTS idx_claims_cache_gin ON keyhippo_rbac.claims_cache USING gin (rbac_claims);

CREATE OR REPLACE FUNCTION keyhippo.random_prefix ()
    RETURNS text
    LANGUAGE sql
    AS $$
    SELECT
        -- 24 bytes generate 32 base64 characters (~192 bits of entropy)
        -- 'base64' encoding gives ~32 characters
        encode(extensions.gen_random_bytes(24), 'base64')
        -- Probability of a collision based on the prefix length:
        --
        -- The random prefix is generated by encoding 24 bytes (192 bits) of random data using base64 encoding.
        -- Base64 encoding of 24 bytes results in a string of approximately 32 characters. Each character
        -- can be one of 64 possible values (A-Z, a-z, 0-9, +, /), yielding:
        --
        --     N = 64^32 ≈ 1.1579 × 10^58 possible unique prefixes.
        --
        -- Using the "birthday paradox" formula, the probability of a collision after
        -- generating 'n' random prefixes is:
        --
        --     P(collision) ≈ 1 - exp(-n^2 / (2 * N))
        --
        -- | Number of Prefixes Generated (n) | Probability of Collision (P) |
        -- |----------------------------------|------------------------------|
        -- | 1 billion (10^9)                 | 4.32 × 10^-39                |
        -- | 1 trillion (10^12)               | 4.32 × 10^-33                |
        -- | 1 quadrillion (10^15)            | 4.32 × 10^-27                |
        --
$$;

-- Function to create an API key
CREATE OR REPLACE FUNCTION keyhippo.create_api_key (key_description text, scope_name text DEFAULT NULL)
    RETURNS TABLE (
        api_key text,
        api_key_id uuid)
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    random_bytes bytea;
    new_api_key text;
    new_api_key_id uuid;
    authenticated_user_id uuid;
    prefix text;
    scope_id uuid;
BEGIN
    -- Get the authenticated user ID
    authenticated_user_id := auth.uid ();
    -- Check if the user is authenticated
    IF authenticated_user_id IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: User not authenticated';
    END IF;
    -- Validate key description length and format
    IF LENGTH(key_description) > 255 OR key_description !~ '^[a-zA-Z0-9_ \-]*$' THEN
        RAISE EXCEPTION '[KeyHippo] Invalid key description';
    END IF;
    -- Handle scope
    IF scope_name IS NULL THEN
        -- Default to user-specific scope
        scope_id := NULL;
    ELSE
        -- Get the scope_id for the provided scope_name
        SELECT
            id INTO scope_id
        FROM
            keyhippo.scopes
        WHERE
            name = scope_name;
        IF scope_id IS NULL THEN
            RAISE EXCEPTION '[KeyHippo] Invalid scope';
        END IF;
    END IF;
    -- Generate 64 bytes of random data for the API key
    random_bytes := extensions.gen_random_bytes(64);
    -- Generate SHA-512 hash of the random bytes and encode as hex (128 characters)
    new_api_key := encode(extensions.digest(random_bytes, 'sha512'), 'hex');
    -- Generate a new UUID for the API key
    new_api_key_id := extensions.gen_random_uuid ();
    -- Generate a unique 32-character prefix
    prefix := keyhippo.random_prefix ();
    -- Attempt to insert the metadata with the unique prefix
    BEGIN
        INSERT INTO keyhippo.api_key_metadata (id, user_id, description, prefix, scope_id)
            VALUES (new_api_key_id, authenticated_user_id, key_description, prefix, scope_id);
    EXCEPTION
        WHEN unique_violation THEN
            RAISE EXCEPTION '[KeyHippo] Prefix collision occurred, unable to insert API key metadata';
    END;
    -- Store the SHA-512 hash of the API key in the secrets table
    INSERT INTO keyhippo.api_key_secrets (key_metadata_id, key_hash)
        VALUES (new_api_key_id, encode(extensions.digest(new_api_key, 'sha512'), 'hex'));
    -- Return the concatenated API key (prefix + key) and its ID
    RETURN QUERY
    SELECT
        prefix || new_api_key,
        new_api_key_id;
END;

$$;

-- Function to verify an API key
CREATE OR REPLACE FUNCTION keyhippo.verify_api_key (api_key text)
    RETURNS TABLE (
        user_id uuid,
        scope_id uuid,
        permissions text[])
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    metadata_id uuid;
    prefix_part text;
    key_part text;
    stored_key_hash text;
    computed_hash text;
    v_user_id uuid;
    v_scope_id uuid;
BEGIN
    -- Ensure the API key is long enough to contain the key part (128 characters for SHA-512 hex)
    IF LENGTH(api_key) <= 128 THEN
        RAISE EXCEPTION 'Invalid API key format';
    END IF;
    -- Split the API key into prefix and key parts
    prefix_part :=
    LEFT (api_key,
        LENGTH(api_key) - 128);
    key_part :=
    RIGHT (api_key,
        128);
    -- Retrieve the metadata using the prefix
    SELECT
        m.id,
        m.user_id,
        m.scope_id INTO metadata_id,
        v_user_id,
        v_scope_id
    FROM
        keyhippo.api_key_metadata m
    WHERE
        m.prefix = prefix_part
        AND NOT m.is_revoked
        AND m.expires_at > NOW();
    -- If no metadata found or not valid, return NULL
    IF metadata_id IS NULL THEN
        RETURN;
    END IF;
    -- Retrieve the stored hash from secrets
    SELECT
        key_hash INTO stored_key_hash
    FROM
        keyhippo.api_key_secrets s
    WHERE
        s.key_metadata_id = metadata_id;
    -- Compute the SHA-512 hash of the provided key part
    computed_hash := encode(extensions.digest(key_part, 'sha512'), 'hex');
    -- Verify the key by comparing the computed hash with the stored hash
    IF computed_hash = stored_key_hash THEN
        -- Update last_used_at if necessary
        UPDATE
            keyhippo.api_key_metadata
        SET
            last_used_at = NOW()
        WHERE
            id = metadata_id
            AND (last_used_at IS NULL
                OR last_used_at < NOW() - INTERVAL '1 minute');
        -- Return user_id, scope_id, and permissions
        RETURN QUERY
        SELECT
            v_user_id,
            v_scope_id,
            ARRAY_AGG(DISTINCT p.name)::text[]
        FROM
            keyhippo.api_key_metadata akm
        LEFT JOIN keyhippo.scope_permissions sp ON akm.scope_id = sp.scope_id
        LEFT JOIN keyhippo_rbac.permissions p ON sp.permission_id = p.id
    WHERE
        akm.id = metadata_id
    GROUP BY
        v_user_id,
        v_scope_id;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION keyhippo.key_has_permission (api_key text, required_permission text)
    RETURNS boolean
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    key_permissions text[];
BEGIN
    SELECT
        permissions INTO key_permissions
    FROM
        keyhippo.verify_api_key (api_key);
    RETURN required_permission = ANY (key_permissions);
END;
$$;

-- Function to get user_id and scope from API key or JWT
CREATE OR REPLACE FUNCTION keyhippo.current_user_context ()
    RETURNS TABLE (
        user_id uuid,
        scope_id uuid)
    LANGUAGE plpgsql
    SECURITY INVOKER
    SET search_path = pg_temp
    AS $$
DECLARE
    api_key text;
    v_user_id uuid;
    v_scope_id uuid;
BEGIN
    api_key := current_setting('request.headers', TRUE)::json ->> 'x-api-key';
    IF api_key IS NOT NULL THEN
        SELECT
            user_id,
            scope_id INTO v_user_id,
            v_scope_id
        FROM
            keyhippo.verify_api_key (api_key);
        IF v_user_id IS NOT NULL THEN
            RETURN QUERY
            SELECT
                v_user_id,
                v_scope_id;
            RETURN;
        END IF;
    END IF;
    RETURN QUERY
    SELECT
        auth.uid (),
        NULL::uuid;
END;
$$;

-- Function to revoke an API key
CREATE OR REPLACE FUNCTION keyhippo.revoke_api_key (api_key_id uuid)
    RETURNS boolean
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    success boolean;
    c_user_id uuid;
    c_scope_id uuid;
BEGIN
    SELECT
        user_id,
        scope_id INTO c_user_id,
        c_scope_id
    FROM
        keyhippo.current_user_context ();
    IF c_user_id IS NULL THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;
    -- Update to set is_revoked only if it's not already revoked
    -- and the user has permission (either they created the key or it's within their scope)
    UPDATE
        keyhippo.api_key_metadata
    SET
        is_revoked = TRUE
    WHERE
        id = api_key_id
        AND ((user_id = c_user_id
                AND scope_id IS NULL)
            OR (scope_id = c_scope_id))
        AND is_revoked = FALSE
    RETURNING
        TRUE INTO success;
    IF success THEN
        -- Delete the secret hash to ensure it's no longer usable
        DELETE FROM keyhippo.api_key_secrets
        WHERE key_metadata_id = api_key_id;
    END IF;
    RETURN COALESCE(success, FALSE);
END;
$$;

-- Function to rotate an API key
CREATE OR REPLACE FUNCTION keyhippo.rotate_api_key (old_api_key_id uuid)
    RETURNS TABLE (
        new_api_key text,
        new_api_key_id uuid)
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    c_user_id uuid;
    c_scope_id uuid;
    key_description text;
    key_scope_id uuid;
BEGIN
    SELECT
        user_id,
        scope_id INTO c_user_id,
        c_scope_id
    FROM
        keyhippo.current_user_context ();
    IF c_user_id IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: User not authenticated';
    END IF;
    -- Retrieve the description and scope, and ensure the key is not revoked
    SELECT
        ak.description,
        ak.scope_id INTO key_description,
        key_scope_id
    FROM
        keyhippo.api_key_metadata ak
    WHERE
        ak.id = old_api_key_id
        AND ((ak.user_id = c_user_id
                AND ak.scope_id IS NULL)
            OR (ak.scope_id = c_scope_id))
        AND ak.is_revoked = FALSE;
    IF key_description IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: Invalid or inactive API key';
    END IF;
    -- Revoke the old key
    PERFORM
        keyhippo.revoke_api_key (old_api_key_id);
    -- Create a new key with the same description and scope
    RETURN QUERY
    SELECT
        *
    FROM
        keyhippo.create_api_key (key_description, (
                SELECT
                    name
                FROM keyhippo.scopes
                WHERE
                    id = key_scope_id));
END;
$$;

-- Pre-request function to check API key and set user context
CREATE OR REPLACE FUNCTION keyhippo.check_request ()
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    req_api_key text := current_setting('request.header.x-api-key', TRUE);
    verified_user_id uuid;
    verified_scope_id uuid;
    verified_permissions text[];
BEGIN
    IF req_api_key IS NULL THEN
        -- No API key provided, continue with normal auth
        RETURN;
    END IF;
    SELECT
        user_id,
        scope_id,
        permissions INTO verified_user_id,
        verified_scope_id,
        verified_permissions
    FROM
        keyhippo.verify_api_key (req_api_key);
    IF verified_user_id IS NULL THEN
        -- No valid API key found, raise an error
        RAISE EXCEPTION 'Invalid API key provided in x-api-key header.';
    ELSE
        -- Set the user context for RLS policies
        PERFORM
            set_config('request.jwt.claim.sub', verified_user_id::text, TRUE);
        PERFORM
            set_config('request.jwt.claim.scope', verified_scope_id::text, TRUE);
        PERFORM
            set_config('request.jwt.claim.permissions', array_to_json(verified_permissions)::text, TRUE);
    END IF;
END;
$$;

-- Grant necessary permissions
GRANT EXECUTE ON FUNCTION keyhippo.create_api_key (text, text) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo.verify_api_key (text) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo.revoke_api_key (uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo.rotate_api_key (uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo.check_request () TO authenticated, authenticator, service_role, anon;

GRANT EXECUTE ON FUNCTION keyhippo.current_user_context () TO authenticated, authenticator, service_role, anon;

ALTER ROLE authenticator SET pgrst.db_pre_request = 'keyhippo.check_request';

GRANT EXECUTE ON FUNCTION auth.uid () TO authenticated;

GRANT USAGE ON SCHEMA keyhippo TO authenticated, authenticator, service_role, anon;

GRANT SELECT ON TABLE keyhippo.api_key_metadata TO authenticated, authenticator, anon;

GRANT SELECT ON TABLE keyhippo.scopes TO authenticated, authenticator, anon;

GRANT SELECT ON TABLE keyhippo.scope_permissions TO authenticated, authenticator, anon;

-- Secure the api_key_secrets table
REVOKE ALL ON keyhippo.api_key_secrets FROM PUBLIC;

GRANT SELECT, INSERT, UPDATE, DELETE ON keyhippo.api_key_secrets TO service_role;

-- Enable Row Level Security on keyhippo tables
ALTER TABLE keyhippo.api_key_metadata ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo.api_key_secrets ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo.scopes ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo.scope_permissions ENABLE ROW LEVEL SECURITY;

-- Create RLS policy for api_key_metadata
CREATE POLICY api_key_metadata_policy ON keyhippo.api_key_metadata
    FOR ALL TO authenticated
        USING ((user_id, scope_id) IN (
            SELECT
                user_id, scope_id
            FROM
                keyhippo.current_user_context ())
                OR (user_id = (
                    SELECT
                        user_id
                    FROM
                        keyhippo.current_user_context ()) AND scope_id IS NULL));

-- Create RLS policy for api_key_secrets to deny all access
CREATE POLICY no_access ON keyhippo.api_key_secrets
    FOR ALL TO PUBLIC
        USING (FALSE);

-- Create RLS policies for keyhippo.api_key_metadata
CREATE POLICY "Users can view their own or in-scope API keys" ON keyhippo.api_key_metadata
    FOR SELECT
        USING ((user_id, scope_id) IN (
            SELECT
                user_id, scope_id
            FROM
                keyhippo.current_user_context ())
                OR (user_id = (
                    SELECT
                        user_id
                    FROM
                        keyhippo.current_user_context ()) AND scope_id IS NULL));

CREATE POLICY "Allow user to insert their own API keys" ON keyhippo.api_key_metadata
    FOR INSERT
        WITH CHECK (user_id = (
            SELECT
                user_id
            FROM
                keyhippo.current_user_context ()));

CREATE POLICY "Allow user to update their own or in-scope API keys" ON keyhippo.api_key_metadata
    FOR UPDATE
        USING ((user_id, scope_id) IN (
            SELECT
                user_id, scope_id
            FROM
                keyhippo.current_user_context ())
                OR (user_id = (
                    SELECT
                        user_id
                    FROM
                        keyhippo.current_user_context ()) AND scope_id IS NULL)) WITH CHECK (user_id = (
            SELECT
                user_id
            FROM keyhippo.current_user_context ()));

-- Create RLS policy for scopes
CREATE POLICY "Allow all authenticated users to view scopes" ON keyhippo.scopes
    FOR SELECT TO authenticated
        USING (TRUE);

-- Ensure that only necessary roles have access to the keyhippo schema
REVOKE ALL ON ALL TABLES IN SCHEMA keyhippo FROM PUBLIC;

GRANT USAGE ON SCHEMA keyhippo TO authenticated, service_role, anon;

-- Notify PostgREST to reload configuration
NOTIFY pgrst,
'reload config';

-- ================================================================
-- RBAC + ABAC Implementation
-- ================================================================
-- -------------------------------
-- RBAC Functions
-- -------------------------------
-- Function: assign_role_to_user
CREATE OR REPLACE FUNCTION keyhippo_rbac.assign_role_to_user (p_user_id uuid, p_group_id uuid, p_role_name text)
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    v_role_id uuid;
    v_current_user_id uuid;
    v_current_scope_id uuid;
BEGIN
    -- Get the current user context
    SELECT
        user_id,
        scope_id INTO v_current_user_id,
        v_current_scope_id
    FROM
        keyhippo.current_user_context ();
    -- Check if the current user has 'manage_roles' permission in the specified group
    IF NOT EXISTS (
        SELECT
            1
        FROM
            keyhippo_rbac.user_group_roles ugr
            JOIN keyhippo_rbac.role_permissions rp ON ugr.role_id = rp.role_id
            JOIN keyhippo_rbac.permissions p ON rp.permission_id = p.id
        WHERE
            ugr.user_id = v_current_user_id
            AND ugr.group_id = p_group_id
            AND p.name = 'manage_roles') THEN
    RAISE EXCEPTION 'Unauthorized to assign roles in this group';
END IF;
    -- Get the role ID
    SELECT
        id INTO v_role_id
    FROM
        keyhippo_rbac.roles
    WHERE
        name = p_role_name
        AND group_id = p_group_id;
    IF v_role_id IS NULL THEN
        RAISE EXCEPTION 'Role % not found in the specified group', p_role_name;
    END IF;
    -- Insert or update the user_group_roles entry
    INSERT INTO keyhippo_rbac.user_group_roles (user_id, group_id, role_id)
        VALUES (p_user_id, p_group_id, v_role_id)
    ON CONFLICT (user_id, group_id, role_id)
        DO UPDATE SET
            role_id = EXCLUDED.role_id;
    -- Update the claims cache
    PERFORM
        keyhippo_rbac.update_user_claims_cache (p_user_id);
END;
$$;

-- Function: update_user_claims_cache
CREATE OR REPLACE FUNCTION keyhippo_rbac.update_user_claims_cache (p_user_id uuid)
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    v_claims jsonb := '{}'::jsonb;
    v_group_id uuid;
    v_role_names text[];
BEGIN
    -- Delete existing claims for the user
    DELETE FROM keyhippo_rbac.claims_cache
    WHERE user_id = p_user_id;
    -- Gather roles for each group
    FOR v_group_id,
    v_role_names IN
    SELECT
        g.id,
        array_agg(DISTINCT r.name)
    FROM
        keyhippo_rbac.user_group_roles ugr
        JOIN keyhippo_rbac.roles r ON ugr.role_id = r.id
        JOIN keyhippo_rbac.groups g ON ugr.group_id = g.id
    WHERE
        ugr.user_id = p_user_id
    GROUP BY
        g.id LOOP
            v_claims := v_claims || jsonb_build_object(v_group_id::text, v_role_names);
        END LOOP;
    -- Insert new claims
    INSERT INTO keyhippo_rbac.claims_cache (user_id, rbac_claims)
        VALUES (p_user_id, v_claims);
    -- If no claims were inserted (user has no roles), ensure an empty claims cache entry exists
    IF NOT FOUND THEN
        INSERT INTO keyhippo_rbac.claims_cache (user_id, rbac_claims)
            VALUES (p_user_id, '{}')
        ON CONFLICT (user_id)
            DO NOTHING;
    END IF;
END;
$$;

-- -------------------------------
-- ABAC Functions
-- -------------------------------
-- Function: set_user_attribute
CREATE OR REPLACE FUNCTION keyhippo_abac.set_user_attribute (p_user_id uuid, p_attribute text, p_value jsonb)
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    v_current_user_id uuid;
    v_current_scope_id uuid;
BEGIN
    -- Get the current user context
    SELECT
        user_id,
        scope_id INTO v_current_user_id,
        v_current_scope_id
    FROM
        keyhippo.current_user_context ();
    -- Check if the current user has 'manage_user_attributes' permission in any group
    IF NOT EXISTS (
        SELECT
            1
        FROM
            keyhippo_rbac.user_group_roles ugr
            JOIN keyhippo_rbac.role_permissions rp ON ugr.role_id = rp.role_id
            JOIN keyhippo_rbac.permissions p ON rp.permission_id = p.id
        WHERE
            ugr.user_id = v_current_user_id
            AND p.name = 'manage_user_attributes') THEN
    RAISE EXCEPTION 'Unauthorized to set user attributes';
END IF;
INSERT INTO keyhippo_abac.user_attributes (user_id, attributes)
    VALUES (p_user_id, jsonb_build_object(p_attribute, p_value))
ON CONFLICT (user_id)
    DO UPDATE SET
        attributes = keyhippo_abac.user_attributes.attributes || jsonb_build_object(p_attribute, p_value);
END;
$$;

-- Function: create_policy
CREATE OR REPLACE FUNCTION keyhippo_abac.create_policy (p_name text, p_description text, p_policy jsonb)
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    v_current_user_id uuid;
    v_current_scope_id uuid;
BEGIN
    -- Get the current user context
    SELECT
        user_id,
        scope_id INTO v_current_user_id,
        v_current_scope_id
    FROM
        keyhippo.current_user_context ();
    -- Check if the current user has 'manage_policies' permission in any group
    IF NOT EXISTS (
        SELECT
            1
        FROM
            keyhippo_rbac.user_group_roles ugr
            JOIN keyhippo_rbac.role_permissions rp ON ugr.role_id = rp.role_id
            JOIN keyhippo_rbac.permissions p ON rp.permission_id = p.id
        WHERE
            ugr.user_id = v_current_user_id
            AND p.name = 'manage_policies') THEN
    RAISE EXCEPTION 'Unauthorized to create policies';
END IF;
INSERT INTO keyhippo_abac.policies (name, description, POLICY)
        VALUES (p_name, p_description, p_policy)
    ON CONFLICT (name)
        DO UPDATE SET
            description = EXCLUDED.description, POLICY = EXCLUDED.policy;
END;
$$;

-- Function: check_abac_policy
CREATE OR REPLACE FUNCTION keyhippo_abac.check_abac_policy (p_user_id uuid, p_policy jsonb)
    RETURNS boolean
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    v_current_user_id uuid;
    v_current_scope_id uuid;
BEGIN
    -- Get the current user context
    SELECT
        user_id,
        scope_id INTO v_current_user_id,
        v_current_scope_id
    FROM
        keyhippo.current_user_context ();
    -- Check if the current user has 'manage_policies' permission in any group
    IF NOT EXISTS (
        SELECT
            1
        FROM
            keyhippo_rbac.user_group_roles ugr
            JOIN keyhippo_rbac.role_permissions rp ON ugr.role_id = rp.role_id
            JOIN keyhippo_rbac.permissions p ON rp.permission_id = p.id
        WHERE
            ugr.user_id = v_current_user_id
            AND p.name = 'manage_policies') THEN
    RAISE EXCEPTION 'Unauthorized to create policies';
END IF;
INSERT INTO keyhippo_abac.policies (name, description, POLICY)
        VALUES (p_name, p_description, p_policy)
    ON CONFLICT (name)
        DO UPDATE SET
            description = EXCLUDED.description, POLICY = EXCLUDED.policy;
END;
$$;

-- Function: evaluate_policies
CREATE OR REPLACE FUNCTION keyhippo_abac.evaluate_policies (p_user_id uuid)
    RETURNS boolean
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    policy_record RECORD;
BEGIN
    FOR policy_record IN
    SELECT
        *
    FROM
        keyhippo_abac.policies LOOP
            IF NOT keyhippo_abac.check_abac_policy (p_user_id, policy_record.policy) THEN
                RETURN FALSE;
            END IF;
        END LOOP;
    RETURN TRUE;
END;
$$;

-- -------------------------------
-- RLS Policies
-- -------------------------------
-- Enable RLS on RBAC Tables
ALTER TABLE keyhippo_rbac.groups ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo_rbac.roles ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo_rbac.permissions ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo_rbac.role_permissions ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo_rbac.user_group_roles ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo_rbac.claims_cache ENABLE ROW LEVEL SECURITY;

-- Enable RLS on ABAC Tables
ALTER TABLE keyhippo_abac.user_attributes ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo_abac.policies ENABLE ROW LEVEL SECURITY;

-- RBAC: User-Group-Roles Access Policy
CREATE POLICY "rbac_user_group_roles_access" ON keyhippo_rbac.user_group_roles
    FOR ALL
        USING ((
            SELECT
                user_id
            FROM
                keyhippo.current_user_context ()) = user_id
                OR EXISTS (
                    SELECT
                        1
                    FROM
                        keyhippo_rbac.user_group_roles ugr
                        JOIN keyhippo_rbac.role_permissions rp ON ugr.role_id = rp.role_id
                        JOIN keyhippo_rbac.permissions p ON rp.permission_id = p.id
                    WHERE
                        ugr.user_id = (
                            SELECT
                                user_id
                            FROM
                                keyhippo.current_user_context ()) AND ugr.group_id = keyhippo_rbac.user_group_roles.group_id AND p.name = 'manage_roles')
                                OR CURRENT_ROLE = 'service_role') WITH CHECK (CURRENT_ROLE = 'service_role');

-- RBAC: Claims Cache Access Policy
CREATE POLICY "rbac_claims_cache_access" ON keyhippo_rbac.claims_cache
    FOR SELECT
        USING ((
            SELECT
                user_id
            FROM
                keyhippo.current_user_context ()) = user_id
                OR CURRENT_ROLE = 'service_role');

-- ABAC: User Attributes Access Policy
CREATE POLICY "abac_user_attributes_access" ON keyhippo_abac.user_attributes
    FOR ALL
        USING ((
            SELECT
                user_id
            FROM
                keyhippo.current_user_context ()) = user_id
                OR EXISTS (
                    SELECT
                        1
                    FROM
                        keyhippo_rbac.user_group_roles ugr
                        JOIN keyhippo_rbac.role_permissions rp ON ugr.role_id = rp.role_id
                        JOIN keyhippo_rbac.permissions p ON rp.permission_id = p.id
                    WHERE
                        ugr.user_id = (
                            SELECT
                                user_id
                            FROM
                                keyhippo.current_user_context ()) AND p.name = 'manage_user_attributes')
                                OR CURRENT_ROLE = 'service_role') WITH CHECK (CURRENT_ROLE = 'service_role');

-- ABAC: Policies Access Policy
CREATE POLICY "abac_policies_access" ON keyhippo_abac.policies
    FOR ALL
        USING (EXISTS (
            SELECT
                1
            FROM
                keyhippo_rbac.user_group_roles ugr
                JOIN keyhippo_rbac.role_permissions rp ON ugr.role_id = rp.role_id
                JOIN keyhippo_rbac.permissions p ON rp.permission_id = p.id
            WHERE
                ugr.user_id = (
                    SELECT
                        user_id
                    FROM
                        keyhippo.current_user_context ()) AND p.name = 'manage_policies')
                        OR CURRENT_ROLE = 'service_role') WITH CHECK (CURRENT_ROLE = 'service_role');

-- -------------------------------
-- Permissions and Grants
-- -------------------------------
-- Grant USAGE on schemas
GRANT USAGE ON SCHEMA keyhippo_rbac TO authenticated, service_role;

GRANT USAGE ON SCHEMA keyhippo_abac TO authenticated, service_role;

-- Grant SELECT on RBAC, ABAC tables
GRANT SELECT ON ALL TABLES IN SCHEMA keyhippo_rbac TO authenticated;

GRANT SELECT ON ALL TABLES IN SCHEMA keyhippo_abac TO authenticated;

-- Grant EXECUTE on RBAC functions
GRANT EXECUTE ON FUNCTION keyhippo_rbac.assign_role_to_user (uuid, uuid, text) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo_rbac.update_user_claims_cache (uuid) TO authenticated;

-- Grant EXECUTE on ABAC functions
GRANT EXECUTE ON FUNCTION keyhippo_abac.set_user_attribute (uuid, text, jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo_abac.create_policy (text, text, jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo_abac.check_abac_policy (uuid, jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo_abac.evaluate_policies (uuid) TO authenticated;

-- Grant SELECT, INSERT, UPDATE, DELETE on all RBAC tables to service_role
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA keyhippo_rbac TO service_role;

-- Grant SELECT, INSERT, UPDATE, DELETE on all ABAC tables to service_role
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA keyhippo_abac TO service_role;

-- -------------------------------
-- Triggers
-- -------------------------------
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

CREATE TRIGGER after_user_group_roles_change
    AFTER INSERT OR UPDATE OR DELETE ON keyhippo_rbac.user_group_roles
    FOR EACH ROW
    EXECUTE FUNCTION keyhippo_rbac.trigger_update_claims_cache ();

-- Notify PostgREST to reload configuration
NOTIFY pgrst,
'reload config';
