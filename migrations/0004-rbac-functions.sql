BEGIN;

-- RBAC management functions
CREATE OR REPLACE FUNCTION keyhippo_rbac.create_group(p_name text, p_description text)
    RETURNS uuid
    LANGUAGE plpgsql
    SECURITY INVOKER
    SET search_path = keyhippo_rbac
    AS $$
DECLARE
    v_group_id uuid;
BEGIN
    INSERT INTO keyhippo_rbac.groups (name, description)
    VALUES (p_name, p_description)
    RETURNING id INTO v_group_id;
    RETURN v_group_id;
END;
$$;

CREATE OR REPLACE FUNCTION keyhippo_rbac.create_role(p_name text, p_description text, p_group_id uuid, p_role_type keyhippo.app_role)
    RETURNS uuid
    LANGUAGE plpgsql
    SECURITY INVOKER
    SET search_path = keyhippo_rbac
    AS $$
DECLARE
    v_role_id uuid;
BEGIN
    INSERT INTO keyhippo_rbac.roles (name, description, group_id, role_type)
    VALUES (p_name, p_description, p_group_id, p_role_type)
    RETURNING id INTO v_role_id;
    RETURN v_role_id;
END;
$$;

CREATE OR REPLACE FUNCTION keyhippo_rbac.assign_role_to_user(p_user_id uuid, p_group_id uuid, p_role_id uuid)
    RETURNS VOID
    LANGUAGE plpgsql
    SECURITY INVOKER
    SET search_path = keyhippo_rbac
    AS $$
BEGIN
    INSERT INTO keyhippo_rbac.user_group_roles (user_id, group_id, role_id)
    VALUES (p_user_id, p_group_id, p_role_id)
    ON CONFLICT (user_id, group_id, role_id)
    DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION keyhippo_rbac.assign_permission_to_role(p_role_id uuid, p_permission_name keyhippo.app_permission)
    RETURNS VOID
    LANGUAGE plpgsql
    SECURITY INVOKER
    SET search_path = keyhippo_rbac
    AS $$
DECLARE
    v_permission_id uuid;
BEGIN
    SELECT id INTO v_permission_id
    FROM keyhippo_rbac.permissions
    WHERE name = p_permission_name;
    
    IF v_permission_id IS NULL THEN
        RAISE EXCEPTION 'Permission % not found', p_permission_name;
    END IF;
    
    INSERT INTO keyhippo_rbac.role_permissions (role_id, permission_id)
    VALUES (p_role_id, v_permission_id)
    ON CONFLICT (role_id, permission_id)
    DO NOTHING;
END;
$$;

-- Function to assign the default user role to a new user
CREATE OR REPLACE FUNCTION keyhippo.assign_default_role()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = keyhippo_rbac, public
    AS $$
DECLARE
    user_group_id uuid;
    user_role_id uuid;
BEGIN
    SELECT id INTO user_group_id
    FROM keyhippo_rbac.groups
    WHERE name = 'User Group';
    
    SELECT id INTO user_role_id
    FROM keyhippo_rbac.roles
    WHERE name = 'User'
    AND group_id = user_group_id;
    
    IF user_group_id IS NOT NULL AND user_role_id IS NOT NULL THEN
        INSERT INTO keyhippo_rbac.user_group_roles (user_id, group_id, role_id)
        VALUES (NEW.id, user_group_id, user_role_id)
        ON CONFLICT (user_id, group_id, role_id)
        DO NOTHING;
    END IF;
    
    RETURN NEW;
END;
$$;

-- Create trigger idempotently
DROP TRIGGER IF EXISTS keyhippo_assign_default_role_trigger ON auth.users;
CREATE TRIGGER keyhippo_assign_default_role_trigger
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION keyhippo.assign_default_role();

COMMIT;