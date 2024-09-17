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
    assert count_result IS NOT NULL,
    'Authenticated user can access api_key_id_owner_id table';
    assert count_result = 0,
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
    assert created_key_result.api_key IS NOT NULL,
    'create_api_key executes successfully for authenticated user';
    assert created_key_result.api_key_id IS NOT NULL,
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
    assert key_count = 1,
    'An API key should be created with the given name for the authenticated user';
END
$$;
-- Attempt to create API key for another user
DO $$
BEGIN
    BEGIN
        PERFORM
            keyhippo.create_api_key (current_setting('test.user2_id'), 'Malicious API Key');
        assert FALSE,
        'Should not be able to create API key for another user';
    EXCEPTION
        WHEN OTHERS THEN
            assert sqlerrm LIKE '%[KeyHippo] Unauthorized: Invalid user ID%',
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
    assert metadata_name = 'Metadata Test Key',
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
    assert other_user_key_count = 0,
    'get_api_key_metadata returns no data for other users';
END
$$;
ROLLBACK;
