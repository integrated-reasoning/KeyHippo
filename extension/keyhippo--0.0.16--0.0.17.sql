-- Add the new grants to the end of the existing setup function
CREATE OR REPLACE FUNCTION keyhippo.setup ()
    RETURNS VOID
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $setup$
BEGIN
    -- Call the existing setup function
    PERFORM
        keyhippo.setup ();
    -- Add the new grants
    GRANT EXECUTE ON FUNCTION keyhippo.load_api_key_info (TEXT) TO authenticated, service_role, anon;
    GRANT EXECUTE ON FUNCTION keyhippo.get_uid_for_key (TEXT) TO authenticated, service_role, anon;
    GRANT USAGE ON SCHEMA keyhippo TO authenticated, service_role, anon;
    RAISE LOG '[KeyHippo] Additional permissions granted successfully.';
END;
$setup$;

-- Grant the permissions immediately for existing installations
GRANT EXECUTE ON FUNCTION keyhippo.load_api_key_info (TEXT) TO authenticated, service_role, anon;

GRANT EXECUTE ON FUNCTION keyhippo.get_uid_for_key (TEXT) TO authenticated, service_role, anon;

GRANT USAGE ON SCHEMA keyhippo TO authenticated, service_role, anon;
