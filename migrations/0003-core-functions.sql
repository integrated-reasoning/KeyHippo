BEGIN;

-- Audit logging function and triggers
CREATE OR REPLACE FUNCTION keyhippo.log_table_change()
    RETURNS TRIGGER
    AS $$
DECLARE
    v_data jsonb;
    v_user_id uuid;
BEGIN
    -- Get the current user ID
    SELECT user_id INTO v_user_id
    FROM keyhippo.current_user_context();
    
    -- Prepare the data JSON
    IF (TG_OP = 'DELETE') THEN
        v_data := jsonb_build_object('old_data', to_jsonb(OLD));
    ELSIF (TG_OP = 'UPDATE') THEN
        v_data := jsonb_build_object('old_data', to_jsonb(OLD), 'new_data', to_jsonb(NEW));
    ELSIF (TG_OP = 'INSERT') THEN
        v_data := jsonb_build_object('new_data', to_jsonb(NEW));
    END IF;
    
    -- Insert into audit_log
    INSERT INTO keyhippo.audit_log (action, table_name, data, user_id)
    VALUES (TG_OP, TG_TABLE_NAME, v_data, v_user_id);
    
    RETURN NEW;
END;
$$
LANGUAGE plpgsql
SET search_path = pg_temp
SECURITY DEFINER;

-- Drop existing audit triggers if they exist
DROP TRIGGER IF EXISTS keyhippo_audit_rbac_groups ON keyhippo_rbac.groups;
DROP TRIGGER IF EXISTS keyhippo_audit_rbac_roles ON keyhippo_rbac.roles;
DROP TRIGGER IF EXISTS keyhippo_audit_rbac_permissions ON keyhippo_rbac.permissions;
DROP TRIGGER IF EXISTS keyhippo_audit_rbac_role_permissions ON keyhippo_rbac.role_permissions;
DROP TRIGGER IF EXISTS keyhippo_audit_rbac_user_group_roles ON keyhippo_rbac.user_group_roles;
DROP TRIGGER IF EXISTS keyhippo_audit_scopes ON keyhippo.scopes;
DROP TRIGGER IF EXISTS keyhippo_audit_scope_permissions ON keyhippo.scope_permissions;
DROP TRIGGER IF EXISTS keyhippo_audit_api_key_metadata ON keyhippo.api_key_metadata;

-- Create audit triggers for all tables
CREATE TRIGGER keyhippo_audit_rbac_groups
    AFTER INSERT OR UPDATE OR DELETE ON keyhippo_rbac.groups
    FOR EACH ROW
    EXECUTE FUNCTION keyhippo.log_table_change();

CREATE TRIGGER keyhippo_audit_rbac_roles
    AFTER INSERT OR UPDATE OR DELETE ON keyhippo_rbac.roles
    FOR EACH ROW
    EXECUTE FUNCTION keyhippo.log_table_change();

CREATE TRIGGER keyhippo_audit_rbac_permissions
    AFTER INSERT OR UPDATE OR DELETE ON keyhippo_rbac.permissions
    FOR EACH ROW
    EXECUTE FUNCTION keyhippo.log_table_change();

CREATE TRIGGER keyhippo_audit_rbac_role_permissions
    AFTER INSERT OR UPDATE OR DELETE ON keyhippo_rbac.role_permissions
    FOR EACH ROW
    EXECUTE FUNCTION keyhippo.log_table_change();

CREATE TRIGGER keyhippo_audit_rbac_user_group_roles
    AFTER INSERT OR UPDATE OR DELETE ON keyhippo_rbac.user_group_roles
    FOR EACH ROW
    EXECUTE FUNCTION keyhippo.log_table_change();

CREATE TRIGGER keyhippo_audit_scopes
    AFTER INSERT OR UPDATE OR DELETE ON keyhippo.scopes
    FOR EACH ROW
    EXECUTE FUNCTION keyhippo.log_table_change();

CREATE TRIGGER keyhippo_audit_scope_permissions
    AFTER INSERT OR UPDATE OR DELETE ON keyhippo.scope_permissions
    FOR EACH ROW
    EXECUTE FUNCTION keyhippo.log_table_change();

CREATE TRIGGER keyhippo_audit_api_key_metadata
    AFTER INSERT OR UPDATE OR DELETE ON keyhippo.api_key_metadata
    FOR EACH ROW
    EXECUTE FUNCTION keyhippo.log_table_change();

-- Authorization function (matching original simple logic)
CREATE OR REPLACE FUNCTION keyhippo.authorize(requested_permission keyhippo.app_permission)
    RETURNS boolean
    AS $$
DECLARE
    bind_permissions int;
    user_role keyhippo.app_role;
BEGIN
    -- Fetch user role from the JWT
    SELECT (current_setting('request.jwt.claims', TRUE)::jsonb ->> 'user_role')::keyhippo.app_role 
    INTO user_role;
    
    SELECT COUNT(*) INTO bind_permissions
    FROM keyhippo_rbac.role_permissions rp
    JOIN keyhippo_rbac.roles r ON rp.role_id = r.id
    JOIN keyhippo_rbac.permissions p ON rp.permission_id = p.id
    WHERE p.name = requested_permission
    AND r.role_type = user_role;
    
    RETURN bind_permissions > 0;
