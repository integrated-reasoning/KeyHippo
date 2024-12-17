# config

Internal configuration settings for KeyHippo.

## Schema

```sql
CREATE TABLE keyhippo_internal.config (
    key text PRIMARY KEY,
    value text NOT NULL,
    description text
);
```

## Columns

| Column | Type | Description |
|--------|------|-------------|
| key | text | Setting name |
| value | text | Setting value |
| description | text | Setting description |

## Security

- RLS enabled
- Accessible only to postgres role
- No direct user access
- System managed

## Core Settings

| Key | Description | Default |
|-----|-------------|---------|
| enable_key_expiry_notifications | Enable notifications | true |
| key_expiry_notification_hours | Hours before expiry | 72 |
| enable_http_logging | Enable HTTP logging | false |
| audit_log_endpoint | Audit log endpoint | https://app.keyhippo.com/api/ingest |
| installation_uuid | Installation identifier | [generated] |
| send_installation_notification | Send install ping | true |

## Example Usage

### Read Configuration
```sql
SELECT value::boolean
FROM keyhippo_internal.config
WHERE key = 'enable_http_logging';
```

### Update Setting
```sql
UPDATE keyhippo_internal.config
SET value = '48'
WHERE key = 'key_expiry_notification_hours';
```

### Batch Configuration
```sql
INSERT INTO keyhippo_internal.config (key, value, description)
VALUES
    ('custom_setting', 'value', 'Description'),
    ('another_setting', 'value', 'Description')
ON CONFLICT (key) DO UPDATE
SET value = EXCLUDED.value,
    description = EXCLUDED.description;
```

## Implementation Notes

1. **Access Control**
```sql
-- RLS policy
CREATE POLICY config_access_policy ON keyhippo_internal.config
    USING (CURRENT_USER = 'postgres');
```

2. **Type Handling**
```sql
-- Boolean settings
SELECT value::boolean FROM keyhippo_internal.config
WHERE key = 'enable_feature';

-- Numeric settings
SELECT value::int FROM keyhippo_internal.config
WHERE key = 'timeout_seconds';

-- JSON settings
SELECT value::jsonb FROM keyhippo_internal.config
WHERE key = 'complex_setting';
```

3. **Default Values**
```sql
-- Set during initialization
SELECT keyhippo.initialize_keyhippo();
```

## Configuration Categories

1. **Notifications**
```sql
-- Key expiry
enable_key_expiry_notifications
key_expiry_notification_hours

-- HTTP logging
enable_http_logging
audit_log_endpoint
```

2. **System Settings**
```sql
-- Installation
installation_uuid
send_installation_notification
```

## Usage Patterns

1. **Feature Flags**
```sql
-- Check if feature is enabled
SELECT EXISTS (
    SELECT 1
    FROM keyhippo_internal.config
    WHERE key = 'enable_feature'
    AND value = 'true'
);
```

2. **System Values**
```sql
-- Get installation ID
SELECT value::uuid
FROM keyhippo_internal.config
WHERE key = 'installation_uuid';
```

3. **Timeouts**
```sql
-- Get notification hours
SELECT value::int
FROM keyhippo_internal.config
WHERE key = 'key_expiry_notification_hours';
```

## Related Functions

- [initialize_keyhippo()](../functions/initialize_keyhippo.md)
- [enable_audit_log_notify()](../functions/enable_audit_log_notify.md)
- [disable_audit_log_notify()](../functions/disable_audit_log_notify.md)

## Security Considerations

1. **Access Control**
   - Only postgres role can access
   - No direct user modification
   - Audit logged changes

2. **Value Validation**
   - Type checking on read
   - Constrained values
   - Default fallbacks

3. **Security Settings**
   - HTTP logging control
   - Notification management
   - System identification