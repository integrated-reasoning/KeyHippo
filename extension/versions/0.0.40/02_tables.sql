-- 02_tables.sql
-- Create required tables in the auth and keyhippo schemas
CREATE TABLE IF NOT EXISTS auth.jwts (
    secret_id uuid PRIMARY KEY,
    user_id uuid,
    CONSTRAINT jwts_secret_id_fkey FOREIGN KEY (secret_id) REFERENCES vault.secrets (id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS keyhippo.user_ids (
    id uuid PRIMARY KEY
);

CREATE TABLE IF NOT EXISTS keyhippo.api_key_id_owner_id (
    api_key_id uuid PRIMARY KEY,
    user_id uuid NOT NULL,
    owner_id uuid,
    CONSTRAINT api_key_id_owner_id_user_id_fkey FOREIGN KEY (user_id) REFERENCES keyhippo.user_ids (id) ON DELETE CASCADE,
    CONSTRAINT api_key_id_owner_id_api_key_id_owner_id_key UNIQUE (api_key_id, owner_id)
);

CREATE TABLE IF NOT EXISTS keyhippo.api_key_id_name (
    api_key_id uuid PRIMARY KEY,
    name text NOT NULL,
    owner_id uuid,
    CONSTRAINT api_key_id_name_api_key_id_fkey FOREIGN KEY (api_key_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id) ON DELETE CASCADE,
    CONSTRAINT api_key_id_name_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id, owner_id)
);

CREATE TABLE IF NOT EXISTS keyhippo.api_key_id_permission (
    api_key_id uuid PRIMARY KEY,
    permission text NOT NULL,
    owner_id uuid,
    CONSTRAINT api_key_id_permission_api_key_id_fkey FOREIGN KEY (api_key_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id) ON DELETE CASCADE,
    CONSTRAINT api_key_id_permission_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id, owner_id)
);

CREATE TABLE IF NOT EXISTS keyhippo.api_key_id_created (
    api_key_id uuid PRIMARY KEY,
    created timestamptz NOT NULL,
    owner_id uuid,
    CONSTRAINT api_key_id_created_api_key_id_fkey FOREIGN KEY (api_key_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id) ON DELETE CASCADE,
    CONSTRAINT api_key_id_created_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id, owner_id)
);

CREATE TABLE IF NOT EXISTS keyhippo.api_key_id_last_used (
    api_key_id uuid PRIMARY KEY,
    last_used timestamptz,
    owner_id uuid,
    CONSTRAINT api_key_id_last_used_api_key_id_fkey FOREIGN KEY (api_key_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id) ON DELETE CASCADE,
    CONSTRAINT api_key_id_last_used_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id, owner_id)
);

CREATE TABLE IF NOT EXISTS keyhippo.api_key_id_total_use (
    api_key_id uuid PRIMARY KEY,
    total_uses bigint DEFAULT 0 NOT NULL,
    owner_id uuid,
    CONSTRAINT api_key_id_total_use_api_key_id_fkey FOREIGN KEY (api_key_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id) ON DELETE CASCADE,
    CONSTRAINT api_key_id_total_use_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id, owner_id)
);

CREATE TABLE IF NOT EXISTS keyhippo.api_key_id_success_rate (
    api_key_id uuid PRIMARY KEY,
    success_rate numeric(5, 2) NOT NULL,
    owner_id uuid,
    CONSTRAINT api_key_id_success_rate_api_key_id_fkey FOREIGN KEY (api_key_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id) ON DELETE CASCADE,
    CONSTRAINT api_key_id_success_rate_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id, owner_id),
    CONSTRAINT api_key_reference_success_rate_success_rate_check CHECK ((success_rate >= 0 AND success_rate <= 100))
);

CREATE TABLE IF NOT EXISTS keyhippo.api_key_id_total_cost (
    api_key_id uuid PRIMARY KEY,
    total_cost numeric(12, 2) DEFAULT 0 NOT NULL,
    owner_id uuid,
    CONSTRAINT api_key_id_total_cost_api_key_id_fkey FOREIGN KEY (api_key_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id) ON DELETE CASCADE,
    CONSTRAINT api_key_id_total_cost_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id, owner_id)
);

CREATE TABLE IF NOT EXISTS keyhippo.api_key_id_revoked (
    api_key_id uuid PRIMARY KEY,
    revoked_at timestamptz DEFAULT now() NOT NULL,
    owner_id uuid,
    CONSTRAINT api_key_id_revoked_api_key_id_fkey FOREIGN KEY (api_key_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id) ON DELETE CASCADE,
    CONSTRAINT api_key_id_revoked_api_key_id_owner_id_fkey FOREIGN KEY (api_key_id, owner_id) REFERENCES keyhippo.api_key_id_owner_id (api_key_id, owner_id)
);
