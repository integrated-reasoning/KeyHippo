BEGIN;

SET search_path TO keyhippo, keyhippo_rbac, public;

-- Create test users and set up authentication (as postgres since we need insert permissions)
SET ROLE postgres;
DO $$
DECLARE
    user1_id uuid := gen_random_uuid();
    user2_id uuid := gen_random_uuid();
    admin_group_id uuid;
    admin_role_id uuid;
    user_group_id uuid;
    user_role_id uuid;
BEGIN
    -- Insert users with explicit IDs
    INSERT INTO auth.users (id, email)
    VALUES (user1_id, 'user1@example.com'),
           (user2_id, 'user2@example.com');
    
    -- Store user IDs as settings for later use
    PERFORM set_config('test.user1_id', user1_id::text, TRUE);
    PERFORM set_config('test.user2_id', user2_id::text, TRUE);
    
    -- Get the Admin Group and Role IDs (should exist from initialization)
    SELECT id INTO admin_group_id
    FROM keyhippo_rbac.groups
    WHERE name = 'Admin Group';
    
    SELECT id INTO admin_role_id
    FROM keyhippo_rbac.roles
    WHERE name = 'Admin' AND group_id = admin_group_id;
    
    SELECT id INTO user_group_id
    FROM keyhippo_rbac.groups
    WHERE name = 'User Group';
    
    SELECT id INTO user_role_id
    FROM keyhippo_rbac.roles
    WHERE name = 'User' AND group_id = user_group_id;
    
    -- Assign admin role to user1
    INSERT INTO keyhippo_rbac.user_group_roles (user_id, group_id, role_id)
    VALUES (user1_id, admin_group_id, admin_role_id)
    ON CONFLICT (user_id, group_id, role_id) DO NOTHING;
    
    -- Assign user role to user2  
    INSERT INTO keyhippo_rbac.user_group_roles (user_id, group_id, role_id)
    VALUES (user2_id, user_group_id, user_role_id)
    ON CONFLICT (user_id, group_id, role_id) DO NOTHING;
    
    -- Set up authentication for user1 (admin)
    PERFORM set_config('request.jwt.claim.sub', user1_id::text, TRUE);
    PERFORM set_config('request.jwt.claims', 
        json_build_object('sub', user1_id, 'role', 'authenticated', 'user_role', 'admin')::text, TRUE);
END
$$;

-- Switch to authenticated role for most tests
SET ROLE authenticated;

-- Test RBAC initialization
DO $$
DECLARE
    group_count integer;
    role_count integer;
    permission_count integer;
    admin_role_permissions integer;
    user_role_permissions integer;
BEGIN
    RAISE NOTICE 'Current user: %', CURRENT_USER;
    RAISE NOTICE 'Current role: %', CURRENT_ROLE;
    
    -- Check groups (should work because we have admin role)
    SELECT COUNT(*) INTO group_count FROM keyhippo_rbac.groups;
    RAISE NOTICE 'Number of groups: %', group_count;
    
    ASSERT group_count = 2, 'Two default groups should be created';
    
    SELECT COUNT(*) INTO role_count FROM keyhippo_rbac.roles;
    ASSERT role_count = 2, 'Two default roles should be created';
    
    SELECT COUNT(*) INTO permission_count FROM keyhippo_rbac.permissions;
    ASSERT permission_count = 6, 'Six default permissions should be created';
    
    SELECT COUNT(*) INTO admin_role_permissions
    FROM keyhippo_rbac.role_permissions rp
    JOIN keyhippo_rbac.roles r ON rp.role_id = r.id
    WHERE r.name = 'Admin';
    ASSERT admin_role_permissions = 6, 'Admin role should have all 6 permissions';
    
    SELECT COUNT(*) INTO user_role_permissions
    FROM keyhippo_rbac.role_permissions rp
    JOIN keyhippo_rbac.roles r ON rp.role_id = r.id
    WHERE r.name = 'User';
    ASSERT user_role_permissions = 1, 'User role should have 1 permission (manage_api_keys)';
