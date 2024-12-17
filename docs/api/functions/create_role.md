# create_role

Create a new role in the RBAC system.

## Synopsis

```sql
keyhippo.create_role(
    name text,
    description text DEFAULT NULL,
    inherit_from uuid[] DEFAULT NULL,
    metadata jsonb DEFAULT NULL
) RETURNS uuid
```

## Description

`create_role` adds a new role and optionally sets up role inheritance. The function:
1. Validates role name format
2. Creates role record
3. Establishes inheritance relationships
4. Records creation in audit log

## Parameters

| Name | Type | Description |
|------|------|-------------|
| name | text | Role identifier (a-z, 0-9, underscore) |
| description | text | Optional role description |
| inherit_from | uuid[] | Optional array of parent role IDs |
| metadata | jsonb | Optional role metadata |

## Return Value

Returns the UUID of the created role.

## Examples

Basic role:
```sql
SELECT create_role('api_reader', 'Read-only API access');
```

Role with inheritance:
```sql
SELECT create_role(
    'senior_analyst',
    'Senior data analyst permissions',
    ARRAY[
        (SELECT role_id FROM roles WHERE name = 'analyst'),
        (SELECT role_id FROM roles WHERE name = 'reporter')
    ]::uuid[]
);
```

Role with metadata:
```sql
SELECT create_role(
    'temporary_admin',
    'Limited-time administrative access',
    NULL,
    '{"expires_at": "2024-12-31", "reason": "Q4 deployment"}'
);
```

## Implementation

Role creation SQL:
```sql
INSERT INTO keyhippo_rbac.roles (
    name,
    description,
    tenant_id,
    metadata
) VALUES (
    $1,
    $2,
    current_tenant(),
    $4
) RETURNING role_id;
```

Inheritance setup:
```sql
INSERT INTO keyhippo_rbac.role_inheritance (
    parent_role_id,
    child_role_id
) 
SELECT parent_id, role_id
FROM unnest($3) as parent_id;
```

## Error Cases

Invalid name format:
```sql
SELECT create_role('Invalid Role');
ERROR:  invalid role name
DETAIL:  Role name must be lowercase, start with letter, 
         contain only a-z, 0-9, underscore
```

Duplicate name:
```sql
SELECT create_role('api_reader');
ERROR:  duplicate key value violates unique constraint
DETAIL:  Role name "api_reader" already exists for this tenant
```

Invalid parent role:
```sql
SELECT create_role(
    'analyst',
    'Data analyst',
    ARRAY['invalid-uuid']::uuid[]
);
ERROR:  invalid parent role
DETAIL:  Role with ID invalid-uuid not found
```

Circular inheritance:
```sql
SELECT create_role('circular', 'Bad inheritance', 
    ARRAY[(SELECT role_id FROM roles WHERE name = 'child')]::uuid[]);
ERROR:  circular role inheritance detected
DETAIL:  Role inheritance would create a cycle
```

## Permissions Required

Caller must have either:
- 'manage_roles' permission
- System administrator access

## Audit Trail

Creates audit entry:
```json
{
    "event_type": "role_created",
    "role_id": "550e8400-e29b-41d4-a716-446655440000",
    "role_name": "api_reader",
    "created_by": "67e55044-10b1-426f-9247-bb680e5fe0c8",
    "inherited_from": ["91c35b46-8c55-4264-8373-cf4b1ce957b9"],
    "timestamp": "2024-01-01T00:00:00Z"
}
```

## See Also

- [assign_role_to_user()](assign_role_to_user.md)
- [assign_permission_to_role()](assign_permission_to_role.md)
- [roles table](../tables/roles.md)