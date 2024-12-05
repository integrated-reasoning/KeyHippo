BEGIN;
SET search_path TO keyhippo, keyhippo_rbac, public, auth;
-- Enable audit log trigger
SELECT
    keyhippo_internal.enable_audit_log_notify ();
-- Create test users and set up authentication
DO $$
DECLARE
    user1_id uuid := gen_random_uuid ();
    user2_id uuid := gen_random_uuid ();
    admin_group_id uuid;
    admin_role_id uuid;
BEGIN
    -- Insert users with explicit IDs
    INSERT INTO auth.users (id, email)
        VALUES (user1_id, 'user1@example.com'),
        (user2_id, 'user2@example.com');
    -- Store user IDs as settings for later use
    PERFORM
        set_config('test.user1_id', user1_id::text, TRUE);
    PERFORM
        set_config('test.user2_id', user2_id::text, TRUE);
    -- Initialize KeyHippo (this creates default groups and roles)
    PERFORM
        keyhippo.initialize_keyhippo ();
    -- Get the Admin Group and Role IDs
    SELECT
        id INTO admin_group_id
    FROM
        keyhippo_rbac.groups
    WHERE
        name = 'Admin Group';
    SELECT
        id INTO admin_role_id
    FROM
        keyhippo_rbac.roles
    WHERE
        name = 'Admin'
        AND group_id = admin_group_id;
    -- Assign admin role to user1
    -- Set up authentication for user1
    PERFORM
        set_config('request.jwt.claim.sub', user1_id::text, TRUE);
    PERFORM
        set_config('request.jwt.claims', json_build_object('sub', user1_id, 'role', 'authenticated', 'user_role', 'admin')::text, TRUE);
END
$$;
-- Switch to authenticated role
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
    -- Check groups
    SELECT
        COUNT(*) INTO group_count
    FROM
        keyhippo_rbac.groups;
    RAISE NOTICE 'Number of groups: %', group_count;
    RAISE NOTICE 'Group names: %', array_agg(name)
FROM
    keyhippo_rbac.groups;
    -- Check if the current user has permissions to see the groups
    RAISE NOTICE 'Can select from groups: %', EXISTS (
        SELECT
            1
        FROM
            information_schema.table_privileges
        WHERE
            table_schema = 'keyhippo_rbac'
            AND table_name = 'groups'
            AND privilege_type = 'SELECT'
            AND grantee = CURRENT_USER);
    ASSERT group_count = 2,
    'Two default groups should be created';
    SELECT
        COUNT(*) INTO role_count
    FROM
        keyhippo_rbac.roles;
    ASSERT role_count = 2,
    'Two default roles should be created';
    SELECT
        COUNT(*) INTO permission_count
    FROM
        keyhippo_rbac.permissions;
    ASSERT permission_count = 7,
    'Seven default permissions should be created';
    SELECT
        COUNT(*) INTO admin_role_permissions
    FROM
        keyhippo_rbac.role_permissions rp
        JOIN keyhippo_rbac.roles r ON rp.role_id = r.id
    WHERE
        r.name = 'Admin';
    ASSERT admin_role_permissions = 7,
    'Admin role should have all 7 permissions';
    SELECT
        COUNT(*) INTO user_role_permissions
    FROM
        keyhippo_rbac.role_permissions rp
        JOIN keyhippo_rbac.roles r ON rp.role_id = r.id
    WHERE
        r.name = 'User';
    ASSERT user_role_permissions = 1,
    'User role should have 1 permission (manage_api_keys)';