END
$$;

-- Test RLS is working - switch to user role and verify restricted access
DO $$
DECLARE
    group_count integer;
    user2_id uuid := current_setting('test.user2_id')::uuid;
BEGIN
    -- Set up authentication for user2 (regular user)
    PERFORM set_config('request.jwt.claim.sub', user2_id::text, TRUE);
    PERFORM set_config('request.jwt.claims', 
        json_build_object('sub', user2_id, 'role', 'authenticated', 'user_role', 'user')::text, TRUE);
    
    -- Try to access groups - should fail because user doesn't have manage_groups permission
    BEGIN
        SELECT COUNT(*) INTO group_count FROM keyhippo_rbac.groups;
        ASSERT group_count = 0, 'User without manage_groups permission should see no groups due to RLS';
    EXCEPTION
        WHEN insufficient_privilege THEN
            RAISE NOTICE 'RLS properly blocked access to groups table';
    END;
    
    -- Switch back to admin user
    PERFORM set_config('request.jwt.claim.sub', current_setting('test.user1_id'), TRUE);
    PERFORM set_config('request.jwt.claims', 
        json_build_object('sub', current_setting('test.user1_id')::uuid, 'role', 'authenticated', 'user_role', 'admin')::text, TRUE);
END
$$;

-- Test create_api_key function
DO $$
DECLARE
    created_key_result record;
    key_count bigint;
BEGIN
    SELECT * INTO created_key_result
    FROM keyhippo.create_api_key('Test API Key');
    
    ASSERT created_key_result.api_key IS NOT NULL,
        'create_api_key executes successfully for authenticated user';
    ASSERT created_key_result.api_key_id IS NOT NULL,
        'create_api_key returns a valid API key ID';
    
    SELECT COUNT(*) INTO key_count
    FROM keyhippo.api_key_metadata
    WHERE description = 'Test API Key'
    AND user_id = current_setting('test.user1_id')::uuid;
    
    ASSERT key_count = 1,
        'An API key should be created with the given name for the authenticated user';
END
$$;

-- Test verify_api_key function
DO $$
DECLARE
    created_key_result record;
    verified_key_result record;
BEGIN
    SELECT * INTO created_key_result
    FROM keyhippo.create_api_key('Verify Test Key');
    
    SELECT * INTO verified_key_result
    FROM keyhippo.verify_api_key(created_key_result.api_key);
    
    ASSERT verified_key_result.user_id = current_setting('test.user1_id')::uuid,
        'verify_api_key should return the correct user_id';
    ASSERT verified_key_result.scope_id IS NULL,
        'verify_api_key should return NULL scope_id for default key';
END
$$;

-- Test revoke_api_key function
DO $$
DECLARE
    created_key_result record;
    revoke_result boolean;
    key_is_revoked boolean;
BEGIN
    SELECT * INTO created_key_result
    FROM keyhippo.create_api_key('Revoke Test Key');
    
    SELECT * INTO revoke_result
    FROM keyhippo.revoke_api_key(created_key_result.api_key_id);
    
    ASSERT revoke_result = TRUE,
        'revoke_api_key should return TRUE for successful revocation';
    
    SELECT is_revoked INTO key_is_revoked
    FROM keyhippo.api_key_metadata
    WHERE id = created_key_result.api_key_id;
    
    ASSERT key_is_revoked = TRUE,
        'API key should be marked as revoked';
END
$$;

-- Test rotate_api_key function
DO $$
DECLARE
    created_key_result record;
    rotated_key_result record;
    old_key_revoked boolean;
