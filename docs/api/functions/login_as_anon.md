# login_as_anon

Impersonates an anonymous user for testing public access.

## Syntax

```sql
keyhippo_impersonation.login_as_anon()
RETURNS void
```

## Security

- SECURITY INVOKER procedure
- Requires postgres role
- Session timeout enforced
- Audit logged

## Example Usage

### Basic Anonymous Access
```sql
CALL keyhippo_impersonation.login_as_anon();
```

### Testing Public Access
```sql
DO $$
BEGIN
    -- Start anonymous session
    CALL keyhippo_impersonation.login_as_anon();
    
    -- Test public access
    ASSERT EXISTS (
        SELECT 1 FROM public.resources
        WHERE is_public = true
    );
    
    -- End session
    CALL keyhippo_impersonation.logout();
END $$;
```

### With Error Handling
```sql
DO $$
BEGIN
    -- Start anonymous session
    CALL keyhippo_impersonation.login_as_anon();
    
    -- Set timeout handler
    PERFORM set_config(
        'session.impersonation_expires',
        (NOW() + INTERVAL '1 hour')::text,
        TRUE
    );
    
EXCEPTION
    WHEN OTHERS THEN
        -- Ensure logout
        CALL keyhippo_impersonation.logout();
        RAISE;
END $$;
```

## Implementation Notes

1. **Session Setup**
```sql
-- Set JWT claims
PERFORM set_config('request.jwt.claim.sub', 'anon', TRUE);
PERFORM set_config('request.jwt.claim.role', 'anon', TRUE);
PERFORM set_config('request.jwt.claims', '{"role": "anon"}', TRUE);
```

2. **State Tracking**
```sql
INSERT INTO keyhippo_impersonation.impersonation_state (
    impersonated_user_id,
    original_role
)
VALUES (
    '00000000-0000-0000-0000-000000000000'::uuid,
    CURRENT_ROLE
);
```

3. **Session Timeout**
```sql
PERFORM set_config(
    'session.impersonation_expires',
    (NOW() + INTERVAL '1 hour')::text,
    TRUE
);
```

## Error Handling

1. **Unauthorized**
```sql
-- Raises exception if not postgres role
CALL keyhippo_impersonation.login_as_anon();
```

2. **Already Impersonating**
```sql
-- Raises exception
-- Must logout first
CALL keyhippo_impersonation.login_as_anon();
```

## Security Considerations

1. **Access Control**
   - Only postgres role can impersonate
   - All actions are audit logged
   - Session timeout enforced
   - Original role preserved

2. **Session Management**
   ```sql
   -- Check timeout
   SELECT current_setting(
       'session.impersonation_expires',
       TRUE
   )::timestamptz > NOW();
   ```

3. **Audit Trail**
   ```sql
   -- Track impersonation
   INSERT INTO keyhippo.audit_log (
       action,
       data
   )
   VALUES (
       'anon_impersonation_start',
       jsonb_build_object(
           'original_role', original_role,
           'timestamp', NOW()
       )
   );
   ```

## Related Functions

- [login_as_user()](login_as_user.md)
- [logout()](logout.md)
- [current_user_context()](current_user_context.md)

## See Also

- [Impersonation State](../tables/impersonation_state.md)
- [Security Best Practices](../security/rls_policies.md)
- [Audit Log](../tables/audit_log.md)