END
$$;
-- Test create_api_key function
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
    'create_api_key executes successfully for authenticated user';
    ASSERT created_key_result.api_key_id IS NOT NULL,
    'create_api_key returns a valid API key ID';
    SELECT
        COUNT(*) INTO key_count
    FROM
        keyhippo.api_key_metadata
    WHERE
        description = 'Test API Key'
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
    SELECT
        * INTO created_key_result
    FROM
        keyhippo.create_api_key ('Verify Test Key');
    SELECT
        * INTO verified_key_result
    FROM
        keyhippo.verify_api_key (created_key_result.api_key);
    ASSERT verified_key_result.user_id = current_setting('test.user1_id')::uuid,
    'verify_api_key should return the correct user_id';
    ASSERT verified_key_result.scope_id IS NULL,
    'verify_api_key should return NULL scope_id for default key';
    ASSERT array_length(verified_key_result.permissions, 1) > 0,
    'verify_api_key should return permissions';
END
$$;
-- Test revoke_api_key function
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
        * INTO revoke_result
    FROM
        keyhippo.revoke_api_key (created_key_result.api_key_id);
    ASSERT revoke_result = TRUE,
    'revoke_api_key should return TRUE for successful revocation';
    SELECT
        is_revoked INTO key_is_revoked
    FROM
        keyhippo.api_key_metadata
    WHERE
        id = created_key_result.api_key_id;
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
    SELECT
        * INTO created_key_result
    FROM
        keyhippo.create_api_key ('Rotate Test Key');
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
    SELECT
        is_revoked INTO old_key_revoked
    FROM
        keyhippo.api_key_metadata
    WHERE
        id = created_key_result.api_key_id;
    ASSERT old_key_revoked = TRUE,
    'Old API key should be revoked after rotation';
END
$$;
-- Test authorize function
DO $$
DECLARE
    authorized boolean;
BEGIN
    SELECT
        * INTO authorized
    FROM
        keyhippo.authorize ('manage_api_keys');
    ASSERT authorized = TRUE,
    'User should be authorized to manage API keys';
    SELECT
        * INTO authorized
    FROM
        keyhippo.authorize ('manage_groups');
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
    SELECT
        * INTO t_group_id
    FROM
        keyhippo_rbac.create_group ('Test Group', 'A test group');
    ASSERT t_group_id IS NOT NULL,
    'create_group should return a valid group ID';
    -- Test create_role
    SELECT
        * INTO t_role_id
    FROM
        keyhippo_rbac.create_role ('Test Role', 'A test role', t_group_id, 'user');
    ASSERT t_role_id IS NOT NULL,
    'create_role should return a valid role ID';
    -- Test assign_role_to_user
    PERFORM
        keyhippo_rbac.assign_role_to_user (t_user_id, t_group_id, t_role_id);
    ASSERT EXISTS (
        SELECT
            1
        FROM
            keyhippo_rbac.user_group_roles
        WHERE
            user_id = t_user_id
            AND group_id = t_group_id
            AND role_id = t_role_id),
    'assign_role_to_user should assign the role to the user';
    -- Test assign_permission_to_role
    PERFORM
        keyhippo_rbac.assign_permission_to_role (t_role_id, 'manage_api_keys');
    ASSERT EXISTS (
        SELECT
            1
        FROM
            keyhippo_rbac.role_permissions rp
            JOIN keyhippo_rbac.permissions p ON rp.permission_id = p.id
        WHERE
            rp.role_id = t_role_id
            AND p.name = 'manage_api_keys'),
    'assign_permission_to_role should assign the permission to the role';
END
$$;
-- Test key expiry notification
SET ROLE postgres;
DO $$
DECLARE
    v_api_key_id uuid;
    v_api_key text;
    v_user_id uuid;
    v_notification_sent boolean := FALSE;
    v_audit_log_entry jsonb;
