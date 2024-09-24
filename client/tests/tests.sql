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
-- Test api_key_id_owner_id access
DO $$
DECLARE
    count_result bigint;
BEGIN
    SELECT
        count(*) INTO count_result
    FROM
        keyhippo.api_key_id_owner_id
    WHERE
        user_id = current_setting('test.user1_id')::uuid;
    ASSERT count_result IS NOT NULL,
    'Authenticated user can access api_key_id_owner_id table';
    ASSERT count_result = 0,
    'Initially, no API keys exist for the user';
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
        keyhippo.create_api_key (current_setting('test.user1_id'), 'Test API Key');
    ASSERT created_key_result.api_key IS NOT NULL,
    'create_api_key executes successfully for authenticated user';
    ASSERT created_key_result.api_key_id IS NOT NULL,
    'create_api_key returns a valid API key ID';
    SELECT
        count(*) INTO key_count
    FROM
        keyhippo.api_key_id_name
    WHERE
        name = 'Test API Key'
        AND api_key_id IN (
            SELECT
                api_key_id
            FROM
                keyhippo.api_key_id_owner_id
            WHERE
                user_id = current_setting('test.user1_id')::uuid);
    ASSERT key_count = 1,
    'An API key should be created with the given name for the authenticated user';
END
$$;
-- Attempt to create API key for another user
DO $$
BEGIN
    BEGIN
        PERFORM
            keyhippo.create_api_key (current_setting('test.user2_id'), 'Malicious API Key');
        ASSERT FALSE,
        'Should not be able to create API key for another user';
    EXCEPTION
        WHEN OTHERS THEN
            ASSERT sqlerrm LIKE '%[KeyHippo] Unauthorized: Invalid user ID%',
            'Authenticated user cannot create API key for another user';
    END;
END
$$;
-- Test get_api_key_metadata function
DO $$
DECLARE
    created_key_result record;
    metadata_name text;
BEGIN
    SELECT
        * INTO created_key_result
    FROM
        keyhippo.create_api_key (current_setting('test.user1_id'), 'Metadata Test Key');
    RAISE NOTICE 'Created API key: %, ID: %', created_key_result.api_key, created_key_result.api_key_id;
    SELECT
        name INTO metadata_name
    FROM
        keyhippo.get_api_key_metadata (current_setting('test.user1_id')::uuid)
    WHERE
        api_key_id = created_key_result.api_key_id;
    RAISE NOTICE 'metadata_name: %', metadata_name;
    ASSERT metadata_name = 'Metadata Test Key',
    'get_api_key_metadata returns correct data for the authenticated user';
END
$$;
-- Attempt to get API key metadata for another user
DO $$
DECLARE
    other_user_key_count bigint;
BEGIN
    SELECT
        count(*) INTO other_user_key_count
    FROM
        keyhippo.get_api_key_metadata (current_setting('test.user2_id')::uuid);
    ASSERT other_user_key_count = 0,
    'get_api_key_metadata returns no data for other users';
END
$$;
-- Test rotating an API key as the owner
DO $$
DECLARE
    created_key_result record;
    rotated_key_result record;
    key_count bigint;
    is_revoked boolean;
    metadata_name text;
