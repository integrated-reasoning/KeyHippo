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
    -- Switch to a role with elevated privileges to insert users
    SET local ROLE postgres;
    -- Insert users with explicit IDs
    INSERT INTO auth.users (id, email)
        VALUES (user1_id, 'user1@example.com'),
        (user2_id, 'user2@example.com');
    -- Store user IDs as settings for later use
    PERFORM
        set_config('test.user1_id', user1_id::text, TRUE);
    PERFORM
        set_config('test.user2_id', user2_id::text, TRUE);
    -- Ensure 'Admin Group' exists
    INSERT INTO keyhippo_rbac.groups (name, description)
        VALUES ('Admin Group', 'Group for administrators')
    ON CONFLICT (name)
        DO UPDATE SET
            description = EXCLUDED.description
        RETURNING
            id INTO admin_group_id;
    -- Ensure 'Admin' role exists and is associated with 'Admin Group'
    INSERT INTO keyhippo_rbac.roles (name, description, group_id)
        VALUES ('Admin', 'Administrator role', admin_group_id)
    ON CONFLICT (name, group_id)
        DO UPDATE SET
            description = EXCLUDED.description
        RETURNING
            id INTO admin_role_id;
    -- Ensure 'manage_user_attributes' permission exists
    INSERT INTO keyhippo_rbac.permissions (name, description)
        VALUES ('manage_user_attributes', 'Permission to manage user attributes')
    ON CONFLICT (name)
        DO NOTHING;
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
    -- Assign user1 to 'Admin' role
    INSERT INTO keyhippo_rbac.user_group_roles (user_id, group_id, role_id)
        VALUES (user1_id, admin_group_id, admin_role_id)
    ON CONFLICT (user_id, group_id, role_id)
        DO NOTHING;
    -- Update claims cache for user1
    PERFORM
        keyhippo_rbac.update_user_claims_cache (user1_id);
    -- Set up authentication context for user1
    PERFORM
        set_config('request.jwt.claim.sub', user1_id::text, TRUE);
    PERFORM
        set_config('request.jwt.claims', json_build_object('sub', user1_id, 'role', 'authenticated')::text, TRUE);
END
$$;
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
    -- Log the details (or raise an exception to view)
    RAISE NOTICE 'Current user: %, Session user: %, Search path: %', CURRENT_USER, SESSION_USER, search_path;
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
    -- Set custom configuration parameters
    PERFORM
        set_config('test.admin_group_id', admin_group::text, TRUE);
    PERFORM
        set_config('test.user_group_id', user_group::text, TRUE);
    PERFORM
        set_config('test.admin_role_id', admin_role::text, TRUE);
    PERFORM
        set_config('test.user_role_id', user_role::text, TRUE);
END
$$;
-- API Key Management Tests
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
END
$$;
-- Test 3: Verify API key authentication
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
-- Test 4: Rotate an API key
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
-- Test 5: Revoke an API key
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
-- Test 6: Handle invalid API key creation
DO $$
BEGIN
    -- Attempt to create an API key with invalid description
    BEGIN
        PERFORM
            keyhippo.create_api_key ('Invalid Key Description !@#$%^&*()');
        ASSERT FALSE,
        'create_api_key should throw an error for invalid description';
    EXCEPTION
        WHEN OTHERS THEN
            ASSERT SQLSTATE = 'P0001',
            'create_api_key should throw exception with SQLSTATE P0001 for invalid description';
    ASSERT POSITION('[KeyHippo] Invalid key description' IN SQLERRM) > 0,
    'Error message should contain "[KeyHippo] Invalid key description"';
    END;
END
$$;
-- Test 7: Prevent SQL injection in API key creation
DO $$
DECLARE
    valid_key_result record;
    key_count bigint;
BEGIN
    -- Create a valid API key
    SELECT
        * INTO valid_key_result
    FROM
        keyhippo.create_api_key ('Valid Test Key');
    ASSERT valid_key_result.api_key IS NOT NULL,
    'Valid API key should be created successfully';
    -- Attempt SQL injection via API key description
    BEGIN
        PERFORM
            keyhippo.create_api_key ('Attack Key''; UPDATE keyhippo.api_key_metadata SET description = ''Attacked'';--');
        ASSERT FALSE,
        'create_api_key should throw an error for SQL injection attempt';
    EXCEPTION
        WHEN OTHERS THEN
            ASSERT SQLSTATE = 'P0001',
            'create_api_key should throw exception with SQLSTATE P0001 for invalid description';
    ASSERT POSITION('[KeyHippo] Invalid key description' IN SQLERRM) > 0,
    'Error message should contain "[KeyHippo] Invalid key description"';
    END;
    -- Verify that the attack did not alter existing API keys
    SELECT
        COUNT(*) INTO key_count
    FROM
        keyhippo.api_key_metadata
    WHERE
        description = 'Attacked';
    ASSERT key_count = 0,
    'No API key descriptions should be altered by SQL injection attempt';