BEGIN
    -- Set expiry notification time to 2 hours for testing purposes
    UPDATE
        keyhippo_internal.config
    SET
        value = '2'
    WHERE
        key = 'key_expiry_notification_hours';
    -- Ensure notifications are enabled
    UPDATE
        keyhippo_internal.config
    SET
        value = 'true'
    WHERE
        key = 'enable_key_expiry_notifications';
    -- Create a test user
    INSERT INTO auth.users (id, email)
        VALUES (gen_random_uuid (), 'testuser@example.com')
    RETURNING
        id INTO v_user_id;
    -- Login as the test user
    PERFORM
        set_config('request.jwt.claim.sub', v_user_id::text, TRUE);
    PERFORM
        set_config('request.jwt.claims', json_build_object('sub', v_user_id, 'role', 'authenticated')::text, TRUE);
    -- Create a test API key using the real create_api_key function
    SELECT
        api_key,
        api_key_id INTO v_api_key,
        v_api_key_id
    FROM
        keyhippo.create_api_key ('Test Expiring Key');
    RAISE NOTICE 'Created API key with ID: %', v_api_key_id;
    -- Logout
    PERFORM
        set_config('request.jwt.claim.sub', '', TRUE);
    PERFORM
        set_config('request.jwt.claims', '', TRUE);
    -- Update the expiry to trigger the notification
    UPDATE
        keyhippo.api_key_metadata
    SET
        expires_at = NOW() + INTERVAL '1 hour'
    WHERE
        id = v_api_key_id;
    RAISE NOTICE 'Updated API key expiry';
    -- Check if a notification was logged
    SELECT
        EXISTS (
            SELECT
                1
            FROM
                keyhippo.audit_log
            WHERE
                action = 'expiring_key'
                AND (data ->> 'expiring_key')::jsonb ->> 'id' = v_api_key_id::text
                AND timestamp > NOW() - INTERVAL '1 minute') INTO v_notification_sent;
    IF v_notification_sent THEN
        RAISE NOTICE 'Notification sent for key %', v_api_key_id;
        -- Fetch and display the audit log entry
        SELECT
            data INTO v_audit_log_entry
        FROM
            keyhippo.audit_log
        WHERE
            action = 'expiring_key'
            AND (data ->> 'expiring_key')::jsonb ->> 'id' = v_api_key_id::text
        ORDER BY
            timestamp DESC
        LIMIT 1;
        RAISE NOTICE 'Audit log entry: %', v_audit_log_entry;
    ELSE
        RAISE NOTICE 'No notification found for key %', v_api_key_id;
        -- Display recent audit log entries for debugging
        RAISE NOTICE 'Recent audit log entries:';
        FOR v_audit_log_entry IN (
            SELECT
                data
            FROM
                keyhippo.audit_log
            WHERE
                timestamp > NOW() - INTERVAL '5 minutes'
            ORDER BY
                timestamp DESC
            LIMIT 5)
        LOOP
            RAISE NOTICE '%', v_audit_log_entry;
        END LOOP;
    END IF;
    -- Cleanup
    DELETE FROM keyhippo.api_key_metadata
    WHERE id = v_api_key_id;
    DELETE FROM auth.users
    WHERE id = v_user_id;
    -- Assert the result
    ASSERT v_notification_sent,
    'An expiry notification should have been sent';
EXCEPTION
    WHEN OTHERS THEN
        -- Cleanup in case of error
        IF v_api_key_id IS NOT NULL THEN
            DELETE FROM keyhippo.api_key_metadata
            WHERE id = v_api_key_id;
            END IF;
    IF v_user_id IS NOT NULL THEN
        DELETE FROM auth.users
        WHERE id = v_user_id;
        END IF;
    RAISE;
END
$$;
-- Test access request functions
--SET ROLE authenticated;
DO $$
DECLARE
    user1_id uuid := current_setting('test.user1_id')::uuid;
    user2_id uuid := current_setting('test.user2_id')::uuid;
    request_id1 uuid;
    request_id2 uuid;
    access_granted boolean;
    visible_requests int;
    debug_info text;
