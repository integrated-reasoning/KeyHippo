BEGIN;
SET search_path TO keyhippo, keyhippo_rbac, public, auth;
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
    INSERT INTO keyhippo_rbac.user_group_roles (user_id, group_id, role_id)
        VALUES (user1_id, admin_group_id, admin_role_id)
    ON CONFLICT (user_id, group_id, role_id)
        DO NOTHING;
    -- Set up authentication for user1
    PERFORM
        set_config('request.jwt.claim.sub', user1_id::text, TRUE);
    PERFORM
        set_config('request.jwt.claims', json_build_object('sub', user1_id, 'role', 'authenticated', 'user_role', 'admin')::text, TRUE);
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
            keyhippo.authorize ('manage_groups');
        end_time := clock_timestamp();
        execution_times := array_append(execution_times, EXTRACT(EPOCH FROM (end_time - start_time)));
    END LOOP;
    SELECT
        'RBAC authorization',
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
    -- Test 2: API key creation
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
    -- Test 3: API key verification
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
