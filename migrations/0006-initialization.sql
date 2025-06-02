BEGIN;

-- Key expiry notification function
CREATE OR REPLACE FUNCTION keyhippo.notify_expiring_key()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    v_endpoint text;
    v_installation_uuid uuid;
    v_payload jsonb;
    v_enable_notifications boolean;
    v_notification_hours int;
    v_request_id bigint;
    v_response_status int;
    v_response_body text;
BEGIN
    RAISE LOG 'notify_expiring_key triggered for key: %', NEW.id;
    
    -- Check if notifications are enabled
    SELECT value::boolean INTO v_enable_notifications
    FROM keyhippo_internal.config
    WHERE key = 'enable_key_expiry_notifications';
    
    IF NOT v_enable_notifications THEN
        RAISE LOG 'Key expiry notifications are disabled';
        RETURN NEW;
    END IF;
    
    -- Get the notification hours from config
    SELECT value::int INTO v_notification_hours
    FROM keyhippo_internal.config
    WHERE key = 'key_expiry_notification_hours';
    
    RAISE LOG 'Notification hours: %, Key expires at: %, Current time: %', v_notification_hours, NEW.expires_at, NOW();
    
    -- If the key is about to expire within the specified hours
    IF NEW.expires_at <= NOW() + (v_notification_hours || ' hours')::interval 
       AND (OLD.expires_at IS NULL OR OLD.expires_at > NOW() + (v_notification_hours || ' hours')::interval) THEN
        
        RAISE LOG 'Key % is expiring soon, preparing notification', NEW.id;
        
        -- Get the endpoint and installation UUID from the config table
        SELECT value INTO v_endpoint
        FROM keyhippo_internal.config
        WHERE key = 'audit_log_endpoint';
        
        SELECT value::uuid INTO v_installation_uuid
        FROM keyhippo_internal.config
        WHERE key = 'installation_uuid';
        
        -- Prepare the payload
        v_payload := jsonb_build_object(
            'event', 'expiring_key',
            'installation_uuid', v_installation_uuid,
            'timestamp', now(),
            'expiring_key', jsonb_build_object(
                'id', NEW.id,
                'user_id', NEW.user_id,
                'description', NEW.description,
                'expires_at', NEW.expires_at
            )
        );
        
        RAISE LOG 'Sending notification to endpoint: % with payload: %', v_endpoint, v_payload;
        
        -- Send the notification with error handling if pg_net is available
        IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'http_post' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'net')) THEN
            BEGIN
                SELECT (result).status, (result).content::text, (result).id 
                INTO v_response_status, v_response_body, v_request_id
                FROM net.http_post(
                    url := v_endpoint, 
                    body := v_payload, 
                    headers := jsonb_build_object('Content-Type', 'application/json')
                ) AS result;
                
                RAISE LOG 'Notification sent. Request ID: %, Status: %, Response: %', v_request_id, v_response_status, v_response_body;
                
                IF v_response_status < 200 OR v_response_status >= 300 THEN
                    RAISE EXCEPTION 'HTTP request failed with status %', v_response_status;
                END IF;
            EXCEPTION
                WHEN OTHERS THEN
                    RAISE LOG 'Error sending notification: %', SQLERRM;
            END;
        ELSE
            RAISE LOG 'pg_net extension not available - skipping HTTP notification for expiring key %', NEW.id;
        END IF;
        
        -- Insert into audit_log
        INSERT INTO keyhippo.audit_log (action, table_name, data)
        VALUES ('expiring_key', TG_TABLE_NAME, v_payload);
        
        RAISE LOG 'Audit log entry created for expiring key %', NEW.id;
    ELSE
        RAISE LOG 'Key % is not expiring soon, no notification sent', NEW.id;
    END IF;
    
    RETURN NEW;
END;
$$;

-- Create trigger for key expiry notifications (idempotent)
DROP TRIGGER IF EXISTS keyhippo_notify_expiring_key_trigger ON keyhippo.api_key_metadata;
CREATE TRIGGER keyhippo_notify_expiring_key_trigger
    BEFORE UPDATE OF expires_at ON keyhippo.api_key_metadata
    FOR EACH ROW
    EXECUTE FUNCTION keyhippo.notify_expiring_key();

-- Function to update expiring keys (for periodic checking)
CREATE OR REPLACE FUNCTION keyhippo.update_expiring_keys()
    RETURNS VOID
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
BEGIN
    -- Update expires_at for keys that are about to expire
    UPDATE keyhippo.api_key_metadata
    SET expires_at = expires_at
    WHERE expires_at <= NOW() + INTERVAL '1 day'
    AND is_revoked = FALSE;
