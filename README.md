# KeyHippo

KeyHippo extends Supabase's Row Level Security (RLS) to support API key authentication and Role-Based Access Control (RBAC) directly in Postgres.

<!-- markdownlint-disable-next-line -->
<div align="center">

![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/integrated-reasoning/KeyHippo/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE-MIT)
[![Super-Linter](https://github.com/integrated-reasoning/KeyHippo/actions/workflows/lint.yml/badge.svg)](https://github.com/marketplace/actions/super-linter)

</div>

## Core Functionality

KeyHippo enables API key authentication and fine-grained access control in Supabase applications while preserving Row Level Security policies. It handles both session-based and API key authentication using SQL and introduces an RBAC system for managing permissions.

Features:

- **API Key Management:**

  - Secure key issuance and validation
  - Key rotation and revocation
  - Automatic key expiration
  - Claims-based metadata
  - HTTP notifications for key events

- **Role-Based Access Control (RBAC):**
  - Hierarchical group-based permissions
  - Built-in roles (admin, user)
  - Fine-grained permission management
  - Default role assignment for new users

## Quick Start

### Database Setup

1. Create a new Supabase migration for the KeyHippo extension:

```bash
supabase migration new add_keyhippo_extension
```

2. Copy the contents of `extension/keyhippo--1.2.5.sql` into the newly created migration file in the `supabase/migrations` directory.

3. Apply the migration to install the extension:

```bash
supabase migration up
```

4. For projects with existing users:

```sql
SELECT keyhippo.initialize_existing_project();
```

This will:

- Create default groups (Admin Group, User Group)
- Create default roles (Admin, User)
- Set up default permissions
- Create a default scope
- Assign the User role to existing users (when using initialize_existing_project)

## Application Integration

KeyHippo integrates with your Supabase application in two main ways:

1. **Direct SQL Access**: Use KeyHippo functions through your application's database connection
2. **REST API**: Access via PostgREST endpoints (requires valid API key in x-api-key header)

### Key Management

```sql
-- Generate a new API key
SELECT * FROM keyhippo.create_api_key('Primary API Key', 'default');

-- Verify an API key (internal use)
SELECT * FROM keyhippo.verify_api_key('your-api-key');

-- Get key metadata in RLS policies
SELECT keyhippo.key_data();

-- Revoke an API key
SELECT keyhippo.revoke_api_key('key-id-uuid');

-- Rotate an existing key
SELECT * FROM keyhippo.rotate_api_key('key-id-uuid');

-- Update key claims
SELECT keyhippo.update_key_claims('key-id-uuid', '{"custom": "data"}'::jsonb);
```

### HTTP Integration

KeyHippo supports HTTP notifications for:

- Key expiry events
- Audit log events
- Installation tracking

Configure endpoints through keyhippo_internal.config:

```sql
-- Set audit log endpoint
UPDATE keyhippo_internal.config
SET value = 'https://your-endpoint.com/audit'
WHERE key = 'audit_log_endpoint';

-- Enable HTTP logging
SELECT keyhippo_internal.enable_audit_log_notify();
```

### RLS Policy Implementation

Example of a policy supporting both authentication methods and RBAC:

```sql
CREATE POLICY "owner_access"
ON "public"."resource_table"
FOR SELECT
USING (
  auth.uid() = resource_table.owner_id
  AND keyhippo.authorize('manage_resources')
);
```

This policy grants access when:

1. The user is authenticated (via session token or API key)
2. They are the owner of the resource
3. They have the 'manage_resources' permission

### RBAC Management

Create a new group, role, and assign permissions:

```sql
-- Create a new group
SELECT keyhippo_rbac.create_group('Developers', 'Group for developer users') AS group_id;

-- Create a new role (role_type can be 'admin' or 'user')
SELECT keyhippo_rbac.create_role('Developer', 'Developer role', group_id, 'user'::keyhippo.app_role) AS role_id;

-- Assign permissions to the role (using valid app_permission enum values)
SELECT keyhippo_rbac.assign_permission_to_role(role_id, 'manage_api_keys'::keyhippo.app_permission);

-- Assign the role to a user
SELECT keyhippo_rbac.assign_role_to_user(auth.uid(), group_id, role_id);
```

Available permissions:

- manage_groups
- manage_roles
- manage_permissions
- manage_scopes
- manage_user_attributes
- manage_api_keys

### Impersonation Functionality

KeyHippo provides secure user impersonation for debugging purposes:

```sql
-- Login as another user (requires postgres role)
CALL keyhippo_impersonation.login_as_user('<user_id>');

-- Login as anonymous user (requires postgres role)
CALL keyhippo_impersonation.login_as_anon();

-- Perform actions as the impersonated user
-- The session will automatically expire after 1 hour

-- End impersonation session
CALL keyhippo_impersonation.logout();
```

**Features:**

- Requires postgres role for impersonation
- Automatic session expiration (1 hour)
- Audit logging of impersonation events
- Support for anonymous user impersonation

## Architecture

### Database Schema

KeyHippo organizes its functionality across several schemas:

- **keyhippo**: Main schema for API key management and core functions
- **keyhippo_rbac**: Role-Based Access Control functionality
- **keyhippo_internal**: Internal configuration and utilities
- **keyhippo_impersonation**: User impersonation functionality

### API Key Management

KeyHippo provides API key management with the following features:

**Key Operations:**

```sql
-- Create a new API key
SELECT * FROM keyhippo.create_api_key('My API Key', 'default');

-- Revoke an existing key
SELECT keyhippo.revoke_api_key('key-id-uuid');

-- Rotate an existing key
SELECT * FROM keyhippo.rotate_api_key('key-id-uuid');

-- Update key claims
SELECT keyhippo.update_key_claims('key-id-uuid', '{"custom": "data"}'::jsonb);
```

**Integration:**

```sql
-- Get current key data in RLS policies
SELECT keyhippo.key_data();

-- Check authorization in RLS policies
SELECT keyhippo.authorize('manage_api_keys');

-- Get current user context
SELECT * FROM keyhippo.current_user_context();
```

## Role-Based Access Control (RBAC)

KeyHippo provides a RBAC system that integrates with Postgres RLS policies:

### RBAC Components

- **Groups:** Logical grouping of users (e.g., "Admin Group", "User Group")
- **Roles:** Assigned to users within groups, with role types:
  - 'admin': Full system access
  - 'user': Limited access based on assigned permissions
- **Permissions:** Built-in permissions:
  - manage_groups
  - manage_roles
  - manage_permissions
  - manage_scopes
  - manage_user_attributes
  - manage_api_keys

### Default Setup

On initialization, KeyHippo creates:

1. Default groups: "Admin Group" and "User Group"
2. Default roles: "Admin" (admin type) and "User" (user type)
3. Admin role gets all permissions
4. User role gets 'manage_api_keys' permission
5. New users automatically get the "User" role

### Usage Example

```sql
-- Check if user has permission in RLS policy
SELECT keyhippo.authorize('manage_api_keys');

-- Get current user's permissions
SELECT permissions FROM keyhippo.current_user_context();
```

## Impersonation

KeyHippo provides user impersonation functionality to assist with debugging and maintnence tasks.

### Usage

```sql
-- Start impersonation (requires postgres role)
CALL keyhippo_impersonation.login_as_user('<user_id>');

-- Impersonate anonymous user
CALL keyhippo_impersonation.login_as_anon();

-- End impersonation session
CALL keyhippo_impersonation.logout();
```

### Security Controls

- Only postgres role can initiate impersonation
- Sessions automatically expire after 1 hour
- All actions during impersonation are logged
- Original role is preserved and restored on logout
- State tracking prevents session manipulation

### Integration with RLS

KeyHippo's authentication and authorization integrate with Supabase's Row Level Security policies. Use auth.uid() to get the current user's ID and keyhippo.authorize() to check permissions within your RLS policies.

**Example RLS Policy:**

```sql
CREATE POLICY "user_can_view_own_data" ON "public"."user_data"
  FOR SELECT USING (
    auth.uid() = user_data.user_id
    AND keyhippo.authorize('manage_api_keys')
  );
```

Note: The example uses 'manage_api_keys' as it's one of the built-in permissions. Your application can define additional permissions as needed.

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=integrated-reasoning/KeyHippo&type=Timeline)](https://star-history.com/#integrated-reasoning/KeyHippo&Timeline)

## Contribution

We welcome community contributions. For guidance, see our Contributing Guide.

## Licensing

KeyHippo is distributed under the MIT license. See the LICENSE file for details.

## Development

### Setting Up Development Environment

1. Install Nix (if not already installed):

For Linux/macOS (multi-user installation recommended):

```bash
sh <(curl -L https://nixos.org/nix/install) --daemon
```

For single-user installation:

```bash
sh <(curl -L https://nixos.org/nix/install) --no-daemon
```

2. Clone the repository:

```bash
git clone https://github.com/integrated-reasoning/KeyHippo.git
cd KeyHippo
```

3. Enter the Nix development shell:

```bash
nix develop
```

4. Set up the local Supabase instance:

```bash
make setup-supabase
```

### Running Tests

KeyHippo uses pgTAP for testing. To run the test suite:

```bash
# Run all tests
make test

# Run pgTAP tests specifically
make pg_tap
```

The test suite verifies:

- API key management functionality
- RBAC system operations
- Impersonation features
- Security controls
- Integration with RLS policies

## Support & Community

For technical support and discussions:

- Open an issue on our [GitHub repository](https://github.com/integrated-reasoning/KeyHippo/issues)
- Follow us on [Twitter](https://x.com/keyhippo) for updates
- Visit [keyhippo.com](https://keyhippo.com)
