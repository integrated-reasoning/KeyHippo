BEGIN;
SET search_path TO keyhippo, public, auth;
-- Create test users and set up authentication
DO $$
DECLARE
    user1_id uuid := gen_random_uuid ();
    user2_id uuid := gen_random_uuid ();
    admin_group_id uuid;
    admin_role_id uuid;
BEGIN
    RAISE NOTICE 'Debug: Creating test users';
    -- Switch to a role with elevated privileges to insert users
    SET local ROLE postgres;
    -- Insert users with explicit IDs
    INSERT INTO auth.users (id, email)
        VALUES (user1_id, 'user1@example.com'),
        (user2_id, 'user2@example.com');
    RAISE NOTICE 'Debug: Users created with IDs: % and %', user1_id, user2_id;
    -- Store user IDs as settings for later use
    PERFORM
        set_config('test.user1_id', user1_id::text, TRUE);
    PERFORM
        set_config('test.user2_id', user2_id::text, TRUE);
    RAISE NOTICE 'Debug: User IDs stored in settings';
    -- Ensure 'Admin Group' exists
    INSERT INTO keyhippo_rbac.groups (name, description)
        VALUES ('Admin Group', 'Group for administrators')
    ON CONFLICT (name)
        DO UPDATE SET
            description = EXCLUDED.description
        RETURNING
            id INTO admin_group_id;
    RAISE NOTICE 'Debug: Admin Group created/updated with ID: %', admin_group_id;
    -- Ensure 'Admin' role exists and is associated with 'Admin Group'
    INSERT INTO keyhippo_rbac.roles (name, description, group_id)
        VALUES ('Admin', 'Administrator role', admin_group_id)
    ON CONFLICT (name, group_id)
        DO UPDATE SET
            description = EXCLUDED.description
        RETURNING
            id INTO admin_role_id;
    RAISE NOTICE 'Debug: Admin Role created/updated with ID: %', admin_role_id;
    -- Ensure 'manage_user_attributes' permission exists
    INSERT INTO keyhippo_rbac.permissions (name, description)
        VALUES ('manage_user_attributes', 'Permission to manage user attributes')
    ON CONFLICT (name)
        DO NOTHING;
    RAISE NOTICE 'Debug: manage_user_attributes permission created/updated';
    -- Assign 'manage_user_attributes' permission to 'Admin' role
    INSERT INTO keyhippo_rbac.role_permissions (role_id, permission_id)
    SELECT
        admin_role_id,
        id
    FROM
        keyhippo_rbac.permissions
    WHERE
        name = 'manage_user_attributes'
    ON CONFLICT (role_id,
        permission_id)
        DO NOTHING;
    RAISE NOTICE 'Debug: manage_user_attributes permission assigned to Admin role';
    -- Assign user1 to 'Admin' role
    INSERT INTO keyhippo_rbac.user_group_roles (user_id, group_id, role_id)
        VALUES (user1_id, admin_group_id, admin_role_id)
    ON CONFLICT (user_id, group_id, role_id)
        DO NOTHING;
    RAISE NOTICE 'Debug: User1 assigned to Admin role';
    -- Update claims cache for user1
    PERFORM
        keyhippo_rbac.update_user_claims_cache (user1_id);
    RAISE NOTICE 'Debug: Claims cache updated for User1';
    -- Set up authentication context for user1
    PERFORM
        set_config('request.jwt.claim.sub', user1_id::text, TRUE);
    PERFORM
        set_config('request.jwt.claims', json_build_object('sub', user1_id, 'role', 'authenticated')::text, TRUE);
    RAISE NOTICE 'Debug: Authentication context set up for User1';
END
$$;
-- Log current user and session details
DO $$
DECLARE
    CURRENT_USER text := CURRENT_USER;
    SESSION_USER text := SESSION_USER;
    search_path text;
BEGIN
    SELECT
        setting INTO search_path
    FROM
        pg_settings
    WHERE
        name = 'search_path';
    RAISE NOTICE 'Debug: Current user: %, Session user: %, Search path: %', CURRENT_USER, SESSION_USER, search_path;
END
$$;
-- Fetch and set group and role IDs
DO $$
DECLARE
    admin_group uuid;
    user_group uuid;
    admin_role uuid;
    user_role uuid;
