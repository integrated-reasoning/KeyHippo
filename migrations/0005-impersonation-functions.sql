BEGIN;

-- Impersonation functions
CREATE OR REPLACE PROCEDURE keyhippo_impersonation.login_as_user(user_id uuid)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = keyhippo_impersonation
AS $$
DECLARE
    auth_user auth.users%ROWTYPE;
    current_role_name NAME;
BEGIN
    -- Ensure only postgres user can call this procedure
    IF CURRENT_USER != 'postgres' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;
    
    -- Get current role before impersonation
    SELECT CURRENT_ROLE INTO current_role_name;
    
    -- Fetch the user based on UUID
    SELECT * INTO auth_user
    FROM auth.users
    WHERE id = user_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User with ID % does not exist', user_id;
    END IF;
    
    -- Set JWT claims using parameterized queries
    PERFORM set_config('request.jwt.claim.sub', auth_user.id::text, TRUE);
    PERFORM set_config('request.jwt.claim.role', COALESCE(auth_user.role, 'authenticated'), TRUE);
    
    IF auth_user.email IS NOT NULL THEN
        PERFORM set_config('request.jwt.claim.email', auth_user.email, TRUE);
    END IF;
    
    IF auth_user.raw_app_meta_data IS NOT NULL THEN
        PERFORM set_config('request.jwt.claims', 
            JSON_STRIP_NULLS(JSON_BUILD_OBJECT('app_metadata', auth_user.raw_app_meta_data))::text, TRUE);
    END IF;
    
    -- Track impersonation state
    INSERT INTO keyhippo_impersonation.impersonation_state (impersonated_user_id, original_role)
    VALUES (user_id, current_role_name)
    ON CONFLICT (impersonated_user_id)
    DO UPDATE SET
        original_role = EXCLUDED.original_role,
        impersonation_time = CURRENT_TIMESTAMP;
    
    -- Set role
    EXECUTE FORMAT('SET ROLE %I', COALESCE(auth_user.role, 'authenticated'));
    
    -- Set session timeout
    PERFORM set_config('session.impersonation_expires', (NOW() + INTERVAL '1 hour')::text, TRUE);
    
    -- Log the impersonation for debugging
    RAISE NOTICE 'Impersonation successful. User ID: %, Role: %, JWT Claims: %', 
        auth_user.id, COALESCE(auth_user.role, 'authenticated'), current_setting('request.jwt.claims', TRUE);
END;
$$;

CREATE OR REPLACE PROCEDURE keyhippo_impersonation.login_as_anon()
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = keyhippo_impersonation
AS $$
DECLARE
    current_role_name NAME;
    ANON_USER_ID uuid := '00000000-0000-0000-0000-000000000000'::uuid;
BEGIN
    -- Ensure only postgres user can call this procedure
    IF CURRENT_USER != 'postgres' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;
    
    -- Get current role before impersonation
    SELECT CURRENT_ROLE INTO current_role_name;
    
    -- Set JWT claims for anonymous login
    PERFORM set_config('request.jwt.claim.sub', 'anon', TRUE);
    PERFORM set_config('request.jwt.claim.role', 'anon', TRUE);
    PERFORM set_config('request.jwt.claim.email', '', TRUE);
    PERFORM set_config('request.jwt.claims', 
        json_build_object('sub', 'anon', 'role', 'anon')::text, TRUE);
    
    -- Track impersonation state
    DELETE FROM keyhippo_impersonation.impersonation_state
    WHERE impersonated_user_id = ANON_USER_ID;
    
    INSERT INTO keyhippo_impersonation.impersonation_state (impersonated_user_id, original_role)
    VALUES (ANON_USER_ID, current_role_name);
    
    -- Set role to anon
    SET ROLE anon;
    
    -- Set session timeout
    PERFORM set_config('session.impersonation_expires', (NOW() + INTERVAL '1 hour')::text, TRUE);
    
    RAISE NOTICE 'Anonymous login successful. Impersonated user ID: %, Original role: %, Session expires: %', 
        ANON_USER_ID, current_role_name, current_setting('session.impersonation_expires', TRUE);
END;
$$;

CREATE OR REPLACE FUNCTION keyhippo_impersonation.get_and_cleanup_impersonation()
    RETURNS text
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = keyhippo_impersonation
    AS $$
DECLARE
    v_original_role text;
