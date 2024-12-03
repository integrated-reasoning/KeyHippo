# KeyHippo PostgreSQL Extension

This directory contains the PostgreSQL extension for KeyHippo, which extends Supabase's Row Level Security (RLS) to support API key authentication and Role-Based Access Control (RBAC) directly in Postgres.

## Installation

To install the KeyHippo extension in your PostgreSQL database:

```sql
select dbdev.install('keyhippo@keyhippo');
create extension "keyhippo@keyhippo" version '1.0.0';
```

Consult [database.dev](https://database.dev/keyhippo/keyhippo) for version updates.

## Usage in RLS Policies

Once installed, you can use KeyHippo functions in your RLS policies. For example:

```sql
CREATE POLICY "owner_access"
ON "public"."resource_table"
FOR SELECT
USING (
  keyhippo.current_user_context().user_id = resource_table.owner_id
  AND keyhippo.authorize('manage_resources')
);
```

This policy allows access when the user is authenticated via a session token or a valid API key and has the 'manage_resources' permission.

## Available Functions

- `keyhippo.create_api_key(description TEXT, scope_name TEXT DEFAULT NULL)`: Creates a new API key for the current authenticated user.
- `keyhippo.revoke_api_key(api_key_id UUID)`: Revokes an existing API key.
- `keyhippo.rotate_api_key(old_api_key_id UUID)`: Rotates an API key by revoking the old one and creating a new one.
- `keyhippo.current_user_context()`: Returns the current user's ID, scope, and permissions.
- `keyhippo.authorize(requested_permission keyhippo.app_permission)`: Checks if the current user has the requested permission.

### RBAC Management Functions

- `keyhippo_rbac.create_group(name TEXT, description TEXT)`: Creates a new group.
- `keyhippo_rbac.create_role(name TEXT, description TEXT, group_id UUID, role_type keyhippo.app_role)`: Creates a new role within a group.
- `keyhippo_rbac.assign_permission_to_role(role_id UUID, permission_name keyhippo.app_permission)`: Assigns a permission to a role.
- `keyhippo_rbac.assign_role_to_user(user_id UUID, group_id UUID, role_id UUID)`: Assigns a role to a user within a group.

### Impersonation Functions

- `keyhippo_impersonation.login_as_user(user_id UUID)`: Allows an admin to impersonate another user.
- `keyhippo_impersonation.logout()`: Ends an impersonation session.

## Contributing

We welcome contributions to the KeyHippo extension. Please see our [Contributing Guide](/docs/Contributing.md) for more information.

## License

The KeyHippo PostgreSQL extension is distributed under the MIT license. See the [LICENSE](../LICENSE) file in the root directory for details.