BEGIN
    -- Fetch Admin Group ID
    SELECT
        id INTO admin_group
    FROM
        keyhippo_rbac.groups
    WHERE
        name = 'Admin Group';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Admin Group not found';
    END IF;
    RAISE NOTICE 'Debug: Admin Group ID fetched: %', admin_group;
    -- Fetch User Group ID
    SELECT
        id INTO user_group
    FROM
        keyhippo_rbac.groups
    WHERE
        name = 'User Group';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User Group not found';
    END IF;
    RAISE NOTICE 'Debug: User Group ID fetched: %', user_group;
    -- Fetch Admin Role ID
    SELECT
        id INTO admin_role
    FROM
        keyhippo_rbac.roles
    WHERE
        name = 'Admin'
        AND group_id = admin_group;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Admin Role not found in Admin Group';
    END IF;
    RAISE NOTICE 'Debug: Admin Role ID fetched: %', admin_role;
    -- Fetch User Role ID
    SELECT
        id INTO user_role
    FROM
        keyhippo_rbac.roles
    WHERE
        name = 'User'
        AND group_id = user_group;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User Role not found in User Group';
    END IF;
    RAISE NOTICE 'Debug: User Role ID fetched: %', user_role;
    -- Set custom configuration parameters
    PERFORM
        set_config('test.admin_group_id', admin_group::text, TRUE);
    PERFORM
        set_config('test.user_group_id', user_group::text, TRUE);
    PERFORM
        set_config('test.admin_role_id', admin_role::text, TRUE);
    PERFORM
        set_config('test.user_role_id', user_role::text, TRUE);
    RAISE NOTICE 'Debug: Group and Role IDs set in configuration';
END
$$;
-- Test 1: Verify initial state (no API keys)
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
    RAISE NOTICE 'Debug: Test 1 passed - No initial API keys';
END
$$;
-- Test 2: Create an API key
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
    RAISE NOTICE 'Debug: Test 2 passed - API key created successfully';
END
$$;
-- Continue with the rest of the tests, adding RAISE NOTICE statements for debugging...
-- Test 25: keyhippo.is_authorized function test
DO $$
DECLARE
    v_admin_group_id uuid;
    v_admin_role_id uuid;
    v_admin_user_id uuid;
    v_manage_users_permission_id uuid;
    v_regular_user_id uuid;
    v_test_table_id oid;
    v_user_group_id uuid;
    v_user_role_id uuid;
    v_view_reports_permission_id uuid;