END;
$$;

-- Function to send initial installation notification
CREATE OR REPLACE FUNCTION keyhippo_internal.send_installation_notification()
    RETURNS VOID
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = keyhippo_internal
    AS $$
DECLARE
    v_installation_uuid uuid;
    v_should_send boolean;
BEGIN
    -- Get installation UUID from config
    SELECT value::uuid INTO v_installation_uuid
    FROM keyhippo_internal.config
    WHERE key = 'installation_uuid';
    
    -- Check if we should send the notification
    SELECT value::boolean INTO v_should_send
    FROM keyhippo_internal.config
    WHERE key = 'send_installation_notification';
    
    IF v_should_send THEN
        -- Update the config to prevent future notifications
        UPDATE keyhippo_internal.config
        SET value = 'false'
        WHERE key = 'send_installation_notification';
    END IF;
END;
$$;

-- HTTP audit notification function (full version with pg_net)
CREATE OR REPLACE FUNCTION keyhippo_internal.notify_audit_change()
    RETURNS TRIGGER
    AS $$
DECLARE
    v_payload jsonb;
    v_request_id bigint;
    v_endpoint text;
    v_installation_uuid uuid;
    v_enable_http_logging boolean;
BEGIN
    SELECT value::boolean INTO v_enable_http_logging
    FROM keyhippo_internal.config
    WHERE key = 'enable_http_logging';
    
    -- Only proceed if HTTP logging is enabled
    IF v_enable_http_logging THEN
        -- Get the endpoint and configuration from the config table
        SELECT value INTO v_endpoint
        FROM keyhippo_internal.config
        WHERE key = 'audit_log_endpoint';
        
        SELECT value::uuid INTO v_installation_uuid
        FROM keyhippo_internal.config
        WHERE key = 'installation_uuid';
        
        -- Prepare the payload
        v_payload = jsonb_build_object(
            'id', NEW.id, 
            'timestamp', NEW.timestamp, 
            'action', NEW.action, 
            'table_name', NEW.table_name, 
            'user_id', NEW.user_id, 
            'function_name', NEW.function_name, 
            'data', NEW.data, 
            'installation_uuid', v_installation_uuid
        );
        
        -- Make the HTTP request if pg_net is available
        IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'http_post' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'net')) THEN
            SELECT net.http_post(v_endpoint, v_payload, headers := '{"Content-Type": "application/json"}'::jsonb) 
            INTO v_request_id;
            
            -- Log the request_id (optional, for debugging)
            RAISE NOTICE 'HTTP Request ID: %', v_request_id;
        ELSE
            RAISE NOTICE 'pg_net extension not available - skipping HTTP notification';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$
LANGUAGE plpgsql
SET search_path = pg_temp
SECURITY DEFINER;

-- Function to enable the audit_log_notify trigger
CREATE OR REPLACE FUNCTION keyhippo_internal.enable_audit_log_notify()
    RETURNS VOID
    LANGUAGE plpgsql
    SET search_path = pg_temp
    SECURITY DEFINER
    AS $$
BEGIN
    -- Create the trigger
    CREATE OR REPLACE TRIGGER keyhippo_audit_log_notify
        AFTER INSERT ON keyhippo.audit_log
        FOR EACH ROW
        EXECUTE FUNCTION keyhippo_internal.notify_audit_change();
    
    -- Update the config to enable HTTP logging
    UPDATE keyhippo_internal.config
    SET value = 'true'
    WHERE key = 'enable_http_logging';
    
    -- If the config doesn't exist, insert it
    INSERT INTO keyhippo_internal.config (key, value, description)
    VALUES ('enable_http_logging', 'true', 'Flag to enable/disable HTTP logging')
    ON CONFLICT (key) DO NOTHING;
END;
$$;

-- Function to disable the audit_log_notify trigger
CREATE OR REPLACE FUNCTION keyhippo_internal.disable_audit_log_notify()
    RETURNS VOID
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
BEGIN
    -- Drop the trigger if it exists
    DROP TRIGGER IF EXISTS keyhippo_audit_log_notify ON keyhippo.audit_log;
    
    -- Update the config to disable HTTP logging
    UPDATE keyhippo_internal.config
    SET value = 'false'
    WHERE key = 'enable_http_logging';
    
    -- If the config doesn't exist, insert it
    INSERT INTO keyhippo_internal.config (key, value, description)
    VALUES ('enable_http_logging', 'false', 'Flag to enable/disable HTTP logging')
    ON CONFLICT (key) DO NOTHING;
