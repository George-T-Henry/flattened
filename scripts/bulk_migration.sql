-- Bulk Migration Script
-- Use this to migrate all existing data from public_profiles to flattened_profiles

-- First, clear existing flattened data (optional)
-- TRUNCATE flattened_profiles;

-- Bulk insert all profiles
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
    created_at,
    last_updated
)
SELECT 
    flattened.*,
    NOW() as created_at,
    NOW() as last_updated
FROM (
    SELECT DISTINCT ON (profile_id) *
    FROM (
        SELECT * FROM flatten_profile_data(
            pp.profile_data, 
            COALESCE(pp.id::TEXT, pp.profile_data->>'id', pp.profile_data->>'profile_id')
        )
        FROM public_profiles pp
        WHERE pp.profile_data IS NOT NULL 
        AND pp.profile_data != '{}'::jsonb
        AND COALESCE(pp.id::TEXT, pp.profile_data->>'id', pp.profile_data->>'profile_id') IS NOT NULL
    ) flattened_data
    WHERE profile_id IS NOT NULL
) flattened
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

-- Show migration results
SELECT 
    'Migration Complete' as status,
    COUNT(*) as profiles_migrated
FROM flattened_profiles;