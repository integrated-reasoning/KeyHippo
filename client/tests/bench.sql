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
-- Performance test function
CREATE OR REPLACE FUNCTION run_performance_test (iterations integer DEFAULT 1000)
    RETURNS TABLE (
        test_name text,
        min_time double precision,
        max_time double precision,
        avg_time double precision,
        median_time double precision,
        stddev_time double precision,
        percentile_90 double precision,
        percentile_95 double precision,
        percentile_99 double precision
    )
    AS $$
DECLARE
    start_time timestamp;
    end_time timestamp;
    user_id uuid := current_setting('test.user1_id')::uuid;
    created_api_key text;
    execution_times double precision[];
    i integer;
BEGIN
    -- Test 1: RBAC claims cache update
    FOR i IN 1..iterations LOOP
        start_time := clock_timestamp();
        PERFORM
            keyhippo_rbac.update_user_claims_cache (user_id);
        end_time := clock_timestamp();
        execution_times := array_append(execution_times, EXTRACT(EPOCH FROM (end_time - start_time)));
    END LOOP;
    SELECT
        'RBAC claims cache update',
        MIN(t),
        MAX(t),
        AVG(t),
        percentile_cont(0.5) WITHIN GROUP (ORDER BY t),
        stddev(t),
        percentile_cont(0.9) WITHIN GROUP (ORDER BY t),
        percentile_cont(0.95) WITHIN GROUP (ORDER BY t),
        percentile_cont(0.99) WITHIN GROUP (ORDER BY t) INTO test_name,
        min_time,
        max_time,
        avg_time,
        median_time,
        stddev_time,
        percentile_90,
        percentile_95,
        percentile_99
    FROM
        unnest(execution_times) t;
    RETURN NEXT;
    -- Reset execution_times array
    execution_times := ARRAY[]::double precision[];
    -- Test 2: ABAC policy evaluation
    FOR i IN 1..iterations LOOP
        start_time := clock_timestamp();
        PERFORM
            keyhippo_abac.evaluate_policies (user_id);
        end_time := clock_timestamp();
        execution_times := array_append(execution_times, EXTRACT(EPOCH FROM (end_time - start_time)));
    END LOOP;
    SELECT
        'ABAC policy evaluation',
        MIN(t),
        MAX(t),
        AVG(t),
        percentile_cont(0.5) WITHIN GROUP (ORDER BY t),
        stddev(t),
        percentile_cont(0.9) WITHIN GROUP (ORDER BY t),
        percentile_cont(0.95) WITHIN GROUP (ORDER BY t),
        percentile_cont(0.99) WITHIN GROUP (ORDER BY t) INTO test_name,
        min_time,
        max_time,
        avg_time,
        median_time,
        stddev_time,
        percentile_90,
        percentile_95,
        percentile_99
    FROM
        unnest(execution_times) t;
    RETURN NEXT;
    -- Reset execution_times array
    execution_times := ARRAY[]::double precision[];
    -- Test 3: API key creation
    FOR i IN 1..iterations LOOP
        start_time := clock_timestamp();
        SELECT
            api_key INTO created_api_key
        FROM
            keyhippo.create_api_key ('Performance Test Key ' || i::text);
        end_time := clock_timestamp();
        execution_times := array_append(execution_times, EXTRACT(EPOCH FROM (end_time - start_time)));
    END LOOP;
    SELECT
        'API key creation',
        MIN(t),
        MAX(t),
        AVG(t),
        percentile_cont(0.5) WITHIN GROUP (ORDER BY t),
        stddev(t),
        percentile_cont(0.9) WITHIN GROUP (ORDER BY t),
        percentile_cont(0.95) WITHIN GROUP (ORDER BY t),
        percentile_cont(0.99) WITHIN GROUP (ORDER BY t) INTO test_name,
        min_time,
        max_time,
        avg_time,
        median_time,
        stddev_time,
        percentile_90,
        percentile_95,
        percentile_99
    FROM
        unnest(execution_times) t;
    RETURN NEXT;
    -- Reset execution_times array
    execution_times := ARRAY[]::double precision[];
    -- Test 4: API key verification
    FOR i IN 1..iterations LOOP
        start_time := clock_timestamp();
        PERFORM
            keyhippo.verify_api_key (created_api_key);
        end_time := clock_timestamp();
        execution_times := array_append(execution_times, EXTRACT(EPOCH FROM (end_time - start_time)));
    END LOOP;
    SELECT
        'API key verification',
        MIN(t),
        MAX(t),
        AVG(t),
        percentile_cont(0.5) WITHIN GROUP (ORDER BY t),
        stddev(t),
        percentile_cont(0.9) WITHIN GROUP (ORDER BY t),
        percentile_cont(0.95) WITHIN GROUP (ORDER BY t),
        percentile_cont(0.99) WITHIN GROUP (ORDER BY t) INTO test_name,
        min_time,
        max_time,
        avg_time,
        median_time,
        stddev_time,
        percentile_90,
        percentile_95,
        percentile_99
    FROM
        unnest(execution_times) t;
    RETURN NEXT;
    END;
$$
LANGUAGE plpgsql;
-- Run performance tests
SELECT
    *
FROM
    run_performance_test (1000);
-- Clean up
DROP FUNCTION run_performance_test (integer);
ROLLBACK;
