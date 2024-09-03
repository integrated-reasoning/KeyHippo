-- Combined migration script to handle existing user accounts and update policies
-- Start transaction
BEGIN;
-- Create temporary schema
CREATE SCHEMA IF NOT EXISTS keyhippo_temp;
-- 1. Create temporary function to handle existing users
CREATE OR REPLACE FUNCTION keyhippo_temp.handle_existing_users ()
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = extensions, pg_temp
    AS $$
DECLARE
    user_record RECORD;
BEGIN
    FOR user_record IN
    SELECT
        id
    FROM
        auth.users LOOP
            -- Insert into keyhippo.user_ids if not exists
            INSERT INTO keyhippo.user_ids (id)
                VALUES (user_record.id)
            ON CONFLICT (id)
                DO NOTHING;
            -- Create user API key secret if not exists
            IF NOT EXISTS (
                SELECT
                    1
                FROM
                    vault.secrets
                WHERE
                    name = user_record.id::text) THEN
            INSERT INTO vault.secrets (secret, name)
                VALUES (encode(digest(gen_random_bytes(32), 'sha512'), 'hex'), user_record.id::text);
        END IF;
END LOOP;
END;
$$;
-- 2. Execute the function to handle existing users
SELECT
    keyhippo_temp.handle_existing_users ();
-- 3. Drop the temporary function
DROP FUNCTION keyhippo_temp.handle_existing_users ();
-- 4. Update policy for keyhippo.api_key_id_created table
DROP POLICY IF EXISTS "select_policy_api_key_id_created" ON keyhippo.api_key_id_created;
CREATE POLICY "select_policy_api_key_id_created" ON keyhippo.api_key_id_created
    FOR SELECT TO anon, authenticated
        USING ((COALESCE(auth.uid (), keyhippo.key_uid ()) = owner_id));
-- 5. Grant SELECT permission on keyhippo.api_key_id_created
GRANT SELECT ON TABLE keyhippo.api_key_id_created TO anon, authenticated;
-- Drop temporary schema
DROP SCHEMA IF EXISTS keyhippo_temp CASCADE;
-- Commit transaction
COMMIT;