END
$$;
-- RBAC and ABAC Tests
-- Test 8: Add user to a group with a role (RBAC)
DO $$
DECLARE
    group_id uuid := current_setting('test.admin_group_id')::uuid;
    role_name text := 'Admin';
    claims_cache_result jsonb;
BEGIN
    -- Add user to group with role
    PERFORM
        keyhippo_rbac.add_user_to_group (current_setting('test.user1_id')::uuid, group_id, role_name);
    -- Query claims cache directly to verify
    SELECT
        rbac_claims INTO claims_cache_result
    FROM
        keyhippo_rbac.claims_cache
    WHERE
        user_id = current_setting('test.user1_id')::uuid;
    ASSERT claims_cache_result IS NOT NULL,
    'Claims cache should be updated for the user';
    ASSERT (claims_cache_result ->> group_id::text) IS NOT NULL,
    'User should have claims for the group';
    ASSERT (claims_cache_result -> group_id::text) ? 'Admin',
    'User should have the Admin role in claims cache';
END
$$;
-- Test 9: Set parent role in RBAC hierarchy
DO $$
DECLARE
    child_role_id uuid := current_setting('test.user_role_id')::uuid;
    v_parent_role_id uuid := current_setting('test.admin_role_id')::uuid;
    retrieved_parent_role_id uuid;
BEGIN
    -- Set parent role
    PERFORM
        keyhippo_rbac.set_parent_role (child_role_id, v_parent_role_id);
    -- Verify the parent role assignment
    SELECT
        parent_role_id INTO retrieved_parent_role_id
    FROM
        keyhippo_rbac.roles
    WHERE
        id = child_role_id;
    ASSERT retrieved_parent_role_id = v_parent_role_id,
    'Parent role should be correctly assigned';
END
$$;
-- Test 10: Prevent circular role hierarchies
DO $$
DECLARE
    child_role_id uuid := current_setting('test.user_role_id')::uuid;
    parent_role_id uuid := current_setting('test.admin_role_id')::uuid;
BEGIN
    -- Set parent role initially
    PERFORM
        keyhippo_rbac.set_parent_role (child_role_id, parent_role_id);
    -- Attempt to create a circular hierarchy
    BEGIN
        PERFORM
            keyhippo_rbac.set_parent_role (parent_role_id, child_role_id);
        ASSERT FALSE,
        'set_parent_role should throw an error for circular hierarchy';
    EXCEPTION
        WHEN OTHERS THEN
            ASSERT SQLSTATE = 'P0001',
            'set_parent_role should throw exception with SQLSTATE P0001 for circular hierarchy';
    ASSERT POSITION('Circular role hierarchy detected' IN SQLERRM) > 0,
    'Error message should indicate circular hierarchy detection';
    END;
END
$$;
-- Test 11: Assign multiple roles to the same user without conflict
DO $$
DECLARE
    admin_group_id uuid := current_setting('test.admin_group_id')::uuid;
    user_group_id uuid := current_setting('test.user_group_id')::uuid;
    admin_role_name text := 'Admin';
    user_role_name text := 'User';
    claims_cache_result jsonb;
BEGIN
    -- Assign Admin role
    PERFORM
        keyhippo_rbac.add_user_to_group (current_setting('test.user1_id')::uuid, admin_group_id, admin_role_name);
    -- Assign User role
    PERFORM
        keyhippo_rbac.add_user_to_group (current_setting('test.user1_id')::uuid, user_group_id, user_role_name);
    -- Query claims cache directly to verify
    SELECT
        rbac_claims INTO claims_cache_result
    FROM
        keyhippo_rbac.claims_cache
    WHERE
        user_id = current_setting('test.user1_id')::uuid;
    ASSERT claims_cache_result IS NOT NULL,
    'Claims cache should be updated for the user';
    ASSERT (claims_cache_result -> admin_group_id::text) ? 'Admin',
    'User should have Admin role in claims cache';
    ASSERT (claims_cache_result -> user_group_id::text) ? 'User',
    'User should have User role in claims cache';
END
$$;
-- Test 12: Create an ABAC policy
DO $$
DECLARE
    policy_name text := 'test-policy';
    description text := 'Test Policy Description';
    POLICY jsonb := '{"type": "attribute_equals", "attribute": "department", "value": "engineering"}'::jsonb;
    created_policy_id uuid;
    retrieved_policy record;
