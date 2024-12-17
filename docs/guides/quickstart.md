# QuickStart Guide

Get started with KeyHippo's basic API key authentication in minutes.

## Prerequisites

- PostgreSQL 14 or higher
- A Supabase project (or compatible PostgreSQL setup)
- Database superuser access for installation

## Installation

1. Install required extensions:
```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_net;
```

2. Install KeyHippo:
```sql
\i sql/keyhippo.sql
```

## Basic Setup

1. Initialize KeyHippo for your project:
```sql
SELECT keyhippo.initialize_keyhippo();
```

This creates:
- Default groups and roles
- Basic permissions
- Required tables and functions

## Create Your First API Key

1. Create a key for authenticated users:
```sql
SELECT * FROM keyhippo.create_api_key('My First API Key');
```

Save the returned API key - it won't be shown again!

## Protect Your Resources

1. Enable Row Level Security on your table:
```sql
CREATE TABLE items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    data jsonb
);

ALTER TABLE items ENABLE ROW LEVEL SECURITY;
```

2. Create an RLS policy using KeyHippo:
```sql
CREATE POLICY "api_access" ON items
    FOR ALL
    TO authenticated, anon
    USING (
        -- Allow access if user is authenticated or has valid API key
        (SELECT user_id FROM keyhippo.current_user_context()) IS NOT NULL
    );
```

## Use Your API Key

1. In your API requests, include the header:
```
x-api-key: your_api_key_here
```

2. Test the access:
```bash
curl -X GET 'https://your-project.supabase.co/rest/v1/items' \
  -H 'x-api-key: your_api_key_here'
```

## Next Steps

- Review the [API Documentation](../api/index.md) for detailed function reference
- Implement [API Key Patterns](api_key_patterns.md) for advanced usage
- Set up [Multi-Tenant Access](multi_tenant.md) for larger applications

## Common Issues

### API Key Not Working
- Ensure the key hasn't expired or been revoked
- Check that the x-api-key header is set correctly
- Verify RLS policies grant necessary permissions

### Permission Errors
- Check user role assignments
- Verify API key scope settings
- Review RLS policy conditions

## Security Tips

1. Never store API keys in your code
2. Use environment variables for key storage
3. Implement key rotation regularly
4. Monitor the audit log for suspicious activity

## Need More?

- For multi-tenant setups, see our [Multi-Tenant Guide](enterprise_quickstart.md)
- Join our [GitHub Discussions](https://github.com/integrated-reasoning/keyhippo/discussions)
- Report issues on our [Issue Tracker](https://github.com/integrated-reasoning/keyhippo/issues)