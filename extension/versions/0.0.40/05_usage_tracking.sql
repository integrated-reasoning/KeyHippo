-- 05_usage_tracking.sql
-- Function to update the last used timestamp for an API key
CREATE OR REPLACE FUNCTION keyhippo.update_last_used (p_api_key_id uuid)
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
BEGIN
    INSERT INTO keyhippo.api_key_id_last_used (api_key_id, last_used, owner_id)
        VALUES (p_api_key_id, now(),
            (
                SELECT
                    owner_id
                FROM
                    keyhippo.api_key_id_owner_id
                WHERE
                    api_key_id = p_api_key_id))
    ON CONFLICT (api_key_id)
        DO UPDATE SET
            last_used = EXCLUDED.last_used;
END;
$$;

-- Function to increment the total use count for an API key
CREATE OR REPLACE FUNCTION keyhippo.increment_total_use (p_api_key_id uuid)
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
BEGIN
    INSERT INTO keyhippo.api_key_id_total_use (api_key_id, total_uses, owner_id)
        VALUES (p_api_key_id, 1, (
                SELECT
                    owner_id
                FROM keyhippo.api_key_id_owner_id
                WHERE
                    api_key_id = p_api_key_id))
ON CONFLICT (api_key_id)
    DO UPDATE SET
        total_uses = keyhippo.api_key_id_total_use.total_uses + 1;
END;
$$;

-- Function to update the success rate for an API key
CREATE OR REPLACE FUNCTION keyhippo.update_success_rate (p_api_key_id uuid, p_success boolean)
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    v_current_rate numeric(5, 2);
    v_total_uses bigint;
    v_new_rate numeric(5, 2);
BEGIN
    SELECT
        success_rate,
        total_uses INTO v_current_rate,
        v_total_uses
    FROM
        keyhippo.api_key_id_success_rate r
        JOIN keyhippo.api_key_id_total_use t USING (api_key_id)
    WHERE
        api_key_id = p_api_key_id;
    IF v_current_rate IS NULL THEN
        v_new_rate := CASE WHEN p_success THEN
            100.00
        ELSE
            0.00
        END;
    ELSE
        v_new_rate := (v_current_rate * v_total_uses + (
                CASE WHEN p_success THEN
                    100.00
                ELSE
                    0.00
                END)) / (v_total_uses + 1);
    END IF;
    INSERT INTO keyhippo.api_key_id_success_rate (api_key_id, success_rate, owner_id)
        VALUES (p_api_key_id, v_new_rate, (
                SELECT
                    owner_id
                FROM
                    keyhippo.api_key_id_owner_id
                WHERE
                    api_key_id = p_api_key_id))
    ON CONFLICT (api_key_id)
        DO UPDATE SET
            success_rate = EXCLUDED.success_rate;
END;
$$;

-- Function to update the total cost for an API key
CREATE OR REPLACE FUNCTION keyhippo.update_total_cost (p_api_key_id uuid, p_cost numeric(12, 2))
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
BEGIN
    INSERT INTO keyhippo.api_key_id_total_cost (api_key_id, total_cost, owner_id)
        VALUES (p_api_key_id, p_cost, (
                SELECT
                    owner_id
                FROM
                    keyhippo.api_key_id_owner_id
                WHERE
                    api_key_id = p_api_key_id))
    ON CONFLICT (api_key_id)
        DO UPDATE SET
            total_cost = keyhippo.api_key_id_total_cost.total_cost + EXCLUDED.total_cost;
END;
$$;

-- Function to record API key usage
CREATE OR REPLACE FUNCTION keyhippo.record_api_key_usage (p_api_key_id uuid, p_success boolean, p_cost numeric(12, 2) DEFAULT 0.00)
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
BEGIN
    -- Update last used timestamp
    PERFORM
        keyhippo.update_last_used (p_api_key_id);
    -- Increment total use count
    PERFORM
        keyhippo.increment_total_use (p_api_key_id);
    -- Update success rate
    PERFORM
        keyhippo.update_success_rate (p_api_key_id, p_success);
    -- Update total cost
    IF p_cost > 0 THEN
        PERFORM
            keyhippo.update_total_cost (p_api_key_id, p_cost);
    END IF;
END;
$$;
