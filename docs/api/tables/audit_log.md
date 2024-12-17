# audit_log

Records all security-relevant operations.

## Table Definition

```sql
CREATE TABLE keyhippo.audit_log (
    event_id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    event_type text NOT NULL,
    event_data jsonb NOT NULL,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    user_id uuid,
    key_id uuid,
    tenant_id uuid,
    client_ip inet,
    session_id uuid,
    CONSTRAINT valid_event_type CHECK (event_type ~ '^[a-z_]{3,50}$'),
    CONSTRAINT valid_event_data CHECK (jsonb_typeof(event_data) = 'object')
);
```

## Indexes

```sql
-- Time-based queries
CREATE INDEX idx_audit_log_time 
ON audit_log(occurred_at DESC);

-- Event type filtering
CREATE INDEX idx_audit_log_type 
ON audit_log(event_type, occurred_at DESC);

-- User activity
CREATE INDEX idx_audit_log_user 
ON audit_log(user_id, occurred_at DESC)
INCLUDE (event_type);

-- API key activity
CREATE INDEX idx_audit_log_key 
ON audit_log(key_id, occurred_at DESC)
INCLUDE (event_type);

-- Tenant isolation
CREATE INDEX idx_audit_log_tenant 
ON audit_log(tenant_id, occurred_at DESC);

-- JSON search
CREATE INDEX idx_audit_log_gin 
ON audit_log USING gin(event_data);
```

## Event Types

Authentication:
```sql
key_created        -- New API key
key_verified      -- Successful key use
key_revoked       -- Key invalidated
key_rotated       -- Key replaced
auth_failed       -- Failed authentication
```

Authorization:
```sql
permission_granted -- New permission
permission_denied  -- Access blocked
role_assigned     -- Role given to user
role_removed      -- Role taken from user
```

User Context:
```sql
user_login        -- User signs in
user_logout       -- User signs out
impersonation_start -- Admin assumes identity
impersonation_end   -- Admin releases identity
```

Resource Access:
```sql
resource_created   -- New resource
resource_accessed  -- Resource read
resource_modified  -- Resource changed
resource_deleted   -- Resource removed
```

System Events:
```sql
config_changed    -- Setting modified
policy_modified   -- RLS policy changed
schema_altered    -- DB structure changed
backup_completed  -- Backup finished
```

## Event Data Format

Authentication events:
```json
{
    "key_id": "550e8400-e29b-41d4-a716-446655440000",
    "key_prefix": "KH2ABJM1",
    "scope": "analytics",
    "expires_at": "2025-01-01T00:00:00Z",
    "created_by": "67e55044-10b1-426f-9247-bb680e5fe0c8"
}
```

Permission events:
```json
{
    "permission": "read_data",
    "role": "analyst",
    "granted_by": "91c35b46-8c55-4264-8373-cf4b1ce957b9",
    "conditions": {
        "time_window": {
            "start": "09:00",
            "end": "17:00"
        }
    }
}
```

Resource events:
```json
{
    "resource_type": "report",
    "resource_id": "550e8400-e29b-41d4-a716-446655440000",
    "operation": "SELECT",
    "rows_affected": 150,
    "query_id": "67e55044-10b1-426f-9247-bb680e5fe0c8"
}
```

## Example Queries

Recent authentication failures:
```sql
SELECT 
    occurred_at,
    client_ip,
    event_data->>'reason' as failure_reason,
    event_data->>'key_prefix' as key_prefix
FROM audit_log
WHERE event_type = 'auth_failed'
AND occurred_at > now() - interval '1 hour'
ORDER BY occurred_at DESC;
```

User activity timeline:
```sql
SELECT 
    occurred_at,
    event_type,
    event_data
FROM audit_log
WHERE user_id = '550e8400-e29b-41d4-a716-446655440000'
AND occurred_at > now() - interval '24 hours'
ORDER BY occurred_at DESC;
```

Permission changes:
```sql
SELECT 
    occurred_at,
    event_data->>'role' as role,
    event_data->>'permission' as permission,
    event_data->>'granted_by' as admin
FROM audit_log
WHERE event_type = 'permission_granted'
AND tenant_id = '91c35b46-8c55-4264-8373-cf4b1ce957b9'
ORDER BY occurred_at DESC;
```

## Retention Policy

```sql
-- Partition by month
CREATE TABLE audit_log_y2024m01 
PARTITION OF audit_log
FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- Auto-create partitions
CREATE OR REPLACE FUNCTION create_audit_partition()
RETURNS trigger AS $$
BEGIN
    EXECUTE format(
        'CREATE TABLE IF NOT EXISTS audit_log_y%sm%s 
         PARTITION OF audit_log
         FOR VALUES FROM (%L) TO (%L)',
        to_char(NEW.occurred_at, 'YYYY'),
        to_char(NEW.occurred_at, 'MM'),
        date_trunc('month', NEW.occurred_at),
        date_trunc('month', NEW.occurred_at + interval '1 month')
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop old partitions
CREATE OR REPLACE FUNCTION drop_old_audit_partitions()
RETURNS void AS $$
DECLARE
    partition_name text;
BEGIN
    FOR partition_name IN
        SELECT relname 
        FROM pg_class c 
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE relkind = 'r' 
        AND nspname = 'keyhippo'
        AND relname ~ '^audit_log_y\d{4}m\d{2}$'
        AND to_timestamp(
            substring(relname from 'y(\d{4})m(\d{2})'),
            'YYYYMM'
        ) < now() - interval '12 months'
    LOOP
        EXECUTE format('DROP TABLE %I', partition_name);
    END LOOP;
END;
$$ LANGUAGE plpgsql;
```

## RLS Policies

```sql
-- Users see their own events
CREATE POLICY user_events ON audit_log
    FOR SELECT
    USING (
        user_id = current_user_id()
    );

-- Admins see tenant events
CREATE POLICY admin_events ON audit_log
    FOR SELECT
    USING (
        has_permission('view_audit_log')
        AND tenant_id = current_tenant_id()
    );

-- System admins see all
CREATE POLICY system_events ON audit_log
    FOR SELECT
    USING (
        has_permission('view_all_audit_logs')
    );
```

## See Also

- [Retention Configuration](../config.md#audit-retention)
- [Event Type Reference](../events.md)
- [Audit Policies](../security/audit_policies.md)