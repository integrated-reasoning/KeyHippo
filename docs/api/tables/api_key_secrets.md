# api_key_secrets

Securely stores API key hashes, separate from metadata for enhanced security.

## Schema

```sql
CREATE TABLE keyhippo.api_key_secrets (
    key_metadata_id uuid PRIMARY KEY REFERENCES keyhippo.api_key_metadata(id) ON DELETE CASCADE,
    key_hash text NOT NULL
);
```

## Columns

| Column | Type | Description |
|--------|------|-------------|
| key_metadata_id | uuid | Foreign key to api_key_metadata |
| key_hash | text | SHA-512 hash of the key |

## Security

- No direct access allowed (RLS denies all)
- Accessible only through SECURITY DEFINER functions
- Automatically purged when key is revoked
- Hash-only storage for zero plaintext exposure

## Access Policy

```sql
CREATE POLICY api_key_secrets_no_access_policy ON keyhippo.api_key_secrets
    FOR ALL TO authenticated
    USING (FALSE);
```

## Usage

Keys are managed exclusively through these functions:

```sql
-- Creation (internal)
INSERT INTO keyhippo.api_key_secrets (key_metadata_id, key_hash)
VALUES (
    'key_id_here',
    encode(extensions.digest('key_here', 'sha512'), 'hex')
);

-- Verification (via verify_api_key function)
SELECT key_hash = computed_hash
FROM keyhippo.api_key_secrets
WHERE key_metadata_id = 'key_id_here';

-- Deletion (on revocation)
DELETE FROM keyhippo.api_key_secrets
WHERE key_metadata_id = 'key_id_here';
```

## Implementation Notes

1. **Key Security**
   - Uses SHA-512 for key hashing
   - No reversible encryption
   - No key reconstruction possible

2. **Automatic Cleanup**
   ```sql
   -- Triggered by key revocation
   CREATE OR REPLACE FUNCTION cleanup_key_secrets()
   RETURNS trigger AS $$
   BEGIN
       IF NEW.is_revoked THEN
           DELETE FROM keyhippo.api_key_secrets
           WHERE key_metadata_id = NEW.id;
       END IF;
       RETURN NEW;
   END;
   $$ LANGUAGE plpgsql;
   ```

3. **Performance**
   - Primary key for efficient lookups
   - Minimal schema for performance
   - Single-row operations only

## Related Tables

- [api_key_metadata](api_key_metadata.md)
- [audit_log](audit_log.md)

## Related Functions

- [create_api_key()](../functions/create_api_key.md)
- [verify_api_key()](../functions/verify_api_key.md)
- [revoke_api_key()](../functions/revoke_api_key.md)

## Security Considerations

1. **Access Control**
   - No direct table access
   - Function-based interface only
   - Audit logging on all changes

2. **Data Protection**
   ```sql
   -- Ensure RLS is enabled
   ALTER TABLE keyhippo.api_key_secrets ENABLE ROW LEVEL SECURITY;

   -- Revoke direct access
   REVOKE ALL ON keyhippo.api_key_secrets FROM authenticated;
   ```

3. **Monitoring**
   ```sql
   -- Track secret counts
   SELECT COUNT(*) FROM keyhippo.api_key_secrets;

   -- Check for orphaned secrets
   SELECT s.key_metadata_id
   FROM keyhippo.api_key_secrets s
   LEFT JOIN keyhippo.api_key_metadata m 
   ON s.key_metadata_id = m.id
   WHERE m.id IS NULL;
   ```