BEGIN
    -- Set up JWT claims for user1 (admin)
    PERFORM
        set_config('request.jwt.claims', json_build_object('sub', user1_id, 'role', 'authenticated', 'user_role', 'admin')::text, TRUE);
    -- Test request_access function for user1
    SELECT
        keyhippo.request_access ('test_resource', 'read') INTO request_id1;
    -- Switch to user2
    PERFORM
        set_config('request.jwt.claims', json_build_object('sub', user2_id, 'role', 'authenticated', 'user_role', 'user')::text, TRUE);
    -- Test request_access function for user2
    SELECT
        keyhippo.request_access ('test_resource', 'write') INTO request_id2;
    -- Check that user2 can only see their own request
    SELECT
        COUNT(*) INTO visible_requests
    FROM
        keyhippo.access_requests;
    SELECT
        current_setting('keyhippo.debug', TRUE) INTO debug_info;
    RAISE NOTICE 'User2 visible requests: %, Debug info: %', visible_requests, debug_info;
    ASSERT visible_requests = 1,
    'User2 should only see their own request';
    -- Verify user2 can't see user1's request
    ASSERT NOT EXISTS (
        SELECT
            1
        FROM
            keyhippo.access_requests
        WHERE
            user_id = user1_id), 'User2 should not be able to see user1''s requests';
    -- Switch back to user1 (admin)
    PERFORM
        set_config('request.jwt.claims', json_build_object('sub', user1_id, 'role', 'authenticated', 'user_role', 'admin')::text, TRUE);
    -- Verify admin can see all requests
    SELECT
        COUNT(*) INTO visible_requests
    FROM
        keyhippo.access_requests;
    SELECT
        current_setting('keyhippo.debug', TRUE) INTO debug_info;
    RAISE NOTICE 'Admin visible requests: %, Debug info: %', visible_requests, debug_info;
    ASSERT visible_requests = 2,
    'Admin should be able to see all requests';
END
$$;
DO $$
DECLARE
    user1_id uuid := current_setting('test.user1_id')::uuid;
    user2_id uuid := current_setting('test.user2_id')::uuid;
    request_id uuid;
    access_granted boolean;
BEGIN
    -- Set up JWT claims for user1 (admin)
    PERFORM
        set_config('request.jwt.claims', json_build_object('sub', user1_id, 'role', 'authenticated', 'user_role', 'admin')::text, TRUE);
    -- Test request_access function
    SELECT
        keyhippo.request_access ('test_resource', 'read') INTO request_id;
    ASSERT request_id IS NOT NULL,
    'request_access should return a valid request ID';
    -- Verify the request was created
    ASSERT EXISTS (
        SELECT
            1
        FROM
            keyhippo.access_requests
        WHERE
            id = request_id
            AND user_id = user1_id
            AND resource_name = 'test_resource'
            AND action = 'read'),
    'Access request should be created in the database';
    -- Test is_granted_access function (should return false for a new request)
    SELECT
        keyhippo.is_granted_access ('test_resource', 'read') INTO access_granted;
    ASSERT access_granted = FALSE,
    'Access should not be granted for a new request';
    -- Test review_access_request function
    PERFORM
        keyhippo.review_access_request (request_id, TRUE);
    -- Verify the request was approved
    ASSERT EXISTS (
        SELECT
            1
        FROM
            keyhippo.access_requests
        WHERE
            id = request_id
            AND status = 'approved'),
    'Access request should be approved';
    -- Test is_granted_access function again (should now return true)
    SELECT
        keyhippo.is_granted_access ('test_resource', 'read') INTO access_granted;
    ASSERT access_granted = TRUE,
    'Access should be granted after approval';
    -- Test access request for another user
    PERFORM
        set_config('request.jwt.claims', json_build_object('sub', user2_id, 'role', 'authenticated', 'user_role', 'user')::text, TRUE);
    SELECT
        keyhippo.request_access ('test_resource', 'write') INTO request_id;
    ASSERT request_id IS NOT NULL,
    'request_access should work for another user';
    -- Verify the new user can't see other user's requests
    ASSERT NOT EXISTS (
        SELECT
            1
        FROM
            keyhippo.access_requests
        WHERE
            user_id = user1_id), 'User should not be able to see other users requests';
    -- Switch back to the admin user
    PERFORM
        set_config('request.jwt.claims', json_build_object('sub', user1_id, 'role', 'authenticated', 'user_role', 'admin')::text, TRUE);
    -- Verify admin can see all requests
    ASSERT EXISTS (
        SELECT
            1
        FROM
            keyhippo.access_requests
        WHERE
            user_id = user2_id), 'Admin should be able to see all user requests';
