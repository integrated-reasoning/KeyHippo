# groups

Manages user group definitions and hierarchies.

## Table Definition

```sql
CREATE TABLE keyhippo_rbac.groups (
    group_id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name text NOT NULL,
    parent_id uuid REFERENCES groups(group_id),
    tenant_id uuid,
    description text,
    metadata jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT valid_group_name CHECK (name ~ '^[a-z][a-z0-9_]{2,62}[a-z0-9]$'),
    CONSTRAINT unique_group_name UNIQUE NULLS NOT DISTINCT (name, tenant_id),
    CONSTRAINT no_self_parent CHECK (group_id != parent_id)
);

-- Track group hierarchy path
CREATE TABLE keyhippo_rbac.group_hierarchy (
    ancestor_id uuid NOT NULL REFERENCES groups(group_id),
    descendant_id uuid NOT NULL REFERENCES groups(group_id),
    depth int NOT NULL,
    PRIMARY KEY (ancestor_id, descendant_id),
    CONSTRAINT valid_depth CHECK (depth >= 0),
    CONSTRAINT no_self_cycle CHECK (ancestor_id != descendant_id)
);
```

## Indexes

```sql
-- Group lookup
CREATE UNIQUE INDEX idx_group_name 
ON groups(name) 
WHERE tenant_id IS NULL;

-- Tenant group lookup
CREATE UNIQUE INDEX idx_tenant_group_name 
ON groups(tenant_id, name) 
WHERE tenant_id IS NOT NULL;

-- Hierarchy traversal
CREATE INDEX idx_group_parent 
ON groups(parent_id);

CREATE INDEX idx_hierarchy_ancestor 
ON group_hierarchy(ancestor_id);

CREATE INDEX idx_hierarchy_descendant 
ON group_hierarchy(descendant_id);
```

## Default Groups

System creates these on initialization:
```sql
INSERT INTO groups (name, description) VALUES
-- Base groups
('users', 'All system users'),
('admins', 'System administrators'),

-- Service groups
('api_services', 'API service accounts'),
('system_services', 'System services'),

-- Security groups
('security_admins', 'Security team'),
('audit_readers', 'Audit log access');
```

## Example Queries

List group hierarchy:
```sql
WITH RECURSIVE group_tree AS (
    -- Base groups
    SELECT 
        group_id,
        name,
        parent_id,
        0 as depth,
        ARRAY[name] as path
    FROM groups
    WHERE parent_id IS NULL
    
    UNION ALL
    
    -- Child groups
    SELECT 
        g.group_id,
        g.name,
        g.parent_id,
        gt.depth + 1,
        gt.path || g.name
    FROM groups g
    JOIN group_tree gt ON gt.group_id = g.parent_id
    WHERE g.tenant_id = current_tenant_id()
)
SELECT 
    lpad(' ', depth * 2) || name as group_tree,
    path
FROM group_tree
ORDER BY path;
```

Find group members:
```sql
SELECT 
    u.email,
    array_agg(r.name) as roles
FROM users u
JOIN user_group_roles ugr ON ugr.user_id = u.id
JOIN roles r ON r.role_id = ugr.role_id
WHERE ugr.group_id = (
    SELECT group_id FROM groups WHERE name = 'engineering'
)
GROUP BY u.id, u.email
ORDER BY u.email;
```

Group permissions:
```sql
SELECT DISTINCT
    g.name as group_name,
    p.name as permission_name
FROM groups g
JOIN user_group_roles ugr ON ugr.group_id = g.group_id
JOIN role_permissions rp ON rp.role_id = ugr.role_id
JOIN permissions p ON p.permission_id = rp.permission_id
WHERE g.tenant_id = current_tenant_id()
ORDER BY g.name, p.name;
```

## Hierarchy Management

Add child group:
```sql
-- Create child
INSERT INTO groups (name, parent_id)
VALUES ('frontend', 
    (SELECT group_id FROM groups WHERE name = 'engineering')
);

-- Update hierarchy
INSERT INTO group_hierarchy (ancestor_id, descendant_id, depth)
SELECT 
    h.ancestor_id,
    g.group_id,
    h.depth + 1
FROM groups g
CROSS JOIN group_hierarchy h
WHERE g.name = 'frontend'
AND h.descendant_id = g.parent_id
UNION ALL
SELECT 
    group_id,
    group_id,
    0
FROM groups
WHERE name = 'frontend';
```

Move group:
```sql
-- Update parent
UPDATE groups 
SET parent_id = new_parent_id 
WHERE group_id = moving_group_id;

-- Rebuild hierarchy
DELETE FROM group_hierarchy;
INSERT INTO group_hierarchy
    (ancestor_id, descendant_id, depth)
WITH RECURSIVE hierarchy AS (
    -- Direct relationships
    SELECT 
        group_id, 
        group_id as descendant_id,
        0 as depth
    FROM groups
    
    UNION ALL
    
    -- Inherited relationships
    SELECT 
        h.group_id,
        g.group_id,
        h.depth + 1
    FROM groups g
    JOIN hierarchy h ON h.descendant_id = g.parent_id
)
SELECT * FROM hierarchy;
```

## Triggers

```sql
-- Maintain updated_at
CREATE TRIGGER update_group_timestamp
    BEFORE UPDATE ON groups
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();

-- Audit group changes
CREATE TRIGGER audit_group_changes
    AFTER INSERT OR UPDATE OR DELETE ON groups
    FOR EACH ROW
    EXECUTE FUNCTION audit_group_change();

-- Maintain hierarchy
CREATE TRIGGER maintain_group_hierarchy
    AFTER INSERT OR UPDATE OR DELETE ON groups
    FOR EACH ROW
    EXECUTE FUNCTION update_group_hierarchy();
```

## RLS Policies

```sql
-- View groups
CREATE POLICY view_groups ON groups
    FOR SELECT
    USING (
        tenant_id IS NULL 
        OR tenant_id = current_tenant_id()
    );

-- Manage groups
CREATE POLICY manage_groups ON groups
    FOR ALL
    USING (
        has_permission('manage_groups')
        AND (
            tenant_id IS NULL 
            OR tenant_id = current_tenant_id()
        )
    );
```

## See Also

- [user_group_roles](user_group_roles.md)
- [create_group()](../functions/create_group.md)
- [assign_role_to_user()](../functions/assign_role_to_user.md)