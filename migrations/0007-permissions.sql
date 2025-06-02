BEGIN;

-- Enable Row Level Security on all tables
ALTER TABLE keyhippo_internal.config ENABLE ROW LEVEL SECURITY;
ALTER TABLE keyhippo_rbac.groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE keyhippo_rbac.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE keyhippo_rbac.permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE keyhippo_rbac.role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE keyhippo_rbac.user_group_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE keyhippo.scopes ENABLE ROW LEVEL SECURITY;
ALTER TABLE keyhippo.scope_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE keyhippo.api_key_metadata ENABLE ROW LEVEL SECURITY;
ALTER TABLE keyhippo.api_key_secrets ENABLE ROW LEVEL SECURITY;
ALTER TABLE keyhippo_impersonation.impersonation_state ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS config_access_policy ON keyhippo_internal.config;
DROP POLICY IF EXISTS groups_access_policy ON keyhippo_rbac.groups;
DROP POLICY IF EXISTS roles_access_policy ON keyhippo_rbac.roles;
DROP POLICY IF EXISTS permissions_access_policy ON keyhippo_rbac.permissions;
DROP POLICY IF EXISTS role_permissions_access_policy ON keyhippo_rbac.role_permissions;
DROP POLICY IF EXISTS user_group_roles_access_policy ON keyhippo_rbac.user_group_roles;
DROP POLICY IF EXISTS scopes_access_policy ON keyhippo.scopes;
DROP POLICY IF EXISTS scope_permissions_access_policy ON keyhippo.scope_permissions;
DROP POLICY IF EXISTS api_key_metadata_access_policy ON keyhippo.api_key_metadata;
DROP POLICY IF EXISTS api_key_secrets_no_access_policy ON keyhippo.api_key_secrets;
DROP POLICY IF EXISTS impersonation_state_access ON keyhippo_impersonation.impersonation_state;

-- Create RLS policies
CREATE POLICY config_access_policy ON keyhippo_internal.config
    USING (CURRENT_USER = 'postgres');

CREATE POLICY groups_access_policy ON keyhippo_rbac.groups
    FOR ALL TO authenticated
    USING (keyhippo.authorize('manage_groups'))
    WITH CHECK (keyhippo.authorize('manage_groups'));

CREATE POLICY roles_access_policy ON keyhippo_rbac.roles
    FOR ALL TO authenticated
    USING (keyhippo.authorize('manage_roles'))
    WITH CHECK (keyhippo.authorize('manage_roles'));

CREATE POLICY permissions_access_policy ON keyhippo_rbac.permissions
    FOR ALL TO authenticated
    USING (keyhippo.authorize('manage_permissions'))
    WITH CHECK (keyhippo.authorize('manage_permissions'));

CREATE POLICY role_permissions_access_policy ON keyhippo_rbac.role_permissions
    FOR ALL TO authenticated
    USING (keyhippo.authorize('manage_roles'))
    WITH CHECK (keyhippo.authorize('manage_roles'));

CREATE POLICY user_group_roles_access_policy ON keyhippo_rbac.user_group_roles
    FOR ALL TO authenticated
    USING (keyhippo.authorize('manage_roles'))
    WITH CHECK (keyhippo.authorize('manage_roles'));

CREATE POLICY scopes_access_policy ON keyhippo.scopes
    FOR ALL TO authenticated
    USING (keyhippo.authorize('manage_scopes'))
    WITH CHECK (keyhippo.authorize('manage_scopes'));

CREATE POLICY scope_permissions_access_policy ON keyhippo.scope_permissions
    FOR ALL TO authenticated
    USING (keyhippo.authorize('manage_scopes'))
    WITH CHECK (keyhippo.authorize('manage_scopes'));

CREATE POLICY api_key_metadata_access_policy ON keyhippo.api_key_metadata
    FOR ALL TO authenticated
    USING (user_id = (SELECT auth.uid()) OR keyhippo.authorize('manage_api_keys'));

CREATE POLICY api_key_secrets_no_access_policy ON keyhippo.api_key_secrets
    FOR ALL TO authenticated
    USING (FALSE);

CREATE POLICY impersonation_state_access ON keyhippo_impersonation.impersonation_state
    USING (CURRENT_USER = 'postgres'
        OR (CURRENT_USER = 'anon' AND impersonated_user_id = '00000000-0000-0000-0000-000000000000'::uuid)
        OR impersonated_user_id::text = CURRENT_USER);

-- Grant schema usage permissions
GRANT USAGE ON SCHEMA keyhippo TO authenticated, anon, service_role;
GRANT USAGE ON SCHEMA keyhippo_internal TO postgres, service_role;
GRANT USAGE ON SCHEMA keyhippo_rbac TO authenticated, anon, service_role;
GRANT USAGE ON SCHEMA keyhippo_impersonation TO postgres, authenticated, anon, service_role;

