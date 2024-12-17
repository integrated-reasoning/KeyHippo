# Row Level Security Policies

RLS implementation for KeyHippo tables.

## Policy Types

### User Context Policies

Basic user access:
```sql
-- Owner access
CREATE POLICY user_resources ON resources
    FOR ALL
    USING (
        owner_id = (current_user_context()->>'user_id')::uuid
    );

-- Group member access
CREATE POLICY group_resources ON resources
    FOR ALL
    USING (
        group_id IN (
            SELECT group_id 
            FROM user_group_roles 
            WHERE user_id = (current_user_context()->>'user_id')::uuid
        )
    );
```

### Tenant Isolation

Multi-tenant separation:
```sql
-- Tenant resources
CREATE POLICY tenant_isolation ON resources
    FOR ALL
    USING (
        tenant_id = (current_user_context()->>'tenant_id')::uuid
    );

-- Cross-tenant access
CREATE POLICY tenant_sharing ON resources
    FOR SELECT
    USING (
        tenant_id = (current_user_context()->>'tenant_id')::uuid
        OR shared_with @> ARRAY[
            (current_user_context()->>'tenant_id')::uuid
        ]
    );
```

### Role-Based Access

Permission checks:
```sql
-- Role-specific access
CREATE POLICY role_access ON resources
    FOR ALL
    USING (
        EXISTS (
            SELECT 1 
            FROM user_group_roles ugr
            JOIN role_permissions rp ON rp.role_id = ugr.role_id
            WHERE ugr.user_id = (current_user_context()->>'user_id')::uuid
            AND rp.permission = 'manage_resources'
        )
    );

-- Hierarchical access
CREATE POLICY role_hierarchy ON resources
    FOR ALL
    USING (
        EXISTS (
            WITH RECURSIVE role_tree AS (
                -- Direct roles
                SELECT role_id, permission_id
                FROM user_group_roles ugr
                WHERE user_id = (current_user_context()->>'user_id')::uuid
                
                UNION
                
                -- Inherited roles
                SELECT ri.child_role_id, rp.permission_id
                FROM role_tree rt
                JOIN role_inheritance ri ON ri.parent_role_id = rt.role_id
                JOIN role_permissions rp ON rp.role_id = ri.child_role_id
            )
            SELECT 1 
            FROM role_tree rt
            JOIN role_permissions rp ON rp.role_id = rt.role_id
            WHERE rp.permission = 'manage_resources'
        )
    );
```

## Implementation Examples

### API Key Management

```sql
-- Key metadata access
CREATE POLICY key_access ON api_key_metadata
    FOR ALL
    USING (
        -- Own keys
        user_id = (current_user_context()->>'user_id')::uuid
        
        OR
        
        -- Admin access
        (
            SELECT has_permission('manage_keys')
            AND tenant_id = (current_user_context()->>'tenant_id')::uuid
        )
    );

-- Key secret access
CREATE POLICY key_secret_access ON api_key_secrets
    FOR SELECT
    USING (
        key_id IN (
            SELECT key_id 
            FROM api_key_metadata
            WHERE user_id = (current_user_context()->>'user_id')::uuid
        )
    );
```

### Group Management

```sql
-- Group access
CREATE POLICY group_access ON groups
    FOR SELECT
    USING (
        tenant_id = (current_user_context()->>'tenant_id')::uuid
        OR tenant_id IS NULL
    )
    WITH CHECK (
        has_permission('manage_groups')
        AND tenant_id = (current_user_context()->>'tenant_id')::uuid
    );

-- Group role management
CREATE POLICY group_roles ON user_group_roles
    FOR ALL
    USING (
        (
            -- Own roles
            user_id = (current_user_context()->>'user_id')::uuid
        )
        OR
        (
            -- Group admin
            group_id IN (
                SELECT group_id 
                FROM group_admins 
                WHERE user_id = (current_user_context()->>'user_id')::uuid
            )
        )
    );
```

### Audit Log Access

```sql
-- Audit log visibility
CREATE POLICY audit_access ON audit_log
    FOR SELECT
    USING (
        -- Own events
        user_id = (current_user_context()->>'user_id')::uuid
        
        OR
        
        -- Tenant auditor
        (
            has_permission('view_audit_log')
            AND tenant_id = (current_user_context()->>'tenant_id')::uuid
        )
        
        OR
        
        -- System auditor
        has_permission('view_all_audit_logs')
    );
```

## Performance Optimization

Index support:
```sql
-- User lookup
CREATE INDEX idx_resource_owner 
ON resources(owner_id)
INCLUDE (tenant_id);

-- Tenant lookup
CREATE INDEX idx_resource_tenant 
ON resources(tenant_id)
INCLUDE (owner_id);

-- Group membership
CREATE INDEX idx_user_groups 
ON user_group_roles(user_id)
INCLUDE (group_id);
```

Permission caching:
```sql
-- Cache table
CREATE UNLOGGED TABLE permission_cache (
    user_id uuid,
    permission text,
    has_access boolean,
    cached_at timestamptz,
    PRIMARY KEY (user_id, permission)
);

-- Cache usage
CREATE POLICY permission_check ON resources
    FOR ALL
    USING (
        EXISTS (
            SELECT 1 
            FROM permission_cache
            WHERE user_id = (current_user_context()->>'user_id')::uuid
            AND permission = 'manage_resources'
            AND has_access = true
            AND cached_at > now() - interval '5 minutes'
        )
    );
```

## Common Patterns

Hierarchical access:
```sql
-- Resource hierarchy
CREATE POLICY hierarchy_access ON resources
    USING (
        WITH RECURSIVE resource_tree AS (
            -- Base resources
            SELECT id, parent_id
            FROM resources
            WHERE owner_id = (current_user_context()->>'user_id')::uuid
            
            UNION
            
            -- Child resources
            SELECT r.id, r.parent_id
            FROM resources r
            JOIN resource_tree rt ON rt.id = r.parent_id
        )
        SELECT EXISTS (
            SELECT 1 FROM resource_tree 
            WHERE id = resources.id
        )
    );
```

Time-based access:
```sql
-- Time window
CREATE POLICY time_access ON resources
    FOR ALL
    USING (
        EXISTS (
            SELECT 1
            FROM user_group_roles ugr
            JOIN role_permissions rp ON rp.role_id = ugr.role_id
            WHERE ugr.user_id = (current_user_context()->>'user_id')::uuid
            AND rp.permission = 'access_resources'
            AND (
                rp.conditions->>'time_start')::time <= current_time
                AND (rp.conditions->>'time_end')::time >= current_time
            )
    );
```

## See Also

- [Function Security](function_security.md)
- [Database Grants](grants.md)
- [current_user_context()](../functions/current_user_context.md)