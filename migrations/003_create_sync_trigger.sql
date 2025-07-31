-- Migration: Create trigger to sync public_profiles to flattened_profiles
-- This trigger automatically flattens and syncs profile data when public_profiles changes

CREATE OR REPLACE FUNCTION sync_flattened_profiles()
RETURNS TRIGGER AS $$
DECLARE
    flattened_data RECORD;
    profile_id_value TEXT;
BEGIN
    -- Handle DELETE operations
    IF TG_OP = 'DELETE' THEN
        -- Extract profile ID from OLD record
        profile_id_value := COALESCE(OLD.id::TEXT, (OLD.profile_data->>'id'), (OLD.profile_data->>'profile_id'));
        
        IF profile_id_value IS NOT NULL THEN
            DELETE FROM flattened_profiles 
            WHERE profile_id = profile_id_value;
            
            RAISE NOTICE 'Deleted flattened profile: %', profile_id_value;
        END IF;
        
        RETURN OLD;
    END IF;
    
    -- Handle INSERT and UPDATE operations
    -- Extract profile ID from NEW record
    profile_id_value := COALESCE(NEW.id::TEXT, (NEW.profile_data->>'id'), (NEW.profile_data->>'profile_id'));
    
    -- Skip if no profile ID can be determined
    IF profile_id_value IS NULL THEN
        RAISE WARNING 'Cannot determine profile ID for flattening, skipping sync';
        RETURN NEW;
    END IF;
    
    -- Skip if profile_data is NULL or empty
    IF NEW.profile_data IS NULL OR NEW.profile_data = '{}'::jsonb THEN
        RAISE WARNING 'Profile data is null or empty for profile ID %, skipping sync', profile_id_value;
        RETURN NEW;
    END IF;
    
    BEGIN
        -- Flatten the profile data
        SELECT * INTO flattened_data 
        FROM flatten_profile_data(NEW.profile_data, profile_id_value);
        
        -- Upsert into flattened_profiles table
        INSERT INTO flattened_profiles (
            profile_id,
            full_name,
            first_name,
            last_name,
            email,
            phone,
            linkedin_url,
            github_url,
            website_url,
            location,
            headline,
            summary,
            current_company,
            current_position,
            current_start_date,
            total_years_experience,
            years_at_current_company,
            previous_companies,
            job_titles,
            industries,
            skills,
            technologies,
            programming_languages,
            education_degrees,
            education_schools,
            education_fields,
            certifications,
            company_size,
            company_industry,
            company_location,
            profile_source,
            original_data,
            last_updated,
            created_at
        ) VALUES (
            flattened_data.profile_id,
            flattened_data.full_name,
            flattened_data.first_name,
            flattened_data.last_name,
            flattened_data.email,
            flattened_data.phone,
            flattened_data.linkedin_url,
            flattened_data.github_url,
            flattened_data.website_url,
            flattened_data.location,
            flattened_data.headline,
            flattened_data.summary,
            flattened_data.current_company,
            flattened_data.current_position,
            flattened_data.current_start_date,
            flattened_data.total_years_experience,
            flattened_data.years_at_current_company,
            flattened_data.previous_companies,
            flattened_data.job_titles,
            flattened_data.industries,
            flattened_data.skills,
            flattened_data.technologies,
            flattened_data.programming_languages,
            flattened_data.education_degrees,
            flattened_data.education_schools,
            flattened_data.education_fields,
            flattened_data.certifications,
            flattened_data.company_size,
            flattened_data.company_industry,
            flattened_data.company_location,
            flattened_data.profile_source,
            flattened_data.original_data,
            NOW(),
            CASE WHEN TG_OP = 'INSERT' THEN NOW() ELSE (SELECT created_at FROM flattened_profiles WHERE profile_id = flattened_data.profile_id) END
        )
        ON CONFLICT (profile_id) DO UPDATE SET
            full_name = EXCLUDED.full_name,
            first_name = EXCLUDED.first_name,
            last_name = EXCLUDED.last_name,
            email = EXCLUDED.email,
            phone = EXCLUDED.phone,
            linkedin_url = EXCLUDED.linkedin_url,
            github_url = EXCLUDED.github_url,
            website_url = EXCLUDED.website_url,
            location = EXCLUDED.location,
            headline = EXCLUDED.headline,
            summary = EXCLUDED.summary,
            current_company = EXCLUDED.current_company,
            current_position = EXCLUDED.current_position,
            current_start_date = EXCLUDED.current_start_date,
            total_years_experience = EXCLUDED.total_years_experience,
            years_at_current_company = EXCLUDED.years_at_current_company,
            previous_companies = EXCLUDED.previous_companies,
            job_titles = EXCLUDED.job_titles,
            industries = EXCLUDED.industries,
            skills = EXCLUDED.skills,
            technologies = EXCLUDED.technologies,
            programming_languages = EXCLUDED.programming_languages,
            education_degrees = EXCLUDED.education_degrees,
            education_schools = EXCLUDED.education_schools,
            education_fields = EXCLUDED.education_fields,
            certifications = EXCLUDED.certifications,
            company_size = EXCLUDED.company_size,
            company_industry = EXCLUDED.company_industry,
            company_location = EXCLUDED.company_location,
            profile_source = EXCLUDED.profile_source,
            original_data = EXCLUDED.original_data,
            last_updated = NOW();
        
        RAISE NOTICE 'Successfully synced flattened profile: % (%, %)', 
                     profile_id_value, flattened_data.full_name, TG_OP;
                     
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Failed to sync flattened profile % (%, %): %', 
                      profile_id_value, flattened_data.full_name, TG_OP, SQLERRM;
        -- Don't fail the original operation, just log the warning
    END;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create the trigger on public_profiles table
-- Note: This assumes public_profiles has columns 'id' and 'profile_data'
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