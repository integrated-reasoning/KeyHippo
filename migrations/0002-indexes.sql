BEGIN;

-- Create indexes for performance (idempotent)
CREATE INDEX IF NOT EXISTS idx_api_key_metadata_user_id ON keyhippo.api_key_metadata (user_id);
CREATE INDEX IF NOT EXISTS idx_api_key_metadata_scope_id ON keyhippo.api_key_metadata (scope_id);
CREATE INDEX IF NOT EXISTS idx_api_key_metadata_prefix ON keyhippo.api_key_metadata (prefix);
CREATE INDEX IF NOT EXISTS idx_api_key_metadata_expires_at ON keyhippo.api_key_metadata (expires_at);

CREATE INDEX IF NOT EXISTS idx_user_group_roles_user_id ON keyhippo_rbac.user_group_roles (user_id);
CREATE INDEX IF NOT EXISTS idx_user_group_roles_group_id ON keyhippo_rbac.user_group_roles (group_id);
CREATE INDEX IF NOT EXISTS idx_user_group_roles_role_id ON keyhippo_rbac.user_group_roles (role_id);

CREATE INDEX IF NOT EXISTS idx_roles_name ON keyhippo_rbac.roles (name);
CREATE INDEX IF NOT EXISTS idx_roles_group_id ON keyhippo_rbac.roles (group_id);

CREATE INDEX IF NOT EXISTS idx_scope_permissions_permission_id ON keyhippo.scope_permissions (permission_id);
CREATE INDEX IF NOT EXISTS idx_scope_permissions_scope_id ON keyhippo.scope_permissions (scope_id);

CREATE INDEX IF NOT EXISTS idx_role_permissions_permission_id ON keyhippo_rbac.role_permissions (permission_id);
CREATE INDEX IF NOT EXISTS idx_role_permissions_role_id ON keyhippo_rbac.role_permissions (role_id);

CREATE INDEX IF NOT EXISTS idx_audit_log_timestamp ON keyhippo.audit_log (timestamp);
CREATE INDEX IF NOT EXISTS idx_audit_log_user_id ON keyhippo.audit_log (user_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_action ON keyhippo.audit_log (action);

COMMIT;