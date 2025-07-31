-- Data Validation Queries
-- Use these queries to validate the flattened data and identify issues

-- 1. Compare record counts between source and target
SELECT 
    'Source vs Target Count' as check_name,
    (SELECT COUNT(*) FROM public_profiles WHERE profile IS NOT NULL) as source_count,
    (SELECT COUNT(*) FROM flattened_profiles) as target_count,
    (SELECT COUNT(*) FROM public_profiles WHERE profile IS NOT NULL) - 
    (SELECT COUNT(*) FROM flattened_profiles) as difference;

-- 2. Find profiles missing from flattened table
SELECT 
    'Missing from Flattened' as check_name,
    COUNT(*) as missing_count
FROM public_profiles pp
WHERE pp.profile IS NOT NULL 
AND pp.profile != '{}'::jsonb
AND COALESCE(pp.id::TEXT, pp.profile->>'id', pp.profile->>'original_id') NOT IN (
    SELECT original_id FROM flattened_profiles
);

-- 3. Show the actual missing profiles (limit 10)
SELECT 
    COALESCE(pp.id::TEXT, pp.profile->>'id', pp.profile->>'original_id') as missing_original_id,
    pp.profile->>'name' as profile_name
FROM public_profiles pp
WHERE pp.profile IS NOT NULL 
AND pp.profile != '{}'::jsonb
AND COALESCE(pp.id::TEXT, pp.profile->>'id', pp.profile->>'original_id') NOT IN (
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

-- 6. Current job validation
SELECT 
    'Profiles with Current Job Info' as check_name,
    COUNT(*) FILTER (WHERE current_company IS NOT NULL) as with_current_company,
    COUNT(*) FILTER (WHERE current_title_from_workexp IS NOT NULL) as with_current_title,
    COUNT(*) as total_profiles
FROM flattened_profiles;

-- 7. Show profiles with work experience data
SELECT 
    original_id,
    full_name,
    current_company,
    current_title_from_workexp,
    CASE WHEN past_experience IS NOT NULL THEN 'Yes' ELSE 'No' END as has_past_experience
FROM flattened_profiles 
WHERE current_company IS NOT NULL OR past_experience IS NOT NULL
LIMIT 10;

-- 8. Check for duplicate original IDs
SELECT 
    'Duplicate Original IDs' as check_name,
    COUNT(*) - COUNT(DISTINCT original_id) as duplicates
FROM flattened_profiles;

-- 9. Skills analysis
SELECT 
    'Skills Statistics' as report_name,
    COUNT(*) FILTER (WHERE skills IS NOT NULL AND skills != '') as profiles_with_skills,
    COUNT(*) as total_profiles,
    ROUND(COUNT(*) FILTER (WHERE skills IS NOT NULL AND skills != '') * 100.0 / COUNT(*), 2) as percentage_with_skills
FROM flattened_profiles;

-- 10. Most common skills (from comma-separated strings)
SELECT 
    TRIM(skill) as skill,
    COUNT(*) as frequency
FROM (
    SELECT unnest(string_to_array(skills, ',')) as skill 
    FROM flattened_profiles 
    WHERE skills IS NOT NULL AND skills != ''
) skill_breakdown
WHERE TRIM(skill) != ''
GROUP BY TRIM(skill)
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

-- 12. Location distribution
SELECT 
    location,
    COUNT(*) as profile_count
FROM flattened_profiles
WHERE location IS NOT NULL AND location != ''
GROUP BY location
ORDER BY profile_count DESC
LIMIT 15;

-- 13. Search text validation
SELECT 
    'Search Text Status' as check_name,
    COUNT(*) as total_profiles,
    COUNT(*) FILTER (WHERE search_text IS NOT NULL) as profiles_with_search_text,
    COUNT(*) FILTER (WHERE search_text IS NULL) as profiles_without_search_text
FROM flattened_profiles;

-- 14. Data completeness overview
SELECT 
    'Data Completeness' as report_name,
    ROUND(COUNT(*) FILTER (WHERE full_name IS NOT NULL) * 100.0 / COUNT(*), 2) as pct_with_name,
    ROUND(COUNT(*) FILTER (WHERE current_title IS NOT NULL) * 100.0 / COUNT(*), 2) as pct_with_title,
    ROUND(COUNT(*) FILTER (WHERE location IS NOT NULL) * 100.0 / COUNT(*), 2) as pct_with_location,
    ROUND(COUNT(*) FILTER (WHERE about_me IS NOT NULL) * 100.0 / COUNT(*), 2) as pct_with_about_me,
    ROUND(COUNT(*) FILTER (WHERE linkedin IS NOT NULL) * 100.0 / COUNT(*), 2) as pct_with_linkedin,
    ROUND(COUNT(*) FILTER (WHERE skills IS NOT NULL AND skills != '') * 100.0 / COUNT(*), 2) as pct_with_skills
FROM flattened_profiles;