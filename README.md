# KeyHippo

KeyHippo provides API key management and Role-Based Access Control (RBAC) for PostgreSQL applications, enabling secure authentication and fine-grained authorization directly in your database.

<!-- markdownlint-disable-next-line -->
<div align="center">

![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/integrated-reasoning/KeyHippo/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE-MIT)
[![Super-Linter](https://github.com/integrated-reasoning/KeyHippo/actions/workflows/lint.yml/badge.svg)](https://github.com/marketplace/actions/super-linter)

</div>

## Core Functionality

KeyHippo extends PostgreSQL applications with comprehensive API key management and RBAC capabilities. It handles authentication through API keys or JWT tokens and provides fine-grained authorization through a flexible permission system.

Features:

- **API Key Management:**
  - Secure key issuance and validation
  - Key rotation and revocation
  - Automatic key expiration
  - Claims-based metadata
  - Prefix-based key organization

- **Role-Based Access Control (RBAC):**
  - Hierarchical group-based permissions
  - Built-in roles (admin, user)
  - Fine-grained permission management
  - Default role assignment for new users

- **User Impersonation:**
  - Secure debugging and support capabilities
  - Session-based impersonation with automatic expiry
  - Comprehensive audit logging

## Quick Start

### Database Setup

1. Start PostgreSQL with Docker:

```bash
nix develop
make setup
```

This will:
- Start a PostgreSQL 17.2 container
- Apply all KeyHippo migrations
- Create default groups (Admin Group, User Group)
- Create default roles (Admin, User)
- Set up default permissions
- Create a default scope

2. For existing databases, apply the migrations manually:

```bash
make migrate
```

### Manual Installation

If you prefer to install without Docker:

1. Ensure PostgreSQL 17+ with the `pgcrypto` extension is available
2. Create the auth schema and users table (see `init.sql` for reference)
3. Apply migrations in order from the `migrations/` directory

## Application Integration

KeyHippo integrates with PostgreSQL applications through:

1. **Direct SQL Access**: Use KeyHippo functions through your application's database connection
2. **API Key Headers**: Pass API keys via `x-api-key` header for authentication

### Key Management

```sql
-- Generate a new API key
SELECT * FROM keyhippo.create_api_key('Primary API Key', 'default');

-- Verify an API key (internal use)
SELECT * FROM keyhippo.verify_api_key('your-api-key');

-- Get key metadata for policies
SELECT keyhippo.key_data();

-- Revoke an API key
SELECT keyhippo.revoke_api_key('key-id-uuid');

-- Rotate an existing key
SELECT * FROM keyhippo.rotate_api_key('key-id-uuid');

-- Update key claims
SELECT keyhippo.update_key_claims('key-id-uuid', '{"custom": "data"}'::jsonb);
```

### Authorization in Applications

Example of using KeyHippo authorization in your application logic:

```sql
-- Check if current user has permission
SELECT keyhippo.authorize('manage_api_keys');

-- Get current user context (works with both API keys and JWT)
SELECT * FROM keyhippo.current_user_context();

-- Use in WHERE clauses for row-level filtering
SELECT * FROM your_table 
WHERE owner_id = (SELECT user_id FROM keyhippo.current_user_context())
AND keyhippo.authorize('read_data');
```

### RBAC Management

Create and manage groups, roles, and permissions:

```sql
-- Create a new group
SELECT keyhippo_rbac.create_group('Developers', 'Group for developer users') AS group_id;

-- Create a new role (role_type can be 'admin' or 'user')
SELECT keyhippo_rbac.create_role('Developer', 'Developer role', group_id, 'user'::keyhippo.app_role) AS role_id;

-- Assign permissions to the role
SELECT keyhippo_rbac.assign_permission_to_role(role_id, 'manage_api_keys'::keyhippo.app_permission);

-- Assign the role to a user (user_id from your auth system)
SELECT keyhippo_rbac.assign_role_to_user(user_id, group_id, role_id);
```

Available permissions:
- `manage_groups`
- `manage_roles`
- `manage_permissions`
- `manage_scopes`
- `manage_user_attributes`
- `manage_api_keys`

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

KeyHippo provides comprehensive API key management:

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
-- Get current key data in application logic
SELECT keyhippo.key_data();

-- Check authorization in application logic
SELECT keyhippo.authorize('manage_api_keys');

-- Get current user context
SELECT * FROM keyhippo.current_user_context();
```

## Role-Based Access Control (RBAC)

KeyHippo provides a comprehensive RBAC system:

### RBAC Components

- **Groups:** Logical grouping of users (e.g., "Admin Group", "User Group")
- **Roles:** Assigned to users within groups, with role types:
  - 'admin': Full system access
  - 'user': Limited access based on assigned permissions
- **Permissions:** Built-in permissions for system operations

### Default Setup

On initialization, KeyHippo creates:

1. Default groups: "Admin Group" and "User Group"
2. Default roles: "Admin" (admin type) and "User" (user type)
3. Admin role gets all permissions
4. User role gets 'manage_api_keys' permission
5. New users automatically get the "User" role

### Usage Example

```sql
-- Check if user has permission in application logic
SELECT keyhippo.authorize('manage_api_keys');

-- Get current user's permissions
SELECT permissions FROM keyhippo.current_user_context();
```

## User Impersonation

KeyHippo provides user impersonation functionality for debugging and maintenance:

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

4. Set up the local PostgreSQL instance:

```bash
make setup
```

### Available Commands

```bash
# Start PostgreSQL container
make start

# Stop PostgreSQL container  
make stop

# Apply migrations
make migrate

# Reset database
make reset

# Run tests
make test

# Run benchmarks
make benchmark

# Connect to database
make psql

# View logs
make logs

# Clean up (remove containers and volumes)
make clean
```

### Running Tests

KeyHippo uses custom SQL tests for verification:

```bash
# Run all tests
make test

# Run benchmarks
make benchmark
```

The test suite verifies:
- API key management functionality
- RBAC system operations
- Impersonation features
- Security controls
- Performance characteristics

### Database Migration System

KeyHippo uses a migration-based approach:

- `migrations/0000-schemas-and-types.sql` - Core schemas and types
- `migrations/0001-tables.sql` - Database tables
- `migrations/0002-indexes.sql` - Performance indexes
- `migrations/0003-core-functions.sql` - Core functionality
- `migrations/0004-rbac-functions.sql` - RBAC functions
- `migrations/0005-impersonation-functions.sql` - Impersonation features
- `migrations/0006-initialization.sql` - Initial data setup
- `migrations/0007-permissions.sql` - Permission grants

Each migration is wrapped in a transaction for safety.

## Support & Community

For technical support and discussions:

- Open an issue on our [GitHub repository](https://github.com/integrated-reasoning/KeyHippo/issues)
- Follow us on [Twitter](https://x.com/keyhippo) for updates
- Visit [keyhippo.com](https://keyhippo.com)