BEGIN
    SELECT * INTO created_key_result
    FROM keyhippo.create_api_key('Rotate Test Key');
    
    SELECT * INTO rotated_key_result
    FROM keyhippo.rotate_api_key(created_key_result.api_key_id);
    
    ASSERT rotated_key_result.new_api_key IS NOT NULL,
        'rotate_api_key should return a new API key';
    ASSERT rotated_key_result.new_api_key_id IS NOT NULL,
        'rotate_api_key should return a new API key ID';
    ASSERT rotated_key_result.new_api_key_id != created_key_result.api_key_id,
        'New API key ID should be different from the old one';
    
    SELECT is_revoked INTO old_key_revoked
    FROM keyhippo.api_key_metadata
    WHERE id = created_key_result.api_key_id;
    
    ASSERT old_key_revoked = TRUE,
        'Old API key should be revoked after rotation';
END
$$;

-- Test authorize function
DO $$
DECLARE
    authorized boolean;
BEGIN
    SELECT * INTO authorized
    FROM keyhippo.authorize('manage_api_keys');
    
    ASSERT authorized = TRUE,
        'Admin user should be authorized to manage API keys';
    
    SELECT * INTO authorized
    FROM keyhippo.authorize('manage_groups');
    
    ASSERT authorized = TRUE,
        'Admin user should be authorized to manage groups';
END
$$;

-- Test RBAC functions
DO $$
DECLARE
    t_group_id uuid;
    t_role_id uuid;
    t_user_id uuid := current_setting('test.user1_id')::uuid;
BEGIN
    -- Test create_group
    SELECT * INTO t_group_id
    FROM keyhippo_rbac.create_group('Test Group', 'A test group');
    
    ASSERT t_group_id IS NOT NULL,
        'create_group should return a valid group ID';
    
    -- Test create_role
    SELECT * INTO t_role_id
    FROM keyhippo_rbac.create_role('Test Role', 'A test role', t_group_id, 'user');
    
    ASSERT t_role_id IS NOT NULL,
        'create_role should return a valid role ID';
    
    -- Test assign_role_to_user
    PERFORM keyhippo_rbac.assign_role_to_user(t_user_id, t_group_id, t_role_id);
    
    ASSERT EXISTS (
        SELECT 1
        FROM keyhippo_rbac.user_group_roles
        WHERE user_id = t_user_id
        AND group_id = t_group_id
        AND role_id = t_role_id
    ), 'assign_role_to_user should assign the role to the user';
    
    -- Test assign_permission_to_role
    PERFORM keyhippo_rbac.assign_permission_to_role(t_role_id, 'manage_api_keys');
    
    ASSERT EXISTS (
        SELECT 1
        FROM keyhippo_rbac.role_permissions rp
        JOIN keyhippo_rbac.permissions p ON rp.permission_id = p.id
        WHERE rp.role_id = t_role_id
        AND p.name = 'manage_api_keys'
    ), 'assign_permission_to_role should assign the permission to the role';
END
$$;

-- Test current_user_context function
DO $$
DECLARE
    ctx record;
BEGIN
    SELECT * INTO ctx FROM keyhippo.current_user_context();
    
    ASSERT ctx.user_id = current_setting('test.user1_id')::uuid,
        'current_user_context should return the correct user_id';
    ASSERT ctx.permissions IS NOT NULL,
        'current_user_context should return permissions array';
    ASSERT array_length(ctx.permissions, 1) > 0,
        'current_user_context should return non-empty permissions';
END
$$;

-- Test key_data function
DO $$
DECLARE
    key_data_result jsonb;
BEGIN
    -- Test with no API key (should return NULL)
    SELECT keyhippo.key_data() INTO key_data_result;
    ASSERT key_data_result IS NULL,
        'key_data should return NULL when no API key is present';
END
$$;

-- Test default role assignment trigger (as postgres role)
SET ROLE postgres;
DO $$
DECLARE
    test_user_id uuid;
    role_assigned boolean;
