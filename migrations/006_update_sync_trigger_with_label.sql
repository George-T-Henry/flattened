-- Migration: Update sync trigger to handle label field
-- This updates the trigger function to pass label data from public_profiles to flattened_profiles

CREATE OR REPLACE FUNCTION sync_flattened_profiles()
RETURNS TRIGGER AS $$
DECLARE
    flattened_data RECORD;
    original_id_value TEXT;
    label_value TEXT;
BEGIN
    -- Handle DELETE operations
    IF TG_OP = 'DELETE' THEN
        -- Extract original ID from OLD record
        original_id_value := COALESCE(OLD.id::TEXT, (OLD.profile->>'id'), (OLD.profile->>'original_id'));
        
        IF original_id_value IS NOT NULL THEN
            DELETE FROM flattened_profiles 
            WHERE original_id = original_id_value;
            
            RAISE NOTICE 'Deleted flattened profile: %', original_id_value;
        END IF;
        
        RETURN OLD;
    END IF;
    
    -- Handle INSERT and UPDATE operations
    -- Extract original ID from NEW record
    original_id_value := COALESCE(NEW.id::TEXT, (NEW.profile->>'id'), (NEW.profile->>'original_id'));
    
    -- Extract label from NEW record (assuming public_profiles now has a label column)
    label_value := NEW.label;
    
    -- Skip if no original ID can be determined
    IF original_id_value IS NULL THEN
        RAISE WARNING 'Cannot determine original ID for flattening, skipping sync';
        RETURN NEW;
    END IF;
    
    -- Skip if profile is NULL or empty
    IF NEW.profile IS NULL OR NEW.profile = '{}'::jsonb THEN
        RAISE WARNING 'Profile data is null or empty for original ID %, skipping sync', original_id_value;
        RETURN NEW;
    END IF;
    
    BEGIN
        -- Flatten the profile data with label
        SELECT * INTO flattened_data 
        FROM flatten_profile_data(NEW.profile, original_id_value, label_value);
        
        -- Check if flattening returned data
        IF NOT FOUND OR flattened_data.original_id IS NULL THEN
            RAISE WARNING 'Flattening function returned no data for original ID %', original_id_value;
            RETURN NEW;
        END IF;
        
        -- Upsert into flattened_profiles table (now including label)
        INSERT INTO flattened_profiles (
            original_id,
            full_name,
            current_title,
            location,
            about_me,
            linkedin,
            gender,
            skills,
            current_company,
            current_title_from_workexp,
            past_experience,
            full_jsonb,
            label
        ) VALUES (
            flattened_data.original_id,
            flattened_data.full_name,
            flattened_data.current_title,
            flattened_data.location,
            flattened_data.about_me,
            flattened_data.linkedin,
            flattened_data.gender,
            flattened_data.skills,
            flattened_data.current_company,
            flattened_data.current_title_from_workexp,
            flattened_data.past_experience,
            flattened_data.full_jsonb,
            flattened_data.label
        )
        ON CONFLICT (original_id) DO UPDATE SET
            full_name = EXCLUDED.full_name,
            current_title = EXCLUDED.current_title,
            location = EXCLUDED.location,
            about_me = EXCLUDED.about_me,
            linkedin = EXCLUDED.linkedin,
            gender = EXCLUDED.gender,
            skills = EXCLUDED.skills,
            current_company = EXCLUDED.current_company,
            current_title_from_workexp = EXCLUDED.current_title_from_workexp,
            past_experience = EXCLUDED.past_experience,
            full_jsonb = EXCLUDED.full_jsonb,
            label = EXCLUDED.label;
        
        RAISE NOTICE 'Successfully synced flattened profile: % (%) with label: %', 
                     original_id_value, flattened_data.full_name, COALESCE(label_value, 'none');
                     
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Failed to sync flattened profile %: %', 
                      original_id_value, SQLERRM;
        -- Don't fail the original operation, just log the warning
    END;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- The trigger creation function remains the same as it references the updated function above
-- Run this to update the existing trigger:
-- SELECT create_public_profiles_sync_trigger();