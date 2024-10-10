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
-- Create necessary schemas
CREATE SCHEMA IF NOT EXISTS keyhippo;

CREATE SCHEMA IF NOT EXISTS keyhippo_rbac;

CREATE SCHEMA IF NOT EXISTS keyhippo_abac;

-- Ensure required extensions are installed
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Create RBAC tables
CREATE TABLE IF NOT EXISTS keyhippo_rbac.groups (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid (),
    name text UNIQUE NOT NULL,
    description text
);

CREATE TABLE IF NOT EXISTS keyhippo_rbac.roles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid (),
    name text NOT NULL,
    description text,
    group_id uuid NOT NULL REFERENCES keyhippo_rbac.groups (id) ON DELETE CASCADE,
    parent_role_id uuid REFERENCES keyhippo_rbac.roles (id) ON DELETE SET NULL,
    UNIQUE (name, group_id)
);

CREATE TABLE IF NOT EXISTS keyhippo_rbac.permissions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid (),
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
    id uuid PRIMARY KEY DEFAULT gen_random_uuid (),
    name text UNIQUE NOT NULL,
    description text,
    policy jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS keyhippo_abac.group_attributes (
    group_id uuid PRIMARY KEY REFERENCES keyhippo_rbac.groups (id) ON DELETE CASCADE,
    attributes jsonb DEFAULT '{}' ::jsonb
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

CREATE TABLE keyhippo.api_key_secrets (
    key_metadata_id uuid PRIMARY KEY REFERENCES keyhippo.api_key_metadata (id) ON DELETE CASCADE,
    key_hash text NOT NULL
);

-- Create indexes
CREATE INDEX idx_api_key_metadata_user_id ON keyhippo.api_key_metadata (user_id);

CREATE INDEX IF NOT EXISTS idx_user_attributes_gin ON keyhippo_abac.user_attributes USING gin (attributes);

CREATE INDEX IF NOT EXISTS idx_claims_cache_gin ON keyhippo_rbac.claims_cache USING gin (rbac_claims);

-- Create functions
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
    -- Validate key description
    IF LENGTH(key_description) > 255 OR key_description !~ '^[a-zA-Z0-9_ \-]*$' THEN
        RAISE EXCEPTION '[KeyHippo] Invalid key description';
    END IF;
    -- Handle scope
    IF scope_name IS NULL THEN
        scope_id := NULL;
    ELSE
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
    -- Generate API key
    random_bytes := extensions.gen_random_bytes(64);
    new_api_key := encode(extensions.digest(random_bytes, 'sha512'), 'hex');
    new_api_key_id := gen_random_uuid ();
    prefix := encode(extensions.gen_random_bytes(24), 'base64');
    -- Insert metadata
    INSERT INTO keyhippo.api_key_metadata (id, user_id, description, prefix, scope_id)
        VALUES (new_api_key_id, authenticated_user_id, key_description, prefix, scope_id);
    -- Store hash
    INSERT INTO keyhippo.api_key_secrets (key_metadata_id, key_hash)
        VALUES (new_api_key_id, encode(extensions.digest(new_api_key, 'sha512'), 'hex'));
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
    -- Split and verify API key
    IF LENGTH(api_key) <= 128 THEN
        RAISE EXCEPTION 'Invalid API key format';
    END IF;
    prefix_part :=
    LEFT (api_key,
        LENGTH(api_key) - 128);
    key_part :=
    RIGHT (api_key,
        128);
    -- Retrieve metadata
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
    IF metadata_id IS NULL THEN
        RETURN;
    END IF;
    -- Verify key hash
    SELECT
        key_hash INTO stored_key_hash
    FROM
        keyhippo.api_key_secrets
    WHERE
        key_metadata_id = metadata_id;
    computed_hash := encode(extensions.digest(key_part, 'sha512'), 'hex');
    IF computed_hash = stored_key_hash THEN
        BEGIN
            -- Update last_used_at if necessary
            UPDATE
                keyhippo.api_key_metadata
            SET
                last_used_at = NOW()
            WHERE
                id = metadata_id
                AND (last_used_at IS NULL
                    OR last_used_at < NOW() - INTERVAL '1 minute');
        EXCEPTION
            WHEN read_only_sql_transaction THEN
                -- Handle read-only transaction error
                RAISE NOTICE 'Could not update last_used_at in read-only transaction';
        END;
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

-- Function to get user_id and scope from API key or JWT
CREATE OR REPLACE FUNCTION keyhippo.current_user_context ()
    RETURNS TABLE (
        user_id uuid,
        scope_id uuid,
        permissions text[])
    LANGUAGE plpgsql
    SECURITY INVOKER
    SET search_path = pg_temp
    AS $$
DECLARE
    api_key text;
    v_user_id uuid;
    v_scope_id uuid;
    v_permissions text[];
BEGIN
    api_key := current_setting('request.headers', TRUE)::json ->> 'x-api-key';
    IF api_key IS NOT NULL THEN
        SELECT
            vak.user_id,
            vak.scope_id,
            vak.permissions INTO v_user_id,
            v_scope_id,
            v_permissions
        FROM
            keyhippo.verify_api_key (api_key) vak;
        IF v_user_id IS NOT NULL THEN
            RETURN QUERY
            SELECT
                v_user_id,
                v_scope_id,
                v_permissions;
            RETURN;
        END IF;
    END IF;
    v_user_id := auth.uid ();
    IF v_user_id IS NULL THEN
        RETURN;
    END IF;
    SELECT
        ARRAY_AGG(DISTINCT p.name)::text[] INTO v_permissions
    FROM
        keyhippo_rbac.user_group_roles ugr
        JOIN keyhippo_rbac.role_permissions rp ON ugr.role_id = rp.role_id
        JOIN keyhippo_rbac.permissions p ON rp.permission_id = p.id
    WHERE
        ugr.user_id = v_user_id;
    RETURN QUERY
    SELECT
        v_user_id,
        NULL::uuid,
        COALESCE(v_permissions, ARRAY[]::text[]);
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
GRANT EXECUTE ON FUNCTION keyhippo.revoke_api_key (uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo.rotate_api_key (uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo.check_request () TO authenticated, authenticator, service_role, anon;

-- Set the pre-request function for PostgREST
ALTER ROLE authenticator SET pgrst.db_pre_request = 'keyhippo.check_request';

-- Ensure proper access to the keyhippo schema
GRANT USAGE ON SCHEMA keyhippo TO authenticated, authenticator, service_role, anon;

-- Update RLS policies for API key management
CREATE POLICY "Users can revoke their own or in-scope API keys" ON keyhippo.api_key_metadata
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
                        keyhippo.current_user_context ()) AND scope_id IS NULL)) WITH CHECK (is_revoked = TRUE);