BEGIN
    RAISE NOTICE 'Debug: Starting test setup';
    -- Create test users
    INSERT INTO auth.users (id, email)
        VALUES (gen_random_uuid (), 'admin@example.com')
    RETURNING
        id INTO v_admin_user_id;
    RAISE NOTICE 'Debug: Admin user created with ID: %', v_admin_user_id;
    INSERT INTO auth.users (id, email)
        VALUES (gen_random_uuid (), 'user@example.com')
    RETURNING
        id INTO v_regular_user_id;
    RAISE NOTICE 'Debug: Regular user created with ID: %', v_regular_user_id;
    -- Insert groups if they don't exist
    INSERT INTO keyhippo_rbac.groups (name)
        VALUES ('Admin Group'),
        ('User Group')
    ON CONFLICT (name)
        DO NOTHING;
    RAISE NOTICE 'Debug: Groups inserted';
    -- Retrieve group IDs
    SELECT
        id INTO v_admin_group_id
    FROM
        keyhippo_rbac.groups
    WHERE
        name = 'Admin Group';
    RAISE NOTICE 'Debug: Admin group ID: %', v_admin_group_id;
    SELECT
        id INTO v_user_group_id
    FROM
        keyhippo_rbac.groups
    WHERE
        name = 'User Group';
    RAISE NOTICE 'Debug: User group ID: %', v_user_group_id;
    -- Insert roles if they don't exist
    INSERT INTO keyhippo_rbac.roles (name, group_id)
        VALUES ('Admin', v_admin_group_id),
        ('User', v_user_group_id)
    ON CONFLICT (name, group_id)
        DO NOTHING;
    RAISE NOTICE 'Debug: Roles inserted';
    -- Retrieve role IDs
    SELECT
        id INTO v_admin_role_id
    FROM
        keyhippo_rbac.roles
    WHERE
        name = 'Admin'
        AND group_id = v_admin_group_id;
    RAISE NOTICE 'Debug: Admin role ID: %', v_admin_role_id;
    SELECT
        id INTO v_user_role_id
    FROM
        keyhippo_rbac.roles
    WHERE
        name = 'User'
        AND group_id = v_user_group_id;
    RAISE NOTICE 'Debug: User role ID: %', v_user_role_id;
    -- Create permissions
    INSERT INTO keyhippo_rbac.permissions (name)
        VALUES ('manage_users'),
        ('view_reports')
    ON CONFLICT (name)
        DO NOTHING;
    -- Retrieve permission IDs
    SELECT
        id INTO v_manage_users_permission_id
    FROM
        keyhippo_rbac.permissions
    WHERE
        name = 'manage_users';
    SELECT
        id INTO v_view_reports_permission_id
    FROM
        keyhippo_rbac.permissions
    WHERE
        name = 'view_reports';
    RAISE NOTICE 'Debug: Permissions created/retrieved. manage_users ID: %, view_reports ID: %', v_manage_users_permission_id, v_view_reports_permission_id;
    -- Assign permissions to roles
    INSERT INTO keyhippo_rbac.role_permissions (role_id, permission_id)
        VALUES (v_admin_role_id, v_manage_users_permission_id),
        (v_admin_role_id, v_view_reports_permission_id),
        (v_user_role_id, v_view_reports_permission_id)
    ON CONFLICT (role_id, permission_id)
        DO NOTHING;
    RAISE NOTICE 'Debug: Permissions assigned to roles';
    -- Assign users to roles
    INSERT INTO keyhippo_rbac.user_group_roles (user_id, group_id, role_id)
        VALUES (v_admin_user_id, v_admin_group_id, v_admin_role_id),
        (v_regular_user_id, v_user_group_id, v_user_role_id)
    ON CONFLICT (user_id, group_id, role_id)
        DO NOTHING;
    RAISE NOTICE 'Debug: Users assigned to roles';
    -- Create a test table
    CREATE TABLE IF NOT EXISTS public.test_reports (
        id serial PRIMARY KEY,
        report_data text
    );
    RAISE NOTICE 'Debug: Test table created';
    SELECT
        oid INTO v_test_table_id
    FROM
        pg_class
    WHERE
        relname = 'test_reports';
    RAISE NOTICE 'Debug: Test table ID: %', v_test_table_id;
    -- Test admin user permissions
    SET LOCAL ROLE authenticated;
    PERFORM
        set_config('request.jwt.claim.sub', v_admin_user_id::text, TRUE);
    RAISE NOTICE 'Debug: About to test admin permissions';
    ASSERT keyhippo.is_authorized (v_test_table_id::regclass,
        'manage_users') = TRUE,
    'Admin should be authorized to manage users';
    RAISE NOTICE 'Debug: Admin manage_users test passed';
    ASSERT keyhippo.is_authorized (v_test_table_id::regclass,
        'view_reports') = TRUE,
    'Admin should be authorized to view reports';
    RAISE NOTICE 'Debug: Admin view_reports test passed';
    -- Test regular user permissions
    PERFORM
        set_config('request.jwt.claim.sub', v_regular_user_id::text, TRUE);
    RAISE NOTICE 'Debug: About to test regular user permissions';
    ASSERT keyhippo.is_authorized (v_test_table_id::regclass,
        'manage_users') = FALSE,
    'Regular user should not be authorized to manage users';
    RAISE NOTICE 'Debug: Regular user manage_users test passed';
    ASSERT keyhippo.is_authorized (v_test_table_id::regclass,
        'view_reports') = TRUE,
    'Regular user should be authorized to view reports';
    RAISE NOTICE 'Debug: Regular user view_reports test passed';
    -- Test non-existent permission
    ASSERT keyhippo.is_authorized (v_test_table_id::regclass,
        'non_existent_permission') = FALSE,
    'Non-existent permission should return false';
    RAISE NOTICE 'Debug: Non-existent permission test passed';
    -- Test with null user
    PERFORM
        set_config('request.jwt.claim.sub', NULL, TRUE);
    RAISE NOTICE 'Debug: About to test null user';
    ASSERT keyhippo.is_authorized (v_test_table_id::regclass,
        'view_reports') = FALSE,
    'Null user should not be authorized';
    RAISE NOTICE 'Debug: Null user test passed';
END
$$;
-- ROLLBACK to ensure no test data persists
ROLLBACK;
