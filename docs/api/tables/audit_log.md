# audit_log

Records all significant system events for security and debugging.

## Schema

```sql
CREATE TABLE keyhippo.audit_log (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    timestamp timestamptz NOT NULL DEFAULT now(),
    action text NOT NULL,
    table_name text,
    data jsonb,
    user_id uuid,
    function_name text
);
```

## Columns

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| timestamp | timestamptz | When the event occurred |
| action | text | Type of action performed |
| table_name | text | Related table (if any) |
| data | jsonb | Event-specific data |
| user_id | uuid | User who performed action |
| function_name | text | Function that triggered event |

## Indexes

- Primary Key on `id`
- Index on `timestamp`
- Index on `action`
- Index on `user_id`

## Security

- RLS enabled
- Read-only for admins
- Write-only through triggers
- No direct modification

## Example Usage

### Query Recent Events
```sql
SELECT 
    timestamp,
    action,
    data->>'description' as details,
    user_id
FROM keyhippo.audit_log
WHERE timestamp > NOW() - INTERVAL '1 day'
ORDER BY timestamp DESC;
```

### Filter by Action
```sql
SELECT 
    timestamp,
    data,
    user_id
FROM keyhippo.audit_log
WHERE action = 'create_api_key'
AND timestamp > NOW() - INTERVAL '7 days';
```

### User Activity
```sql
SELECT 
    date_trunc('hour', timestamp) as time,
    action,
    count(*) as events
FROM keyhippo.audit_log
WHERE user_id = 'user_uuid_here'
GROUP BY 1, 2
ORDER BY 1 DESC;
```

## Common Events

1. **API Key Events**
```json
{
    "action": "create_api_key",
    "data": {
        "key_id": "uuid",
        "description": "Key description",
        "scope": "scope_name"
    }
}
```

2. **Role Changes**
```json
{
    "action": "assign_role",
    "data": {
        "user_id": "uuid",
        "role_id": "uuid",
        "group_id": "uuid"
    }
}
```

3. **Permission Updates**
```json
{
    "action": "grant_permission",
    "data": {
        "role_id": "uuid",
        "permission": "permission_name"
    }
}
```

## Implementation Notes

1. **Automatic Logging**
```sql
-- Via trigger
CREATE OR REPLACE FUNCTION keyhippo.log_table_change()
RETURNS TRIGGER AS $$
-- Implementation
$$;
```

2. **Data Retention**
```sql
-- Example cleanup
DELETE FROM keyhippo.audit_log
WHERE timestamp < NOW() - INTERVAL '90 days';
```

3. **Performance**
   - Partitioned by month
   - Regular cleanup
   - Efficient indexes

## Views

### Activity Summary
```sql
CREATE VIEW audit_summary AS
SELECT 
    date_trunc('day', timestamp) as day,
    action,
    count(*) as events
FROM keyhippo.audit_log
GROUP BY 1, 2;
```

### User Actions
```sql
CREATE VIEW user_audit AS
SELECT 
    al.timestamp,
    al.action,
    al.data,
    u.email as user_email
FROM keyhippo.audit_log al
JOIN auth.users u ON al.user_id = u.id;
```

## Related Tables

- [api_key_metadata](api_key_metadata.md)
- [user_group_roles](user_group_roles.md)
- [role_permissions](role_permissions.md)

## See Also

- [Security Policies](../security/rls_policies.md)
- [Function Security](../security/function_security.md)