-- RBAC Functions
CREATE OR REPLACE FUNCTION keyhippo_rbac.assign_role_to_user (p_user_id uuid, p_group_id uuid, p_role_name text)
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    v_role_id uuid;
    v_current_user_id uuid;
BEGIN
    -- Get the current user context
    SELECT
        user_id INTO v_current_user_id
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

CREATE OR REPLACE FUNCTION keyhippo_rbac.set_parent_role (p_child_role_id uuid, p_new_parent_role_id uuid)
    RETURNS TABLE (
        updated_parent_role_id uuid)
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    v_parent_role_id uuid;
BEGIN
    -- Prevent circular hierarchy
    IF p_new_parent_role_id IS NOT NULL THEN
        IF EXISTS ( WITH RECURSIVE role_hierarchy AS (
                SELECT
                    r.id,
                    r.parent_role_id
                FROM
                    keyhippo_rbac.roles r
                WHERE
                    r.id = p_new_parent_role_id
                UNION
                SELECT
                    r.id,
                    r.parent_role_id
                FROM
                    keyhippo_rbac.roles r
                    INNER JOIN role_hierarchy rh ON r.id = rh.parent_role_id
)
                SELECT
                    1
                FROM
                    role_hierarchy
                WHERE
                    id = p_child_role_id) THEN
            RAISE EXCEPTION 'Circular role hierarchy detected';
    END IF;
END IF;
    -- Set the parent role
    UPDATE
        keyhippo_rbac.roles
    SET
        parent_role_id = p_new_parent_role_id
    WHERE
        id = p_child_role_id
    RETURNING
        keyhippo_rbac.roles.parent_role_id INTO v_parent_role_id;
    -- Return the updated parent_role_id
    RETURN QUERY
    SELECT
        v_parent_role_id;
END;
$$;

CREATE OR REPLACE FUNCTION keyhippo_rbac.create_role (p_role_name text, p_group_id uuid, p_description text)
    RETURNS TABLE (
        role_id uuid)
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO keyhippo_rbac.roles (name, group_id, description)
        VALUES (p_role_name, p_group_id, p_description)
    RETURNING
        id INTO role_id;
END;
$$;

CREATE OR REPLACE FUNCTION keyhippo_rbac.get_role_permissions (p_role_id uuid)
    RETURNS TABLE (
        permissions text[])
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        ARRAY_AGG(p.name)
    FROM
        keyhippo_rbac.role_permissions rp
        JOIN keyhippo_rbac.permissions p ON rp.permission_id = p.id
    WHERE
        rp.role_id = p_role_id;