END;
$$
LANGUAGE plpgsql
STABLE
SECURITY DEFINER SET search_path = '';

-- Function to get user_id and scope from API key or JWT
CREATE OR REPLACE FUNCTION keyhippo.current_user_context()
    RETURNS TABLE (
        user_id uuid,
        scope_id uuid,
        permissions text[]
    )
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = keyhippo_impersonation, keyhippo_rbac, keyhippo
    AS $$
DECLARE
    api_key text;
    v_user_id uuid;
    v_scope_id uuid;
    v_permissions text[];
BEGIN
    -- First try API key authentication
    api_key := current_setting('request.headers', TRUE)::json ->> 'x-api-key';
    IF api_key IS NOT NULL THEN
        SELECT vak.user_id, vak.scope_id, vak.permissions 
        INTO v_user_id, v_scope_id, v_permissions
        FROM keyhippo.verify_api_key(api_key) vak;
        
        IF v_user_id IS NOT NULL THEN
            RETURN QUERY SELECT v_user_id, v_scope_id, v_permissions;
            RETURN;
        END IF;
    END IF;
    
    -- Then try auth.uid()
    v_user_id := auth.uid();
    
    -- If that fails, check for impersonation
    IF v_user_id IS NULL THEN
        SELECT impersonated_user_id INTO v_user_id
        FROM impersonation_state
        WHERE original_role = 'postgres'
        ORDER BY impersonation_time DESC
        LIMIT 1;
    END IF;
    
    -- If we have a user_id through any method, get their permissions
    IF v_user_id IS NOT NULL THEN
        SELECT ARRAY_AGG(DISTINCT p.name::text) INTO v_permissions
        FROM keyhippo_rbac.user_group_roles ugr
        JOIN keyhippo_rbac.role_permissions rp ON ugr.role_id = rp.role_id
        JOIN keyhippo_rbac.permissions p ON rp.permission_id = p.id
        WHERE ugr.user_id = v_user_id;
        
        RETURN QUERY SELECT v_user_id, NULL::uuid, COALESCE(v_permissions, ARRAY[]::text[]);
    END IF;
END;
$$;

-- Function to verify an API key
CREATE OR REPLACE FUNCTION keyhippo.verify_api_key(api_key text)
    RETURNS TABLE (
        user_id uuid,
        scope_id uuid,
        permissions text[]
    )
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = keyhippo, keyhippo_rbac, public
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
    
    prefix_part := LEFT(api_key, LENGTH(api_key) - 128);
    key_part := RIGHT(api_key, 128);
    
    -- Retrieve metadata
    SELECT m.id, m.user_id, m.scope_id
    INTO metadata_id, v_user_id, v_scope_id
    FROM keyhippo.api_key_metadata m
    WHERE m.prefix = prefix_part
    AND NOT m.is_revoked
    AND m.expires_at > NOW();
    
    IF metadata_id IS NULL THEN
        RETURN;
    END IF;
    
    -- Verify key hash
    SELECT key_hash INTO stored_key_hash
    FROM keyhippo.api_key_secrets
    WHERE key_metadata_id = metadata_id;
    
    computed_hash := encode(digest(key_part, 'sha512'), 'hex');
    
    IF computed_hash = stored_key_hash THEN
        -- Check if the transaction is not read-only before performing UPDATE
        IF current_setting('transaction_read_only', TRUE) = 'off' THEN
            -- Update last_used_at if necessary
            UPDATE keyhippo.api_key_metadata
            SET last_used_at = NOW()
            WHERE id = metadata_id
            AND (last_used_at IS NULL OR last_used_at < NOW() - INTERVAL '1 minute');
        ELSE
            -- Log that the UPDATE was skipped due to read-only transaction
            RAISE LOG 'verify_api_key() - Skipping last_used_at update for api_key_metadata_id: % due to read-only transaction.', metadata_id;
        END IF;
        
        -- Return user_id, scope_id, and permissions
        RETURN QUERY
        SELECT v_user_id, v_scope_id, ARRAY_AGG(DISTINCT p.name::text)
        FROM keyhippo.api_key_metadata akm
        LEFT JOIN keyhippo.scope_permissions sp ON akm.scope_id = sp.scope_id
        LEFT JOIN keyhippo_rbac.permissions p ON sp.permission_id = p.id
        WHERE akm.id = metadata_id
        GROUP BY v_user_id, v_scope_id;
    END IF;
END;
$$;

