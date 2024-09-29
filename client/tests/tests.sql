BEGIN;
SET search_path TO keyhippo, public, auth;
-- Create test users and set up authentication
DO $$
DECLARE
    user1_id uuid := gen_random_uuid ();
    user2_id uuid := gen_random_uuid ();
BEGIN
    SET local ROLE supabase_auth_admin;
    -- Insert users with explicit IDs
    INSERT INTO auth.users (id, email)
        VALUES (user1_id, 'user1@example.com'),
        (user2_id, 'user2@example.com');
    -- Store user IDs as settings for later use
    PERFORM
        set_config('test.user1_id', user1_id::text, TRUE);
    PERFORM
        set_config('test.user2_id', user2_id::text, TRUE);
    -- Set up authentication for user1
    PERFORM
        set_config('request.jwt.claim.sub', user1_id::text, TRUE);
    PERFORM
        set_config('request.jwt.claims', json_build_object('sub', user1_id)::text, TRUE);
END
$$;
-- Switch to authenticated role
SET local ROLE authenticated;
-- Verify initial state (no API keys)
DO $$
DECLARE
    key_count bigint;
BEGIN
    SELECT
        COUNT(*) INTO key_count
    FROM
        keyhippo.api_key_metadata
    WHERE
        user_id = current_setting('test.user1_id')::uuid;
    ASSERT key_count = 0,
    'Initially, no API keys should exist for the user';
END
$$;
-- Create API key
DO $$
DECLARE
    created_key_result record;
    key_count bigint;
BEGIN
    SELECT
        * INTO created_key_result
    FROM
        keyhippo.create_api_key ('Test API Key');
    ASSERT created_key_result.api_key IS NOT NULL,
    'create_api_key should return a valid API key';
    ASSERT created_key_result.api_key_id IS NOT NULL,
    'create_api_key should return a valid API key ID';
    SELECT
        COUNT(*) INTO key_count
    FROM
        keyhippo.api_key_metadata
    WHERE
        id = created_key_result.api_key_id
        AND user_id = current_setting('test.user1_id')::uuid;
    ASSERT key_count = 1,
    'An API key should be created for the authenticated user';
END
$$;
-- Verify API key
DO $$
DECLARE
    created_key_result record;
    verified_result record;
BEGIN
    SELECT
        * INTO created_key_result
    FROM
        keyhippo.create_api_key ('Verify Test Key');
    SELECT
        * INTO verified_result
    FROM
        keyhippo.verify_api_key (created_key_result.api_key);
    ASSERT verified_result.user_id = current_setting('test.user1_id')::uuid,
    'verify_api_key should return the correct user ID';
    ASSERT verified_result.scope_id IS NULL,
    'verify_api_key should return NULL scope_id for default key';
    ASSERT verified_result.permissions IS NOT NULL,
    'verify_api_key should return permissions';
END
$$;
-- Rotate API key
DO $$
DECLARE
    created_key_result record;
    rotated_key_result record;
    old_key_revoked boolean;
    old_key_user_id uuid;
    new_key_user_id uuid;
BEGIN
    -- Create an initial API key
    SELECT
        * INTO created_key_result
    FROM
        keyhippo.create_api_key ('Rotate Test Key');
    -- Rotate the API key
    SELECT
        * INTO rotated_key_result
    FROM
        keyhippo.rotate_api_key (created_key_result.api_key_id);
    ASSERT rotated_key_result.new_api_key IS NOT NULL,
    'rotate_api_key should return a new API key';
    ASSERT rotated_key_result.new_api_key_id IS NOT NULL,
    'rotate_api_key should return a new API key ID';
    ASSERT rotated_key_result.new_api_key_id != created_key_result.api_key_id,
    'New API key ID should be different from the old one';
    -- Check if the old key is revoked
    SELECT
        is_revoked,
        user_id INTO old_key_revoked,
        old_key_user_id
    FROM
        keyhippo.api_key_metadata
    WHERE
        id = created_key_result.api_key_id;
    ASSERT old_key_revoked,
    'Old API key should be revoked after rotation';
    -- Check if the new key belongs to the same user
    SELECT
        user_id INTO new_key_user_id
    FROM
        keyhippo.api_key_metadata
    WHERE
        id = rotated_key_result.new_api_key_id;
    ASSERT old_key_user_id = new_key_user_id,
    'New API key should belong to the same user as the old key';
END
$$;
-- Revoke API key
DO $$
DECLARE
    created_key_result record;
    revoke_result boolean;
    key_is_revoked boolean;
BEGIN
    SELECT
        * INTO created_key_result
    FROM
        keyhippo.create_api_key ('Revoke Test Key');
    SELECT
        keyhippo.revoke_api_key (created_key_result.api_key_id) INTO revoke_result;
    ASSERT revoke_result,
    'revoke_api_key should return true for successful revocation';
    SELECT
        is_revoked INTO key_is_revoked
    FROM
        keyhippo.api_key_metadata
    WHERE
        id = created_key_result.api_key_id;
    ASSERT key_is_revoked,
    'API key should be marked as revoked after revocation';