BEGIN
    -- Create an API key for user1
    SELECT
        * INTO created_key_result
    FROM
        keyhippo.create_api_key (current_setting('test.user1_id'), 'Rotate Test Key');
    ASSERT created_key_result.api_key IS NOT NULL,
    'API key created successfully for rotation test';
    -- Rotate the API key
    SELECT
        * INTO rotated_key_result
    FROM
        keyhippo.rotate_api_key (created_key_result.api_key_id);
    ASSERT rotated_key_result.new_api_key IS NOT NULL,
    'rotate_api_key returns a new API key';
    ASSERT rotated_key_result.new_api_key_id IS NOT NULL,
    'rotate_api_key returns a new API key ID';
    -- Check that the old API key is revoked
    SELECT
        EXISTS (
            SELECT
                1
            FROM
                keyhippo.api_key_id_revoked
            WHERE
                api_key_id = created_key_result.api_key_id) INTO is_revoked;
    ASSERT is_revoked,
    'Old API key is revoked after rotation';
    -- Check that the new API key exists
    SELECT
        count(*) INTO key_count
    FROM
        keyhippo.api_key_id_owner_id
    WHERE
        api_key_id = rotated_key_result.new_api_key_id
        AND user_id = current_setting('test.user1_id')::uuid;
    ASSERT key_count = 1,
    'New API key is associated with the user after rotation';
    -- Verify that the new API key has the same name as the old one
    SELECT
        name INTO metadata_name
    FROM
        keyhippo.api_key_id_name
    WHERE
        api_key_id = rotated_key_result.new_api_key_id;
    ASSERT metadata_name = 'Rotate Test Key',
    'New API key retains the same name after rotation';
    -- Optional: Additional checks can be added here
END
$$;
-- Attempt to rotate API key as another user
DO $$
DECLARE
    created_key_result record;
BEGIN
    -- Create an API key for user1
    SELECT
        * INTO created_key_result
    FROM
        keyhippo.create_api_key (current_setting('test.user1_id'), 'Unauthorized Rotate Test Key');
    -- Attempt to rotate the API key as user2
    -- Set authentication to user2
    PERFORM
        set_config('request.jwt.claim.sub', current_setting('test.user2_id'), TRUE);
    PERFORM
        set_config('request.jwt.claims', json_build_object('sub', current_setting('test.user2_id')::uuid)::text, TRUE);
    BEGIN
        SELECT
            *
        FROM
            keyhippo.rotate_api_key (created_key_result.api_key_id);
        ASSERT FALSE,
        'Should not be able to rotate another user''s API key';
    EXCEPTION
        WHEN OTHERS THEN
            ASSERT sqlerrm LIKE '%[KeyHippo] Unauthorized%',
            'Cannot rotate API key owned by another user';
    END;
    -- Restore authentication to user1
    PERFORM
        set_config('request.jwt.claim.sub', current_setting('test.user1_id'), TRUE);
    PERFORM
        set_config('request.jwt.claims', json_build_object('sub', current_setting('test.user1_id')::uuid)::text, TRUE);
END
$$;
ROLLBACK;

-- ================================================================
-- RBAC + ABAC Test Suite for KeyHippo
-- ================================================================
-- Begin a transaction to ensure tests do not affect the actual data
BEGIN;
-- Set up test environment
SET search_path TO keyhippo_rbac, keyhippo_abac, public, auth;
-- -------------------------------
-- 1. Create Test Users
-- -------------------------------
DO $$
BEGIN
    -- Insert test users with explicit IDs
    INSERT INTO auth.users (id, email)
        VALUES ('11111111-1111-1111-1111-111111111111', 'test_admin@example.com'),
        ('22222222-2222-2222-2222-222222222222', 'test_user@example.com')
    ON CONFLICT
        DO NOTHING;
END
$$;
-- -------------------------------
-- 2. Assign Roles to Users
-- -------------------------------
-- Assign Admin Role to test_admin
DO $$
BEGIN
    -- Assign 'Admin' role to 'test_admin' in 'Admin Group'
    PERFORM
        keyhippo_rbac.assign_role_to_user ('11111111-1111-1111-1111-111111111111'::uuid, -- test_admin_id
            (
                SELECT
                    id
                FROM keyhippo_rbac.groups
                WHERE
                    name = 'Admin Group'), -- Admin Group ID
            'Admin' -- Role Name
);
END
$$;
-- Assign User Role to test_user
DO $$
BEGIN
    -- Assign 'User' role to 'test_user' in 'User Group'
    PERFORM
        keyhippo_rbac.assign_role_to_user ('22222222-2222-2222-2222-222222222222'::uuid, -- test_user_id
            (
                SELECT
                    id
                FROM keyhippo_rbac.groups
                WHERE
                    name = 'User Group'), -- User Group ID
            'User' -- Role Name
);
END
$$;
-- -------------------------------
-- 3. Verify Role Assignments
-- -------------------------------
-- Verify that Admin Role is assigned to test_admin
DO $$
DECLARE
    admin_role_count integer;
