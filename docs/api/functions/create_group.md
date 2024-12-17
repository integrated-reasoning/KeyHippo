# create_group

Create a new user group.

## Synopsis

```sql
keyhippo.create_group(
    name text,
    description text DEFAULT NULL,
    metadata jsonb DEFAULT NULL
) RETURNS uuid
```

## Description

`create_group` creates a new user group and:
1. Validates group name format
2. Sets group description and metadata
3. Records creation in audit log
4. Returns group identifier

## Parameters

| Name | Type | Description |
|------|------|-------------|
| name | text | Group identifier |
| description | text | Optional details |
| metadata | jsonb | Optional data |

## Examples

Basic group:
```sql
SELECT create_group('engineering');
```

With description:
```sql
SELECT create_group(
    'data_team',
    'Data analytics and reporting team'
);
```

With metadata:
```sql
SELECT create_group(
    'temporary_access',
    'Limited time access group',
    '{
        "expires_at": "2024-12-31",
        "manager": "jane.doe@example.com"
    }'
);
```

## Implementation

Group creation SQL:
```sql
INSERT INTO keyhippo_rbac.groups (
    name,
    description,
    tenant_id,
    metadata,
    created_at,
    created_by
)
VALUES (
    $1,
    $2,
    current_tenant(),
    $3,
    now(),
    current_user_id()
)
RETURNING group_id;
```

## Error Cases

Invalid name:
```sql
SELECT create_group('Invalid Group!');
ERROR:  invalid group name
DETAIL:  Name must be lowercase, start with letter, use only a-z, 0-9, underscore
```

Duplicate name:
```sql
SELECT create_group('engineering');
ERROR:  duplicate key value violates unique constraint
DETAIL:  Group name "engineering" already exists for this tenant
```

Name too long:
```sql
SELECT create_group('very_long_group_name_that_exceeds_maximum_length');
ERROR:  value too long for type character varying(63)
```

## Permissions Required

Caller must have either:
- 'manage_groups' permission
- System administrator access

## Group Naming Rules

Format requirements:
```sql
-- Valid names
engineering
data_team_2024
temp_access_1

-- Invalid names
Engineering    -- uppercase
data-team     -- hyphens
2024_group    -- starts with number
_hidden       -- starts with underscore
```

## Default Groups

System creates these groups:
```sql
-- Base groups
SELECT create_group('users', 'All system users');
SELECT create_group('admins', 'System administrators');

-- Service groups
SELECT create_group('api_services', 'API service accounts');
SELECT create_group('system_services', 'System services');
```

## Group Hierarchy

Groups can reference parents:
```sql
-- Add engineering sub-groups
SELECT create_group('frontend', parent_id := eng_id);
SELECT create_group('backend', parent_id := eng_id);
SELECT create_group('devops', parent_id := eng_id);

-- Permissions inherit down hierarchy
CREATE POLICY group_hierarchy ON resources
    USING (
        EXISTS (
            SELECT 1 FROM group_hierarchy gh
            WHERE gh.child_id = current_group_id()
            AND gh.parent_id = resource_group_id
        )
    );
```

## Audit Trail

Creates audit entry:
```json
{
    "event_type": "group_created",
    "group_id": "550e8400-e29b-41d4-a716-446655440000",
    "group_name": "engineering",
    "created_by": "67e55044-10b1-426f-9247-bb680e5fe0c8",
    "tenant_id": "91c35b46-8c55-4264-8373-cf4b1ce957b9",
    "timestamp": "2024-01-01T00:00:00Z"
}
```

## See Also

- [groups table](../tables/groups.md)
- [user_group_roles table](../tables/user_group_roles.md)
- [assign_role_to_user()](assign_role_to_user.md)