END
$$;
-- Test access request functions and RLS policies
DO $$
DECLARE
    user1_id uuid := current_setting('test.user1_id')::uuid;
    user2_id uuid := current_setting('test.user2_id')::uuid;
    request_id1 uuid;
    request_id2 uuid;
    access_granted boolean;
    visible_requests int;
BEGIN
    -- Set up JWT claims for user1 (admin)
    PERFORM
        set_config('request.jwt.claims', json_build_object('sub', user1_id, 'role', 'authenticated', 'user_role', 'admin')::text, TRUE);
    -- Test request_access function for user1
    SELECT
        keyhippo.request_access ('test_resource', 'read') INTO request_id1;
    ASSERT request_id1 IS NOT NULL,
    'request_access should return a valid request ID for user1';
    -- Verify the request was created for user1
    ASSERT EXISTS (
        SELECT
            1
        FROM
            keyhippo.access_requests
        WHERE
            id = request_id1
            AND user_id = user1_id
            AND resource_name = 'test_resource'
            AND action = 'read'),
    'Access request should be created in the database for user1';
    -- Switch to user2
    PERFORM
        set_config('request.jwt.claims', json_build_object('sub', user2_id, 'role', 'authenticated', 'user_role', 'user')::text, TRUE);
    -- Test request_access function for user2
    SELECT
        keyhippo.request_access ('test_resource', 'write') INTO request_id2;
    ASSERT request_id2 IS NOT NULL,
    'request_access should return a valid request ID for user2';
    -- Verify the request was created for user2
    ASSERT EXISTS (
        SELECT
            1
        FROM
            keyhippo.access_requests
        WHERE
            id = request_id2
            AND user_id = user2_id
            AND resource_name = 'test_resource'
            AND action = 'write'),
    'Access request should be created in the database for user2';
    -- Check that user2 can only see their own request
    SELECT
        COUNT(*) INTO visible_requests
    FROM
        keyhippo.access_requests;
    ASSERT visible_requests = 1,
    'User2 should only see their own request';
    -- Verify user2 can't see user1's request
    ASSERT NOT EXISTS (
        SELECT
            1
        FROM
            keyhippo.access_requests
        WHERE
            user_id = user1_id), 'User2 should not be able to see user1''s requests';
    -- Switch back to user1 (admin)
    PERFORM
        set_config('request.jwt.claims', json_build_object('sub', user1_id, 'role', 'authenticated', 'user_role', 'admin')::text, TRUE);
    -- Verify admin can see all requests
    SELECT
        COUNT(*) INTO visible_requests
    FROM
        keyhippo.access_requests;
    ASSERT visible_requests = 2,
    'Admin should be able to see all requests';
    -- Test review_access_request function
    PERFORM
        keyhippo.review_access_request (request_id2, TRUE);
    -- Verify the request was approved
    ASSERT EXISTS (
        SELECT
            1
        FROM
            keyhippo.access_requests
        WHERE
            id = request_id2
            AND status = 'approved'),
    'Access request should be approved';
    -- Switch back to user2
    PERFORM
        set_config('request.jwt.claims', json_build_object('sub', user2_id, 'role', 'authenticated', 'user_role', 'user')::text, TRUE);
    -- Test is_granted_access function (should now return true for user2)
    SELECT
        keyhippo.is_granted_access ('test_resource', 'write') INTO access_granted;
    ASSERT access_granted = TRUE,
    'Access should be granted after approval for user2';
END
$$;
-- Clean up
ROLLBACK;