BEGIN
    -- Create ABAC policy
    SELECT
        keyhippo_abac.create_policy (policy_name, description, POLICY) INTO created_policy_id;
    ASSERT created_policy_id IS NOT NULL,
    'ABAC policy should be created successfully';
    -- Verify the policy creation in the database
    SELECT
        * INTO retrieved_policy
    FROM
        keyhippo_abac.policies
    WHERE
        name = policy_name;
    ASSERT retrieved_policy IS NOT NULL,
    'ABAC policy should exist in the database';
    ASSERT retrieved_policy.description = description,
    'ABAC policy description should match';
    ASSERT retrieved_policy.policy = POLICY, 'ABAC policy content should match';
END
$$;
-- Test 13: Evaluate ABAC policies for a user
DO $$
DECLARE
    v_user_id uuid := current_setting('test.user1_id')::uuid;
    evaluation_result boolean;
    policy_id uuid;
    POLICY jsonb := '{"type": "attribute_equals", "attribute": "department", "value": "engineering"}'::jsonb;
BEGIN
    -- Create the policy
    SELECT
        keyhippo_abac.create_policy ('Test Policy', 'Test department policy', POLICY) INTO policy_id;
    ASSERT policy_id IS NOT NULL,
    'Policy should be created successfully';
    -- Set the user's attribute
    PERFORM
        keyhippo_abac.set_user_attribute (v_user_id, 'department', '"engineering"'::jsonb);
    -- Evaluate the policies
    SELECT
        keyhippo_abac.evaluate_policies (v_user_id) INTO evaluation_result;
    ASSERT evaluation_result = TRUE,
    'User should satisfy the ABAC policy';
    -- Clean up
    DELETE FROM keyhippo_abac.policies
    WHERE id = policy_id;
    DELETE FROM keyhippo_abac.user_attributes
    WHERE user_id = v_user_id;
END
$$;
-- Test 14: Retrieve user attributes (ABAC)
DO $$
DECLARE
    v_user_id uuid := current_setting('test.user1_id')::uuid;
    attribute text := 'department';
    expected_value text := 'engineering';
    retrieved_value text;
BEGIN
    -- Ensure the user has the attribute set
    PERFORM
        keyhippo_abac.set_user_attribute (v_user_id, attribute, '"engineering"'::jsonb);
    -- Retrieve the user attribute
    SELECT
        (attributes ->> attribute) INTO retrieved_value
    FROM
        keyhippo_abac.user_attributes
    WHERE
        user_id = v_user_id;
    ASSERT retrieved_value = expected_value,
    'Retrieved user attribute should match the expected value';
END
$$;
-- Test 15: Evaluate policies with multiple attributes correctly
DO $$
DECLARE
    policy1 jsonb := '{"type": "attribute_equals", "attribute": "department", "value": "engineering"}'::jsonb;
    policy2 jsonb := '{"type": "attribute_equals", "attribute": "location", "value": "HQ"}'::jsonb;
    user_id uuid := current_setting('test.user1_id')::uuid;
    evaluation_result boolean;
BEGIN
    -- Create ABAC policies
    PERFORM
        keyhippo_abac.create_policy ('Engineering Policy', 'Department Policy', policy1);
    PERFORM
        keyhippo_abac.create_policy ('Location Policy', 'Location Policy', policy2);
    -- Set user attributes
    PERFORM
        keyhippo_abac.set_user_attribute (user_id, 'department', '"engineering"'::jsonb);
    PERFORM
        keyhippo_abac.set_user_attribute (user_id, 'location', '"HQ"'::jsonb);
    -- Evaluate the policies
    SELECT
        keyhippo_abac.evaluate_policies (user_id) INTO evaluation_result;
    ASSERT evaluation_result = TRUE,
    'User should satisfy both ABAC policies';
END
$$;
-- Test 16: Fail when creating a duplicate policy
DO $$
DECLARE
    policy_name text := 'duplicate-policy';
    description text := 'Duplicate Policy';
    POLICY jsonb := '{"type": "attribute_equals", "attribute": "department", "value": "engineering"}'::jsonb;
    first_creation_id uuid;
    key_count bigint;
