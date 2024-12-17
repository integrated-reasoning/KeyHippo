# create_group

Creates a new RBAC group for organizing users and roles.

## Syntax

```sql
keyhippo_rbac.create_group(
    p_name text,
    p_description text
)
RETURNS uuid
```

## Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| p_name | text | Name of the group |
| p_description | text | Description of the group's purpose |

## Returns

Returns the UUID of the newly created group.

## Security

- SECURITY INVOKER function
- Requires manage_groups permission
- Audit logged
- Transaction safe

## Example Usage

### Basic Creation
```sql
SELECT keyhippo_rbac.create_group(
    'Engineering',
    'Engineering team group'
);
```

### With Role Setup
```sql
DO $$
DECLARE
    group_id uuid;
BEGIN
    -- Create group
    SELECT keyhippo_rbac.create_group(
        'Product Team',
        'Product management and design team'
    ) INTO group_id;
    
    -- Create roles in group
    PERFORM keyhippo_rbac.create_role(
        'Product Manager',
        'Team lead role',
        group_id,
        'admin'
    );
    
    PERFORM keyhippo_rbac.create_role(
        'Designer',
        'Design team member',
        group_id,
        'user'
    );
END $$;
```

### Hierarchical Groups
```sql
DO $$
DECLARE
    parent_id uuid;
    child_id uuid;
BEGIN
    -- Create parent group
    SELECT keyhippo_rbac.create_group(
        'Organization',
        'Top level organization group'
    ) INTO parent_id;
    
    -- Create department group
    SELECT keyhippo_rbac.create_group(
        'Engineering Department',
        'Engineering department group'
    ) INTO child_id;
    
    -- Link groups (using custom table)
    INSERT INTO group_hierarchy(parent_id, child_id)
    VALUES (parent_id, child_id);
END $$;
```

## Implementation Notes

1. **Group Creation**
```sql
INSERT INTO keyhippo_rbac.groups (name, description)
VALUES (p_name, p_description)
RETURNING id
```

2. **Unique Constraints**
```sql
-- Name must be unique
ALTER TABLE keyhippo_rbac.groups
ADD CONSTRAINT groups_name_key UNIQUE (name);
```

3. **Audit Logging**
```sql
-- Automatically logged via trigger
keyhippo_audit_rbac_groups
```

## Error Handling

1. **Duplicate Name**
```sql
-- Raises exception
SELECT keyhippo_rbac.create_group('Existing Name', 'Description');
```

2. **Invalid Name**
```sql
-- Raises exception
SELECT keyhippo_rbac.create_group('', 'Empty name not allowed');
```

3. **Permission Check**
```sql
-- Raises exception if missing manage_groups permission
SELECT keyhippo_rbac.create_group('New Group', 'Description');
```

## Performance

- Single insert operation
- Minimal constraints
- Efficient audit logging
- No cascading effects

## Related Functions

- [create_role()](create_role.md)
- [assign_role_to_user()](assign_role_to_user.md)
- [assign_permission_to_role()](assign_permission_to_role.md)

## See Also

- [Groups Table](../tables/groups.md)
- [Roles Table](../tables/roles.md)
- [RBAC Security](../security/rls_policies.md)