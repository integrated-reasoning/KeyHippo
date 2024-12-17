# check_request

PreRequest check function for PostgREST that validates API key authentication.

## Syntax

```sql
keyhippo.check_request()
RETURNS void
```

## Security

- SECURITY DEFINER function
- Used as pgrst.db_pre_request
- Enforces API key validation
- Prevents unauthorized access

## Example Usage

### Enable PreRequest Check
```sql
-- Enable for PostgREST
ALTER ROLE authenticator 
SET pgrst.db_pre_request = 'keyhippo.check_request';

-- Reload configuration
NOTIFY pgrst, 'reload config';
```

### Test Configuration
```sql
DO $$
BEGIN
    -- Should raise exception with no API key
    PERFORM keyhippo.check_request();
EXCEPTION
    WHEN OTHERS THEN
        ASSERT SQLERRM = 'No registered API key found in x-api-key header.';
END $$;
```

## Implementation Notes

1. **Request Validation**
```sql
-- Skip check for authenticated users
IF CURRENT_ROLE <> 'anon' THEN
    RETURN;
END IF;

-- Check API key
SELECT * INTO ctx
FROM keyhippo.current_user_context();

IF ctx.user_id IS NULL THEN
    RAISE EXCEPTION 'No registered API key found in x-api-key header.';
END IF;
```

2. **Security Context**
```sql
-- Sets pg_temp search path
SET search_path = pg_temp
```

## Error Handling

1. **No API Key**
```sql
-- Raises exception
'No registered API key found in x-api-key header.'
```

2. **Invalid Key**
```sql
-- Raises exception
'No registered API key found in x-api-key header.'
```

3. **Role Check**
```sql
-- Allows authenticated users
-- Checks anon requests
IF CURRENT_ROLE <> 'anon' THEN
    RETURN;
END IF;
```

## Security Considerations

1. **API Key Validation**
   - Checks key presence
   - Validates key format
   - Verifies key status

2. **Role Management**
   - Handles authenticated users
   - Validates anonymous access
   - Maintains security context

3. **Error Handling**
   - Clear error messages
   - No sensitive data exposure
   - Consistent behavior

## Performance Impact

- Fast key validation
- Caches results
- Minimal overhead
- Required for security

## PostgREST Integration

1. **Configuration**
```sql
-- Set pre-request function
ALTER ROLE authenticator 
SET pgrst.db_pre_request = 'keyhippo.check_request';

-- Apply changes
NOTIFY pgrst, 'reload config';
```

2. **Headers**
```bash
# Required header
x-api-key: your_api_key_here
```

3. **Error Responses**
```json
{
    "code": "PGRST301",
    "message": "No registered API key found in x-api-key header."
}
```

## Related Functions

- [verify_api_key()](verify_api_key.md)
- [current_user_context()](current_user_context.md)
- [authorize()](authorize.md)

## See Also

- [API Key Metadata](../tables/api_key_metadata.md)
- [Security Policies](../security/rls_policies.md)
- [Function Security](../security/function_security.md)