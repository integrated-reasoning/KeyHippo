# Performance Benchmarks

Detailed performance metrics for KeyHippo operations. All benchmarks were performed on a single core of an AMD Ryzen Threadripper 3960X.

## Core Operations

| Operation | Avg Time (ms) | P99 Time (ms) | P99 Ops/Sec |
|-----------|---------------|---------------|-------------|
| RBAC authorization | 0.0254 | 0.0360 | 27,778 |
| Assign role to user | 0.0107 | 0.0160 | 62,500 |
| Create scope | 0.0881 | 0.1450 | 6,897 |
| Create group | 0.0892 | 0.1440 | 6,944 |
| Create role | 0.1082 | 0.1720 | 5,814 |
| API key verification | 0.0527 | 0.0650 | 15,385 |
| API key creation | 0.4546 | 0.7990 | 1,252 |

## Understanding the Numbers

### Latency Distribution

- **Avg Time**: Average latency for the operation
- **P99 Time**: 99th percentile latency (worst case for 99% of operations)
- **P99 Ops/Sec**: Operations per second at P99 latency

### Key Metrics

- RBAC authorization completes in < 0.036ms (P99)
- API key verification takes < 0.065ms (P99)
- New keys are created in < 0.8ms (P99)

## Real-World Impact

These numbers translate to:

- Handle 27.7K RBAC checks/second/core
- Process 15.3K API keys/second/core
- Create 1.2K new keys/second/core

## Performance Tips

### API Key Verification
```sql
-- Cache verified keys for 1 minute
UPDATE keyhippo.api_key_metadata
SET last_used_at = NOW()
WHERE id = key_id
    AND (
        last_used_at IS NULL 
        OR last_used_at < NOW() - INTERVAL '1 minute'
    );
```

### RBAC Checks
```sql
-- Use materialized permissions for frequent checks
CREATE MATERIALIZED VIEW user_permissions AS
SELECT 
    user_id,
    array_agg(DISTINCT p.name) as permissions
FROM keyhippo_rbac.user_group_roles ugr
JOIN keyhippo_rbac.role_permissions rp ON ugr.role_id = rp.role_id
JOIN keyhippo_rbac.permissions p ON rp.permission_id = p.id
GROUP BY user_id;

-- Refresh async
REFRESH MATERIALIZED VIEW CONCURRENTLY user_permissions;
```

### Batch Operations
```sql
-- Batch role assignments
INSERT INTO keyhippo_rbac.user_group_roles (user_id, group_id, role_id)
SELECT 
    u.id,
    g.id,
    r.id
FROM unnest($1::uuid[]) AS user_ids(id)
CROSS JOIN (SELECT id FROM keyhippo_rbac.groups WHERE name = 'default') g
CROSS JOIN (SELECT id FROM keyhippo_rbac.roles WHERE name = 'user') r;
```

## Scaling Considerations

1. **Connection Pooling**
   - Use PgBouncer in transaction mode
   - Configure appropriate pool sizes

2. **Index Strategy**
   ```sql
   -- Optimize key lookups
   CREATE INDEX idx_api_keys_prefix ON keyhippo.api_key_metadata (prefix);
   
   -- Optimize permission checks
   CREATE INDEX idx_role_permissions_role ON keyhippo_rbac.role_permissions (role_id);
   ```

3. **Query Optimization**
   ```sql
   -- Use EXISTS for performance
   CREATE POLICY "resource_access" ON resources
       FOR ALL
       USING (
           EXISTS (
               SELECT 1 
               FROM keyhippo.current_user_context()
               WHERE user_id = resources.owner_id
           )
       );
   ```

## Benchmark Environment

- CPU: AMD Ryzen Threadripper 3960X
- Single core benchmarks
- PostgreSQL 14
- Default configuration
- No query caching
- Local connections (no network latency)

## Monitoring Performance

1. Track key metrics:
```sql
CREATE VIEW keyhippo_metrics AS
SELECT
    date_trunc('hour', created_at) as time_bucket,
    count(*) as keys_created,
    count(DISTINCT user_id) as unique_users
FROM keyhippo.api_key_metadata
GROUP BY 1
ORDER BY 1 DESC;
```

2. Monitor slow operations:
```sql
-- Add to postgresql.conf
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.track = all

-- Query slow operations
SELECT query, mean_time, calls
FROM pg_stat_statements
WHERE query LIKE '%keyhippo%'
ORDER BY mean_time DESC
LIMIT 10;
```

## Related Documentation

- [Multi-Tenant Guide](guides/multi_tenant.md)
- [API Key Patterns](guides/api_key_patterns.md)
- [Security Best Practices](api/security/rls_policies.md)