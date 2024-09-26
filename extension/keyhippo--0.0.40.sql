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

-- Ensure required extensions are installed
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Create the api_key_metadata table
CREATE TABLE keyhippo.api_key_metadata (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
    description text,
    created_at timestamptz NOT NULL DEFAULT now(),
    last_used_at timestamptz,
    expires_at timestamptz NOT NULL DEFAULT (now() + interval '90 days'),
    is_revoked boolean NOT NULL DEFAULT FALSE
);

-- Indexes for faster lookups
CREATE INDEX idx_api_key_metadata_user_id ON keyhippo.api_key_metadata (user_id);

-- Create the api_key_secrets table (not accessible by the user)
CREATE TABLE keyhippo.api_key_secrets (
    key_metadata_id uuid PRIMARY KEY REFERENCES keyhippo.api_key_metadata (id) ON DELETE CASCADE,
    key_hash text NOT NULL
);

-- Function to create an API key
CREATE OR REPLACE FUNCTION keyhippo.create_api_key (key_description text)
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
BEGIN
    -- Get the authenticated user ID
    authenticated_user_id := auth.uid ();
    -- Check if the user is authenticated
    IF authenticated_user_id IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: User not authenticated';
    END IF;
    -- Validate key description length and format
    IF LENGTH(key_description) > 255 OR key_description !~ '^[a-zA-Z0-9_ -]*$' THEN
        RAISE EXCEPTION '[KeyHippo] Invalid key description';
    END IF;
    -- Generate 64 bytes of random data
    random_bytes := extensions.gen_random_bytes(64);
    -- Generate SHA512 hash of the random bytes and encode as hex
    new_api_key := encode(extensions.digest(random_bytes, 'sha512'), 'hex');
    -- Generate a new UUID for the API key
    new_api_key_id := gen_random_uuid ();
    -- Store the metadata without the key hash
    INSERT INTO keyhippo.api_key_metadata (id, user_id, description)
        VALUES (new_api_key_id, authenticated_user_id, key_description);
    -- Store the hashed key in the secrets table
    INSERT INTO keyhippo.api_key_secrets (key_metadata_id, key_hash)
        VALUES (new_api_key_id, extensions.crypt(new_api_key, extensions.gen_salt('bf', 8)));
    -- Return the API key and its ID
    RETURN QUERY
    SELECT
        new_api_key,
        new_api_key_id;
END;
$$;

-- Function to verify an API key
CREATE OR REPLACE FUNCTION keyhippo.verify_api_key (api_key text)
    RETURNS uuid
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    verified_user_id uuid;
    authenticated_user_id uuid;
    key_metadata_id uuid;
    current_last_used timestamptz;
    is_valid boolean;
BEGIN
    -- First, retrieve the necessary information without updating
    SELECT
        m.user_id,
        m.id,
        m.last_used_at,
        (NOT m.is_revoked
            AND m.expires_at > NOW()) AS valid INTO verified_user_id,
        key_metadata_id,
        current_last_used,
        is_valid
    FROM
        keyhippo.api_key_metadata m
        JOIN keyhippo.api_key_secrets s ON m.id = s.key_metadata_id
    WHERE
        s.key_hash = extensions.crypt(api_key, s.key_hash);
    -- If the key is found and is valid, proceed with potential update
    IF verified_user_id IS NOT NULL AND is_valid THEN
        -- Get the authenticated user ID
        authenticated_user_id := auth.uid ();
        -- If the user is already authenticated, ensure the key belongs to them:
        IF authenticated_user_id IS NOT NULL AND authenticated_user_id != verified_user_id THEN
            RAISE EXCEPTION 'Unauthorized: Authenticated user % does not own this key', authenticated_user_id;
        END IF;
        -- If last_used_at needs updating
        IF current_last_used IS NULL OR current_last_used < NOW() - INTERVAL '1 minute' THEN
            -- Perform the update in a separate transaction
            -- (allows verify_api_key to be called without granting UPDATE)
            PERFORM
                pg_advisory_xact_lock(hashtext('verify_api_key'::text || key_metadata_id::text));
            BEGIN
                UPDATE
                    keyhippo.api_key_metadata
                SET
                    last_used_at = NOW()
                WHERE
                    id = key_metadata_id;
            EXCEPTION
                WHEN read_only_sql_transaction THEN
                    -- Log the error or handle it as needed
                    RAISE NOTICE 'Could not update last_used_at in read-only transaction';
            END;
        END IF;