BEGIN
    -- Get the original role
    SELECT original_role::text INTO v_original_role
    FROM impersonation_state
    WHERE original_role = 'postgres'
    ORDER BY impersonation_time DESC
    LIMIT 1;
    
    IF v_original_role IS NULL THEN
        RAISE EXCEPTION 'Current user is not being impersonated';
    END IF;
    
    -- Clean up state
    DELETE FROM impersonation_state
    WHERE original_role = 'postgres';
    
    RETURN v_original_role;
END;
$$;

CREATE OR REPLACE PROCEDURE keyhippo_impersonation.logout()
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = keyhippo_impersonation
AS $$
DECLARE
    v_original_role text;
BEGIN
    IF current_setting('session.impersonation_expires', TRUE) IS NULL THEN
        RAISE EXCEPTION 'Not in an impersonation session';
    END IF;
    
    -- Get original role and cleanup state
    v_original_role := keyhippo_impersonation.get_and_cleanup_impersonation();
    
    -- Clear JWT claims
    PERFORM set_config('request.jwt.claim.sub', '', TRUE);
    PERFORM set_config('request.jwt.claim.role', '', TRUE);
    PERFORM set_config('request.jwt.claim.email', '', TRUE);
    PERFORM set_config('request.jwt.claims', '', TRUE);
    
    -- Reset role
    EXECUTE FORMAT('SET ROLE %I', v_original_role);
    
    -- Clear session
    PERFORM set_config('session.impersonation_expires', '', TRUE);
    
    RAISE NOTICE 'Logout successful. Original role: %', v_original_role;
END;
$$;

CREATE OR REPLACE FUNCTION keyhippo_impersonation.generate_random_user_data()
    RETURNS TABLE (
        id uuid,
        email text,
        encrypted_password text,
        email_confirmed_at timestamptz,
        last_sign_in_at timestamptz,
        raw_app_meta_data jsonb,
        raw_user_meta_data jsonb,
        is_super_admin boolean,
        created_at timestamptz,
        updated_at timestamptz,
        phone text,
        phone_confirmed_at timestamptz,
        confirmation_token text,
        confirmation_sent_at timestamptz,
        recovery_token text,
        recovery_sent_at timestamptz,
        email_change_token_new text,
        email_change text,
        email_change_sent_at timestamptz,
        aud text,
        banned_until timestamptz,
        role text
    )
    AS $$
DECLARE
    random_string text;
BEGIN
    id := gen_random_uuid();
    random_string := encode(gen_random_bytes(8), 'hex');
    email := random_string || '@example.com';
    encrypted_password := crypt('password', gen_salt('bf'));
    email_confirmed_at := now() - (random() * interval '90 days');
    last_sign_in_at := now() - (random() * interval '30 days');
    raw_app_meta_data := jsonb_build_object('provider', 'email', 'providers', ARRAY['email']);
    raw_user_meta_data := jsonb_build_object('name', 'Test User ' || random_string);
    is_super_admin := FALSE;
    created_at := now() - (random() * interval '180 days');
    updated_at := created_at + (random() * (now() - created_at));
    phone := '+1' || lpad(floor(random() * 10000000000)::text, 10, '0');
    phone_confirmed_at := NULL;
    confirmation_token := encode(gen_random_bytes(32), 'hex');
    confirmation_sent_at := created_at;
    recovery_token := NULL;
    recovery_sent_at := NULL;
    email_change_token_new := NULL;
    email_change := NULL;
    email_change_sent_at := NULL;
    aud := 'authenticated';
    banned_until := NULL;
    role := 'authenticated';
    RETURN NEXT;
END;
$$
LANGUAGE plpgsql
SECURITY INVOKER SET search_path = keyhippo_impersonation, public VOLATILE;

-- Function to create a new auth.user for testing
CREATE OR REPLACE FUNCTION keyhippo_impersonation.generate_new_user()
    RETURNS uuid
    AS $$
DECLARE
    new_user_id uuid;
BEGIN
    INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, last_sign_in_at, raw_app_meta_data, raw_user_meta_data, is_super_admin, created_at, updated_at, phone, phone_confirmed_at, confirmation_token, confirmation_sent_at, recovery_token, recovery_sent_at, email_change_token_new, email_change, email_change_sent_at, aud, banned_until, role)
    SELECT *
    FROM keyhippo_impersonation.generate_random_user_data()
    RETURNING id INTO new_user_id;
    
    -- The default role assignment should be handled by the trigger automatically
    RETURN new_user_id;
END;
$$
LANGUAGE plpgsql
VOLATILE SET search_path = keyhippo_impersonation, public
SECURITY DEFINER;

COMMIT;