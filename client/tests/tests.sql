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
-- Test adding user to a group and assigning roles (RBAC)
DO $$
DECLARE
    user1_id uuid := current_setting('test.user1_id')::uuid;
    user2_id uuid := current_setting('test.user2_id')::uuid;
    admin_group_id uuid;
    admin_role_id uuid;
BEGIN
    -- Create group and role if not exists
    INSERT INTO keyhippo_rbac.groups (name, description)
        VALUES ('Test Admin Group', 'Group for testing RBAC')
    ON CONFLICT (name)
        DO UPDATE SET
            description = 'Group for testing RBAC';
    SELECT
        id INTO admin_group_id
    FROM
        keyhippo_rbac.groups
    WHERE
        name = 'Test Admin Group';
    INSERT INTO keyhippo_rbac.roles (name, description, group_id)
        VALUES ('Admin Role', 'Role with admin privileges', admin_group_id)
    ON CONFLICT (name)
        DO UPDATE SET
            description = 'Role with admin privileges';
    SELECT
        id INTO admin_role_id
    FROM
        keyhippo_rbac.roles
    WHERE
        name = 'Admin Role';
    -- Add user1 to the Admin Group and assign Admin Role
    PERFORM
        keyhippo_rbac.add_user_to_group (user1_id, admin_group_id, 'Admin Role');
    -- Verify that user1 is assigned to the Admin Role
    ASSERT EXISTS (
        SELECT
            1
        FROM
            keyhippo_rbac.user_group_roles
        WHERE
            user_id = user1_id
            AND group_id = admin_group_id
            AND role_id = admin_role_id),
    'User1 should be assigned to the Admin Role in the Admin Group';
    -- Verify that user2 is not in the Admin Role
    ASSERT NOT EXISTS (
        SELECT
            1
        FROM
            keyhippo_rbac.user_group_roles
        WHERE
            user_id = user2_id
            AND group_id = admin_group_id),
    'User2 should not have the Admin Role';
END
$$;
-- Test updating user claims cache (RBAC)
DO $$
DECLARE
    user1_id uuid := current_setting('test.user1_id')::uuid;
    claims jsonb;
BEGIN
    -- Manually update user1's claims cache
    PERFORM
        keyhippo_rbac.update_user_claims_cache (user1_id);
    -- Check that the claims cache has been updated
    SELECT
        rbac_claims INTO claims
    FROM
        keyhippo_rbac.claims_cache
    WHERE
        user_id = user1_id;
    ASSERT claims @> '{"Test Admin Group": ["Admin Role"]}',
    'User1 should have Admin Role in Test Admin Group within the claims cache';
END
$$;
-- Test ABAC policy creation and evaluation
DO $$
DECLARE
    user1_id uuid := current_setting('test.user1_id')::uuid;
    user2_id uuid := current_setting('test.user2_id')::uuid;
    abac_policy jsonb;
    result boolean;
BEGIN
    -- Create an ABAC policy that requires a "department" attribute to be "engineering"
    abac_policy := jsonb_build_object('attribute', 'department', 'type', 'attribute_equals', 'value', 'engineering');
    PERFORM
        keyhippo_abac.create_policy ('Engineering Department Policy', 'Policy for engineering department', abac_policy);
    -- Assign "department" attribute to user1 as "engineering"
    INSERT INTO keyhippo_abac.user_attributes (user_id, attributes)
        VALUES (user1_id, jsonb_build_object('department', 'engineering'))
    ON CONFLICT (user_id)
        DO UPDATE SET
            attributes = jsonb_build_object('department', 'engineering');
    -- Assign "department" attribute to user2 as "sales"
    INSERT INTO keyhippo_abac.user_attributes (user_id, attributes)
        VALUES (user2_id, jsonb_build_object('department', 'sales'))
    ON CONFLICT (user_id)
        DO UPDATE SET
            attributes = jsonb_build_object('department', 'sales');
    -- Evaluate ABAC policies for user1
    SELECT
        keyhippo_abac.evaluate_policies (user1_id) INTO result;
    ASSERT result = TRUE,
    'User1 should pass the engineering department ABAC policy';
    -- Evaluate ABAC policies for user2
    SELECT
        keyhippo_abac.evaluate_policies (user2_id) INTO result;
    ASSERT result = FALSE,
    'User2 should fail the engineering department ABAC policy';
