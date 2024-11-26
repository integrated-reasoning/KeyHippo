# KeyHippo PostgreSQL Extension

KeyHippo extends Supabase's Row Level Security (RLS) to support API key authentication and Role-Based Access Control (RBAC) directly in Postgres.

## Installation

Install the KeyHippo extension in your PostgreSQL database:

```sql
select dbdev.install('keyhippo@keyhippo');
create extension "keyhippo@keyhippo" version '1.0.0';
```

For updates, visit the [KeyHippo extension catalog entry](https://database.dev/keyhippo/keyhippo).

## Core Features

### API Key Authentication

KeyHippo enables secure API key management directly in Postgres. Each API key is hashed for storage, ensuring plaintext keys are never exposed.

### Unified RLS Policies

With KeyHippo, session tokens and API keys can coexist under unified RLS policies, simplifying authentication logic.

### Role-Based Access Control (RBAC)

Define fine-grained access control through groups, roles, and permissions that integrate seamlessly with your database.

### Impersonation

Administrators can impersonate users for troubleshooting or support tasks without compromising security.

## Usage

### API Key Management

Generate an API key for an authenticated user:

```sql
SELECT * FROM keyhippo.create_api_key('Primary API Key', 'default');
```

Revoke an API key:

```sql
SELECT keyhippo.revoke_api_key('<api_key_id>');
```

Rotate an API key (revoke the old one, create a new one):

```sql
SELECT * FROM keyhippo.rotate_api_key('<old_api_key_id>');
```

### RLS Policy Integration

Example policy combining user authentication and permission checks:

```sql
CREATE POLICY "owner_access"
ON "public"."resource_table"
FOR SELECT
USING (
  keyhippo.current_user_context().user_id = resource_table.owner_id
  AND keyhippo.authorize('manage_resources')
);
```

This policy allows access when the user is authenticated and has the necessary permission.

### RBAC Management

Create and manage roles, groups, and permissions:

```sql
-- Create a new group
SELECT keyhippo_rbac.create_group('Developers', 'Group for developer users') AS group_id;

-- Create a new role
SELECT keyhippo_rbac.create_role('Developer', 'Developer role', '<group_id>', 'user') AS role_id;

-- Assign a permission to the role
SELECT keyhippo_rbac.assign_permission_to_role('<role_id>', 'manage_resources');

-- Assign the role to a user
SELECT keyhippo_rbac.assign_role_to_user('<user_id>', '<group_id>', '<role_id>');
```

### Impersonation Functions

Admins can act on behalf of other users:

```sql
CALL keyhippo_impersonation.login_as_user('<user_id>');

-- Perform actions as the impersonated user

CALL keyhippo_impersonation.logout();
```

## Integration with Supabase

KeyHippo integrates seamlessly with Supabase and PostgREST, enabling API key and RBAC functionality within your existing stack.

## Security Highlights

- **Hashed Keys:** Only key hashes are stored, ensuring plaintext keys are unavailable after creation.
- **Scoped Permissions:** API keys include scoping to restrict their usage.
- **Session Interoperability:** Works alongside session-based authentication.

## Contribution

Contributions are welcome. See our [Contributing Guide](https://github.com/integrated-reasoning/KeyHippo/blob/main/CONTRIBUTING.md) for details.

## License

KeyHippo is distributed under the MIT license. See the [LICENSE](https://github.com/integrated-reasoning/KeyHippo/blob/main/LICENSE) file for more information.

## Support

For technical issues, open a GitHub issue. For commercial support, visit [keyhippo.com](https://keyhippo.com).
