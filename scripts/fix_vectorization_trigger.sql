-- Fix Vectorization Trigger
-- This fixes the trigger_vectorization function to use 'original_id' instead of 'id'

CREATE OR REPLACE FUNCTION trigger_vectorization()
RETURNS TRIGGER AS $$
DECLARE
    job_id uuid;
BEGIN
    -- Insert a job into the vectorization queue
    INSERT INTO vectorization_queue (profile_id, status, created_at, updated_at)
    VALUES (NEW.original_id, 'pending', NOW(), NOW())
    RETURNING id INTO job_id;

    -- Log the trigger activation
    INSERT INTO vectorization_logs (job_id, message, created_at)
    VALUES (job_id, 'Vectorization job queued for profile: ' || NEW.original_id, NOW());

    -- Attempt to call the webhook/edge function immediately
    PERFORM pg_notify('vectorization_request', json_build_object(
        'profile_id', NEW.original_id,
        'job_id', job_id,
        'action', 'vectorize'
    )::text);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Verify the fix
SELECT 'Vectorization trigger fixed - now uses original_id column' as status;