BEGIN
    SELECT
        COUNT(*) INTO admin_role_count
    FROM
        keyhippo_rbac.user_group_roles
    WHERE
        user_id = '11111111-1111-1111-1111-111111111111'::uuid
        AND role_id = (
            SELECT
                id
            FROM
                keyhippo_rbac.roles
            WHERE
                name = 'Admin');
    ASSERT admin_role_count = 1,
    'Admin Role assigned to test_admin';
END
$$;
-- Verify that User Role is assigned to test_user
DO $$
DECLARE
    user_role_count integer;
BEGIN
    SELECT
        COUNT(*) INTO user_role_count
    FROM
        keyhippo_rbac.user_group_roles
    WHERE
        user_id = '22222222-2222-2222-2222-222222222222'::uuid
        AND role_id = (
            SELECT
                id
            FROM
                keyhippo_rbac.roles
            WHERE
                name = 'User');
    ASSERT user_role_count = 1,
    'User Role assigned to test_user';
END
$$;
-- -------------------------------
-- 4. Verify Role Permissions
-- -------------------------------
-- Verify that Admin Role has all permissions
DO $$
DECLARE
    admin_permissions_count integer;
BEGIN
    SELECT
        COUNT(*) INTO admin_permissions_count
    FROM
        keyhippo_rbac.role_permissions rp
        JOIN keyhippo_rbac.permissions p ON rp.permission_id = p.id
    WHERE
        rp.role_id = (
            SELECT
                id
            FROM
                keyhippo_rbac.roles
            WHERE
                name = 'Admin');
    ASSERT admin_permissions_count = 4,
    'Admin Role has all permissions';
END
$$;
-- Verify that User Role has read and write permissions only
DO $$
DECLARE
    user_permissions_count integer;
BEGIN
    SELECT
        COUNT(*) INTO user_permissions_count
    FROM
        keyhippo_rbac.role_permissions rp
        JOIN keyhippo_rbac.permissions p ON rp.permission_id = p.id
    WHERE
        rp.role_id = (
            SELECT
                id
            FROM
                keyhippo_rbac.roles
            WHERE
                name = 'User');
    ASSERT user_permissions_count = 2,
    'User Role has read and write permissions only';
END
$$;
-- -------------------------------
-- 5. ABAC Policy Creation and Verification
-- -------------------------------
-- Create ABAC Policy: Engineering Access
DO $$
BEGIN
    PERFORM
        keyhippo_abac.create_policy ('Engineering Access', 'Access restricted to engineering department', '{"type": "attribute_equals", "attribute": "department", "value": "engineering"}'::jsonb);
END
$$;
-- Verify ABAC Policy Creation
DO $$
DECLARE
    policy_count integer;
BEGIN
    SELECT
        COUNT(*) INTO policy_count
    FROM
        keyhippo_abac.policies
    WHERE
        name = 'Engineering Access';
    ASSERT policy_count = 1,
    'ABAC Policy "Engineering Access" created';
END
$$;
-- -------------------------------
-- 6. Assign Attributes to Users
-- -------------------------------
-- Assign both "department" and "location" attributes to test_admin
DO $$
BEGIN
    INSERT INTO keyhippo_abac.user_attributes (user_id, attributes)
        VALUES ('11111111-1111-1111-1111-111111111111'::uuid, '{"department": "engineering", "location": "HQ"}'::jsonb)
    ON CONFLICT (user_id)
        DO UPDATE SET
            attributes = keyhippo_abac.user_attributes.attributes || EXCLUDED.attributes;
