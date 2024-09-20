-- 07_rls_policies.sql
-- Enable Row Level Security on all tables
ALTER TABLE keyhippo.api_key_id_created ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo.api_key_id_last_used ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo.api_key_id_name ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo.api_key_id_owner_id ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo.api_key_id_permission ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo.api_key_id_revoked ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo.api_key_id_success_rate ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo.api_key_id_total_cost ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo.api_key_id_total_use ENABLE ROW LEVEL SECURITY;

ALTER TABLE keyhippo.user_ids ENABLE ROW LEVEL SECURITY;

-- Helper function for RLS policies
CREATE OR REPLACE FUNCTION auth.keyhippo_check (owner_id uuid)
    RETURNS boolean
    LANGUAGE sql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
    SELECT
        (auth.uid () = owner_id)
        OR (keyhippo.key_uid () = owner_id);
$$;

-- Create RLS policies for each table
CREATE POLICY "select_policy_api_key_id_created" ON keyhippo.api_key_id_created
    FOR SELECT TO anon, authenticated
        USING (auth.keyhippo_check (owner_id));

CREATE POLICY "select_policy_api_key_id_last_used" ON keyhippo.api_key_id_last_used
    FOR SELECT TO anon, authenticated
        USING (auth.keyhippo_check (owner_id));

CREATE POLICY "select_policy_api_key_id_name" ON keyhippo.api_key_id_name
    FOR SELECT TO anon, authenticated
        USING (auth.keyhippo_check (owner_id));

CREATE POLICY "select_policy_api_key_id_owner_id" ON keyhippo.api_key_id_owner_id
    FOR SELECT TO anon, authenticated
        USING (auth.keyhippo_check (owner_id));

CREATE POLICY "select_policy_api_key_id_permission" ON keyhippo.api_key_id_permission
    FOR SELECT TO anon, authenticated
        USING (auth.keyhippo_check (owner_id));

CREATE POLICY "select_policy_api_key_id_revoked" ON keyhippo.api_key_id_revoked
    FOR SELECT TO anon, authenticated
        USING (auth.keyhippo_check (owner_id));

CREATE POLICY "select_policy_api_key_id_success_rate" ON keyhippo.api_key_id_success_rate
    FOR SELECT TO anon, authenticated
        USING (auth.keyhippo_check (owner_id));

CREATE POLICY "select_policy_api_key_id_total_cost" ON keyhippo.api_key_id_total_cost
    FOR SELECT TO anon, authenticated
        USING (auth.keyhippo_check (owner_id));

CREATE POLICY "select_policy_api_key_id_total_use" ON keyhippo.api_key_id_total_use
    FOR SELECT TO anon, authenticated
        USING (auth.keyhippo_check (owner_id));

CREATE POLICY "select_policy_user_ids" ON keyhippo.user_ids
    FOR SELECT TO anon, authenticated
        USING (auth.uid () = id);
