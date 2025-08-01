-- Fix Skills Index Error
-- Run this script to fix the B-tree index size limitation error

-- Drop the problematic B-tree index
DROP INDEX IF EXISTS idx_flattened_profiles_skills;

-- Create a GIN index instead for full-text search on skills
CREATE INDEX IF NOT EXISTS idx_flattened_profiles_skills 
ON flattened_profiles USING GIN(to_tsvector('english', COALESCE(skills, '')));

-- Verify the index was created
SELECT 
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_indexes 
WHERE tablename = 'flattened_profiles' 
AND indexname = 'idx_flattened_profiles_skills';

-- Test the new index with a skills search
EXPLAIN (ANALYZE, BUFFERS)
SELECT original_id, full_name, skills
FROM flattened_profiles 
WHERE to_tsvector('english', COALESCE(skills, '')) @@ plainto_tsquery('JavaScript')
LIMIT 10;

RAISE NOTICE 'Skills index fix complete! Use full-text search syntax for skills queries.';