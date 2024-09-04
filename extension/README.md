# KeyHippo PostgreSQL Extension

This directory contains the PostgreSQL extension for KeyHippo, which extends Supabase's Row Level Security (RLS) framework to support API key authentication.

## Installation

To install the KeyHippo extension in your PostgreSQL database:

```sql
select dbdev.install('keyhippo@keyhippo');
create extension "keyhippo@keyhippo" version '0.0.30';
```

## Usage in RLS Policies

Once installed, you can use KeyHippo functions in your RLS policies. For example:

```sql
CREATE POLICY "owner_access"
ON "public"."resource_table"
USING (
  auth.uid() = resource_table.owner_id
  OR auth.keyhippo_check(resource_table.owner_id)
);
```

This policy allows access when the user is authenticated via a session token (`auth.uid()`) or a valid API key associated with the resource owner (`auth.keyhippo_check()`).

## Available Functions

- `auth.keyhippo_check(user_id UUID)`: Checks if the current request is authenticated with a valid API key for the given user ID.
- `keyhippo.create_api_key(user_id UUID, description TEXT)`: Creates a new API key for the specified user.
- `keyhippo.revoke_api_key(key_id UUID)`: Revokes an existing API key.

For a complete list of functions and their usage, please refer to our [API Reference](/docs/API-Reference.md).

## Contributing

If you're interested in contributing to the development of the KeyHippo extension, please see our [Contributing Guide](/docs/Contributing.md).

## License

The KeyHippo PostgreSQL extension is distributed under the MIT license. See the [LICENSE](../LICENSE) file in the root directory for details.
