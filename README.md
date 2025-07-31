# Flattened Profiles - SQL Database Operations

This repository contains SQL procedures and migrations for automatically flattening and synchronizing profile data from a JSONB `public_profiles` table to a structured `flattened_profiles` table in Supabase (PostgreSQL).

## Overview

The system automatically:
- Watches the `public_profiles` table for INSERT, UPDATE, and DELETE operations
- Extracts and flattens complex JSONB profile data into structured columns
- Maintains synchronized flattened data for improved query performance
- Provides full-text search capabilities on flattened data

## Table Structure

### Source Table: `public_profiles`
Expected structure:
```sql
CREATE TABLE public_profiles (
    id TEXT PRIMARY KEY,
    profile JSONB
);
```

### Target Table: `flattened_profiles`
Structured table with extracted and computed fields:
```sql
CREATE TABLE flattened_profiles (
    search_text tsvector DEFAULT to_tsvector('english'::regconfig, COALESCE((full_jsonb)::text, ''::text)),
    original_id text UNIQUE,
    full_name text,
    current_title text,
    location text,
    about_me text,
    linkedin text,
    gender text,
    skills text,
    current_company text,
    current_title_from_workexp text,
    past_experience text,
    full_jsonb jsonb
);
```

## Installation & Setup

### 1. Prerequisites
- Supabase project with PostgreSQL database
- `public_profiles` table with columns `id` and `profile` (JSONB)
- `flattened_profiles` table already exists (as shown above)
- Appropriate database permissions for creating functions and triggers

### 2. Setup Instructions

Since your `flattened_profiles` table already exists, **skip Migration 001** and proceed with:

#### Step A: Create the Flattening Function
Run `migrations/002_create_flatten_profile_function.sql` in Supabase SQL Editor

#### Step B: Create the Sync Trigger  
Run `migrations/003_create_sync_trigger.sql` in Supabase SQL Editor

#### Step C: Enable the Trigger
```sql
SELECT create_public_profiles_sync_trigger();
```

### 3. Verify Installation
Check that the trigger is active:
```sql
SELECT 
    trigger_name, 
    event_manipulation, 
    action_timing
FROM information_schema.triggers 
WHERE trigger_name = 'sync_flattened_profiles_trigger';
```

### 4. Test the System
Insert a test profile:
```sql
INSERT INTO public_profiles (id, profile) VALUES (
    'test_profile_001',
    '{
        "name": "Jane Smith",
        "headline": "Product Manager",
        "location": "New York, NY",
        "summary": "Experienced PM with 8+ years in tech",
        "linkedin": "https://linkedin.com/in/janesmith",
        "gender": "Female",
        "skills": ["Product Strategy", "User Research", "Agile"],
        "work_experience": [
            {
                "company": "BigTech Corp",
                "title": "Senior Product Manager", 
                "start_date": "2021-03",
                "end_date": "current"
            }
        ]
    }'::jsonb
);
```

Check if it was flattened:
```sql
SELECT original_id, full_name, current_company, skills
FROM flattened_profiles 
WHERE original_id = 'test_profile_001';
```

## Data Flow

```
public_profiles (id, profile JSONB) → [Trigger] → flatten_profile_data() → flattened_profiles (Structured)
```

1. **INSERT/UPDATE**: New or changed profiles are automatically flattened and upserted
2. **DELETE**: Corresponding flattened records are removed
3. **Search Text**: Full-text search vectors are automatically maintained

## Expected JSONB Structure

The flattening function expects profile data in this format:

```json
{
  "name": "John Doe",
  "email": "john@example.com",
  "phone": "+1-555-0123",
  "linkedin": "https://linkedin.com/in/johndoe",
  "location": "San Francisco, CA",
  "headline": "Senior Software Engineer",
  "summary": "Experienced developer...",
  "skills": ["JavaScript", "Python", "React"],
  "technologies": ["Node.js", "PostgreSQL", "Docker"],
  "programming_languages": ["JavaScript", "Python", "Go"],
  "work_experience": [
    {
      "company": "Tech Corp",
      "title": "Senior Software Engineer",
      "start_date": "2022-01",
      "end_date": "current",
      "industry": "Technology",
      "location": "San Francisco, CA"
    }
  ],
  "education": [
    {
      "school": "University of Technology",
      "degree": "Bachelor of Science",
      "field": "Computer Science",
      "start_date": "2018",
      "end_date": "2022"
    }
  ],
  "certifications": [
    {
      "name": "AWS Certified Solutions Architect",
      "issuer": "Amazon",
      "date": "2023-06"
    }
  ]
}
```