BEGIN
    -- Create the policy once
    SELECT
        keyhippo_abac.create_policy (policy_name, description, POLICY) INTO first_creation_id;
    ASSERT first_creation_id IS NOT NULL,
    'First creation of duplicate policy should succeed';
    -- Attempt to create the same policy again
    BEGIN
        PERFORM
            keyhippo_abac.create_policy (policy_name, description, POLICY);
        ASSERT FALSE,
        'Creating a duplicate policy should throw an error';
    EXCEPTION
        WHEN unique_violation THEN
            ASSERT TRUE,
            'Creating a duplicate policy should throw unique_violation error';
    END;
    -- Verify that only one policy exists
    SELECT
        COUNT(*) INTO key_count
    FROM
        keyhippo_abac.policies
    WHERE
        name = policy_name;
    ASSERT key_count = 1,
    'Only one instance of the duplicate policy should exist';
    -- Clean up
    DELETE FROM keyhippo_abac.policies
    WHERE id = first_creation_id;
END
$$;
-- Test 17: Fail policy evaluation if an attribute is missing
DO $$
DECLARE
    policy_name text := 'Location Policy ' || gen_random_uuid ();
    POLICY jsonb := '{"type": "attribute_equals", "attribute": "location", "value": "HQ"}'::jsonb;
    v_user_id uuid := current_setting('test.user1_id')::uuid;
    evaluation_result boolean;
    policy_id uuid;
BEGIN
    -- Create the policy
    SELECT
        keyhippo_abac.create_policy (policy_name, 'Test ' || policy_name, POLICY) INTO policy_id;
    ASSERT policy_id IS NOT NULL,
    'Policy should be created successfully';
    -- Ensure the user has no 'location' attribute
    DELETE FROM keyhippo_abac.user_attributes
    WHERE user_id = v_user_id;
    INSERT INTO keyhippo_abac.user_attributes (user_id, attributes)
        VALUES (v_user_id, '{"other_attribute": "some_value"}'::jsonb);
    -- Evaluate the policies
    SELECT
        keyhippo_abac.evaluate_policies (v_user_id) INTO evaluation_result;
    ASSERT evaluation_result = FALSE,
    'Policy evaluation should fail if attribute is missing';
    -- Clean up
    DELETE FROM keyhippo_abac.policies
    WHERE id = policy_id;
    DELETE FROM keyhippo_abac.user_attributes
    WHERE user_id = v_user_id;
END
$$;
-- Test 18: Fail policy evaluation for user with missing attributes
DO $$
DECLARE
    POLICY jsonb := '{"type": "attribute_equals", "attribute": "department", "value": "engineering"}'::jsonb;
    user_id uuid := current_setting('test.user1_id')::uuid;
    evaluation_result boolean;
BEGIN
    -- Create the policy
    PERFORM
        keyhippo_abac.create_policy ('Engineering Access', 'Access restricted to engineering department', POLICY);
    -- User doesn't have the 'department' attribute set
    PERFORM
        keyhippo_abac.set_user_attribute (user_id, 'department', NULL::jsonb);
    -- Evaluate the policies
    SELECT
        keyhippo_abac.evaluate_policies (user_id) INTO evaluation_result;
    ASSERT evaluation_result = FALSE,
    'Policy evaluation should fail if user lacks required attributes';
END
$$;
-- Test 19: Evaluate policies with multiple attributes
DO $$
DECLARE
    multi_attribute_policy jsonb := '{"type": "and", "conditions": [{"type": "attribute_equals", "attribute": "department", "value": "engineering"}, {"type": "attribute_equals", "attribute": "location", "value": "HQ"}]}'::jsonb;
    user_id uuid := current_setting('test.user1_id')::uuid;
    evaluation_result boolean;
BEGIN
    -- Create ABAC policy
    PERFORM
        keyhippo_abac.create_policy ('Multi-Attribute Policy', 'Engineering at HQ', multi_attribute_policy);
    -- Set the user's attributes
    PERFORM
        keyhippo_abac.set_user_attribute (user_id, 'department', '"engineering"'::jsonb);
    PERFORM
        keyhippo_abac.set_user_attribute (user_id, 'location', '"HQ"'::jsonb);
    -- Evaluate the policies
    SELECT
        keyhippo_abac.evaluate_policies (user_id) INTO evaluation_result;
    ASSERT evaluation_result = TRUE,
    'User should satisfy the multi-attribute ABAC policy';
END
$$;
-- Test 20: Reject policy creation with invalid data types
DO $$
DECLARE
    error_message text;
BEGIN
    -- Attempt to create a policy with invalid data types
    BEGIN
        PERFORM
            keyhippo_abac.create_policy ('Invalid Data Type Policy', 'Invalid value type', '{"type": "attribute_equals", "attribute": "department", "value": 123}'::jsonb);
        ASSERT FALSE,
        'create_policy should throw an error for invalid data types';
    EXCEPTION
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
    ASSERT SQLSTATE = 'P0001',
    'create_policy should throw exception with SQLSTATE P0001 for invalid policy format';
    ASSERT error_message LIKE '%Invalid policy format: value must be a string, boolean, or null%',
    'Error message should indicate invalid value type';
    END;
