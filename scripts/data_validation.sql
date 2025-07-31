-- Data Validation Queries
-- Use these queries to validate the flattened data and identify issues

-- 1. Compare record counts between source and target
SELECT 
    'Source vs Target Count' as check_name,
    (SELECT COUNT(*) FROM public_profiles WHERE profile_data IS NOT NULL) as source_count,
    (SELECT COUNT(*) FROM flattened_profiles) as target_count,
    (SELECT COUNT(*) FROM public_profiles WHERE profile_data IS NOT NULL) - 
    (SELECT COUNT(*) FROM flattened_profiles) as difference;

-- 2. Find profiles missing from flattened table
SELECT 
    'Missing from Flattened' as check_name,
    COUNT(*) as missing_count
FROM public_profiles pp
WHERE pp.profile_data IS NOT NULL 
AND pp.profile_data != '{}'::jsonb
AND COALESCE(pp.id::TEXT, pp.profile_data->>'id', pp.profile_data->>'original_id') NOT IN (
    SELECT original_id FROM flattened_profiles
);

-- 3. Show the actual missing profiles (limit 10)
SELECT 
    COALESCE(pp.id::TEXT, pp.profile_data->>'id', pp.profile_data->>'original_id') as missing_original_id,
    pp.profile_data->>'name' as profile_name
FROM public_profiles pp
WHERE pp.profile_data IS NOT NULL 
AND pp.profile_data != '{}'::jsonb
AND COALESCE(pp.id::TEXT, pp.profile_data->>'id', pp.profile_data->>'original_id') NOT IN (
    SELECT original_id FROM flattened_profiles
)
LIMIT 10;

-- 4. Check for profiles with null essential fields
SELECT 
    'Profiles with Missing Essential Data' as check_name,
    COUNT(*) as count
FROM flattened_profiles 
WHERE full_name IS NULL OR full_name = '';

-- 5. Show profiles with missing essential data
SELECT 
    original_id,
    full_name,
    current_company,
    total_years_experience
FROM flattened_profiles 
WHERE full_name IS NULL OR full_name = ''
LIMIT 10;

-- 6. Experience validation - negative or unrealistic values
SELECT 
    'Invalid Experience Values' as check_name,
    COUNT(*) as count
FROM flattened_profiles 
WHERE total_years_experience < 0 
OR total_years_experience > 60
OR years_at_current_company < 0
OR years_at_current_company > total_years_experience + 5;

-- 7. Show invalid experience profiles
SELECT 
    original_id,
    full_name,
    total_years_experience,
    years_at_current_company,
    current_company
FROM flattened_profiles 
WHERE total_years_experience < 0 
OR total_years_experience > 60
OR years_at_current_company < 0
OR years_at_current_company > total_years_experience + 5
LIMIT 10;

-- 8. Check for duplicate original IDs
SELECT 
    'Duplicate Original IDs' as check_name,
    COUNT(*) - COUNT(DISTINCT original_id) as duplicates
FROM flattened_profiles;

-- 9. Array field statistics
SELECT 
    'Array Field Statistics' as report_name,
    AVG(array_length(skills, 1)) as avg_skills_count,
    AVG(array_length(technologies, 1)) as avg_tech_count,
    AVG(array_length(previous_companies, 1)) as avg_prev_companies,
    AVG(array_length(job_titles, 1)) as avg_job_titles
FROM flattened_profiles
WHERE skills IS NOT NULL;

-- 10. Most common skills
SELECT 
    skill,
    COUNT(*) as frequency
FROM (
    SELECT unnest(skills) as skill 
    FROM flattened_profiles 
    WHERE skills IS NOT NULL
) skill_breakdown
GROUP BY skill
ORDER BY frequency DESC
LIMIT 20;

-- 11. Most common current companies
SELECT 
    current_company,
    COUNT(*) as employee_count
FROM flattened_profiles
WHERE current_company IS NOT NULL AND current_company != ''
GROUP BY current_company
ORDER BY employee_count DESC
LIMIT 20;

-- 12. Experience distribution
SELECT 
    CASE 
        WHEN total_years_experience < 2 THEN '0-1 years'
        WHEN total_years_experience < 5 THEN '2-4 years'
        WHEN total_years_experience < 10 THEN '5-9 years'
        WHEN total_years_experience < 15 THEN '10-14 years'
        WHEN total_years_experience < 20 THEN '15-19 years'
        ELSE '20+ years'
    END as experience_range,
    COUNT(*) as profile_count
FROM flattened_profiles
WHERE total_years_experience IS NOT NULL
GROUP BY experience_range
ORDER BY 
    CASE experience_range
        WHEN '0-1 years' THEN 1
        WHEN '2-4 years' THEN 2
        WHEN '5-9 years' THEN 3
        WHEN '10-14 years' THEN 4
        WHEN '15-19 years' THEN 5
        ELSE 6
    END;

-- 13. Recent updates check
SELECT 
    'Recent Updates' as check_name,
    COUNT(*) as profiles_updated_last_hour
FROM flattened_profiles
WHERE last_updated > NOW() - INTERVAL '1 hour';

-- 14. Search vector validation
SELECT 
    'Search Vector Status' as check_name,
    COUNT(*) as total_profiles,
    COUNT(*) FILTER (WHERE search_vector IS NOT NULL) as profiles_with_search_vector,
    COUNT(*) FILTER (WHERE search_vector IS NULL) as profiles_without_search_vector
FROM flattened_profiles;