ELSE
    -- If the key is not valid, set verified_user_id to NULL
    verified_user_id := NULL;
    END IF;
    RETURN verified_user_id;
END;

$$;

-- Function to get user_id from API key or JWT
CREATE OR REPLACE FUNCTION keyhippo.current_user_id ()
    RETURNS uuid
    LANGUAGE plpgsql
    SECURITY INVOKER
    SET search_path = pg_temp
    AS $$
DECLARE
    api_key text;
    user_id uuid;
BEGIN
    api_key := current_setting('request.headers', TRUE)::json ->> 'x-api-key';
    IF api_key IS NOT NULL THEN
        SELECT
            keyhippo.verify_api_key (api_key) INTO user_id;
        IF user_id IS NOT NULL THEN
            RETURN user_id;
        END IF;
    END IF;
    RETURN auth.uid ();
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
    c_user_id uuid := keyhippo.current_user_id ();
BEGIN
    IF c_user_id IS NULL THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;
    -- Update to set is_revoked only if it's not already revoked
    UPDATE
        keyhippo.api_key_metadata
    SET
        is_revoked = TRUE
    WHERE
        id = api_key_id
        AND user_id = c_user_id
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
    c_user_id uuid := auth.uid ();
    key_description text;
BEGIN
    IF c_user_id IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: User not authenticated';
    END IF;
    -- Retrieve the description and ensure the key is not revoked
    SELECT
        ak.description INTO key_description
    FROM
        keyhippo.api_key_metadata ak
    WHERE
        ak.id = old_api_key_id
        AND ak.user_id = c_user_id
        AND ak.is_revoked = FALSE;
    IF key_description IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: Invalid or inactive API key';
    END IF;
    -- Revoke the old key
    PERFORM
        keyhippo.revoke_api_key (old_api_key_id);
    -- Create a new key with the same description
    RETURN QUERY
    SELECT
        *
    FROM
        keyhippo.create_api_key (key_description);
END;
$$;

