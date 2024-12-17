# permissions

Defines available permissions for role-based access control.

## Table Definition

```sql
CREATE TABLE keyhippo_rbac.permissions (
    permission_id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name text NOT NULL,
    description text,
    resource_type text NOT NULL,
    actions text[] NOT NULL,
    conditions_schema jsonb,
    metadata jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT valid_permission_name CHECK (name ~ '^[a-z][a-z0-9_]{2,62}[a-z0-9]$'),
    CONSTRAINT valid_resource_type CHECK (resource_type ~ '^[a-z][a-z0-9_]{2,62}[a-z0-9]$'),
    CONSTRAINT valid_actions CHECK (array_length(actions, 1) > 0),
    CONSTRAINT unique_permission_name UNIQUE (name)
);
```

## Indexes

```sql
-- Permission lookup
CREATE UNIQUE INDEX idx_permission_name 
ON permissions(name);

-- Resource type lookup
CREATE INDEX idx_permission_resource 
ON permissions(resource_type);

-- Array overlap for action checks
CREATE INDEX idx_permission_actions 
ON permissions USING gin(actions);
```

## Columns

| Name | Type | Description |
|------|------|-------------|
| permission_id | uuid | Primary key |
| name | text | Permission identifier |
| description | text | Permission details |
| resource_type | text | Target resource |
| actions | text[] | Allowed operations |
| conditions_schema | jsonb | Valid condition format |
| metadata | jsonb | Additional data |
| created_at | timestamptz | Creation time |
| updated_at | timestamptz | Last modified |

## Default Permissions

System creates these on initialization:
```sql
INSERT INTO permissions (name, resource_type, actions) VALUES
('manage_keys', 'api_key', 
    ARRAY['create', 'read', 'update', 'delete']),
('read_keys', 'api_key', 
    ARRAY['read']),
('manage_roles', 'role', 
    ARRAY['create', 'read', 'update', 'delete']),
('assign_roles', 'role', 
    ARRAY['assign', 'revoke']),
('manage_groups', 'group', 
    ARRAY['create', 'read', 'update', 'delete']),
('audit_read', 'audit_log', 
    ARRAY['read']);
```

## Example Queries

List all permissions:
```sql
SELECT 
    name,
    resource_type,
    array_to_string(actions, ', ') as actions
FROM permissions
ORDER BY resource_type, name;
```

Find permissions by action:
```sql
SELECT name, description
FROM permissions
WHERE 'delete' = ANY(actions)
ORDER BY name;
```

Check permission existence:
```sql
SELECT EXISTS (
    SELECT 1 FROM permissions
    WHERE name = 'manage_keys'
    AND 'create' = ANY(actions)
) as can_create;
```

## Conditions Schema

Example schema for time-based conditions:
```json
{
    "type": "object",
    "properties": {
        "time_window": {
            "type": "object",
            "properties": {
                "start": {
                    "type": "string",
                    "format": "time"
                },
                "end": {
                    "type": "string",
                    "format": "time"
                }
            },
            "required": ["start", "end"]
        }
    }
}
```

## Triggers

```sql
-- Maintain updated_at
CREATE TRIGGER update_permission_timestamp
    BEFORE UPDATE ON permissions
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();

-- Validate conditions schema
CREATE TRIGGER validate_conditions_schema
    BEFORE INSERT OR UPDATE ON permissions
    FOR EACH ROW
    EXECUTE FUNCTION validate_json_schema();
```

## RLS Policies

```sql
-- Read access to all
CREATE POLICY read_permissions ON permissions
    FOR SELECT
    USING (true);

-- Modify only with permission
CREATE POLICY manage_permissions ON permissions
    FOR ALL
    USING (
        has_permission('manage_permissions')
    );
```

## See Also

- [role_permissions](role_permissions.md)
- [assign_permission_to_role()](../functions/assign_permission_to_role.md)
- [authorize()](../functions/authorize.md)