END
$$;
-- Assign "department" attribute to test_user as "sales"
DO $$
BEGIN
    INSERT INTO keyhippo_abac.user_attributes (user_id, attributes)
        VALUES ('22222222-2222-2222-2222-222222222222'::uuid, '{"department": "sales"}'::jsonb)
    ON CONFLICT (user_id)
        DO UPDATE SET
            attributes = keyhippo_abac.user_attributes.attributes || EXCLUDED.attributes;
END
$$;
-- -------------------------------
-- 7. Evaluate ABAC Policies
-- -------------------------------
-- Evaluate policies for test_admin (should pass both policies)
DO $$
DECLARE
    policy_result boolean;
BEGIN
    policy_result := keyhippo_abac.evaluate_policies ('11111111-1111-1111-1111-111111111111'::uuid);
    RAISE NOTICE 'Policy evaluation result: %', policy_result;
    ASSERT policy_result = TRUE,
    'test_admin should satisfy all ABAC policies (department and location)';
END
$$;
-- Evaluate policies for test_user (should fail)
DO $$
DECLARE
    policy_result boolean;
BEGIN
    policy_result := keyhippo_abac.evaluate_policies ('22222222-2222-2222-2222-222222222222'::uuid);
    ASSERT policy_result = FALSE,
    'test_user does not satisfy ABAC policies';
END
$$;
-- -------------------------------
-- 8. Claims Cache Verification
-- -------------------------------
-- Update claims cache for test_admin
DO $$
BEGIN
    PERFORM
        keyhippo_rbac.update_user_claims_cache ('11111111-1111-1111-1111-111111111111'::uuid);
END
$$;
-- Update claims cache for test_user
DO $$
BEGIN
    PERFORM
        keyhippo_rbac.update_user_claims_cache ('22222222-2222-2222-2222-222222222222'::uuid);
END
$$;
-- Verify claims_cache for test_admin using Group UUID
DO $$
DECLARE
    claims jsonb;
    admin_group_id text;
BEGIN
    -- Retrieve Admin Group ID
    SELECT
        id::text INTO admin_group_id
    FROM
        keyhippo_rbac.groups
    WHERE
        name = 'Admin Group';
    -- Retrieve claims_cache
    SELECT
        rbac_claims INTO claims
    FROM
        keyhippo_rbac.claims_cache
    WHERE
        user_id = '11111111-1111-1111-1111-111111111111'::uuid;
    -- Construct expected JSONB with group UUID as key
    ASSERT claims @> jsonb_build_object(admin_group_id, ARRAY['Admin'])::jsonb,
    'test_admin has correct claims_cache entries';
END
$$;
-- Verify claims_cache for test_user using Group UUID
DO $$
DECLARE
    claims jsonb;
    user_group_id text;
BEGIN
    -- Retrieve User Group ID
    SELECT
        id::text INTO user_group_id
    FROM
        keyhippo_rbac.groups
    WHERE
        name = 'User Group';
    -- Retrieve claims_cache
    SELECT
        rbac_claims INTO claims
    FROM
        keyhippo_rbac.claims_cache
    WHERE
        user_id = '22222222-2222-2222-2222-222222222222'::uuid;
    -- Construct expected JSONB with group UUID as key
    ASSERT claims @> jsonb_build_object(user_group_id, ARRAY['User'])::jsonb,
    'test_user has correct claims_cache entries';
END
$$;
-- -------------------------------
-- 9. ABAC Policy Evaluation with Missing Attributes
-- -------------------------------
-- Create ABAC Policy: HQ Access
DO $$
BEGIN
    PERFORM
        keyhippo_abac.create_policy ('HQ Access', 'Access restricted to HQ location', '{"type": "attribute_equals", "attribute": "location", "value": "HQ"}'::jsonb);
END
$$;
-- Verify ABAC Policy Creation for HQ Access
DO $$
DECLARE
    policy_count integer;
BEGIN
    SELECT
        COUNT(*) INTO policy_count
    FROM
        keyhippo_abac.policies
    WHERE
        name = 'HQ Access';
    ASSERT policy_count = 1,
    'ABAC Policy "HQ Access" created';
