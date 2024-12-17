# key_data

Retrieve metadata for an API key.

## Synopsis

```sql
keyhippo.key_data(
    key_id uuid
) RETURNS jsonb
```

## Description

`key_data` returns detailed information about an API key including:
1. Key status and expiration
2. Usage statistics
3. Associated permissions
4. Audit history

## Parameters

| Name | Type | Description |
|------|------|-------------|
| key_id | uuid | Key identifier |

## Return Value

Returns JSONB object:
```json
{
    "key_id": "550e8400-e29b-41d4-a716-446655440000",
    "key_prefix": "KH2ABJM1",
    "status": "active",
    "created_at": "2024-01-01T00:00:00Z",
    "expires_at": "2025-01-01T00:00:00Z",
    "last_used_at": "2024-01-02T10:30:00Z",
    "usage": {
        "total_requests": 1542,
        "last_24h": 127,
        "failed_attempts": 3
    },
    "scope": {
        "name": "analytics",
        "permissions": ["read_data", "export_reports"]
    },
    "metadata": {
        "description": "Analytics API",
        "environment": "production",
        "created_by": "john.doe@example.com"
    }
}
```

## Examples

Basic lookup:
```sql
SELECT key_data('550e8400-e29b-41d4-a716-446655440000');
```

Check key status:
```sql
SELECT (key_data('550e8400-e29b-41d4-a716-446655440000')->>'status') = 'active' 
AS is_active;
```

Usage statistics:
```sql
SELECT 
    k->>'key_prefix' as prefix,
    (k->'usage'->>'total_requests')::int as requests,
    (k->'usage'->>'last_24h')::int as recent_requests
FROM (
    SELECT key_data(key_id) as k
    FROM api_key_metadata
    WHERE created_at > now() - interval '7 days'
) recent_keys
ORDER BY recent_requests DESC;
```

## Implementation

Data collection SQL:
```sql
WITH key_info AS (
    SELECT 
        k.key_id,
        k.key_prefix,
        k.status,
        k.created_at,
        k.expires_at,
        k.last_used_at,
        k.metadata,
        s.name as scope_name,
        s.permissions as scope_permissions
    FROM api_key_metadata k
    LEFT JOIN scopes s ON s.scope_id = k.scope_id
    WHERE k.key_id = $1
),
key_usage AS (
    SELECT
        count(*) as total_requests,
        count(*) FILTER (
            WHERE created_at > now() - interval '24 hours'
        ) as last_24h,
        count(*) FILTER (
            WHERE success = false
        ) as failed_attempts
    FROM request_log
    WHERE key_id = $1
)
SELECT jsonb_build_object(
    'key_id', key_id,
    'key_prefix', key_prefix,
    'status', status,
    'created_at', created_at,
    'expires_at', expires_at,
    'last_used_at', last_used_at,
    'usage', jsonb_build_object(
        'total_requests', total_requests,
        'last_24h', last_24h,
        'failed_attempts', failed_attempts
    ),
    'scope', jsonb_build_object(
        'name', scope_name,
        'permissions', scope_permissions
    ),
    'metadata', metadata
)
FROM key_info, key_usage;
```

## Error Cases

Key not found:
```sql
SELECT key_data('550e8400-e29b-41d4-a716-446655440000');
ERROR:  key not found
DETAIL:  No key exists with ID 550e8400-e29b-41d4-a716-446655440000
```

Permission denied:
```sql
SELECT key_data('550e8400-e29b-41d4-a716-446655440000');
ERROR:  permission denied
DETAIL:  Current user cannot view this key's data
```

## Permissions Required

Caller must either:
- Own the key
- Have 'view_any_key' permission
- Be system administrator

## Performance

Function uses indexes:
```sql
CREATE INDEX idx_key_metadata_id 
ON api_key_metadata(key_id);

CREATE INDEX idx_request_log_key 
ON request_log(key_id, created_at DESC);

CREATE INDEX idx_request_log_recent 
ON request_log(key_id, created_at DESC) 
WHERE created_at > now() - interval '24 hours';
```

Usage data is pre-aggregated hourly:
```sql
CREATE MATERIALIZED VIEW key_usage_hourly AS
SELECT 
    key_id,
    date_trunc('hour', created_at) as hour,
    count(*) as requests,
    count(*) FILTER (WHERE success = false) as failed
FROM request_log
GROUP BY key_id, date_trunc('hour', created_at);

REFRESH MATERIALIZED VIEW CONCURRENTLY key_usage_hourly;
```

## See Also

- [api_key_metadata table](../tables/api_key_metadata.md)
- [verify_api_key()](verify_api_key.md)
- [create_api_key()](create_api_key.md)