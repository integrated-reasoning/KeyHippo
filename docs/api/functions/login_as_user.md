# login_as_user

Impersonates a specific user for debugging or support.

## Syntax

```sql
keyhippo_impersonation.login_as_user(user_id uuid)
RETURNS void
```

## Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| user_id | uuid | ID of user to impersonate |

## Security

- SECURITY INVOKER procedure
- Requires postgres role
- Session timeout enforced
- Audit logged

## Example Usage

### Basic Impersonation
```sql
CALL keyhippo_impersonation.login_as_user('user_id_here');
```

### Complete Support Flow
```sql
DO $$
DECLARE
    v_user_id uuid;
BEGIN
    -- Find user
    SELECT id INTO v_user_id
    FROM auth.users
    WHERE email = 'user@example.com';
    
    -- Start impersonation
    CALL keyhippo_impersonation.login_as_user(v_user_id);
    
    -- Perform support actions
    -- ...
    
    -- End impersonation
    CALL keyhippo_impersonation.logout();
END $$;
```

### With Error Handling
```sql
DO $$
BEGIN
    -- Start impersonation
    CALL keyhippo_impersonation.login_as_user('user_id_here');
    
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
PERFORM set_config('request.jwt.claim.sub', user_id::text, TRUE);
PERFORM set_config('request.jwt.claim.role', user_role, TRUE);
PERFORM set_config('request.jwt.claim.email', user_email, TRUE);
```

2. **State Tracking**
```sql
INSERT INTO keyhippo_impersonation.impersonation_state (
    impersonated_user_id,
    original_role
)
VALUES (
    user_id,
    CURRENT_ROLE
);
```

3. **Session Timeout**
```sql
-- Set 1 hour timeout
PERFORM set_config(
    'session.impersonation_expires',
    (NOW() + INTERVAL '1 hour')::text,
    TRUE
);
```

## Error Handling

1. **Invalid User**
```sql
-- Raises exception
CALL keyhippo_impersonation.login_as_user('invalid_user_id');
```

2. **Unauthorized**
```sql
-- Raises exception if not postgres role
CALL keyhippo_impersonation.login_as_user('user_id');
```

3. **Already Impersonating**
```sql
-- Raises exception
-- Must logout first
CALL keyhippo_impersonation.login_as_user('another_user_id');
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
       user_id,
       data
   )
   VALUES (
       'impersonation_start',
       impersonated_user_id,
       jsonb_build_object(
           'original_role', original_role,
           'timestamp', NOW()
       )
   );
   ```

## Related Functions

- [login_as_anon()](login_as_anon.md)
- [logout()](logout.md)
- [current_user_context()](current_user_context.md)

## See Also

- [Impersonation State](../tables/impersonation_state.md)
- [Security Best Practices](../security/rls_policies.md)
- [Audit Log](../tables/audit_log.md)