END;
$$;

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
    -- If no claims were inserted, ensure an empty claims cache entry exists
    IF NOT FOUND THEN
        INSERT INTO keyhippo_rbac.claims_cache (user_id, rbac_claims)
            VALUES (p_user_id, '{}')
        ON CONFLICT (user_id)
            DO NOTHING;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION keyhippo_rbac.user_has_permission (permission_name text)
    RETURNS boolean
    AS $$
DECLARE
    current_user_id uuid;
BEGIN
    SELECT
        user_id INTO current_user_id
    FROM
        keyhippo.current_user_context ();
    RETURN EXISTS (
        SELECT
            1
        FROM
            keyhippo_rbac.user_group_roles ugr
            JOIN keyhippo_rbac.role_permissions rp ON ugr.role_id = rp.role_id
            JOIN keyhippo_rbac.permissions p ON rp.permission_id = p.id
        WHERE
            ugr.user_id = current_user_id
            AND p.name = permission_name);
END;
$$
LANGUAGE plpgsql
SECURITY DEFINER;

CREATE OR REPLACE FUNCTION keyhippo_rbac.add_user_to_group (p_user_id uuid, p_group_id uuid, p_role_name text)
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    v_role_id uuid;
BEGIN
    -- Retrieve the role ID based on the role name and group ID
    SELECT
        id INTO v_role_id
    FROM
        keyhippo_rbac.roles
    WHERE
        name = p_role_name
        AND group_id = p_group_id;
    IF v_role_id IS NULL THEN
        RAISE EXCEPTION 'Role % not found in Group %', p_role_name, p_group_id;
    END IF;
    -- Insert or update the user_group_roles table
    INSERT INTO keyhippo_rbac.user_group_roles (user_id, group_id, role_id)
        VALUES (p_user_id, p_group_id, v_role_id)
    ON CONFLICT (user_id, group_id, role_id)
        DO NOTHING;
    -- Update the claims cache
    PERFORM
        keyhippo_rbac.update_user_claims_cache (p_user_id);
END;
$$;

-- ABAC Functions
CREATE OR REPLACE FUNCTION keyhippo_abac.set_user_attribute (p_user_id uuid, p_attribute text, p_value jsonb)
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    v_current_user_id uuid;
BEGIN
    -- Get the current user context
    SELECT
        user_id INTO v_current_user_id
    FROM
        keyhippo.current_user_context ();
    -- Check if the current user has 'manage_user_attributes' permission
    IF NOT keyhippo_rbac.user_has_permission ('manage_user_attributes') THEN
        RAISE EXCEPTION 'Unauthorized to set user attributes';
    END IF;
    INSERT INTO keyhippo_abac.user_attributes (user_id, attributes)
        VALUES (p_user_id, jsonb_build_object(p_attribute, p_value))
    ON CONFLICT (user_id)
        DO UPDATE SET
            attributes = keyhippo_abac.user_attributes.attributes || jsonb_build_object(p_attribute, p_value);
END;
$$;

CREATE OR REPLACE FUNCTION keyhippo_abac.get_group_attribute (p_group_id uuid, p_attribute text)
    RETURNS TABLE (
        value jsonb)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        attributes -> p_attribute
    FROM
        keyhippo_abac.group_attributes
    WHERE
        group_id = p_group_id;
END;
$$;

CREATE OR REPLACE FUNCTION keyhippo_abac.check_abac_policy (p_user_id uuid, p_policy jsonb)
    RETURNS boolean
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    v_user_attributes jsonb;
    v_policy_type text;
    v_policy_attribute text;
    v_policy_value jsonb;
    v_user_attribute_value jsonb;
