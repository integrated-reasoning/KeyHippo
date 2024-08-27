BEGIN;
DROP POLICY IF EXISTS "select_policy_api_key_id_created" ON keyhippo.api_key_id_created;
CREATE POLICY "select_policy_api_key_id_created" ON keyhippo.api_key_id_created
    FOR SELECT TO anon, authenticated
        USING ((COALESCE(auth.uid (), keyhippo.key_uid ()) = owner_id));
GRANT SELECT ON TABLE keyhippo.api_key_id_created TO anon, authenticated;
COMMIT;