END
$$;
-- Test RBAC and ABAC functionality
DO $$
DECLARE
    current_user_id uuid;
    current_group_id uuid;
    current_role_id uuid;
    manage_groups_permission_id uuid;
    manage_permissions_permission_id uuid;
    manage_roles_permission_id uuid;
    manage_user_attributes_permission_id uuid;
    manage_policies_permission_id uuid;
    policy_id uuid;
BEGIN
    -- Get the current user's ID
    SELECT
        user_id INTO current_user_id
    FROM
        keyhippo.current_user_context ();
    -- Create necessary permissions (this needs to be done with elevated privileges)
    SET LOCAL ROLE postgres;
    INSERT INTO keyhippo_rbac.permissions (name, description)
        VALUES ('manage_groups', 'Permission to manage groups'),
        ('manage_permissions', 'Permission to manage permissions'),
        ('manage_roles', 'Permission to manage roles'),
        ('manage_user_attributes', 'Permission to manage user attributes'),
        ('manage_policies', 'Permission to manage policies')
    ON CONFLICT (name)
        DO NOTHING;
    SELECT
        id INTO manage_groups_permission_id
    FROM
        keyhippo_rbac.permissions
    WHERE
        name = 'manage_groups';
    SELECT
        id INTO manage_permissions_permission_id
    FROM
        keyhippo_rbac.permissions
    WHERE
        name = 'manage_permissions';
    SELECT
        id INTO manage_roles_permission_id
    FROM
        keyhippo_rbac.permissions
    WHERE
        name = 'manage_roles';
    SELECT
        id INTO manage_user_attributes_permission_id
    FROM
        keyhippo_rbac.permissions
    WHERE
        name = 'manage_user_attributes';
    SELECT
        id INTO manage_policies_permission_id
    FROM
        keyhippo_rbac.permissions
    WHERE
        name = 'manage_policies';
    -- Create a test group
    INSERT INTO keyhippo_rbac.groups (name, description)
        VALUES ('Test Group', 'A group for testing')
    RETURNING
        id INTO current_group_id;
    -- Create a test role with all necessary permissions
    INSERT INTO keyhippo_rbac.roles (name, description, group_id)
        VALUES ('Test Role', 'A role for testing', current_group_id)
    RETURNING
        id INTO current_role_id;
    -- Assign all necessary permissions to the role
    INSERT INTO keyhippo_rbac.role_permissions (role_id, permission_id)
        VALUES (current_role_id, manage_groups_permission_id),
        (current_role_id, manage_permissions_permission_id),
        (current_role_id, manage_roles_permission_id),
        (current_role_id, manage_user_attributes_permission_id),
        (current_role_id, manage_policies_permission_id);
    -- Assign role to user
    INSERT INTO keyhippo_rbac.user_group_roles (user_id, group_id, role_id)
        VALUES (current_user_id, current_group_id, current_role_id);
    -- Update claims cache
    PERFORM
        keyhippo_rbac.update_user_claims_cache (current_user_id);
    -- Switch back to authenticated role for the rest of the tests
    SET LOCAL ROLE authenticated;
    -- Verify role assignment
    ASSERT EXISTS (
        SELECT
            1
        FROM
            keyhippo_rbac.user_group_roles
        WHERE
            user_id = current_user_id
            AND group_id = current_group_id
            AND role_id = current_role_id),
    'Role should be assigned to user';
    -- Verify claims cache update
    ASSERT EXISTS (
        SELECT
            1
        FROM
            keyhippo_rbac.claims_cache
        WHERE
            user_id = current_user_id
            AND rbac_claims @> jsonb_build_object(current_group_id::text, ARRAY['Test Role'])),
    'Claims cache should be updated with new role';
    -- Test ABAC functionality
    -- Set user attribute
    PERFORM
        keyhippo_abac.set_user_attribute (current_user_id, 'department', '"engineering"'::jsonb);
    -- Create ABAC policy
    SELECT
        keyhippo_abac.add_policy ('Engineering Access', 'Access for engineering department', '{"type": "attribute_equals", "attribute": "department", "value": "engineering"}'::jsonb) INTO policy_id;
    -- Evaluate policy
    ASSERT keyhippo_abac.evaluate_policies (current_user_id),
    'User should satisfy the ABAC policy';
    -- Change user attribute
    PERFORM
        keyhippo_abac.set_user_attribute (current_user_id, 'department', '"sales"'::jsonb);
    -- Re-evaluate policy
    ASSERT NOT keyhippo_abac.evaluate_policies (current_user_id),
    'User should not satisfy the ABAC policy after attribute change';
END
$$;