-- Function to create an API key
CREATE OR REPLACE FUNCTION keyhippo.create_api_key(key_description text, scope_name text DEFAULT NULL)
    RETURNS TABLE (
        api_key text,
        api_key_id uuid
    )
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = keyhippo, public
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
    SELECT user_id INTO authenticated_user_id
    FROM keyhippo.current_user_context();
    
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
        SELECT id INTO scope_id
        FROM keyhippo.scopes
        WHERE name = scope_name;
        
        IF scope_id IS NULL THEN
            RAISE EXCEPTION '[KeyHippo] Invalid scope';
        END IF;
    END IF;
    
    -- Generate API key
    random_bytes := gen_random_bytes(64);
    new_api_key := encode(digest(random_bytes, 'sha512'), 'hex');
    new_api_key_id := gen_random_uuid();
    prefix := encode(gen_random_bytes(24), 'base64');
    
    -- Insert metadata
    INSERT INTO keyhippo.api_key_metadata (id, user_id, description, prefix, scope_id)
    VALUES (new_api_key_id, authenticated_user_id, key_description, prefix, scope_id);
    
    -- Store hash
    INSERT INTO keyhippo.api_key_secrets (key_metadata_id, key_hash)
    VALUES (new_api_key_id, encode(digest(new_api_key, 'sha512'), 'hex'));
    
    RETURN QUERY SELECT prefix || new_api_key, new_api_key_id;
END;
$$;

-- Function to revoke an API key
CREATE OR REPLACE FUNCTION keyhippo.revoke_api_key(api_key_id uuid)
    RETURNS boolean
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = keyhippo, public
    AS $$
DECLARE
    success boolean;
    c_user_id uuid;
    c_scope_id uuid;
BEGIN
    SELECT user_id, scope_id INTO c_user_id, c_scope_id
    FROM keyhippo.current_user_context();
    
    IF c_user_id IS NULL THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;
    
    -- Update to set is_revoked only if it's not already revoked
    -- and the user has permission (either they created the key or it's within their scope)
    UPDATE keyhippo.api_key_metadata
    SET is_revoked = TRUE
    WHERE id = api_key_id
    AND ((user_id = c_user_id AND scope_id IS NULL)
         OR (scope_id = c_scope_id))
    AND is_revoked = FALSE
    RETURNING TRUE INTO success;
    
    IF success THEN
        -- Delete the secret hash to ensure it's no longer usable
        DELETE FROM keyhippo.api_key_secrets
        WHERE key_metadata_id = api_key_id;
    END IF;
    
    RETURN COALESCE(success, FALSE);
END;
$$;

-- Function to rotate an API key
CREATE OR REPLACE FUNCTION keyhippo.rotate_api_key(old_api_key_id uuid)
    RETURNS TABLE (
        new_api_key text,
        new_api_key_id uuid
    )
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = keyhippo, public
    AS $$
DECLARE
    c_user_id uuid;
    c_scope_id uuid;
    key_description text;
    key_scope_id uuid;
BEGIN
    SELECT user_id, scope_id INTO c_user_id, c_scope_id
    FROM keyhippo.current_user_context();
    
    IF c_user_id IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: User not authenticated';
    END IF;
    
    -- Retrieve the description and scope, and ensure the key is not revoked
    SELECT ak.description, ak.scope_id
    INTO key_description, key_scope_id
    FROM keyhippo.api_key_metadata ak
    WHERE ak.id = old_api_key_id
    AND ((ak.user_id = c_user_id AND ak.scope_id IS NULL)
         OR (ak.scope_id = c_scope_id))
    AND ak.is_revoked = FALSE;
    
    IF key_description IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: Invalid or inactive API key';
    END IF;
    
    -- Revoke the old key
    PERFORM keyhippo.revoke_api_key(old_api_key_id);
    
    -- Create a new key with the same description and scope
    RETURN QUERY
    SELECT *
    FROM keyhippo.create_api_key(key_description, (
        SELECT name FROM keyhippo.scopes WHERE id = key_scope_id
    ));
END;
$$;

-- Function to update claims
CREATE OR REPLACE FUNCTION keyhippo.update_key_claims(key_id uuid, new_claims jsonb)
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = keyhippo, public
    AS $$
DECLARE
    c_user_id uuid;
    c_scope_id uuid;
BEGIN
    -- Get current user context
    SELECT user_id, scope_id INTO c_user_id, c_scope_id
    FROM keyhippo.current_user_context();
    
    IF c_user_id IS NULL THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;
    
    -- Update claims if user has permission
    UPDATE keyhippo.api_key_metadata
    SET claims = new_claims
    WHERE id = key_id
    AND ((user_id = c_user_id AND scope_id IS NULL)
         OR (scope_id = c_scope_id));
END;
$$;

-- Function to get key_data
CREATE OR REPLACE FUNCTION keyhippo.key_data()
    RETURNS jsonb
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = keyhippo, public
    AS $$
DECLARE
    api_key text;
    key_metadata jsonb;
BEGIN
    -- Get API key from request header
    api_key := current_setting('request.headers', TRUE)::json ->> 'x-api-key';
    
    -- If no API key, return null
    IF api_key IS NULL THEN
        RETURN NULL;
    END IF;
    
    -- Get key metadata including claims
    SELECT jsonb_build_object('id', akm.id, 'description', akm.description, 'claims', akm.claims)
    INTO key_metadata
    FROM keyhippo.api_key_metadata akm
    WHERE akm.prefix = LEFT(api_key, LENGTH(api_key) - 128)
    AND NOT akm.is_revoked
    AND akm.expires_at > NOW();
    
    RETURN key_metadata;
END;
$$;

COMMIT;