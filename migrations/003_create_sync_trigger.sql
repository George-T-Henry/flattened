-- Migration: Create trigger to sync public_profiles to flattened_profiles
-- This trigger automatically flattens and syncs profile data when public_profiles changes

CREATE OR REPLACE FUNCTION sync_flattened_profiles()
RETURNS TRIGGER AS $$
DECLARE
    flattened_data RECORD;
    original_id_value TEXT;
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
        -- Flatten the profile data
        SELECT * INTO flattened_data 
        FROM flatten_profile_data(NEW.profile, original_id_value);
        
        -- Check if flattening returned data
        IF NOT FOUND OR flattened_data.original_id IS NULL THEN
            RAISE WARNING 'Flattening function returned no data for original ID %', original_id_value;
            RETURN NEW;
        END IF;
        
        -- Upsert into flattened_profiles table
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
            full_jsonb
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
            flattened_data.full_jsonb
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
            full_jsonb = EXCLUDED.full_jsonb;
        
        RAISE NOTICE 'Successfully synced flattened profile: % (%)', 
                     original_id_value, flattened_data.full_name;
                     
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Failed to sync flattened profile %: %', 
                      original_id_value, SQLERRM;
        -- Don't fail the original operation, just log the warning
    END;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create the trigger on public_profiles table
-- Note: This assumes public_profiles has columns 'id' and 'profile'
-- Adjust the trigger creation based on your actual table structure

CREATE OR REPLACE FUNCTION create_public_profiles_sync_trigger()
RETURNS void AS $$
BEGIN
    -- Drop existing trigger if it exists
    DROP TRIGGER IF EXISTS sync_flattened_profiles_trigger ON public_profiles;
    
    -- Create the trigger
    CREATE TRIGGER sync_flattened_profiles_trigger
        AFTER INSERT OR UPDATE OR DELETE ON public_profiles
        FOR EACH ROW
        EXECUTE FUNCTION sync_flattened_profiles();
        
    RAISE NOTICE 'Created sync trigger on public_profiles table';
    
EXCEPTION WHEN undefined_table THEN
    RAISE WARNING 'public_profiles table does not exist yet. Run this after creating public_profiles table.';
WHEN OTHERS THEN
    RAISE WARNING 'Failed to create trigger: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;

-- Uncomment the following line after public_profiles table exists:
-- SELECT create_public_profiles_sync_trigger();