## Key Features

### 1. Intelligent Data Extraction
- **Field mapping**: Maps JSONB fields to structured columns
- **Skills handling**: Converts arrays to comma-separated strings  
- **Work experience parsing**: Extracts current job and formats past experience
- **Flexible data types**: Handles both array and string skill formats

### 2. Current Position Detection
- Identifies current employment from work experience array
- Handles "current", "present", "ongoing" end dates
- Extracts company and title information for current employer
- Fallback to headline field if no current job found

### 3. Full-Text Search
- Automatic search text vector generation from full JSONB
- Optimized for PostgreSQL full-text search
- Supports complex search queries

### 4. Error Handling
- Graceful handling of malformed data
- Warning logs for failed extractions
- Original operations continue even if flattening fails
- Data validation and completeness checks

## Usage Examples

### Query Flattened Data
```sql
-- Find profiles by company
SELECT full_name, current_title, current_company
FROM flattened_profiles 
WHERE current_company ILIKE '%google%';

-- Search by skills (comma-separated string)
SELECT full_name, current_company, skills
FROM flattened_profiles 
WHERE skills ILIKE '%JavaScript%';

-- Full-text search
SELECT full_name, current_title, current_company
FROM flattened_profiles 
WHERE search_text @@ plainto_tsquery('software engineer postgresql');

-- Location-based search
SELECT full_name, current_title, location
FROM flattened_profiles 
WHERE location ILIKE '%New York%';
```

### Manual Operations
```sql
-- Manually sync a specific profile  
SELECT * FROM flatten_profile_data(
    (SELECT profile FROM public_profiles WHERE id = 'profile_123'),
    'profile_123'
);

-- Bulk migrate existing data (use the bulk_migration.sql script)
INSERT INTO flattened_profiles (
    original_id, full_name, current_title, location, about_me, 
    linkedin, gender, skills, current_company, current_title_from_workexp, 
    past_experience, full_jsonb
)
SELECT * FROM (
    SELECT DISTINCT ON (original_id) *
    FROM (
        SELECT * FROM flatten_profile_data(
            pp.profile, 
            COALESCE(pp.id::TEXT, pp.profile->>'id', pp.profile->>'original_id')
        )
        FROM public_profiles pp
        WHERE pp.profile IS NOT NULL 
        AND pp.profile != '{}'::jsonb
    ) flattened_data
    WHERE original_id IS NOT NULL
) unique_profiles
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
```

## Monitoring & Maintenance

### Check Sync Status
```sql
-- Compare counts
SELECT 
    (SELECT COUNT(*) FROM public_profiles WHERE profile IS NOT NULL) as source_count,
    (SELECT COUNT(*) FROM flattened_profiles) as flattened_count;

-- Check data completeness
SELECT 
    COUNT(*) as total_profiles,
    COUNT(*) FILTER (WHERE full_name IS NOT NULL) as with_names,
    COUNT(*) FILTER (WHERE current_company IS NOT NULL) as with_companies,
    COUNT(*) FILTER (WHERE skills IS NOT NULL AND skills != '') as with_skills
FROM flattened_profiles;
```

### Performance Optimization
```sql
-- Analyze table statistics
ANALYZE flattened_profiles;

-- Reindex search text if needed
REINDEX INDEX idx_flattened_profiles_search;
```

## Troubleshooting

### Common Issues

1. **Trigger not firing**: Ensure `public_profiles` table exists and trigger is created
2. **Missing original IDs**: Check that profiles have `id` field in table or JSONB
3. **Column mismatch errors**: Verify table has correct column names (`profile`, not `profile_data`)
4. **Performance issues**: Monitor search_text index usage for large datasets

### Debug Mode
Enable detailed logging:
```sql
SET log_min_messages = 'NOTICE';
```

### Validate Setup
Run data validation queries from `scripts/data_validation.sql` to check system health.

## Utility Scripts

See `scripts/` directory for:
- Bulk data migration scripts
- Data validation queries  
- Performance monitoring queries
- Backup and restore procedures

## Contributing

When modifying the flattening logic:
1. Test with sample data first
2. Consider backwards compatibility
3. Update this README with any schema changes
4. Run the full test suite

## License

This project is part of the SMB profile ingestion system.