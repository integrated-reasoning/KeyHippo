# config

Stores system-wide configuration settings.

## Table Definition

```sql
CREATE TABLE keyhippo_internal.config (
    key text PRIMARY KEY,
    value jsonb NOT NULL,
    description text,
    modified_at timestamptz NOT NULL DEFAULT now(),
    modified_by uuid NOT NULL,
    requires_restart boolean DEFAULT false,
    metadata jsonb,
    CONSTRAINT valid_key CHECK (key ~ '^[a-z][a-z0-9_]{2,62}[a-z0-9]$'),
    CONSTRAINT valid_value CHECK (jsonb_typeof(value) IN ('object', 'string', 'number', 'boolean'))
);
```

## Default Settings

Authentication:
```sql
INSERT INTO config (key, value, description) VALUES
('key_format', '"prefix.key"', 'API key format string'),
('key_prefix_length', '8', 'Length of key prefix'),
('key_strength', '32', 'Bytes of key entropy'),
('key_expiry_days', '365', 'Default key lifetime'),
('max_keys_per_user', '10', 'Key limit per user');
```

Authorization:
```sql
INSERT INTO config (key, value, description) VALUES
('permission_cache_ttl', '300', 'Cache lifetime in seconds'),
('max_role_depth', '5', 'Maximum role inheritance depth'),
('require_mfa', 'false', 'Require MFA for admin actions'),
('session_lifetime', '86400', 'Session TTL in seconds');
```

Rate Limiting:
```sql
INSERT INTO config (key, value, description) VALUES
('rate_limits', '{
    "anonymous": {
        "requests_per_minute": 60,
        "burst": 5
    },
    "authenticated": {
        "requests_per_minute": 1000,
        "burst": 50
    }
}', 'Rate limit configuration');
```

Audit:
```sql
INSERT INTO config (key, value, description) VALUES
('audit_level', '"standard"', 'Audit detail level'),
('retention_months', '12', 'Audit log retention'),
('log_queries', 'false', 'Record SQL queries'),
('log_client_ip', 'true', 'Record client IPs');
```

## Example Queries

Get setting:
```sql
SELECT value FROM config WHERE key = 'key_expiry_days';
```

Update setting:
```sql
UPDATE config 
SET 
    value = '180'::jsonb,
    modified_at = now(),
    modified_by = current_user_id()
WHERE key = 'key_expiry_days';
```

Check modified settings:
```sql
SELECT 
    key,
    value,
    modified_at,
    (SELECT email FROM users WHERE id = modified_by) as modified_by
FROM config
WHERE modified_at > now() - interval '24 hours'
ORDER BY modified_at DESC;
```

Settings requiring restart:
```sql
SELECT key, value, description
FROM config
WHERE requires_restart = true
AND modified_at > pg_postmaster_start_time();
```

## Setting Types

Simple values:
```sql
-- String
"prefix.key"

-- Number
60

-- Boolean
true
```

Complex objects:
```json
{
    "levels": {
        "anonymous": {
            "max": 60,
            "window": "1 minute"
        },
        "authenticated": {
            "max": 1000,
            "window": "1 minute"
        }
    },
    "headers": {
        "required": ["x-api-key"],
        "optional": ["x-request-id"]
    }
}
```

## Implementation Notes

Access function:
```sql
CREATE FUNCTION get_config(
    setting text,
    default_value jsonb DEFAULT NULL
) RETURNS jsonb AS $$
    SELECT COALESCE(
        (SELECT value FROM config WHERE key = $1),
        $2
    );
$$ LANGUAGE sql STABLE;
```

Cache table:
```sql
CREATE UNLOGGED TABLE config_cache (
    key text PRIMARY KEY,
    value jsonb NOT NULL,
    cached_at timestamptz NOT NULL DEFAULT now()
);
```

Invalidation trigger:
```sql
CREATE TRIGGER invalidate_config_cache
    AFTER UPDATE ON config
    FOR EACH ROW
    EXECUTE FUNCTION invalidate_config();
```

## Error Cases

Invalid key:
```sql
INSERT INTO config (key, value) VALUES ('123_invalid', '0');
ERROR:  new row violates check constraint "valid_key"
DETAIL:  Key must start with letter, use only a-z, 0-9, underscore
```

Invalid value:
```sql
UPDATE config SET value = 'invalid'::jsonb;
ERROR:  new row violates check constraint "valid_value"
DETAIL:  Value must be valid JSON object, string, number, or boolean
```

## Permissions Required

Read settings:
- Any authenticated user

Modify settings:
- 'manage_config' permission
- System administrator access

## See Also

- [System Configuration](../config.md)
- [initialize_keyhippo()](../functions/initialize_keyhippo.md)
- [Configuration API](../api/config.md)