BEGIN
    -- Create a new user
    INSERT INTO auth.users (email) 
    VALUES ('trigger_test@example.com')
    RETURNING id INTO test_user_id;
    
    -- Check if default role was assigned
    SELECT EXISTS (
        SELECT 1
        FROM keyhippo_rbac.user_group_roles ugr
        JOIN keyhippo_rbac.roles r ON ugr.role_id = r.id
        WHERE ugr.user_id = test_user_id
        AND r.name = 'User'
    ) INTO role_assigned;
    
    ASSERT role_assigned = TRUE,
        'Default User role should be assigned to new users automatically';
    
    -- Clean up
    DELETE FROM auth.users WHERE id = test_user_id;
END
$$;

-- Test update_key_claims function
SET ROLE authenticated;
DO $$
DECLARE
    created_key_result record;
    updated_claims jsonb := '{"test": "value", "number": 42}';
    retrieved_claims jsonb;
BEGIN
    SELECT * INTO created_key_result
    FROM keyhippo.create_api_key('Claims Test Key');
    
    -- Update claims
    PERFORM keyhippo.update_key_claims(created_key_result.api_key_id, updated_claims);
    
    -- Retrieve claims
    SELECT claims INTO retrieved_claims
    FROM keyhippo.api_key_metadata
    WHERE id = created_key_result.api_key_id;
    
    ASSERT retrieved_claims = updated_claims,
        'update_key_claims should update the claims correctly';
END
$$;

-- Test scope functionality
DO $$
DECLARE
    test_scope_id uuid;
    scope_count bigint;
    api_key_result record;
BEGIN
    -- Test creating a scope (switch to postgres for this)
    SET ROLE postgres;
    INSERT INTO keyhippo.scopes (name, description)
    VALUES ('test_scope', 'Test scope for testing')
    RETURNING id INTO test_scope_id;
    
    SET ROLE authenticated;
    
    -- Verify scope was created
    SELECT COUNT(*) INTO scope_count
    FROM keyhippo.scopes
    WHERE name = 'test_scope';
    
    ASSERT scope_count = 1,
        'Test scope should be created successfully';
    
    -- Test creating API key with scope
    SELECT * INTO api_key_result
    FROM keyhippo.create_api_key('Scoped Key', 'test_scope');
    
    ASSERT api_key_result.api_key IS NOT NULL,
        'Should be able to create API key with valid scope';
    
    -- Verify the scope is associated
    ASSERT EXISTS (
        SELECT 1
        FROM keyhippo.api_key_metadata
        WHERE id = api_key_result.api_key_id
        AND scope_id = test_scope_id
    ), 'API key should be associated with the correct scope';
END
$$;

-- Test audit logging functionality
DO $$
DECLARE
    initial_audit_count bigint;
    final_audit_count bigint;
    test_group_id uuid;
BEGIN
    -- Count initial audit log entries
    SELECT COUNT(*) INTO initial_audit_count FROM keyhippo.audit_log;
    
    -- Perform an action that should be audited
    SELECT * INTO test_group_id
    FROM keyhippo_rbac.create_group('Audit Test Group', 'Group for audit testing');
    
    -- Count final audit log entries
    SELECT COUNT(*) INTO final_audit_count FROM keyhippo.audit_log;
    
    ASSERT final_audit_count > initial_audit_count,
        'Creating a group should generate audit log entries';
    
    -- Verify the audit log contains the expected entry
    ASSERT EXISTS (
        SELECT 1
        FROM keyhippo.audit_log
        WHERE action = 'INSERT'
        AND table_name = 'groups'
        AND data->>'new_data' IS NOT NULL
    ), 'Audit log should contain INSERT entry for groups table';
END
$$;

-- Test is_authorized function
DO $$
DECLARE
    authorized boolean;
BEGIN
    SELECT keyhippo.is_authorized('keyhippo_rbac.groups', 'manage_groups') INTO authorized;
    ASSERT authorized = TRUE,
        'is_authorized should return TRUE for admin user with manage_groups permission';
END
$$;

DO $$
BEGIN
    RAISE NOTICE 'All tests passed successfully!';
END
$$;

ROLLBACK;