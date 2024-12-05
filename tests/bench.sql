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
-- Function to calculate performance statistics
CREATE OR REPLACE FUNCTION calculate_performance_stats (execution_times double precision[])
    RETURNS jsonb
    AS $$
DECLARE
    stats jsonb;
    p99_time double precision;
BEGIN
    SELECT
        percentile_cont(0.99) WITHIN GROUP (ORDER BY t) INTO p99_time
    FROM
        unnest(execution_times) t;
    SELECT
        jsonb_build_object('min_time', MIN(t), 'max_time', MAX(t), 'avg_time', AVG(t), 'median_time', percentile_cont(0.5) WITHIN GROUP (ORDER BY t), 'stddev_time', stddev(t), 'percentile_90', percentile_cont(0.9) WITHIN GROUP (ORDER BY t), 'percentile_95', percentile_cont(0.95) WITHIN GROUP (ORDER BY t), 'percentile_99', p99_time, 'p99_ops_per_second', 1 / p99_time) INTO stats
    FROM
        unnest(execution_times) t;
    RETURN stats;
    END;
$$
LANGUAGE plpgsql;
-- Performance test function
CREATE OR REPLACE FUNCTION run_performance_test (iterations integer DEFAULT 1000)
    RETURNS jsonb
    AS $$
DECLARE
    start_time timestamp;
    end_time timestamp;
    user_id uuid := current_setting('test.user1_id')::uuid;
    created_api_key text;
    execution_times double precision[];
    i integer;
    test_group_id uuid;
    test_role_id uuid;
    test_scope_id uuid;
    results jsonb := '{}'::jsonb;
BEGIN
    -- Test 1: RBAC authorization
    FOR i IN 1..iterations LOOP
        start_time := clock_timestamp();
        PERFORM
            keyhippo.authorize ('manage_groups');
        end_time := clock_timestamp();
        execution_times := array_append(execution_times, EXTRACT(EPOCH FROM (end_time - start_time)));
    END LOOP;
    results := results || jsonb_build_object('RBAC authorization', calculate_performance_stats (execution_times));
    -- Test 2: Create group
    execution_times := ARRAY[]::double precision[];
    FOR i IN 1..iterations LOOP
        start_time := clock_timestamp();
        SELECT
            keyhippo_rbac.create_group ('Test Group ' || i::text, 'Test group description') INTO test_group_id;
        end_time := clock_timestamp();
        execution_times := array_append(execution_times, EXTRACT(EPOCH FROM (end_time - start_time)));
    END LOOP;
    results := results || jsonb_build_object('Create group', calculate_performance_stats (execution_times));
    -- Test 3: Create role
    execution_times := ARRAY[]::double precision[];
    FOR i IN 1..iterations LOOP
        start_time := clock_timestamp();
        SELECT
            keyhippo_rbac.create_role ('Test Role ' || i::text, 'Test role description', test_group_id, 'user'::keyhippo.app_role) INTO test_role_id;
        end_time := clock_timestamp();
        execution_times := array_append(execution_times, EXTRACT(EPOCH FROM (end_time - start_time)));
    END LOOP;
    results := results || jsonb_build_object('Create role', calculate_performance_stats (execution_times));
    -- Test 4: Assign role to user
    execution_times := ARRAY[]::double precision[];
    FOR i IN 1..iterations LOOP
        start_time := clock_timestamp();
        PERFORM
            keyhippo_rbac.assign_role_to_user (user_id, test_group_id, test_role_id);
        end_time := clock_timestamp();
        execution_times := array_append(execution_times, EXTRACT(EPOCH FROM (end_time - start_time)));
    END LOOP;
    results := results || jsonb_build_object('Assign role to user', calculate_performance_stats (execution_times));
    -- Test 5: API key creation
    execution_times := ARRAY[]::double precision[];
    FOR i IN 1..iterations LOOP
        start_time := clock_timestamp();
        SELECT
            api_key INTO created_api_key
        FROM
            keyhippo.create_api_key ('Performance Test Key ' || i::text);
        end_time := clock_timestamp();
        execution_times := array_append(execution_times, EXTRACT(EPOCH FROM (end_time - start_time)));
    END LOOP;
    results := results || jsonb_build_object('API key creation', calculate_performance_stats (execution_times));
    -- Test 6: API key verification
    execution_times := ARRAY[]::double precision[];
    FOR i IN 1..iterations LOOP
        start_time := clock_timestamp();
        PERFORM
            keyhippo.verify_api_key (created_api_key);
        end_time := clock_timestamp();
        execution_times := array_append(execution_times, EXTRACT(EPOCH FROM (end_time - start_time)));
    END LOOP;
    results := results || jsonb_build_object('API key verification', calculate_performance_stats (execution_times));
    -- Test 7: Create scope
    execution_times := ARRAY[]::double precision[];
    FOR i IN 1..iterations LOOP
        start_time := clock_timestamp();
        INSERT INTO keyhippo.scopes (name, description)
            VALUES ('test_scope_' || i::text, 'Test scope description')
        RETURNING
            id INTO test_scope_id;
        end_time := clock_timestamp();
        execution_times := array_append(execution_times, EXTRACT(EPOCH FROM (end_time - start_time)));
    END LOOP;
    results := results || jsonb_build_object('Create scope', calculate_performance_stats (execution_times));
    RETURN results;
END;
$$
LANGUAGE plpgsql;
-- Run performance tests and display results as JSON
SELECT
    run_performance_test (10000)::text AS performance_results;
-- Clean up
DROP FUNCTION run_performance_test (integer);
DROP FUNCTION calculate_performance_stats (double precision[]);
ROLLBACK;