END
$$;
-- Check existing ABAC policies
DO $$
DECLARE
    policy_record RECORD;
BEGIN
    FOR policy_record IN
    SELECT
        *
    FROM
        keyhippo_abac.policies LOOP
            RAISE NOTICE 'Policy: % - %', policy_record.name, policy_record.policy;
        END LOOP;
END
$$;
-- Check test_admin attributes
DO $$
DECLARE
    user_attributes jsonb;
BEGIN
    SELECT
        attributes INTO user_attributes
    FROM
        keyhippo_abac.user_attributes
    WHERE
        user_id = '11111111-1111-1111-1111-111111111111'::uuid;
    RAISE NOTICE 'test_admin attributes: %', user_attributes;
END
$$;
-- Remove "location" attribute from test_admin
DO $$
BEGIN
    UPDATE
        keyhippo_abac.user_attributes
    SET
        attributes = attributes - 'location'
    WHERE
        user_id = '11111111-1111-1111-1111-111111111111'::uuid;
END
$$;
-- Check test_admin attributes after removal
DO $$
DECLARE
    user_attributes jsonb;
BEGIN
    SELECT
        attributes INTO user_attributes
    FROM
        keyhippo_abac.user_attributes
    WHERE
        user_id = '11111111-1111-1111-1111-111111111111'::uuid;
    RAISE NOTICE 'test_admin attributes after removal: %', user_attributes;
END
$$;
-- Check test_admin attributes before policy evaluation
DO $$
DECLARE
    user_attributes jsonb;
BEGIN
    SELECT
        attributes INTO user_attributes
    FROM
        keyhippo_abac.user_attributes
    WHERE
        user_id = '11111111-1111-1111-1111-111111111111'::uuid;
    RAISE NOTICE 'test_admin attributes immediately before policy evaluation: %', user_attributes;
END
$$;
-- Evaluate policies for test_admin before adding "location" attribute (should fail)
DO $$
DECLARE
    policy_result boolean;
BEGIN
    policy_result := keyhippo_abac.evaluate_policies ('11111111-1111-1111-1111-111111111111'::uuid);
    IF policy_result = FALSE THEN
        RAISE NOTICE 'Test passed: test_admin does not satisfy all ABAC policies due to missing "location" attribute';
    ELSE
        RAISE EXCEPTION 'Test failed: test_admin unexpectedly satisfies all ABAC policies without "location" attribute';
    END IF;
END
$$;
-- Assign "location" attribute to test_admin as "HQ"
DO $$
BEGIN
    UPDATE
        keyhippo_abac.user_attributes
    SET
        attributes = attributes || '{"location": "HQ"}'::jsonb
    WHERE
        user_id = '11111111-1111-1111-1111-111111111111'::uuid;
END
$$;
-- Check test_admin attributes after adding location
DO $$
DECLARE
    user_attributes jsonb;
BEGIN
    SELECT
        attributes INTO user_attributes
    FROM
        keyhippo_abac.user_attributes
    WHERE
        user_id = '11111111-1111-1111-1111-111111111111'::uuid;
    RAISE NOTICE 'test_admin attributes after adding location: %', user_attributes;
END
$$;
-- Re-evaluate policies for test_admin after adding "location" attribute (should pass)
DO $$
DECLARE
    policy_result boolean;
BEGIN
    policy_result := keyhippo_abac.evaluate_policies ('11111111-1111-1111-1111-111111111111'::uuid);
    IF policy_result = TRUE THEN
        RAISE NOTICE 'Test passed: test_admin now satisfies all ABAC policies after adding "location" attribute';
    ELSE
        RAISE EXCEPTION 'Test failed: test_admin does not satisfy all ABAC policies even after adding "location" attribute';
    END IF;
END
$$;
-- -------------------------------
-- 10. Clean Up After Tests
-- -------------------------------
-- Rollback the transaction to clean up test data
ROLLBACK;
