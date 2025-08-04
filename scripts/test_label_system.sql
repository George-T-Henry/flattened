-- Test script for the label system
-- This script tests the updated flattening system with label support

-- First, let's create some test data with labels
DO $$
BEGIN
    RAISE NOTICE 'Testing label system for flattened profiles...';
END $$;

-- Test 1: Insert a profile with a label
INSERT INTO public_profiles (id, profile, label) VALUES (
    'test_label_001',
    '{
        "name": "Sarah Johnson",
        "headline": "Senior Data Scientist",
        "location": "Seattle, WA",
        "summary": "ML Engineer with 6+ years in healthcare analytics",
        "linkedin": "https://linkedin.com/in/sarahjohnson",
        "gender": "Female",
        "skills": ["Python", "Machine Learning", "SQL", "TensorFlow"],
        "work_experience": [
            {
                "company": "HealthTech Solutions",
                "title": "Senior Data Scientist", 
                "start_date": "2022-01",
                "end_date": "current"
            },
            {
                "company": "DataCorp",
                "title": "Data Analyst", 
                "start_date": "2018-06",
                "end_date": "2021-12"
            }
        ]
    }'::jsonb,
    'Q4 2024 Healthcare Candidates'
);

-- Test 2: Insert a profile without a label (should handle NULL)
INSERT INTO public_profiles (id, profile, label) VALUES (
    'test_label_002',
    '{
        "name": "Mike Chen",
        "headline": "DevOps Engineer",
        "location": "San Francisco, CA",
        "summary": "Cloud infrastructure specialist",
        "skills": ["AWS", "Docker", "Kubernetes", "Python"],
        "work_experience": [
            {
                "company": "CloudFirst Inc",
                "title": "Senior DevOps Engineer", 
                "start_date": "2021-03",
                "end_date": "present"
            }
        ]
    }'::jsonb,
    NULL
);

-- Test 3: Insert a profile with a different label
INSERT INTO public_profiles (id, profile, label) VALUES (
    'test_label_003',
    '{
        "name": "Lisa Rodriguez",
        "headline": "Frontend Developer",
        "location": "Austin, TX",
        "summary": "React specialist with design background",
        "skills": ["React", "TypeScript", "CSS", "Figma"],
        "work_experience": [
            {
                "company": "StartupXYZ",
                "title": "Senior Frontend Developer", 
                "start_date": "2023-01",
                "end_date": "current"
            }
        ]
    }'::jsonb,
    'Tech Startup Candidates'
);

-- Wait a moment for triggers to process
SELECT pg_sleep(1);

-- Verify the data was flattened with labels
SELECT 
    original_id,
    full_name,
    current_company,
    skills,
    label,
    CASE 
        WHEN label IS NULL THEN 'No Label'
        ELSE 'Has Label: ' || label
    END as label_status
FROM flattened_profiles 
WHERE original_id IN ('test_label_001', 'test_label_002', 'test_label_003')
ORDER BY original_id;

-- Test label-based queries
SELECT 
    COUNT(*) as total_profiles,
    COUNT(*) FILTER (WHERE label IS NOT NULL) as profiles_with_labels,
    COUNT(*) FILTER (WHERE label IS NULL) as profiles_without_labels
FROM flattened_profiles 
WHERE original_id LIKE 'test_label_%';

-- Test querying by specific labels
SELECT 
    original_id,
    full_name,
    current_title,
    label
FROM flattened_profiles 
WHERE label = 'Q4 2024 Healthcare Candidates';

-- Test updating a profile's label
UPDATE public_profiles 
SET label = 'Updated Tech Candidates' 
WHERE id = 'test_label_002';

-- Wait for trigger
SELECT pg_sleep(1);

-- Verify the label was updated in flattened_profiles
SELECT 
    original_id,
    full_name,
    label
FROM flattened_profiles 
WHERE original_id = 'test_label_002';

-- Clean up test data
DELETE FROM public_profiles WHERE id IN ('test_label_001', 'test_label_002', 'test_label_003');

DO $$
BEGIN
    RAISE NOTICE 'Label system testing completed successfully!';
END $$;