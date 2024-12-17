# user_group_roles

Maps users to roles through group membership.

## Table Definition

```sql
CREATE TABLE keyhippo_rbac.user_group_roles (
    user_id uuid NOT NULL,
    group_id uuid NOT NULL REFERENCES groups(group_id),
    role_id uuid NOT NULL REFERENCES roles(role_id),
    granted_at timestamptz NOT NULL DEFAULT now(),
    granted_by uuid NOT NULL,
    expires_at timestamptz,
    metadata jsonb,
    CONSTRAINT pk_user_group_roles 
        PRIMARY KEY (user_id, group_id, role_id),
    CONSTRAINT valid_expiry 
        CHECK (expires_at > granted_at),
    CONSTRAINT active_grant 
        CHECK (expires_at IS NULL OR expires_at > now())
);
```

## Indexes

```sql
-- User role lookup
CREATE INDEX idx_user_roles 
ON user_group_roles(user_id, role_id)
INCLUDE (expires_at);

-- Group member lookup
CREATE INDEX idx_group_users 
ON user_group_roles(group_id, user_id)
INCLUDE (role_id);

-- Expiring roles
CREATE INDEX idx_role_expiry 
ON user_group_roles(expires_at) 
WHERE expires_at IS NOT NULL;

-- Role assignment lookup
CREATE INDEX idx_role_assignments 
ON user_group_roles(role_id, group_id);
```

## Example Queries

User's roles:
```sql
SELECT 
    r.name as role_name,
    g.name as group_name,
    ugr.expires_at,
    ugr.granted_at,
    (SELECT email FROM users WHERE id = ugr.granted_by) as granted_by
FROM user_group_roles ugr
JOIN roles r ON r.role_id = ugr.role_id
JOIN groups g ON g.group_id = ugr.group_id
WHERE ugr.user_id = '550e8400-e29b-41d4-a716-446655440000'
ORDER BY ugr.granted_at DESC;
```

Group members with role:
```sql
SELECT 
    u.email,
    ugr.granted_at,
    ugr.expires_at
FROM user_group_roles ugr
JOIN users u ON u.id = ugr.user_id
WHERE ugr.group_id = (
    SELECT group_id FROM groups WHERE name = 'engineering'
)
AND ugr.role_id = (
    SELECT role_id FROM roles WHERE name = 'developer'
)
ORDER BY ugr.granted_at DESC;
```

Expiring roles:
```sql
SELECT 
    u.email,
    r.name as role_name,
    g.name as group_name,
    ugr.expires_at
FROM user_group_roles ugr
JOIN users u ON u.id = ugr.user_id
JOIN roles r ON r.role_id = ugr.role_id
JOIN groups g ON g.group_id = ugr.group_id
WHERE ugr.expires_at < now() + interval '7 days'
AND ugr.expires_at > now()
ORDER BY ugr.expires_at;
```

Role inheritance:
```sql
WITH RECURSIVE role_tree AS (
    -- Direct roles
    SELECT 
        ugr.role_id,
        r.name as role_name,
        0 as depth
    FROM user_group_roles ugr
    JOIN roles r ON r.role_id = ugr.role_id
    WHERE ugr.user_id = '550e8400-e29b-41d4-a716-446655440000'
    AND (ugr.expires_at IS NULL OR ugr.expires_at > now())
    
    UNION
    
    -- Inherited roles
    SELECT 
        rp.role_id,
        r.name,
        rt.depth + 1
    FROM role_tree rt
    JOIN role_permissions rp ON rp.permission_id IN (
        SELECT permission_id 
        FROM role_permissions 
        WHERE role_id = rt.role_id
    )
    JOIN roles r ON r.role_id = rp.role_id
    WHERE rt.depth < 5
)
SELECT DISTINCT
    role_name,
    depth as inheritance_depth
FROM role_tree
ORDER BY depth, role_name;
```

## Triggers

```sql
-- Validate role assignments
CREATE TRIGGER validate_role_assignment
    BEFORE INSERT OR UPDATE ON user_group_roles
    FOR EACH ROW
    EXECUTE FUNCTION validate_role_assignment();

-- Record in audit log
CREATE TRIGGER audit_role_assignment
    AFTER INSERT OR UPDATE OR DELETE ON user_group_roles
    FOR EACH ROW
    EXECUTE FUNCTION audit_role_change();

-- Clear permission cache
CREATE TRIGGER invalidate_permission_cache
    AFTER INSERT OR UPDATE OR DELETE ON user_group_roles
    FOR EACH ROW
    EXECUTE FUNCTION invalidate_user_permissions();
```

## Functions

Validate assignment:
```sql
CREATE FUNCTION validate_role_assignment()
RETURNS trigger AS $$
BEGIN
    -- Check for role conflicts
    IF EXISTS (
        SELECT 1
        FROM role_conflicts rc
        WHERE rc.role_id = NEW.role_id
        AND EXISTS (
            SELECT 1 FROM user_group_roles ugr
            WHERE ugr.user_id = NEW.user_id
            AND ugr.role_id = rc.conflicts_with
        )
    ) THEN
        RAISE EXCEPTION 'role assignment conflict';
    END IF;
    
    -- Check group membership
    IF NOT EXISTS (
        SELECT 1 FROM group_members
        WHERE user_id = NEW.user_id
        AND group_id = NEW.group_id
    ) THEN
        RAISE EXCEPTION 'user not in group';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

## RLS Policies

```sql
-- Users see their roles
CREATE POLICY user_roles ON user_group_roles
    FOR SELECT
    USING (
        user_id = current_user_id()
    );

-- Group admins manage members
CREATE POLICY group_admin ON user_group_roles
    FOR ALL
    USING (
        group_id IN (
            SELECT group_id FROM group_admins
            WHERE user_id = current_user_id()
        )
    );

-- Role admins manage assignments
CREATE POLICY role_admin ON user_group_roles
    FOR ALL
    USING (
        has_permission('manage_roles')
    );
```

## See Also

- [groups](groups.md)
- [roles](roles.md)
- [assign_role_to_user()](../functions/assign_role_to_user.md)