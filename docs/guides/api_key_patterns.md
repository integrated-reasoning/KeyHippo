# API Key Implementation Patterns

## Key Format

Structure:
```
prefix.key
KH2ABJM1.NBTGK19FH27DJSM4
```

Components:
```sql
-- Prefix (8 chars)
base32(first_5_bytes)
Used for key lookup

-- Key (32 chars)
base32(random_bytes(30))
Used for authentication
```

Implementation:
```sql
CREATE FUNCTION generate_api_key()
RETURNS text AS $$
DECLARE
    key_bytes bytea;
    key_string text;
    prefix_string text;
BEGIN
    -- Generate random bytes
    key_bytes := gen_random_bytes(30);
    
    -- Create prefix from first 5 bytes
    prefix_string := encode(
        substring(key_bytes FROM 1 FOR 5),
        'base32'
    );
    
    -- Create key from all bytes
    key_string := encode(key_bytes, 'base32');
    
    RETURN prefix_string || '.' || key_string;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

## Storage Pattern

Split storage model:
```sql
-- Metadata (searchable)
CREATE TABLE api_key_metadata (
    key_id uuid PRIMARY KEY,
    key_prefix text NOT NULL,
    user_id uuid NOT NULL,
    scope text,
    expires_at timestamptz,
    status text
);

-- Secrets (restricted)
CREATE TABLE api_key_secrets (
    key_id uuid PRIMARY KEY,
    key_hash text NOT NULL
);
```

Key creation:
```sql
WITH new_key AS (
    SELECT 
        gen_random_uuid() as key_id,
        generate_api_key() as key_string
)
INSERT INTO api_key_metadata (
    key_id,
    key_prefix,
    user_id,
    scope,
    expires_at
)
SELECT 
    key_id,
    split_part(key_string, '.', 1),
    current_user_id(),
    'default',
    now() + interval '1 year'
FROM new_key
RETURNING key_id;

INSERT INTO api_key_secrets (
    key_id,
    key_hash
)
SELECT 
    key_id,
    crypt(key_string, gen_salt('bf', 10))
FROM new_key;
```

## Validation Pattern

Fast path lookup:
```sql
CREATE INDEX idx_api_key_prefix 
ON api_key_metadata(key_prefix);

CREATE INDEX idx_api_key_status 
ON api_key_metadata(status, expires_at) 
WHERE status = 'active';
```

Validation function:
```sql
CREATE FUNCTION verify_api_key(key text)
RETURNS jsonb AS $$
DECLARE
    key_parts text[];
    key_data record;
    result jsonb;
