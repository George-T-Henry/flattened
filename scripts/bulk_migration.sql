-- Bulk Migration Script
-- Use this to migrate all existing data from public_profiles to flattened_profiles

-- First, clear existing flattened data (optional)
-- TRUNCATE flattened_profiles;

-- Bulk insert all profiles
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
)
SELECT flattened.*
FROM (
    SELECT DISTINCT ON (original_id) *
    FROM (
        SELECT * FROM flatten_profile_data(
            pp.profile, 
            COALESCE(pp.id::TEXT, pp.profile->>'id', pp.profile->>'original_id')
        )
        FROM public_profiles pp
        WHERE pp.profile IS NOT NULL 
        AND pp.profile != '{}'::jsonb
        AND COALESCE(pp.id::TEXT, pp.profile->>'id', pp.profile->>'original_id') IS NOT NULL
    ) flattened_data
    WHERE original_id IS NOT NULL
) flattened
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

-- Show migration results and validation
DO $$
DECLARE
    source_count INTEGER;
    target_count INTEGER;
    failed_count INTEGER;
BEGIN
    -- Get counts
    SELECT COUNT(*) INTO source_count 
    FROM public_profiles 
    WHERE profile IS NOT NULL AND profile != '{}'::jsonb;
    
    SELECT COUNT(*) INTO target_count 
    FROM flattened_profiles;
    
    failed_count := source_count - target_count;
    
    -- Report results
    RAISE NOTICE 'Migration Results:';
    RAISE NOTICE '  Source profiles: %', source_count;
    RAISE NOTICE '  Migrated profiles: %', target_count;
    RAISE NOTICE '  Failed migrations: %', failed_count;
    
    IF failed_count > 0 THEN
        RAISE WARNING 'Some profiles failed to migrate. Check logs for details.';
    ELSE
        RAISE NOTICE 'All profiles migrated successfully!';
    END IF;
END $$;

-- Final validation query
SELECT 
    'Migration Complete' as status,
    COUNT(*) as profiles_migrated,
    COUNT(*) FILTER (WHERE full_name IS NOT NULL) as profiles_with_names,
    COUNT(*) FILTER (WHERE current_company IS NOT NULL) as profiles_with_companies
FROM flattened_profiles;