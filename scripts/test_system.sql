-- Test System Script
-- Use this to test the flattened profiles system after applying fixes

-- 1. Test table creation (run this first if table doesn't exist)
\echo 'Testing table structure...'
\d flattened_profiles

-- 2. Test the flattening function with sample data
\echo 'Testing flatten_profile_data function...'
SELECT * FROM flatten_profile_data(
    '{
        "name": "Test User",
        "headline": "Software Engineer",
        "location": "San Francisco, CA",
        "summary": "Experienced developer with 5+ years",
        "linkedin": "https://linkedin.com/in/testuser",
        "gender": "Non-binary",
        "skills": ["JavaScript", "Python", "React"],
        "work_experience": [
            {
                "company": "Tech Corp",
                "title": "Senior Software Engineer",
                "start_date": "2021-01",
                "end_date": "current"
            },
            {
                "company": "StartupCo",
                "title": "Full Stack Developer",
                "start_date": "2019-01",
                "end_date": "2020-12"
            }
        ]
    }'::jsonb,
    'test_profile_001'
);

-- 3. Test trigger creation function
\echo 'Testing trigger creation...'
SELECT create_public_profiles_sync_trigger();

-- 4. Check trigger exists
\echo 'Verifying trigger exists...'
SELECT 
    trigger_name, 
    event_manipulation, 
    action_timing
FROM information_schema.triggers 
WHERE trigger_name = 'sync_flattened_profiles_trigger';

-- 5. Test search text trigger
\echo 'Testing search text trigger...'
INSERT INTO flattened_profiles (
    original_id, full_name, full_jsonb
) VALUES (
    'search_test_001', 
    'Search Test User',
    '{"name": "Search Test User", "skills": ["PostgreSQL", "Full-text search"]}'::jsonb
) ON CONFLICT (original_id) DO UPDATE SET
    full_name = EXCLUDED.full_name,
    full_jsonb = EXCLUDED.full_jsonb;

-- Verify search text was generated
SELECT 
    original_id, 
    full_name, 
    search_text IS NOT NULL as has_search_text
FROM flattened_profiles 
WHERE original_id = 'search_test_001';

-- 6. Test search functionality
\echo 'Testing full-text search...'
SELECT 
    original_id, 
    full_name
FROM flattened_profiles 
WHERE search_text @@ plainto_tsquery('PostgreSQL search')
LIMIT 5;

-- 7. Performance test
\echo 'Testing query performance...'
EXPLAIN (ANALYZE, BUFFERS) 
SELECT original_id, full_name, current_company 
FROM flattened_profiles 
WHERE search_text @@ plainto_tsquery('software engineer')
LIMIT 10;

-- 8. Clean up test data
\echo 'Cleaning up test data...'
DELETE FROM flattened_profiles WHERE original_id = 'search_test_001';

\echo 'System test complete!'