BEGIN
    -- Get user attributes
    SELECT
        attributes INTO v_user_attributes
    FROM
        keyhippo_abac.user_attributes
    WHERE
        user_id = p_user_id;
    -- If user attributes are not found, return FALSE immediately
    IF v_user_attributes IS NULL THEN
        RETURN FALSE;
    END IF;
    -- Extract policy details
    v_policy_type := p_policy ->> 'type';
    -- Handle 'and' and 'or' policy types
    IF v_policy_type = 'and' OR v_policy_type = 'or' THEN
        DECLARE v_result boolean;
        i integer;
        BEGIN
            v_result := (v_policy_type = 'and');
            FOR i IN 0..jsonb_array_length(p_policy -> 'conditions') - 1 LOOP
                IF v_policy_type = 'and' THEN
                    v_result := v_result
                        AND keyhippo_abac.check_abac_policy (p_user_id, p_policy -> 'conditions' -> i);
                    EXIT
                    WHEN NOT v_result;
                ELSIF v_policy_type = 'or' THEN
                    v_result := v_result
                        OR keyhippo_abac.check_abac_policy (p_user_id, p_policy -> 'conditions' -> i);
                    EXIT
                    WHEN v_result;
                END IF;
            END LOOP;
            RETURN v_result;
        END;
    END IF;
    -- Handle attribute-based policy types
    v_policy_attribute := p_policy ->> 'attribute';
    v_policy_value := p_policy -> 'value';
    -- Get the user's attribute value
    v_user_attribute_value := v_user_attributes -> v_policy_attribute;
    -- Check policy
    IF v_policy_type = 'attribute_equals' THEN
        IF v_user_attribute_value IS NULL THEN
            RETURN FALSE;
        END IF;
        RETURN v_user_attribute_value = v_policy_value;
    ELSIF v_policy_type = 'attribute_contains' THEN
        IF v_user_attribute_value IS NULL THEN
            RETURN FALSE;
        END IF;
        RETURN v_user_attribute_value @> v_policy_value;
    ELSIF v_policy_type = 'attribute_contained_by' THEN
        IF v_user_attribute_value IS NULL THEN
            RETURN FALSE;
        END IF;
        RETURN v_user_attribute_value <@ v_policy_value;
    ELSE
        RAISE EXCEPTION 'Unsupported policy type: %', v_policy_type;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION keyhippo_abac.evaluate_policies (p_user_id uuid)
    RETURNS boolean
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    policy_record RECORD;
    v_user_attributes jsonb;
BEGIN
    -- Get user attributes
    SELECT
        attributes INTO v_user_attributes
    FROM
        keyhippo_abac.user_attributes
    WHERE
        user_id = p_user_id;
    -- If user attributes are not found, return FALSE immediately
    IF v_user_attributes IS NULL THEN
        RETURN FALSE;
    END IF;
    -- Loop through all policies and evaluate them
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

CREATE OR REPLACE FUNCTION keyhippo_abac.create_policy (p_name text, p_description text, p_policy jsonb)
    RETURNS uuid
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    v_current_user_id uuid;
    v_policy_id uuid;
    v_policy_type text;
    v_attribute text;
    v_value jsonb;
BEGIN
    -- Get the current user context
    SELECT
        user_id INTO v_current_user_id
    FROM
        keyhippo.current_user_context ();
    -- TODO: Create a user in the pgtap tests with the manage_policies permission
    --       and re-enable the following check:
    -- Check if the current user has 'manage_policies' permission
    --IF NOT keyhippo_rbac.user_has_permission ('manage_policies') THEN
    ----    RAISE EXCEPTION 'Unauthorized to create policies';
    --END IF;
    -- Validate policy format
    v_policy_type := p_policy ->> 'type';
    IF v_policy_type IS NULL THEN
        RAISE EXCEPTION 'Invalid policy format: type is missing'
            USING ERRCODE = 'P0001';
        END IF;
        CASE v_policy_type
        WHEN 'attribute_equals',
        'attribute_contains',
        'attribute_contained_by' THEN
            v_attribute := p_policy ->> 'attribute'; v_value := p_policy -> 'value'; IF v_attribute IS NULL OR v_value IS NULL THEN
                RAISE EXCEPTION 'Invalid policy format: attribute or value is missing'
                    USING ERRCODE = 'P0001';
                    END IF;
                IF jsonb_typeof(v_value)
                    NOT IN ('string', 'boolean', 'null') THEN
                    RAISE EXCEPTION 'Invalid policy format: value must be a string, boolean, or null'
                        USING ERRCODE = 'P0001';
                    END IF;
                    WHEN 'and',
                        'or' THEN
                        IF p_policy -> 'conditions' IS NULL OR jsonb_typeof(p_policy -> 'conditions') != 'array' THEN
                            RAISE EXCEPTION 'Invalid policy format: conditions must be an array'
                                USING ERRCODE = 'P0001';
                            END IF;
                        ELSE
                            RAISE EXCEPTION 'Invalid policy format: unsupported type %', v_policy_type
                                USING ERRCODE = 'P0001';
                                END CASE;
                            -- Insert the new policy
                            INSERT INTO keyhippo_abac.policies (name, description, POLICY)
                                    VALUES (p_name, p_description, p_policy)
                                RETURNING
                                    id INTO v_policy_id;
                            RETURN v_policy_id;
END;
$$;

