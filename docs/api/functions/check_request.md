# check_request

Validate an incoming API request against security rules.

## Synopsis

```sql
keyhippo.check_request(
    request_data jsonb,
    options jsonb DEFAULT NULL
) RETURNS boolean
```

## Description

`check_request` performs security checks on API requests:
1. Validates API key if present
2. Checks rate limits
3. Validates request format
4. Logs request metadata
5. Updates usage statistics

## Parameters

| Name | Type | Description |
|------|------|-------------|
| request_data | jsonb | Request details |
| options | jsonb | Check options |

## Request Data Format

Required fields:
```json
{
    "method": "GET|POST|PUT|DELETE",
    "path": "/api/v1/resource",
    "headers": {
        "x-api-key": "prefix.key",
        "content-type": "application/json"
    },
    "client_ip": "10.0.0.1",
    "timestamp": "2024-01-01T00:00:00Z"
}
```

Optional fields:
```json
{
    "body": {"key": "value"},
    "query": {"filter": "value"},
    "user_agent": "curl/7.64.1",
    "request_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

## Examples

Basic check:
```sql
SELECT check_request('{
    "method": "GET",
    "path": "/api/v1/items",
    "headers": {
        "x-api-key": "KH2ABJM1.NBTGK19FH27DJSM4"
    },
    "client_ip": "10.0.0.1"
}');
```

With options:
```sql
SELECT check_request(
    request_data := '{
        "method": "POST",
        "path": "/api/v1/items",
        "headers": {
            "x-api-key": "KH2ABJM1.NBTGK19FH27DJSM4"
        },
        "body": {
            "name": "test"
        }
    }',
    options := '{
        "rate_limit": {
            "window": "1 minute",
            "max_requests": 60
        },
        "require_body_hash": true
    }'
);
```

Batch check:
```sql
INSERT INTO request_log (passed, checked_at)
SELECT 
    check_request(request_data) as passed,
    now() as checked_at
FROM json_array_elements('[
    {"method": "GET", "path": "/api/v1/items"},
    {"method": "POST", "path": "/api/v1/items"}
]'::json) as request_data;
```

## Implementation

Request processing:
```sql
-- 1. Extract API key
SELECT verify_api_key(
    (request_data->'headers'->>'x-api-key')::text
) INTO key_context;

-- 2. Check rate limit
SELECT check_rate_limit(
    (request_data->>'client_ip')::inet,
    key_context->>'key_id'
) INTO rate_ok;

-- 3. Validate request format
SELECT validate_request_format(
    request_data,
    (options->>'schema_version')::text
) INTO format_ok;

-- 4. Log request
INSERT INTO request_log (
    request_id,
    method,
    path,
    client_ip,
    key_id,
    passed
) VALUES (
    coalesce(
        (request_data->>'request_id')::uuid,
        gen_random_uuid()
    ),
    request_data->>'method',
    request_data->>'path',
    (request_data->>'client_ip')::inet,
    (key_context->>'key_id')::uuid,
    rate_ok AND format_ok
);

-- 5. Update statistics
UPDATE api_key_metadata
SET 
    last_used_at = now(),
    request_count = request_count + 1
WHERE key_id = (key_context->>'key_id')::uuid;
```

## Error Cases

Invalid request data:
```sql
ERROR:  invalid request data
DETAIL:  Missing required field "method"
```

Rate limit exceeded:
```sql
ERROR:  rate limit exceeded
DETAIL:  Max 60 requests per minute
HINT:   Try again in 35 seconds
```

Invalid API key:
```sql
ERROR:  invalid api key
DETAIL:  Key "KH2ABJM1.NBTGK19FH27DJSM4" not found or expired
```

Format validation:
```sql
ERROR:  invalid request format
DETAIL:  Body hash mismatch
HINT:   Include content-md5 header
```

## Request Validation Rules

Method validation:
```sql
method IN ('GET', 'POST', 'PUT', 'DELETE', 'PATCH')
```

Path validation:
```sql
path ~ '^/api/v[0-9]+/[a-z0-9_/-]+$'
```

Header requirements:
```sql
headers ? 'x-api-key'
headers ? 'content-type' WHEN method IN ('POST', 'PUT', 'PATCH')
```

IP validation:
```sql
client_ip <<= any(allowed_networks)
client_ip != '0.0.0.0/0'
```

## Rate Limiting

Default limits:
```sql
-- Anonymous requests
60 per minute per IP

-- Authenticated requests
1000 per minute per key

-- Burst handling
{
    "burst": true,
    "burst_limit": 5,
    "burst_period": "1 second"
}
```

## See Also

- [verify_api_key()](verify_api_key.md)
- [request_log table](../tables/request_log.md)
- [rate_limits table](../tables/rate_limits.md)