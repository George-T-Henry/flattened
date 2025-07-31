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

-- Show migration results
SELECT 
    'Migration Complete' as status,
    COUNT(*) as profiles_migrated
FROM flattened_profiles;