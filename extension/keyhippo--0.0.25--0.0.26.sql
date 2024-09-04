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
-- 3. Create a function to update policies with elevated privileges
CREATE OR REPLACE FUNCTION keyhippo_temp.update_policies ()
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = keyhippo, pg_temp
    AS $$
DECLARE
    tbl_name text;
BEGIN
    FOR tbl_name IN
    SELECT
        table_name
    FROM
        information_schema.tables
    WHERE
        table_schema = 'keyhippo'
        AND table_name LIKE 'api_key_id_%' LOOP
            EXECUTE format('
            DROP POLICY IF EXISTS "select_policy_%1$s" ON keyhippo.%1$I;
            CREATE POLICY "select_policy_%1$s" ON keyhippo.%1$I
                FOR SELECT TO anon, authenticated
                USING ((SELECT auth.uid() = owner_id) OR
                    (SELECT keyhippo.key_uid() = owner_id)
                );
            GRANT SELECT ON TABLE keyhippo.%1$I TO anon, authenticated;
        ', tbl_name);
        END LOOP;
END;
$$;
-- 4. Execute the policy update function
SELECT
    keyhippo_temp.update_policies ();
-- 5. Drop all temporary functions
DROP FUNCTION IF EXISTS keyhippo_temp.handle_existing_users ();
DROP FUNCTION IF EXISTS keyhippo_temp.update_policies ();
-- Drop temporary schema
DROP SCHEMA IF EXISTS keyhippo_temp CASCADE;
-- Commit transaction
COMMIT;
