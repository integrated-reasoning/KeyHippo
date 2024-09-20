-- 10_grants.sql
-- Grant necessary permissions for the internal functions
REVOKE ALL ON FUNCTION keyhippo_internal._get_secret_uuid_for_api_key (text) FROM PUBLIC;

-- Grant permissions for public functions
GRANT EXECUTE ON FUNCTION keyhippo.create_api_key_public (TEXT) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo.get_api_key (TEXT, TEXT) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo.get_api_key_metadata_public () TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo.revoke_api_key_public (TEXT) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo.rotate_api_key_public (uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION keyhippo.load_api_key_info_public () TO authenticated;

-- Grant permissions for internal functions used in request handling
GRANT EXECUTE ON FUNCTION keyhippo.check_request () TO authenticated, service_role, anon;

GRANT EXECUTE ON FUNCTION keyhippo.key_uid () TO authenticated, service_role, anon;

GRANT EXECUTE ON FUNCTION keyhippo.get_uid_for_key (TEXT) TO authenticated, service_role, anon;

-- Grant SELECT permissions on tables
GRANT SELECT ON ALL TABLES IN SCHEMA keyhippo TO authenticated;

-- Grant SELECT on auth.jwts to authenticated and service_role
GRANT SELECT ON auth.jwts TO authenticated, service_role;

-- Grant USAGE on keyhippo schema
GRANT USAGE ON SCHEMA keyhippo TO authenticated, service_role, anon;

-- Notify PostgREST to reload its configuration
NOTIFY pgrst,
'reload config';