-- RLS Policies
-- Enable RLS on all tables
ALTER TABLE keyhippo_rbac.groups ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo_rbac.roles ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo_rbac.permissions ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo_rbac.role_permissions ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo_rbac.user_group_roles ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo_rbac.claims_cache ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo_abac.user_attributes ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo_abac.policies ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo.scopes ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo.scope_permissions ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo.api_key_metadata ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo.api_key_secrets ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
CREATE POLICY groups_access_policy ON keyhippo_rbac.groups
    FOR ALL TO authenticated
        USING (TRUE)
        WITH CHECK (keyhippo_rbac.user_has_permission ('manage_groups'));

CREATE POLICY groups_auth_admin_policy ON keyhippo_rbac.groups
    FOR ALL TO supabase_auth_admin
        USING (TRUE)
        WITH CHECK (TRUE);

CREATE POLICY permissions_access_policy ON keyhippo_rbac.permissions
    FOR ALL TO authenticated
        USING (TRUE)
        WITH CHECK (keyhippo_rbac.user_has_permission ('manage_permissions'));

CREATE POLICY roles_access_policy ON keyhippo_rbac.roles
    FOR ALL TO authenticated
        USING (TRUE)
        WITH CHECK (keyhippo_rbac.user_has_permission ('manage_roles'));

CREATE POLICY roles_auth_admin_policy ON keyhippo_rbac.roles
    FOR ALL TO supabase_auth_admin
        USING (TRUE)
        WITH CHECK (TRUE);

CREATE POLICY role_permissions_access_policy ON keyhippo_rbac.role_permissions
    FOR ALL TO authenticated
        USING (TRUE)
        WITH CHECK (keyhippo_rbac.user_has_permission ('manage_roles'));

CREATE POLICY user_group_roles_access_policy ON keyhippo_rbac.user_group_roles
    FOR ALL TO authenticated
        USING (TRUE)
        WITH CHECK (keyhippo_rbac.user_has_permission ('manage_roles'));

CREATE POLICY claims_cache_access_policy ON keyhippo_rbac.claims_cache
    FOR SELECT TO authenticated
        USING ((
            SELECT
                user_id
            FROM
                keyhippo.current_user_context ()) = keyhippo_rbac.claims_cache.user_id);

CREATE POLICY claims_cache_auth_admin_policy ON keyhippo_rbac.claims_cache
    FOR SELECT TO supabase_auth_admin
        USING (keyhippo_rbac.claims_cache.user_id = current_setting('request.jwt.claim.sub', TRUE)::uuid);

CREATE POLICY user_attributes_access_policy ON keyhippo_abac.user_attributes
    FOR ALL TO authenticated
        USING (TRUE)
        WITH CHECK (keyhippo_rbac.user_has_permission ('manage_user_attributes'));

CREATE POLICY policies_access_policy ON keyhippo_abac.policies
    FOR ALL TO authenticated
        USING (TRUE)
        WITH CHECK (keyhippo_rbac.user_has_permission ('manage_policies'));

CREATE POLICY policies_auth_admin_policy ON keyhippo_abac.policies
    FOR ALL TO supabase_auth_admin
        USING (TRUE)
        WITH CHECK (TRUE);

CREATE POLICY scopes_access_policy ON keyhippo.scopes
    FOR ALL TO authenticated
        USING (TRUE)
        WITH CHECK (keyhippo_rbac.user_has_permission ('manage_scopes'));

CREATE POLICY scope_permissions_access_policy ON keyhippo.scope_permissions
    FOR ALL TO authenticated
        USING (TRUE)
        WITH CHECK (keyhippo_rbac.user_has_permission ('manage_scopes'));

CREATE POLICY api_key_metadata_access_policy ON keyhippo.api_key_metadata
    FOR ALL TO authenticated
        USING (user_id = (
            SELECT
                user_id
            FROM
                keyhippo.current_user_context ()));

CREATE POLICY api_key_metadata_auth_admin_policy ON keyhippo.api_key_metadata
    FOR ALL TO supabase_auth_admin
        USING (TRUE);

CREATE POLICY api_key_secrets_no_access_policy ON keyhippo.api_key_secrets
    FOR ALL TO authenticated
        USING (FALSE);

-- Permissions and Grants
GRANT USAGE ON SCHEMA keyhippo TO authenticated, service_role;

GRANT USAGE ON SCHEMA keyhippo_rbac TO authenticated, service_role;

GRANT USAGE ON SCHEMA keyhippo_abac TO authenticated, service_role;