-- Grant necessary permissions
GRANT EXECUTE ON FUNCTION keyhippo.create_api_key (text) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo.verify_api_key (text) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo.revoke_api_key (uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo.rotate_api_key (uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION auth.uid () TO authenticated;

GRANT USAGE ON SCHEMA keyhippo TO authenticated, service_role, anon;

-- Grant SELECT on api_key_metadata to authenticated users
GRANT SELECT ON TABLE keyhippo.api_key_metadata TO authenticated;

-- Secure the api_key_secrets table
REVOKE ALL ON keyhippo.api_key_secrets FROM PUBLIC;

GRANT SELECT, INSERT, UPDATE, DELETE ON keyhippo.api_key_secrets TO service_role;

-- Enable Row Level Security on keyhippo.api_key_metadata
ALTER TABLE keyhippo.api_key_metadata ENABLE ROW LEVEL SECURITY;

-- Enable Row Level Security on keyhippo.api_key_secrets
ALTER TABLE keyhippo.api_key_secrets ENABLE ROW LEVEL SECURITY;

-- Create RLS policy for api_key_metadata
CREATE POLICY api_key_metadata_policy ON keyhippo.api_key_metadata
    FOR ALL TO authenticated
        USING (user_id = auth.uid ());

-- Create RLS policy for api_key_secrets to deny all access
CREATE POLICY no_access ON keyhippo.api_key_secrets
    FOR ALL TO PUBLIC
        USING (FALSE);

-- Create RLS policies for keyhippo.api_key_metadata
CREATE POLICY "Users can only view their own API keys" ON keyhippo.api_key_metadata
    FOR ALL
        USING (user_id = keyhippo.current_user_id ());

CREATE POLICY "Allow user to insert their own API keys" ON keyhippo.api_key_metadata
    FOR INSERT
        WITH CHECK (user_id = keyhippo.current_user_id ());

CREATE POLICY "Allow user to select their own API keys" ON keyhippo.api_key_metadata
    FOR SELECT
        USING (user_id = keyhippo.current_user_id ());

CREATE POLICY "Allow user to update their own API keys" ON keyhippo.api_key_metadata
    FOR UPDATE
        USING (user_id = keyhippo.current_user_id ())
        WITH CHECK (user_id = keyhippo.current_user_id ());

-- Ensure that only necessary roles have access to the keyhippo schema
REVOKE ALL ON ALL TABLES IN SCHEMA keyhippo FROM PUBLIC;

GRANT USAGE ON SCHEMA keyhippo TO authenticated, service_role, anon;

-- Notify PostgREST to reload configuration
NOTIFY pgrst,
'reload config';

-- ================================================================
-- RBAC + ABAC Implementation
-- ================================================================
-- Create RBAC Schema
CREATE SCHEMA IF NOT EXISTS keyhippo_rbac;

-- Create ABAC Schema
CREATE SCHEMA IF NOT EXISTS keyhippo_abac;

-- -------------------------------
-- RBAC Tables
-- -------------------------------
-- Create Groups Table
CREATE TABLE IF NOT EXISTS keyhippo_rbac.groups (
    id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid (),
    name text UNIQUE NOT NULL,
    description text
);

-- Create Roles Table
CREATE TABLE IF NOT EXISTS keyhippo_rbac.roles (
    id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid (),
    name text NOT NULL,
    description text,
    group_id uuid NOT NULL REFERENCES keyhippo_rbac.groups (id) ON DELETE CASCADE,
    parent_role_id uuid REFERENCES keyhippo_rbac.roles (id) ON DELETE SET NULL,
    UNIQUE (name, group_id)
);

-- Create Permissions Table
CREATE TABLE IF NOT EXISTS keyhippo_rbac.permissions (
    id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid (),
    name text UNIQUE NOT NULL,
    description text
);

-- Create Role-Permissions Mapping Table
CREATE TABLE IF NOT EXISTS keyhippo_rbac.role_permissions (
    role_id uuid NOT NULL REFERENCES keyhippo_rbac.roles (id) ON DELETE CASCADE,
    permission_id uuid NOT NULL REFERENCES keyhippo_rbac.permissions (id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

-- Create User-Group-Roles Mapping Table
CREATE TABLE IF NOT EXISTS keyhippo_rbac.user_group_roles (
    user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
    group_id uuid NOT NULL REFERENCES keyhippo_rbac.groups (id) ON DELETE CASCADE,
    role_id uuid NOT NULL REFERENCES keyhippo_rbac.roles (id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, group_id, role_id)
);

-- Create Claims Cache Table
CREATE TABLE IF NOT EXISTS keyhippo_rbac.claims_cache (
    user_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
    rbac_claims jsonb DEFAULT '{}' ::jsonb
);

-- -------------------------------
-- ABAC Tables
-- -------------------------------
-- Create User Attributes Table (ABAC)
CREATE TABLE IF NOT EXISTS keyhippo_abac.user_attributes (
    user_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
    attributes jsonb DEFAULT '{}' ::jsonb
);

-- Create Policies Table (ABAC)
CREATE TABLE IF NOT EXISTS keyhippo_abac.policies (
    id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid (),
    name text UNIQUE NOT NULL,
    description text,
    policy jsonb NOT NULL
);

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
BEGIN
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
BEGIN
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
BEGIN
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
    v_attribute_value jsonb;
    v_policy_attribute text;
    v_policy_value jsonb;
BEGIN
    v_policy_attribute := p_policy ->> 'attribute';
    v_policy_value := p_policy -> 'value';
    SELECT
        attributes -> v_policy_attribute INTO v_attribute_value
    FROM
        keyhippo_abac.user_attributes
    WHERE
        user_id = p_user_id;
    IF v_attribute_value IS NULL THEN
        RETURN FALSE;
    END IF;
    RETURN CASE WHEN p_policy ->> 'type' = 'attribute_equals' THEN
        v_attribute_value = v_policy_value
    WHEN p_policy ->> 'type' = 'attribute_contains' THEN
        v_attribute_value @> v_policy_value
    ELSE
        FALSE
    END;
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
        USING (keyhippo.current_user_id () = user_id
            OR CURRENT_ROLE = 'service_role')
            WITH CHECK (CURRENT_ROLE = 'service_role');

-- RBAC: Claims Cache Access Policy
CREATE POLICY "rbac_claims_cache_access" ON keyhippo_rbac.claims_cache
    FOR SELECT
        USING (keyhippo.current_user_id () = user_id
            OR CURRENT_ROLE = 'service_role');

-- ABAC: User Attributes Access Policy
CREATE POLICY "abac_user_attributes_access" ON keyhippo_abac.user_attributes
    FOR ALL
        USING (keyhippo.current_user_id () = user_id
            OR CURRENT_ROLE = 'service_role')
            WITH CHECK (CURRENT_ROLE = 'service_role');

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
-- Indexes for Performance
-- -------------------------------
CREATE INDEX IF NOT EXISTS idx_user_attributes_gin ON keyhippo_abac.user_attributes USING gin (attributes);

CREATE INDEX IF NOT EXISTS idx_claims_cache_gin ON keyhippo_rbac.claims_cache USING gin (rbac_claims);

-- -------------------------------
-- Default Data Insertion
-- -------------------------------
-- Insert default groups
INSERT INTO keyhippo_rbac.groups (name, description)
    VALUES ('Admin Group', 'Group with administrative privileges'),
    ('User Group', 'Group with standard user privileges')
ON CONFLICT (name)
    DO NOTHING;

-- Insert default roles
INSERT INTO keyhippo_rbac.roles (name, description, group_id)
SELECT
    'Admin',
    'Administrator Role',
    id
FROM
    keyhippo_rbac.groups
WHERE
    name = 'Admin Group'
ON CONFLICT (name,
    group_id)
    DO NOTHING;

INSERT INTO keyhippo_rbac.roles (name, description, group_id)
SELECT
    'User',
    'Standard User Role',
    id
FROM
    keyhippo_rbac.groups
WHERE
    name = 'User Group'
ON CONFLICT (name,
    group_id)
    DO NOTHING;

-- Insert default permissions
INSERT INTO keyhippo_rbac.permissions (name, description)
    VALUES ('read', 'Read Permission'),
    ('write', 'Write Permission'),
    ('delete', 'Delete Permission'),
    ('manage_policies', 'Manage ABAC Policies')
ON CONFLICT (name)
    DO NOTHING;

-- Assign permissions to roles
INSERT INTO keyhippo_rbac.role_permissions (role_id, permission_id)
SELECT
    r.id,
    p.id
FROM
    keyhippo_rbac.roles r
    CROSS JOIN keyhippo_rbac.permissions p
WHERE
    r.name = 'Admin'
ON CONFLICT
    DO NOTHING;

INSERT INTO keyhippo_rbac.role_permissions (role_id, permission_id)
SELECT
    r.id,
    p.id
FROM
    keyhippo_rbac.roles r
    JOIN keyhippo_rbac.permissions p ON p.name IN ('read', 'write')
WHERE
    r.name = 'User'
ON CONFLICT
    DO NOTHING;

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
