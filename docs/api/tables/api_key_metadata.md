# api_key_metadata

Stores metadata for API keys while keeping sensitive information separate.

## Schema

```sql
CREATE TABLE keyhippo.api_key_metadata (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    scope_id uuid REFERENCES keyhippo.scopes(id),
    description text,
    prefix text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now(),
    last_used_at timestamptz,
    expires_at timestamptz NOT NULL DEFAULT (now() + interval '100 years'),
    is_revoked boolean NOT NULL DEFAULT FALSE,
    claims jsonb DEFAULT '{}'::jsonb
);
```

## Columns

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key and identifier for the API key |
| user_id | uuid | Foreign key to auth.users - the key owner |
| scope_id | uuid | Optional foreign key to keyhippo.scopes |
| description | text | User-provided description of the key |
| prefix | text | Unique prefix used for key identification |
| created_at | timestamptz | Timestamp of key creation |
| last_used_at | timestamptz | Last time the key was used |
| expires_at | timestamptz | When the key expires (defaults to 100 years) |
| is_revoked | boolean | Whether the key has been revoked |
| claims | jsonb | Optional custom claims/metadata for the key |

## Indexes

- Primary Key on `id`
- Unique index on `prefix`
- Index on `user_id` for faster lookups

## Row Level Security

```sql
CREATE POLICY api_key_metadata_access_policy ON keyhippo.api_key_metadata
    FOR ALL TO authenticated
    USING (
        user_id = auth.uid()
        OR keyhippo.authorize('manage_api_keys')
    );
```

Users can only see and manage their own API keys unless they have the 'manage_api_keys' permission.

## Triggers

- `keyhippo_audit_api_key_metadata` - Logs changes to the audit log
- `keyhippo_notify_expiring_key_trigger` - Handles key expiration notifications

## Related Tables

- [api_key_secrets](api_key_secrets.md) - Stores the secure hash of the key
- [scopes](scopes.md) - Defines available scopes
- [audit_log](audit_log.md) - Tracks changes to API keys

## Usage Example

```sql
-- Create a new API key
SELECT * FROM keyhippo.create_api_key('Production API');

-- List all active keys for current user
SELECT 
    id,
    description,
    created_at,
    last_used_at,
    expires_at
FROM keyhippo.api_key_metadata
WHERE user_id = auth.uid()
    AND NOT is_revoked
    AND expires_at > NOW();

-- Revoke a key
UPDATE keyhippo.api_key_metadata
SET is_revoked = TRUE
WHERE id = 'key_id_here'
    AND user_id = auth.uid();
```

## Notes

- The actual API key is never stored in this table
- The `prefix` is used for quick key lookups without exposing the full key
- Changes are automatically logged to the audit system
- Supports custom claims for additional metadata
- Integrates with the key expiration notification system