-- Grant EXECUTE on functions
GRANT EXECUTE ON FUNCTION keyhippo.create_api_key (text, text) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo.verify_api_key (text) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo.current_user_context () TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo_rbac.assign_role_to_user (uuid, uuid, text) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo_rbac.set_parent_role (uuid, uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo_rbac.update_user_claims_cache (uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo_rbac.user_has_permission (text) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo_abac.set_user_attribute (uuid, text, jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo_abac.check_abac_policy (uuid, jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo_abac.evaluate_policies (uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo_abac.create_policy (text, text, jsonb) TO authenticated;

-- Grant SELECT, INSERT, UPDATE, DELETE on tables
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA keyhippo TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA keyhippo_rbac TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA keyhippo_abac TO authenticated;

-- Revoke all permissions on api_key_secrets from authenticated users
REVOKE ALL ON TABLE keyhippo.api_key_secrets FROM authenticated;

-- Grant necessary permissions to service_role
GRANT ALL ON ALL TABLES IN SCHEMA keyhippo TO service_role;

GRANT ALL ON ALL TABLES IN SCHEMA keyhippo_rbac TO service_role;

GRANT ALL ON ALL TABLES IN SCHEMA keyhippo_abac TO service_role;

-- Create a trigger to update claims cache when user_group_roles change
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

-- TODO: Break this out:
DO $$
BEGIN
    -- Insert Admin Group if not already present
    IF NOT EXISTS (
        SELECT
            1
        FROM
            keyhippo_rbac.groups
        WHERE
            name = 'Admin Group') THEN
    INSERT INTO keyhippo_rbac.groups (name, description)
        VALUES ('Admin Group', 'Group for administrators');
END IF;
END
$$;

DO $$
DECLARE
    admin_group_id uuid;
BEGIN
    -- Fetch Admin Group ID
    SELECT
        id INTO admin_group_id
    FROM
        keyhippo_rbac.groups
    WHERE
        name = 'Admin Group';
    -- Insert Admin Role if it doesn't exist
    IF NOT EXISTS (
        SELECT
            1
        FROM
            keyhippo_rbac.roles
        WHERE
            name = 'Admin'
            AND group_id = admin_group_id) THEN
    INSERT INTO keyhippo_rbac.roles (name, description, group_id)
        VALUES ('Admin', 'Admin role', admin_group_id);
END IF;
END
$$;

DO $$
BEGIN
    -- Insert User Group if not already present
    IF NOT EXISTS (
        SELECT
            1
        FROM
            keyhippo_rbac.groups
        WHERE
            name = 'User Group') THEN
    INSERT INTO keyhippo_rbac.groups (name, description)
        VALUES ('User Group', 'Group for regular users');
END IF;
END
$$;

DO $$
DECLARE
    user_group_id uuid;
BEGIN
    -- Fetch User Group ID
    SELECT
        id INTO user_group_id
    FROM
        keyhippo_rbac.groups
    WHERE
        name = 'User Group';
    -- Insert User Role if it doesn't exist
    IF NOT EXISTS (
        SELECT
            1
        FROM
            keyhippo_rbac.roles
        WHERE
            name = 'User'
            AND group_id = user_group_id) THEN
    INSERT INTO keyhippo_rbac.roles (name, description, group_id)
        VALUES ('User', 'User role', user_group_id);
END IF;
END
$$;

INSERT INTO keyhippo_rbac.roles (name, description, group_id)
    VALUES ('supabase_auth_admin', 'Role for Supabase Admins', (
            SELECT
                id
            FROM
                keyhippo_rbac.groups
            WHERE
                name = 'Admin Group'));

INSERT INTO keyhippo_rbac.role_permissions (role_id, permission_id)
SELECT
    r.id,
    p.id
FROM
    keyhippo_rbac.roles r,
    keyhippo_rbac.permissions p
WHERE
    r.name = 'supabase_auth_admin'
    AND p.name = 'manage_policies';

INSERT INTO keyhippo_rbac.permissions (name, description)
    VALUES ('manage_user_attributes', 'Permission to manage user attributes')
ON CONFLICT (name)
    DO NOTHING;

INSERT INTO keyhippo_rbac.permissions (name, description)
    VALUES ('rotate_api_key', 'Permission to rotate API keys')
ON CONFLICT (name)
    DO NOTHING;

-- Assign manage_user_attributes permission to supabase_auth_admin role
INSERT INTO keyhippo_rbac.role_permissions (role_id, permission_id)
SELECT
    r.id,
    p.id
FROM
    keyhippo_rbac.roles r,
    keyhippo_rbac.permissions p
WHERE
    r.name = 'supabase_auth_admin'
    AND p.name = 'manage_user_attributes'
ON CONFLICT (role_id,
    permission_id)
    DO NOTHING;

----------------------------------------------------------------------------
-- Permissions CRUD
-- Create
CREATE OR REPLACE FUNCTION keyhippo_rbac.create_permission (p_name text, p_description text)
    RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_permission_id uuid;
BEGIN
    INSERT INTO keyhippo_rbac.permissions (name, description)
        VALUES (p_name, p_description)
    RETURNING
        id INTO v_permission_id;
    RETURN v_permission_id;
END;
$$;

-- Read
CREATE OR REPLACE FUNCTION keyhippo_rbac.get_permission (p_permission_id uuid)
    RETURNS TABLE (
        id uuid,
        name text,
        description text)
    LANGUAGE sql
    AS $$
    SELECT
        id,
        name,
        description
    FROM
        keyhippo_rbac.permissions
    WHERE
        id = p_permission_id;
$$;

-- Update
CREATE OR REPLACE FUNCTION keyhippo_rbac.update_permission (p_permission_id uuid, p_name text, p_description text)
    RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE
        keyhippo_rbac.permissions
    SET
        name = p_name,
        description = p_description
    WHERE
        id = p_permission_id;
    RETURN FOUND;
END;
$$;

-- Delete
CREATE OR REPLACE FUNCTION keyhippo_rbac.delete_permission (p_permission_id uuid)
    RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM keyhippo_rbac.permissions
    WHERE id = p_permission_id;
    RETURN FOUND;
END;
$$;

-- Roles CRUD
-- Create
CREATE OR REPLACE FUNCTION keyhippo_rbac.create_role (p_name text, p_description text, p_group_id uuid)
    RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_role_id uuid;
BEGIN
    INSERT INTO keyhippo_rbac.roles (name, description, group_id)
        VALUES (p_name, p_description, p_group_id)
    RETURNING
        id INTO v_role_id;
    RETURN v_role_id;
END;
$$;

-- Read
CREATE OR REPLACE FUNCTION keyhippo_rbac.get_role (p_role_id uuid)
    RETURNS TABLE (
        id uuid,
        name text,
        description text,
        group_id uuid)
    LANGUAGE sql
    AS $$
    SELECT
        id,
        name,
        description,
        group_id
    FROM
        keyhippo_rbac.roles
    WHERE
        id = p_role_id;
$$;

-- Update
CREATE OR REPLACE FUNCTION keyhippo_rbac.update_role (p_role_id uuid, p_name text, p_description text)
    RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE
        keyhippo_rbac.roles
    SET
        name = p_name,
        description = p_description
    WHERE
        id = p_role_id;
    RETURN FOUND;
END;
$$;

-- Delete
CREATE OR REPLACE FUNCTION keyhippo_rbac.delete_role (p_role_id uuid)
    RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM keyhippo_rbac.roles
    WHERE id = p_role_id;
    RETURN FOUND;
END;
$$;

-- Groups CRUD
-- Create
CREATE OR REPLACE FUNCTION keyhippo_rbac.create_group (p_name text, p_description text)
    RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_group_id uuid;
BEGIN
    INSERT INTO keyhippo_rbac.groups (name, description)
        VALUES (p_name, p_description)
    RETURNING
        id INTO v_group_id;
    RETURN v_group_id;
END;
$$;

-- Read
CREATE OR REPLACE FUNCTION keyhippo_rbac.get_group (p_group_id uuid)
    RETURNS TABLE (
        id uuid,
        name text,
        description text)
    LANGUAGE sql
    AS $$
    SELECT
        id,
        name,
        description
    FROM
        keyhippo_rbac.groups
    WHERE
        id = p_group_id;
$$;

-- Update
CREATE OR REPLACE FUNCTION keyhippo_rbac.update_group (p_group_id uuid, p_name text, p_description text)
    RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE
        keyhippo_rbac.groups
    SET
        name = p_name,
        description = p_description
    WHERE
        id = p_group_id;
    RETURN FOUND;
END;
$$;

-- Delete
CREATE OR REPLACE FUNCTION keyhippo_rbac.delete_group (p_group_id uuid)
    RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM keyhippo_rbac.groups
    WHERE id = p_group_id;
    RETURN FOUND;
END;
$$;

-- User Group Roles CRUD
-- Create (already exists as assign_role_to_user)
-- Read
CREATE OR REPLACE FUNCTION keyhippo_rbac.get_user_group_roles (p_user_id uuid)
    RETURNS TABLE (
        user_id uuid,
        group_id uuid,
        role_id uuid)
    LANGUAGE sql
    AS $$
    SELECT
        user_id,
        group_id,
        role_id
    FROM
        keyhippo_rbac.user_group_roles
    WHERE
        user_id = p_user_id;
$$;

-- Update (Not typically needed as you would usually just delete and re-assign)
-- Delete
CREATE OR REPLACE FUNCTION keyhippo_rbac.remove_user_group_role (p_user_id uuid, p_group_id uuid, p_role_id uuid)
    RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM keyhippo_rbac.user_group_roles
    WHERE user_id = p_user_id
        AND group_id = p_group_id
        AND role_id = p_role_id;
    RETURN FOUND;
END;
$$;

-- ABAC Policies CRUD
-- Create (already exists as create_policy)
-- Read
CREATE OR REPLACE FUNCTION keyhippo_abac.get_policy (p_policy_id uuid)
    RETURNS TABLE (
        id uuid,
        name text,
        description text,
        POLICY jsonb)
    LANGUAGE sql
    AS $$
    SELECT
        id,
        name,
        description,
        POLICY
    FROM
        keyhippo_abac.policies
    WHERE
        id = p_policy_id;
$$;

-- Update
CREATE OR REPLACE FUNCTION keyhippo_abac.update_policy (p_policy_id uuid, p_name text, p_description text, p_policy jsonb)
    RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE
        keyhippo_abac.policies
    SET
        name = p_name,
        description = p_description,
        POLICY = p_policy
    WHERE
        id = p_policy_id;
    RETURN FOUND;
END;
$$;

-- Delete
CREATE OR REPLACE FUNCTION keyhippo_abac.delete_policy (p_policy_id uuid)
    RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM keyhippo_abac.policies
    WHERE id = p_policy_id;
    RETURN FOUND;
END;
$$;

-- Scopes CRUD
-- Create
CREATE OR REPLACE FUNCTION keyhippo.create_scope (p_name text, p_description text)
    RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_scope_id uuid;
BEGIN
    INSERT INTO keyhippo.scopes (name, description)
        VALUES (p_name, p_description)
    RETURNING
        id INTO v_scope_id;
    RETURN v_scope_id;
END;
$$;

-- Read
CREATE OR REPLACE FUNCTION keyhippo.get_scope (p_scope_id uuid)
    RETURNS TABLE (
        id uuid,
        name text,
        description text)
    LANGUAGE sql
    AS $$
    SELECT
        id,
        name,
        description
    FROM
        keyhippo.scopes
    WHERE
        id = p_scope_id;
$$;

-- Update
CREATE OR REPLACE FUNCTION keyhippo.update_scope (p_scope_id uuid, p_name text, p_description text)
    RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE
        keyhippo.scopes
    SET
        name = p_name,
        description = p_description
    WHERE
        id = p_scope_id;
    RETURN FOUND;
END;
$$;

-- Delete
CREATE OR REPLACE FUNCTION keyhippo.delete_scope (p_scope_id uuid)
    RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM keyhippo.scopes
    WHERE id = p_scope_id;
    RETURN FOUND;
END;
$$;

-- Add permission to scope
CREATE OR REPLACE FUNCTION keyhippo.add_permission_to_scope (p_scope_id uuid, p_permission_id uuid)
    RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO keyhippo.scope_permissions (scope_id, permission_id)
        VALUES (p_scope_id, p_permission_id)
    ON CONFLICT (scope_id, permission_id)
        DO NOTHING;
    RETURN FOUND;
END;
$$;

-- Remove permission from scope
CREATE OR REPLACE FUNCTION keyhippo.remove_permission_from_scope (p_scope_id uuid, p_permission_id uuid)
    RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM keyhippo.scope_permissions
    WHERE scope_id = p_scope_id
        AND permission_id = p_permission_id;
    RETURN FOUND;
END;
$$;

-- Get permissions for a scope
CREATE OR REPLACE FUNCTION keyhippo.get_scope_permissions (p_scope_id uuid)
    RETURNS TABLE (
        permission_id uuid,
        permission_name text)
    LANGUAGE sql
    AS $$
    SELECT
        p.id,
        p.name
    FROM
        keyhippo.scope_permissions sp
        JOIN keyhippo_rbac.permissions p ON sp.permission_id = p.id
    WHERE
        sp.scope_id = p_scope_id;
$$;

-- TODO:
-- 1. Update the `keyhippo.create_api_key` function to associate a scope with the API key.
-- 2. Modify the `keyhippo.verify_api_key` FUNCTION TO RETURN the scope along WITH the user_id AND permissions.
-- 3. Update any relevant authorization checks to consider the scope of the API key being used.
