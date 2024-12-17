# api_key_metadata

Stores API key metadata and status information.

## Table Definition

```sql
CREATE TABLE keyhippo.api_key_metadata (
    key_id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    key_prefix text NOT NULL,
    user_id uuid NOT NULL,
    scope text,
    tenant_id uuid,
    description text NOT NULL,
    status text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    last_used_at timestamptz,
    metadata jsonb,
    version integer NOT NULL DEFAULT 1,
    CONSTRAINT valid_key_prefix CHECK (key_prefix ~ '^[A-Z2-7]{8}$'),
    CONSTRAINT valid_status CHECK (status IN ('active', 'revoked', 'expired')),
    CONSTRAINT valid_description CHECK (length(description) <= 255)
);
```

## Indexes

```sql
-- Fast key lookup by prefix
CREATE UNIQUE INDEX idx_api_key_prefix 
ON api_key_metadata(key_prefix);

-- Status checks
CREATE INDEX idx_api_key_status 
ON api_key_metadata(status);

-- Expiration checks
CREATE INDEX idx_api_key_expires 
ON api_key_metadata(expires_at) 
WHERE status = 'active';

-- User key lookup
CREATE INDEX idx_api_key_user 
ON api_key_metadata(user_id) 
INCLUDE (key_prefix, status);
```

## Columns

| Name | Type | Description |
|------|------|-------------|
| key_id | uuid | Primary key |
| key_prefix | text | First 8 chars of key (base32) |
| user_id | uuid | Key owner reference |
| scope | text | Permission scope |
| tenant_id | uuid | Multi-tenant isolation |
| description | text | Key identifier (≤255 chars) |
| status | text | active/revoked/expired |
| created_at | timestamptz | Creation timestamp |
| expires_at | timestamptz | Expiration timestamp |
| last_used_at | timestamptz | Last verification time |
| metadata | jsonb | Additional key data |
| version | integer | Key format version |

## Example Queries

List active keys for user:
```sql
SELECT key_prefix, description, expires_at
FROM api_key_metadata
WHERE user_id = 'user-uuid'
AND status = 'active'
ORDER BY created_at DESC;
```

Find expiring keys:
```sql
SELECT key_id, key_prefix, description
FROM api_key_metadata
WHERE status = 'active'
AND expires_at < now() + interval '7 days'
ORDER BY expires_at;
```

Key usage stats:
```sql
SELECT 
    date_trunc('day', last_used_at) as date,
    count(*) as keys_used
FROM api_key_metadata
WHERE last_used_at >= now() - interval '30 days'
GROUP BY 1
ORDER BY 1;
```

## RLS Policies

```sql
-- Users can only see their own keys
CREATE POLICY user_keys ON api_key_metadata
    FOR ALL
    USING (
        user_id = (current_user_context()->>'user_id')::uuid
    );

-- Tenant isolation
CREATE POLICY tenant_keys ON api_key_metadata
    FOR ALL
    USING (
        tenant_id = (current_user_context()->>'tenant_id')::uuid
    );
```

## Triggers

```sql
-- Update last_used_at on verification
CREATE TRIGGER update_last_used
    AFTER UPDATE OF last_used_at
    ON api_key_metadata
    FOR EACH ROW
    EXECUTE FUNCTION audit_key_usage();

-- Check expiration on verification
CREATE TRIGGER check_expiration
    BEFORE UPDATE
    ON api_key_metadata
    FOR EACH ROW
    EXECUTE FUNCTION validate_key_status();
```

## See Also

- [api_key_secrets](api_key_secrets.md) - Stores key hashes
- [create_api_key()](../functions/create_api_key.md) - Creates keys
- [verify_api_key()](../functions/verify_api_key.md) - Validates keys