END;
$$;

-- Authorization helper function (original version)
CREATE OR REPLACE FUNCTION keyhippo.is_authorized(target_resource regclass, required_permission text)
    RETURNS boolean
    AS $$
DECLARE
    v_user_id uuid;
    v_user_id_text text;
    v_is_authorized boolean;
BEGIN
    -- Get the current user ID from the JWT claim
    v_user_id_text := current_setting('request.jwt.claim.sub', TRUE);
    
    -- If no user ID is found or it's an empty string, return false
    IF v_user_id_text IS NULL OR v_user_id_text = '' THEN
        RETURN FALSE;
    END IF;
    
    -- Try to cast the user ID to UUID
    BEGIN
        v_user_id := v_user_id_text::uuid;
    EXCEPTION
        WHEN invalid_text_representation THEN
            -- If casting fails, return false
            RETURN FALSE;
    END;
    
    -- Check if the user has the required permission
    SELECT EXISTS (
        SELECT 1
        FROM keyhippo_rbac.user_group_roles ugr
        JOIN keyhippo_rbac.role_permissions rp ON ugr.role_id = rp.role_id
        JOIN keyhippo_rbac.permissions p ON rp.permission_id = p.id
        WHERE ugr.user_id = v_user_id
        AND p.name = required_permission::keyhippo.app_permission
    ) INTO v_is_authorized;
    
    RETURN v_is_authorized;
END;
$$
LANGUAGE plpgsql
SET search_path = pg_temp
SECURITY DEFINER;

-- PostgREST request checking function
CREATE OR REPLACE FUNCTION keyhippo.check_request()
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_temp
    AS $$
DECLARE
    ctx record;
BEGIN
    IF CURRENT_ROLE <> 'anon' THEN
        -- If not using the anon role, allow the request to pass
        RETURN;
    END IF;
    
    -- Check if the provided API key is valid
    SELECT * INTO ctx
    FROM keyhippo.current_user_context();
    
    IF ctx.user_id IS NULL THEN
        -- No valid API key found, raise an error
        RAISE EXCEPTION 'No registered API key found in x-api-key header.';
    END IF;
END;
$$;

-- Initialization function
CREATE OR REPLACE FUNCTION keyhippo.initialize_keyhippo()
    RETURNS VOID
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = keyhippo, keyhippo_internal, keyhippo_rbac, public
    AS $$
DECLARE
    admin_group_id uuid;
    admin_role_id uuid;
    installation_uuid uuid;
    user_group_id uuid;
    user_role_id uuid;