BEGIN
    -- Split key
    key_parts := string_to_array(key, '.');
    IF array_length(key_parts, 1) != 2 THEN
        RETURN NULL;
    END IF;

    -- Lookup metadata
    SELECT INTO key_data
        k.key_id,
        k.user_id,
        k.scope,
        k.status,
        k.expires_at,
        s.key_hash
    FROM api_key_metadata k
    JOIN api_key_secrets s ON s.key_id = k.key_id
    WHERE k.key_prefix = key_parts[1]
    AND k.status = 'active'
    AND k.expires_at > now();

    -- Key not found
    IF key_data IS NULL THEN
        RETURN NULL;
    END IF;

    -- Verify hash
    IF NOT crypt(key, key_data.key_hash) = key_data.key_hash THEN
        RETURN NULL;
    END IF;

    -- Return context
    RETURN jsonb_build_object(
        'user_id', key_data.user_id,
        'key_id', key_data.key_id,
        'scope', key_data.scope
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

## Rotation Pattern

Graceful rotation:
```sql
CREATE FUNCTION rotate_api_key(
    old_key_id uuid,
    grace_period interval DEFAULT '24 hours'
) RETURNS text AS $$
DECLARE
    new_key_id uuid;
    new_key text;
BEGIN
    -- Start transaction
    BEGIN
        -- Create new key
        SELECT 
            k.key_id, k.key_string 
        INTO new_key_id, new_key
        FROM create_api_key(
            (SELECT description FROM api_key_metadata 
             WHERE key_id = old_key_id)
        ) k;

        -- Copy metadata
        UPDATE api_key_metadata 
        SET
            scope = old.scope,
            metadata = jsonb_set(
                old.metadata,
                '{rotation}',
                jsonb_build_object(
                    'previous_key', old_key_id,
                    'rotated_at', now()
                )
            )
        FROM api_key_metadata old
        WHERE api_key_metadata.key_id = new_key_id
        AND old.key_id = old_key_id;

        -- Set expiry on old key
        UPDATE api_key_metadata 
        SET
            expires_at = now() + grace_period,
            metadata = jsonb_set(
                metadata,
                '{rotation}',
                jsonb_build_object(
                    'new_key', new_key_id,
                    'rotated_at', now()
                )
            )
        WHERE key_id = old_key_id;

        RETURN new_key;
    EXCEPTION WHEN OTHERS THEN
        -- Cleanup on error
        DELETE FROM api_key_metadata 
        WHERE key_id = new_key_id;
        RAISE;
    END;
END;
$$ LANGUAGE plpgsql;
```

## Rate Limiting Pattern

Implementation:
```sql
CREATE UNLOGGED TABLE rate_limits (
    key_id uuid,
    window_start timestamptz,
    request_count int,
    PRIMARY KEY (key_id, window_start)
);

CREATE FUNCTION check_rate_limit(
    key_id uuid,
    window interval,
    max_requests int
) RETURNS boolean AS $$
DECLARE
    window_start timestamptz;
    current_count int;
BEGIN
    -- Calculate window
    window_start := date_trunc(
        'minute',
        now()
    );
    
    -- Get/update count
    INSERT INTO rate_limits AS r
        (key_id, window_start, request_count)
    VALUES
        ($1, window_start, 1)
    ON CONFLICT (key_id, window_start) DO UPDATE
    SET request_count = r.request_count + 1
    RETURNING request_count INTO current_count;
    
    -- Check limit
    RETURN current_count <= max_requests;
END;
$$ LANGUAGE plpgsql;
```

Cleanup job:
```sql
CREATE FUNCTION cleanup_rate_limits()
RETURNS void AS $$
BEGIN
    DELETE FROM rate_limits
    WHERE window_start < now() - interval '1 hour';
END;
$$ LANGUAGE sql;
```

## Scope Pattern

Scope definition:
```sql
CREATE TABLE scopes (
    name text PRIMARY KEY,
    permissions text[],
    conditions jsonb
);

INSERT INTO scopes (name, permissions, conditions) VALUES
(
    'analytics',
    ARRAY['read_data', 'export_reports'],
    '{
        "time_window": {
            "start": "00:00",
            "end": "23:59"
        },
        "rate_limit": {
            "requests_per_minute": 60
        }
    }'
);
```

Permission check:
```sql
CREATE FUNCTION check_scope_permission(
    scope_name text,
    permission text
) RETURNS boolean AS $$
    SELECT EXISTS (
        SELECT 1 FROM scopes
        WHERE name = $1
        AND $2 = ANY(permissions)
        AND evaluate_conditions(conditions)
    );
$$ LANGUAGE sql STABLE;
```

## Audit Pattern

Key events:
```sql
INSERT INTO audit_log (event_type, event_data) 
VALUES (
    'key_created',
    jsonb_build_object(
        'key_id', key_id,
        'key_prefix', key_prefix,
        'scope', scope,
        'created_by', current_user_id()
    )
);
```

Usage tracking:
```sql
CREATE MATERIALIZED VIEW key_usage_stats AS
SELECT 
    key_id,
    date_trunc('hour', created_at) as hour,
    count(*) as requests,
    count(*) FILTER (
        WHERE success = false
    ) as failed_requests
FROM request_log
WHERE created_at > now() - interval '30 days'
GROUP BY key_id, date_trunc('hour', created_at);

REFRESH MATERIALIZED VIEW CONCURRENTLY key_usage_stats;
```

## See Also

- [create_api_key()](../api/functions/create_api_key.md)
- [verify_api_key()](../api/functions/verify_api_key.md)
- [rotate_api_key()](../api/functions/rotate_api_key.md)