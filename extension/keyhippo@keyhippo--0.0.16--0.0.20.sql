-- Drop the old load_api_key_info function if it exists
DO $$
BEGIN
    -- Check if the function exists in the schema and is part of an extension
    IF EXISTS (
        SELECT
            1
        FROM
            pg_proc p
            JOIN pg_namespace n ON p.pronamespace = n.oid
            LEFT JOIN pg_extension e ON e.extnamespace = n.oid
                AND p.oid = ANY (e.extconfig)
        WHERE
            p.proname = 'load_api_key_info'
            AND n.nspname = 'keyhippo'
            AND e.extname IS NOT NULL) THEN
    -- Drop the function from the extension
    EXECUTE 'ALTER EXTENSION ' || quote_ident(e.extname) || ' DROP FUNCTION keyhippo.load_api_key_info(text)';
    -- Drop the function itself
    EXECUTE 'DROP FUNCTION keyhippo.load_api_key_info(text)';
    RAISE NOTICE 'Dropped function keyhippo.load_api_key_info(text) from extension and schema.';
ELSIF EXISTS (
        SELECT
            1
        FROM
            pg_proc p
            JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE
            p.proname = 'load_api_key_info'
            AND n.nspname = 'keyhippo') THEN
    -- If the function is not part of an extension, just drop the function
    EXECUTE 'DROP FUNCTION keyhippo.load_api_key_info(text)';
    RAISE NOTICE 'Dropped function keyhippo.load_api_key_info(text) from schema.';
ELSE
    RAISE NOTICE 'Function keyhippo.load_api_key_info(text) does not exist, skipping drop.';
END IF;
END
$$;

-- Create the new load_api_key_info function
CREATE OR REPLACE FUNCTION keyhippo.load_api_key_info (id_of_user text)
    RETURNS jsonb
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = extensions
    AS $$
DECLARE
    key_info jsonb := '[]'::jsonb;
    jwt_record RECORD;
    vault_record RECORD;
    jwt_count int;
BEGIN
    RAISE LOG '[KeyHippo] Starting load_api_key_info for user: %', id_of_user;
    -- Check if the function is being executed as the correct user
    IF auth.uid () != id_of_user::uuid THEN
        RAISE LOG '[KeyHippo] Unauthorized access attempt for user: %. Current auth.uid(): %', id_of_user, auth.uid ();
        RETURN NULL;
    END IF;
    -- Log the number of JWT records found
    SELECT
        COUNT(*) INTO jwt_count
    FROM
        auth.jwts
    WHERE
        user_id = id_of_user::uuid;
    RAISE LOG '[KeyHippo] Found % JWT records for user: %', jwt_count, id_of_user;
    FOR jwt_record IN
    SELECT
        secret_id
    FROM
        auth.jwts
    WHERE
        user_id = id_of_user::uuid LOOP
            RAISE LOG '[KeyHippo] Processing secret_id: %', jwt_record.secret_id;
            BEGIN
                SELECT
                    description INTO STRICT vault_record
                FROM
                    vault.decrypted_secrets
                WHERE
                    id = jwt_record.secret_id;
                RAISE LOG '[KeyHippo] Found description: %', vault_record.description;
                key_info := key_info || jsonb_build_object('id', jwt_record.secret_id, 'description', vault_record.description);
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    RAISE LOG '[KeyHippo] No data found in vault.decrypted_secrets for secret_id: %', jwt_record.secret_id;
                WHEN OTHERS THEN
                    RAISE LOG '[KeyHippo] Error processing secret_id %: %', jwt_record.secret_id, SQLERRM;
            END;
    END LOOP;
    RAISE LOG '[KeyHippo] Completed load_api_key_info. Total keys: %', jsonb_array_length(key_info);
    RETURN key_info;
END
$$;
