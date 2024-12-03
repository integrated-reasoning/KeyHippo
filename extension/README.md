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

Full usage details can be found on [GitHub](https://github.com/integrated-reasoning/KeyHippo/blob/main/README.md).

## Integration with Supabase

KeyHippo integrates with Supabase and PostgREST, enabling API key and RBAC functionality within your existing stack.

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
