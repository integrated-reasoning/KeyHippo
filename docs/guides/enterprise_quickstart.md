# Enterprise QuickStart Guide

This guide covers setting up KeyHippo for enterprise environments with advanced security and scalability requirements.

## Prerequisites

- PostgreSQL 12 or higher
- Administrative database access
- Network access for all application servers

## Installation Steps

1. **Initial Setup**

```sql
-- Run as superuser
CREATE EXTENSION IF NOT EXISTS keyhippo;
SELECT initialize_keyhippo('enterprise');
```

2. **Configure Enterprise Settings**

```sql
-- Enable advanced security features
UPDATE keyhippo_internal.config SET 
  require_key_rotation = true,
  max_key_age_days = 90,
  enforce_strong_passwords = true,
  audit_level = 'full';
```

3. **Set Up RBAC Structure**

```sql
-- Create base enterprise roles
SELECT create_role('system_admin');
SELECT create_role('security_admin');
SELECT create_role('key_manager');
SELECT create_role('auditor');

-- Create enterprise groups
SELECT create_group('it_ops');
SELECT create_group('security');
SELECT create_group('development');

-- Assign permissions
SELECT assign_permission_to_role('manage_keys', 'key_manager');
SELECT assign_permission_to_role('view_audit', 'auditor');
SELECT assign_permission_to_role('manage_roles', 'security_admin');
```

## Security Configuration

### 1. Key Rotation Policy

Configure automatic key rotation:

```sql
SELECT update_expiring_keys(
  warning_days := 14,
  revocation_days := 7
);
```

### 2. RLS Policies

Enable strict RLS policies:

```sql
ALTER TABLE keyhippo.api_key_metadata ENABLE ROW LEVEL SECURITY;
ALTER TABLE keyhippo_rbac.user_group_roles ENABLE ROW LEVEL SECURITY;
```

### 3. Audit Configuration

Enable comprehensive auditing:

```sql
CREATE POLICY audit_log_policy ON keyhippo.audit_log
  USING (current_user_context()->>'role' IN ('auditor', 'system_admin'));
```

## Multi-Tenant Setup

For enterprise multi-tenant deployments:

1. Create tenant isolation:
```sql
SELECT create_group('tenant_' || tenant_id) 
FROM tenant_list;
```

2. Configure tenant-specific roles:
```sql
-- For each tenant
SELECT create_role('tenant_admin_' || tenant_id);
SELECT create_role('tenant_user_' || tenant_id);
```

## Monitoring & Maintenance

### 1. Health Checks

Regular system health monitoring:

```sql
-- Check key status
SELECT * FROM keyhippo.api_key_metadata 
WHERE expires_at < NOW() + INTERVAL '30 days';

-- Audit log review
SELECT * FROM keyhippo.audit_log 
WHERE event_type = 'security_violation'
AND created_at > NOW() - INTERVAL '24 hours';
```

### 2. Backup Configuration

Implement regular backups:

```sql
-- Example backup script
pg_dump -t 'keyhippo.*' -t 'keyhippo_rbac.*' -t 'keyhippo_internal.*' dbname > keyhippo_backup.sql
```

## Best Practices

1. **Key Management**
   - Implement regular key rotation
   - Use short-lived keys for automated systems
   - Apply principle of least privilege

2. **Access Control**
   - Segregate duties using RBAC
   - Regularly audit access patterns
   - Remove unused permissions

3. **Monitoring**
   - Set up alerts for security events
   - Monitor key usage patterns
   - Track failed authentication attempts

4. **Compliance**
   - Maintain audit logs
   - Document access policies
   - Regular security reviews

## Troubleshooting

Common enterprise deployment issues:

1. **Performance**
   - Optimize indexes for large deployments
   - Monitor query performance
   - Configure connection pooling

2. **Security**
   - Debug RLS policy issues
   - Resolve permission conflicts
   - Track audit log errors

3. **Integration**
   - API gateway configuration
   - Load balancer setup
   - Network security

## Next Steps

- Review [Multi-Tenant Guide](multi_tenant.md)
- Implement [API Key Patterns](api_key_patterns.md)
- Configure monitoring systems
- Set up backup procedures

## Support

For enterprise support:
- Email: enterprise@keyhippo.com
- Documentation: https://docs.keyhippo.com/enterprise
- Security updates: https://security.keyhippo.com