-- Grant table permissions for keyhippo schema
GRANT SELECT, INSERT, UPDATE, DELETE ON keyhippo.scopes TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON keyhippo.scope_permissions TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON keyhippo.api_key_metadata TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON keyhippo.audit_log TO authenticated, service_role;

-- Grant table permissions for keyhippo_rbac schema
GRANT SELECT, INSERT, UPDATE, DELETE ON keyhippo_rbac.groups TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON keyhippo_rbac.roles TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON keyhippo_rbac.permissions TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON keyhippo_rbac.role_permissions TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON keyhippo_rbac.user_group_roles TO authenticated, service_role;

-- Grant config table permissions to postgres
GRANT ALL PRIVILEGES ON keyhippo_internal.config TO postgres, service_role;

-- Revoke all permissions on api_key_secrets from authenticated users (security)
REVOKE ALL ON keyhippo.api_key_secrets FROM authenticated, anon;
GRANT ALL ON keyhippo.api_key_secrets TO postgres, service_role;

-- Grant permissions for impersonation
GRANT ALL ON keyhippo_impersonation.impersonation_state TO postgres, service_role;
GRANT SELECT, DELETE ON keyhippo_impersonation.impersonation_state TO anon;

-- Grant EXECUTE permissions on core functions
GRANT EXECUTE ON FUNCTION keyhippo.current_user_context() TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION keyhippo.authorize(keyhippo.app_permission) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION keyhippo.verify_api_key(text) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION keyhippo.create_api_key(text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION keyhippo.revoke_api_key(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION keyhippo.rotate_api_key(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION keyhippo.update_key_claims(uuid, jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION keyhippo.key_data() TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION keyhippo.is_authorized(regclass, text) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION keyhippo.check_request() TO authenticated, service_role, anon;

-- Grant EXECUTE permissions on RBAC functions
GRANT EXECUTE ON FUNCTION keyhippo_rbac.create_group(text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION keyhippo_rbac.create_role(text, text, uuid, keyhippo.app_role) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION keyhippo_rbac.assign_role_to_user(uuid, uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION keyhippo_rbac.assign_permission_to_role(uuid, keyhippo.app_permission) TO authenticated, service_role;

-- Grant EXECUTE permissions on initialization functions
GRANT EXECUTE ON FUNCTION keyhippo.initialize_keyhippo() TO postgres, service_role;
GRANT EXECUTE ON FUNCTION keyhippo.initialize_existing_project() TO postgres, service_role;
GRANT EXECUTE ON FUNCTION keyhippo.assign_default_role() TO postgres, service_role;

-- Grant EXECUTE permissions on audit and expiry functions
GRANT EXECUTE ON FUNCTION keyhippo.log_table_change() TO postgres, service_role;
GRANT EXECUTE ON FUNCTION keyhippo.notify_expiring_key() TO postgres, service_role;
GRANT EXECUTE ON FUNCTION keyhippo.update_expiring_keys() TO postgres, service_role;
GRANT EXECUTE ON FUNCTION keyhippo_internal.enable_audit_log_notify() TO postgres, service_role;
GRANT EXECUTE ON FUNCTION keyhippo_internal.disable_audit_log_notify() TO postgres, service_role;
GRANT EXECUTE ON FUNCTION keyhippo_internal.send_installation_notification() TO postgres, service_role;
GRANT EXECUTE ON FUNCTION keyhippo_internal.notify_audit_change() TO postgres, service_role;

-- Grant EXECUTE permissions on impersonation functions
GRANT EXECUTE ON PROCEDURE keyhippo_impersonation.login_as_user(uuid) TO postgres;
GRANT EXECUTE ON PROCEDURE keyhippo_impersonation.login_as_anon() TO postgres;
GRANT EXECUTE ON FUNCTION keyhippo_impersonation.get_and_cleanup_impersonation() TO authenticated, anon, service_role;
GRANT EXECUTE ON PROCEDURE keyhippo_impersonation.logout() TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION keyhippo_impersonation.generate_random_user_data() TO postgres, service_role;
GRANT EXECUTE ON FUNCTION keyhippo_impersonation.generate_new_user() TO postgres, service_role;

-- Grant sequence permissions
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA keyhippo TO authenticated, service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA keyhippo_rbac TO authenticated, service_role;

-- Grant permissions for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA keyhippo GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA keyhippo_rbac GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA keyhippo GRANT USAGE, SELECT ON SEQUENCES TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA keyhippo_rbac GRANT USAGE, SELECT ON SEQUENCES TO authenticated, service_role;

-- Set as pre-request check for PostgREST
ALTER ROLE authenticator SET pgrst.db_pre_request = 'keyhippo.check_request';

-- Notify PostgREST to reload configuration
NOTIFY pgrst, 'reload config';

COMMIT;