END
$$;
-- Test 21: Reject policy creation with missing fields
DO $$
BEGIN
    -- Attempt to create a policy with missing fields
    BEGIN
        PERFORM
            keyhippo_abac.create_policy ('Incomplete Policy', 'Missing fields', '{"type": "attribute_equals"}'::jsonb);
        ASSERT FALSE,
        'create_policy should throw an error for missing fields';
    EXCEPTION
        WHEN OTHERS THEN
            ASSERT SQLSTATE = 'P0001',
            'create_policy should throw exception with SQLSTATE P0001 for invalid policy format';
    ASSERT POSITION('Invalid policy format' IN SQLERRM) > 0,
    'Error message should indicate invalid policy format';
    END;
END
$$;
-- Test 22: Reject invalid policy formats
DO $$
BEGIN
    -- Attempt to create a policy with an unsupported type
    BEGIN
        PERFORM
            keyhippo_abac.create_policy ('Invalid Policy', 'Invalid Policy Description', '{"type": "invalid_type", "attribute": "department", "value": "engineering"}'::jsonb);
        ASSERT FALSE,
        'create_policy should throw an error for unsupported policy type';
    EXCEPTION
        WHEN OTHERS THEN
            ASSERT SQLSTATE = 'P0001',
            'create_policy should throw exception with SQLSTATE P0001 for invalid policy format';
    ASSERT POSITION('Invalid policy format' IN SQLERRM) > 0,
    'Error message should indicate invalid policy format';
    END;
END
$$;
-- Test 23: Create and evaluate policies with 'or' conditions
DO $$
DECLARE
    or_policy jsonb := '{"type": "or", "conditions": [{"type": "attribute_equals", "attribute": "role", "value": "admin"}, {"type": "attribute_equals", "attribute": "department", "value": "engineering"}]}'::jsonb;
    v_user_id uuid := current_setting('test.user1_id')::uuid;
    evaluation_result boolean;
    policy_id uuid;
BEGIN
    -- Create ABAC policy
    SELECT
        keyhippo_abac.create_policy ('Or Condition Policy', 'User must be admin or in engineering', or_policy) INTO policy_id;
    -- Set the user's role to 'admin' (should pass the policy)
    PERFORM
        keyhippo_abac.set_user_attribute (v_user_id, 'role', '"admin"'::jsonb);
    -- Evaluate the policies
    SELECT
        keyhippo_abac.evaluate_policies (v_user_id) INTO evaluation_result;
    ASSERT evaluation_result = TRUE,
    'User with role admin should satisfy the OR condition policy';
    -- Change the user's role to 'user' and set department to 'engineering' (should still pass)
    PERFORM
        keyhippo_abac.set_user_attribute (v_user_id, 'role', '"user"'::jsonb);
    PERFORM
        keyhippo_abac.set_user_attribute (v_user_id, 'department', '"engineering"'::jsonb);
    -- Re-evaluate the policies
    SELECT
        keyhippo_abac.evaluate_policies (v_user_id) INTO evaluation_result;
    ASSERT evaluation_result = TRUE,
    'User with department engineering should satisfy the OR condition policy';
    -- Clean up
    DELETE FROM keyhippo_abac.policies
    WHERE id = policy_id;
END
$$;
-- Test 24: Fail policy evaluation for user with insufficient attributes
DO $$
DECLARE
    POLICY jsonb := '{"type": "and", "conditions": [{"type": "attribute_equals", "attribute": "department", "value": "engineering"}, {"type": "attribute_equals", "attribute": "level", "value": "senior"}]}'::jsonb;
    user_id uuid := current_setting('test.user1_id')::uuid;
    evaluation_result boolean;
BEGIN
    -- Create ABAC policy
    PERFORM
        keyhippo_abac.create_policy ('Senior Engineering Policy', 'Access restricted to senior engineers', POLICY);
    -- Set only one attribute
    PERFORM
        keyhippo_abac.set_user_attribute (user_id, 'department', '"engineering"'::jsonb);
    PERFORM
        keyhippo_abac.set_user_attribute (user_id, 'level', NULL::jsonb);
    -- Evaluate the policies
    SELECT
        keyhippo_abac.evaluate_policies (user_id) INTO evaluation_result;
    ASSERT evaluation_result = FALSE,
    'Policy evaluation should fail when user lacks required attributes';
END
$$;
-- ROLLBACK to ensure no test data persists
ROLLBACK;
