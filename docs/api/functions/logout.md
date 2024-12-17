# logout

Ends an impersonation session and restores original role.

## Syntax

```sql
keyhippo_impersonation.logout()
RETURNS void
```

## Security

- SECURITY INVOKER procedure
- Safe for all roles
- Cleans up session state
- Audit logged

## Example Usage

### Basic Logout
```sql
CALL keyhippo_impersonation.logout();
```

### Complete Session
```sql
DO $$
BEGIN
    -- Start impersonation
    CALL keyhippo_impersonation.login_as_user('user_id_here');
    
    -- Perform actions
    -- ...
    
    -- End session
    CALL keyhippo_impersonation.logout();
END $$;
```

### With Error Handling
```sql
DO $$
BEGIN
    -- Start session
    CALL keyhippo_impersonation.login_as_user('user_id_here');
    
    BEGIN
        -- Perform actions
        -- ...
    EXCEPTION
        WHEN OTHERS THEN
            -- Always logout
            CALL keyhippo_impersonation.logout();
            RAISE;
    END;
    
    -- Normal logout
    CALL keyhippo_impersonation.logout();
END $$;
```

## Implementation Notes

1. **Session Cleanup**
```sql
-- Clear JWT claims
PERFORM set_config('request.jwt.claim.sub', '', TRUE);
PERFORM set_config('request.jwt.claim.role', '', TRUE);
PERFORM set_config('request.jwt.claims', '', TRUE);
```

2. **Role Reset**
```sql
-- Restore original role
EXECUTE FORMAT(
    'SET ROLE %I',
    original_role
);
```

3. **State Cleanup**
```sql
-- Remove impersonation state
DELETE FROM keyhippo_impersonation.impersonation_state
WHERE original_role = 'postgres';
```

## Error Handling

1. **Not Impersonating**
```sql
-- Raises exception
CALL keyhippo_impersonation.logout();
```

2. **Session Expired**
```sql
-- Still performs cleanup
CALL keyhippo_impersonation.logout();
```

## Security Considerations

1. **Session Cleanup**
   - Removes all JWT claims
   - Restores original role
   - Clears session state
   - Logs action

2. **State Verification**
   ```sql
   -- Get original role
   SELECT original_role::text
   FROM keyhippo_impersonation.get_and_cleanup_impersonation();
   ```

3. **Audit Trail**
   ```sql
   -- Track logout
   INSERT INTO keyhippo.audit_log (
       action,
       data
   )
   VALUES (
       'impersonation_end',
       jsonb_build_object(
           'original_role', original_role,
           'timestamp', NOW()
       )
   );
   ```

## Related Functions

- [login_as_user()](login_as_user.md)
- [login_as_anon()](login_as_anon.md)
- [current_user_context()](current_user_context.md)

## See Also

- [Impersonation State](../tables/impersonation_state.md)
- [Security Best Practices](../security/rls_policies.md)
- [Audit Log](../tables/audit_log.md)