BEGIN
    -- Add configurations for key expiry notifications
    INSERT INTO keyhippo_internal.config (key, value, description)
    VALUES 
        ('key_expiry_notification_hours', '72', 'Number of hours before key expiry to send notification'),
        ('enable_key_expiry_notifications', 'true', 'Flag to enable/disable key expiry notifications')
    ON CONFLICT (key) DO UPDATE SET
        value = EXCLUDED.value, 
        description = EXCLUDED.description;
    
    -- Upsert the default value for the audit log endpoint
    INSERT INTO keyhippo_internal.config (key, value, description)
    VALUES ('audit_log_endpoint', 'https://app.keyhippo.com/api/ingest', 'Endpoint for sending audit log notifications')
    ON CONFLICT (key) DO UPDATE SET
        value = EXCLUDED.value, 
        description = EXCLUDED.description;
    
    -- Generate and store installation UUID
    installation_uuid := gen_random_uuid();
    INSERT INTO keyhippo_internal.config (key, value, description)
    VALUES ('installation_uuid', installation_uuid::text, 'Unique identifier for this KeyHippo installation')
    ON CONFLICT (key) DO UPDATE SET
        value = EXCLUDED.value, 
        description = EXCLUDED.description;
    
    -- Set HTTP logging to false by default
    INSERT INTO keyhippo_internal.config (key, value, description)
    VALUES ('enable_http_logging', 'false', 'Flag to enable/disable HTTP logging')
    ON CONFLICT (key) DO UPDATE SET
        value = EXCLUDED.value, 
        description = EXCLUDED.description;
    
    -- Create default groups
    INSERT INTO keyhippo_rbac.groups (name, description)
    VALUES 
        ('Admin Group', 'Group for administrators'),
        ('User Group', 'Group for regular users')
    ON CONFLICT (name) DO NOTHING;
    
    -- Fetch group IDs
    SELECT id INTO admin_group_id
    FROM keyhippo_rbac.groups
    WHERE name = 'Admin Group';
    
    SELECT id INTO user_group_id
    FROM keyhippo_rbac.groups
    WHERE name = 'User Group';
    
    -- Create default roles
    INSERT INTO keyhippo_rbac.roles (name, description, group_id, role_type)
    VALUES 
        ('Admin', 'Administrator role', admin_group_id, 'admin'),
        ('User', 'Regular user role', user_group_id, 'user')
    ON CONFLICT (name, group_id) DO NOTHING;
    
    -- Fetch role IDs
    SELECT id INTO admin_role_id
    FROM keyhippo_rbac.roles
    WHERE name = 'Admin' AND group_id = admin_group_id;
    
    SELECT id INTO user_role_id
    FROM keyhippo_rbac.roles
    WHERE name = 'User' AND group_id = user_group_id;
    
    -- Create default permissions
    INSERT INTO keyhippo_rbac.permissions (name, description)
    VALUES 
        ('manage_groups', 'Manage groups'),
        ('manage_roles', 'Manage roles'),
        ('manage_permissions', 'Manage permissions'),
        ('manage_scopes', 'Manage scopes'),
        ('manage_api_keys', 'Manage API keys'),
        ('manage_user_attributes', 'Manage user attributes')
    ON CONFLICT (name) DO NOTHING;
    
    -- Assign all permissions to the Admin role
    INSERT INTO keyhippo_rbac.role_permissions (role_id, permission_id)
    SELECT admin_role_id, id
    FROM keyhippo_rbac.permissions
    ON CONFLICT (role_id, permission_id) DO NOTHING;
    
    -- Assign manage_api_keys permission to the User role
    INSERT INTO keyhippo_rbac.role_permissions (role_id, permission_id)
    SELECT user_role_id, id
    FROM keyhippo_rbac.permissions
    WHERE name = 'manage_api_keys'
    ON CONFLICT (role_id, permission_id) DO NOTHING;
    
    -- Create a default scope
    INSERT INTO keyhippo.scopes (name, description)
    VALUES ('default', 'Default scope for API keys')
    ON CONFLICT (name) DO NOTHING;
    
    -- Set up the send_installation_notification config if it doesn't exist
    INSERT INTO keyhippo_internal.config (key, value, description)
    VALUES ('send_installation_notification', 'true', 'Flag to send initial installation notification')
    ON CONFLICT (key) DO NOTHING;
    
    -- Send the installation notification only if the config is set to true
    IF (SELECT value::boolean FROM keyhippo_internal.config WHERE key = 'send_installation_notification') THEN
        PERFORM keyhippo_internal.send_installation_notification();
    END IF;
END;
$$;

-- Function to initialize KeyHippo for an existing project
CREATE OR REPLACE FUNCTION keyhippo.initialize_existing_project()
    RETURNS VOID
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = keyhippo, keyhippo_rbac, public
    AS $$
DECLARE
    user_record RECORD;
    user_group_id uuid;
    user_role_id uuid;
BEGIN
    -- Initialize KeyHippo
    PERFORM keyhippo.initialize_keyhippo();
    
    -- Get the User Group and Role IDs
    SELECT id INTO user_group_id
    FROM keyhippo_rbac.groups
    WHERE name = 'User Group';
    
    SELECT id INTO user_role_id
    FROM keyhippo_rbac.roles
    WHERE name = 'User' AND group_id = user_group_id;
    
    -- Assign the default role to all existing users
    FOR user_record IN SELECT id FROM auth.users LOOP
        INSERT INTO keyhippo_rbac.user_group_roles (user_id, group_id, role_id)
        VALUES (user_record.id, user_group_id, user_role_id)
        ON CONFLICT (user_id, group_id, role_id) DO NOTHING;
    END LOOP;
END;
$$;

-- Schedule cron job for key expiry checking if pg_cron is available
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'schedule' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'cron')) THEN
        PERFORM cron.schedule('0 * * * *', $cron$
            SELECT keyhippo.update_expiring_keys();
        $cron$);
        RAISE NOTICE 'Scheduled hourly key expiry check with pg_cron';
    ELSE
        RAISE NOTICE 'pg_cron extension not available - key expiry checking must be done manually or with external scheduler';
    END IF;
END $$;

-- Run the initialization function
SELECT keyhippo.initialize_keyhippo();

COMMIT;