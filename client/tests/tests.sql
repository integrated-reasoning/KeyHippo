BEGIN;
-- Grant necessary permissions
GRANT USAGE ON SCHEMA keyhippo TO postgres;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA keyhippo TO postgres;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA keyhippo TO postgres;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA keyhippo TO postgres;
GRANT USAGE ON SCHEMA keyhippo_rbac TO postgres;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA keyhippo_rbac TO postgres;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA keyhippo_rbac TO postgres;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA keyhippo_rbac TO postgres;
GRANT USAGE ON SCHEMA keyhippo_abac TO postgres;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA keyhippo_abac TO postgres;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA keyhippo_abac TO postgres;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA keyhippo_abac TO postgres;
SET search_path TO keyhippo, keyhippo_rbac, keyhippo_abac, public, auth;
-- Create test users and set up authentication
DO $$
DECLARE
    user1_id uuid := gen_random_uuid ();
    user2_id uuid := gen_random_uuid ();
    admin_id uuid := gen_random_uuid ();
BEGIN
    SET local ROLE supabase_auth_admin;
    -- Insert users with explicit IDs
    INSERT INTO auth.users (id, email)
        VALUES (user1_id, 'user1@example.com'),
        (user2_id, 'user2@example.com'),
        (admin_id, 'admin@example.com');
    -- Store user IDs as settings for later use
    PERFORM
        set_config('test.user1_id', user1_id::text, TRUE);
    PERFORM
        set_config('test.user2_id', user2_id::text, TRUE);
    PERFORM
        set_config('test.admin_id', admin_id::text, TRUE);
    -- Set up initial authentication for admin
    PERFORM
        set_config('request.jwt.claim.sub', admin_id::text, TRUE);
    PERFORM
        set_config('request.jwt.claims', json_build_object('sub', admin_id)::text, TRUE);
END
$$;
-- Switch to postgres role for the remainder of the tests
SET local ROLE postgres;
-- Create scopes if they don't exist
INSERT INTO keyhippo.scopes (name, description)
    VALUES ('user_management', 'Manage user roles and attributes'),
    ('api_key_management', 'Manage API keys')
ON CONFLICT (name)
    DO NOTHING;
-- Create API keys for different scopes
DO $$
DECLARE
    user_management_key text;
    api_key_management_key text;
    user_specific_key text;
    user_management_scope_id uuid;
    api_key_management_scope_id uuid;
BEGIN
    -- Get scope IDs
    SELECT
        id INTO user_management_scope_id
    FROM
        keyhippo.scopes
    WHERE
        name = 'user_management';
    SELECT
        id INTO api_key_management_scope_id
    FROM
        keyhippo.scopes
    WHERE
        name = 'api_key_management';
    -- Create a key for user management
    SELECT
        api_key INTO user_management_key
    FROM
        keyhippo.create_api_key ('User Management Key', 'user_management');
    -- Create a key for API key management
    SELECT
        api_key INTO api_key_management_key
    FROM
        keyhippo.create_api_key ('API Key Management Key', 'api_key_management');
    -- Create a user-specific key (no scope)
    SELECT
        api_key INTO user_specific_key
    FROM
        keyhippo.create_api_key ('User-Specific Key');
    -- Store keys for later use
    PERFORM
        set_config('test.user_management_key', user_management_key, TRUE);
    PERFORM
        set_config('test.api_key_management_key', api_key_management_key, TRUE);
    PERFORM
        set_config('test.user_specific_key', user_specific_key, TRUE);
    -- Assign permissions to scopes
    INSERT INTO keyhippo_rbac.permissions (name, description)
        VALUES ('manage_roles', 'Manage user roles'),
        ('manage_user_attributes', 'Manage user attributes')
    ON CONFLICT (name)
        DO NOTHING;
    -- Link permissions to scopes
    INSERT INTO keyhippo.scope_permissions (scope_id, permission_id)
    SELECT
        user_management_scope_id,
        id
    FROM
        keyhippo_rbac.permissions
    WHERE
        name IN ('manage_roles', 'manage_user_attributes')
    ON CONFLICT
        DO NOTHING;
END
$$;
-- Test: Verify API key with scope
DO $$
DECLARE
    verified_result record;
    expected_permissions text[] := ARRAY['manage_roles', 'manage_user_attributes'];
BEGIN
    SELECT
        * INTO verified_result
    FROM
        keyhippo.verify_api_key (current_setting('test.user_management_key'));
    ASSERT verified_result.user_id = current_setting('test.admin_id')::uuid,
    'verify_api_key should return the correct user ID';
    ASSERT verified_result.scope_id IS NOT NULL,
    'verify_api_key should return a scope ID for scoped key';
    ASSERT verified_result.permissions @> expected_permissions,
    'User management key should have correct permissions. ' || 'Expected: ' || array_to_string(expected_permissions, ', ') || ', Actual: ' || array_to_string(verified_result.permissions, ', ');
END
$$;
-- Test: Attempt to use API key for unauthorized action
DO $$
BEGIN
    -- Use API key management key to try and set user attribute (should fail)
    PERFORM
        set_config('request.header.x-api-key', current_setting('test.api_key_management_key'), TRUE);
    BEGIN
        PERFORM
            keyhippo_abac.set_user_attribute (current_setting('test.user1_id')::uuid, 'test_attribute', '"test_value"'::jsonb);
        RAISE EXCEPTION 'Should not be able to set user attribute with API key management key';
    EXCEPTION
        WHEN insufficient_privilege THEN
            ASSERT SQLERRM LIKE '%Unauthorized to set user attributes%',
            'Should raise an Unauthorized error, but got: ' || SQLERRM;
    END;
END
$$;
-- Test: Use API key for authorized action
DO $$
BEGIN
    -- Use user management key to set user attribute (should succeed)
    PERFORM
        set_config('request.header.x-api-key', current_setting('test.user_management_key'), TRUE);
    PERFORM
        keyhippo_abac.set_user_attribute (current_setting('test.user1_id')::uuid, 'test_attribute', '"test_value"'::jsonb);
    -- Verify the attribute was set
    ASSERT EXISTS (
        SELECT
            1
        FROM
            keyhippo_abac.user_attributes
        WHERE
            user_id = current_setting('test.user1_id')::uuid
            AND attributes ->> 'test_attribute' = 'test_value'),
    'User attribute should be set successfully';
END
$$;
-- Test: RLS policy with API key
DO $$
DECLARE
    test_account_id uuid;
BEGIN
    -- Insert a test account for user1
    INSERT INTO public.test_accounts (user_id, name, email)
        VALUES (current_setting('test.user1_id')::uuid, 'Test User 1', 'testuser1@example.com')
    RETURNING
        id INTO test_account_id;
    -- Try to access the test account with user management key (should succeed)
    PERFORM
        set_config('request.header.x-api-key', current_setting('test.user_management_key'), TRUE);
    ASSERT EXISTS (
        SELECT
            1
        FROM
            public.test_accounts
        WHERE
            id = test_account_id), 'Should be able to access test account with user management key';
    -- Try to access the test account with user-specific key (should fail)
    PERFORM
        set_config('request.header.x-api-key', current_setting('test.user_specific_key'), TRUE);
    ASSERT NOT EXISTS (
        SELECT
            1
        FROM
            public.test_accounts
        WHERE
            id = test_account_id), 'Should not be able to access test account with user-specific key';
END
$$;
-- Clean up
ROLLBACK;