END
$$;
-- Test assigning parent role (RBAC hierarchy)
DO $$
DECLARE
    child_role_id uuid;
    parent_role_id uuid;
BEGIN
    -- Create parent and child roles
    INSERT INTO keyhippo_rbac.roles (name, description, group_id)
        VALUES ('Parent Role', 'Parent role for testing hierarchy', (
                SELECT
                    id
                FROM
                    keyhippo_rbac.groups
                WHERE
                    name = 'Test Admin Group'))
    ON CONFLICT (name)
        DO UPDATE SET
            description = 'Parent role for testing hierarchy';
    SELECT
        id INTO parent_role_id
    FROM
        keyhippo_rbac.roles
    WHERE
        name = 'Parent Role';
    INSERT INTO keyhippo_rbac.roles (name, description, group_id)
        VALUES ('Child Role', 'Child role for testing hierarchy', (
                SELECT
                    id
                FROM
                    keyhippo_rbac.groups
                WHERE
                    name = 'Test Admin Group'))
    ON CONFLICT (name)
        DO UPDATE SET
            description = 'Child role for testing hierarchy';
    SELECT
        id INTO child_role_id
    FROM
        keyhippo_rbac.roles
    WHERE
        name = 'Child Role';
    -- Assign child role a parent role
    PERFORM
        keyhippo_rbac.set_parent_role (child_role_id, parent_role_id);
    -- Verify that the parent-child relationship is established
    ASSERT EXISTS (
        SELECT
            1
        FROM
            keyhippo_rbac.roles
        WHERE
            id = child_role_id
            AND parent_role_id = parent_role_id),
    'Child Role should have Parent Role as its parent';
    -- Verify circular hierarchy prevention
    BEGIN
        PERFORM
            keyhippo_rbac.set_parent_role (parent_role_id, child_role_id);
        ASSERT FALSE,
        'Should not be able to set circular role hierarchy';
    EXCEPTION
        WHEN OTHERS THEN
            ASSERT sqlerrm LIKE '%Circular role hierarchy detected%',
            'Circular role hierarchy should be prevented';
    END;
END
$$;
-- Test ABAC attribute retrieval
DO $$
DECLARE
    user1_id uuid := current_setting('test.user1_id')::uuid;
    department jsonb;
BEGIN
    -- Retrieve the "department" attribute for user1
    SELECT
        keyhippo_abac.get_user_attribute (user1_id, 'department') INTO department;
    ASSERT department = '"engineering"',
    'User1 should have the "engineering" department attribute';
END
$$;
-- Test RLS policy enforcement for RBAC tables
DO $$
DECLARE
    user1_id uuid := current_setting('test.user1_id')::uuid;
    user2_id uuid := current_setting('test.user2_id')::uuid;
    group_count bigint;
BEGIN
    -- Check access to groups table
    SELECT
        count(*) INTO group_count
    FROM
        keyhippo_rbac.groups;
    ASSERT group_count > 0,
    'Authenticated user should have access to groups table';
    -- Switch to user2 (without admin privileges)
    PERFORM
        set_config('request.jwt.claim.sub', user2_id::text, TRUE);
    PERFORM
        set_config('request.jwt.claims', json_build_object('sub', user2_id)::text, TRUE);
    -- Ensure user2 does not have access to groups table
    BEGIN
        SELECT
            count(*) INTO group_count
        FROM
            keyhippo_rbac.groups;
        ASSERT FALSE,
        'User2 should not have access to groups table';
    EXCEPTION
        WHEN OTHERS THEN
            ASSERT sqlerrm LIKE '%permission denied%',
            'User2 should be denied access to groups table';
    END;
    -- Switch back to user1 (with admin privileges)
    PERFORM
        set_config('request.jwt.claim.sub', user1_id::text, TRUE);
    PERFORM
        set_config('request.jwt.claims', json_build_object('sub', user1_id)::text, TRUE);
END
$$;
-- Clean up
ROLLBACK;
