# groups

Organizes users and roles into logical groups.

## Schema

```sql
CREATE TABLE keyhippo_rbac.groups (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text UNIQUE NOT NULL,
    description text
);
```

## Columns

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| name | text | Unique group name |
| description | text | Optional description |

## Indexes

- Primary Key on `id`
- Unique index on `name`

## Security

- RLS enabled
- Requires manage_groups permission
- Audit logged
- Referenced by roles

## Example Usage

### Create Group
```sql
INSERT INTO keyhippo_rbac.groups (name, description)
VALUES (
    'Engineering',
    'Engineering department'
);
```

### Group Hierarchy
```sql
DO $$
DECLARE
    parent_id uuid;
    team_id uuid;
BEGIN
    -- Create parent group
    INSERT INTO keyhippo_rbac.groups (name, description)
    VALUES ('Engineering', 'Engineering department')
    RETURNING id INTO parent_id;
    
    -- Create team group
    INSERT INTO keyhippo_rbac.groups (name, description)
    VALUES ('Backend Team', 'Backend development team')
    RETURNING id INTO team_id;
    
    -- Link groups (custom table)
    INSERT INTO group_hierarchy (parent_id, child_id)
    VALUES (parent_id, team_id);
END $$;
```

### Query Structure
```sql
WITH RECURSIVE group_tree AS (
    -- Base case
    SELECT id, name, description, 0 as level
    FROM keyhippo_rbac.groups
    WHERE id = 'root_group_id'
    
    UNION ALL
    
    -- Recursive case
    SELECT g.id, g.name, g.description, gt.level + 1
    FROM keyhippo_rbac.groups g
    JOIN group_hierarchy gh ON g.id = gh.child_id
    JOIN group_tree gt ON gh.parent_id = gt.id
)
SELECT * FROM group_tree;
```

## Implementation Notes

1. **Access Control**
```sql
-- RLS policy
CREATE POLICY groups_access_policy ON keyhippo_rbac.groups
    FOR ALL
    TO authenticated
    USING (keyhippo.authorize('manage_groups'))
    WITH CHECK (keyhippo.authorize('manage_groups'));
```

2. **Audit Logging**
```sql
-- Via trigger
keyhippo_audit_rbac_groups
```

3. **Role Integration**
```sql
-- Referenced by
keyhippo_rbac.roles.group_id
```

## Common Patterns

1. **Department Structure**
```sql
INSERT INTO keyhippo_rbac.groups (name, description)
VALUES
    ('Engineering', 'Engineering department'),
    ('Product', 'Product management'),
    ('Design', 'Design team'),
    ('Operations', 'Operations team');
```

2. **Team Organization**
```sql
INSERT INTO keyhippo_rbac.groups (name, description)
VALUES
    ('Backend', 'Backend development'),
    ('Frontend', 'Frontend development'),
    ('Infrastructure', 'Infrastructure team'),
    ('QA', 'Quality assurance');
```

3. **Project Groups**
```sql
INSERT INTO keyhippo_rbac.groups (name, description)
VALUES
    ('Project Alpha', 'Project Alpha team'),
    ('Project Beta', 'Project Beta team');
```

## Related Tables

- [roles](roles.md)
- [user_group_roles](user_group_roles.md)
- [group_hierarchy](group_hierarchy.md)

## See Also

- [create_group()](../functions/create_group.md)
- [create_role()](../functions/create_role.md)
- [RBAC Security](../security/rls_policies.md)