-- 06_user_management.sql
-- Function to handle new user creation
CREATE OR REPLACE FUNCTION keyhippo.handle_new_user ()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
BEGIN
    INSERT INTO keyhippo.user_ids (id)
        VALUES (NEW.id);
    RETURN NEW;
END;
$$;

-- Trigger to automatically handle new user creation
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION keyhippo.handle_new_user ();

-- Function to create user API key secret
CREATE OR REPLACE FUNCTION keyhippo.create_user_api_key_secret ()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = extensions, pg_temp
    AS $$
DECLARE
    rand_bytes bytea := gen_random_bytes(32);
    user_api_key_secret text := encode(digest(rand_bytes, 'sha512'), 'hex');
BEGIN
    INSERT INTO vault.secrets (secret, name)
        VALUES (user_api_key_secret, NEW.id);
    RETURN NEW;
END;
$$;

-- Trigger to automatically create user API key secret
CREATE TRIGGER on_user_created__create_user_api_key_secret
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION keyhippo.create_user_api_key_secret ();

-- Function to remove user vault secrets
CREATE OR REPLACE FUNCTION keyhippo.remove_user_vault_secrets ()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = keyhippo, pg_temp
    AS $$
DECLARE
    jwt_record RECORD;
BEGIN
    DELETE FROM vault.secrets
    WHERE name = OLD.id::text;
    FOR jwt_record IN
    SELECT
        secret_id
    FROM
        auth.jwts
    WHERE
        user_id = OLD.id LOOP
            DELETE FROM vault.secrets
            WHERE id = jwt_record.secret_id;
        END LOOP;
    RETURN OLD;
END;
$$;

-- Trigger to automatically remove user vault secrets
CREATE TRIGGER on_auth_user_deleted
    AFTER DELETE ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION keyhippo.remove_user_vault_secrets ();

-- Function to load API key info for a user
CREATE OR REPLACE FUNCTION keyhippo.load_api_key_info (id_of_user text)
    RETURNS jsonb
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = extensions, pg_temp
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
