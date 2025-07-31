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
    profile_data JSONB,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

### Target Table: `flattened_profiles`
Structured table with extracted and computed fields:
- **Basic Info**: name, email, phone, social URLs, location
- **Professional**: current position, company, headline, summary
- **Experience**: total years, current tenure, previous companies, titles, industries
- **Skills**: skills, technologies, programming languages (arrays)
- **Education**: degrees, schools, fields of study (arrays)
- **Metadata**: search vector, timestamps, original JSONB data

## Installation & Setup

### 1. Prerequisites
- Supabase project with PostgreSQL database
- `public_profiles` table with JSONB profile data
- Appropriate database permissions for creating functions and triggers

### 2. Run Migrations
Execute the SQL files in order:

```bash
# 1. Create the flattened_profiles table and search functions
psql -f migrations/001_create_flattened_profiles_table.sql

# 2. Create the profile flattening function
psql -f migrations/002_create_flatten_profile_function.sql

# 3. Create the sync trigger
psql -f migrations/003_create_sync_trigger.sql
```

### 3. Enable the Trigger
After your `public_profiles` table exists, run:
```sql
SELECT create_public_profiles_sync_trigger();
```

### 4. Verify Installation
Check that the trigger is active:
```sql
SELECT 
    trigger_name, 
    event_manipulation, 
    action_timing,
    action_statement
FROM information_schema.triggers 
WHERE trigger_name = 'sync_flattened_profiles_trigger';
```

## Data Flow

```
public_profiles (JSONB) → [Trigger] → flatten_profile_data() → flattened_profiles (Structured)
```

1. **INSERT/UPDATE**: New or changed profiles are automatically flattened and upserted
2. **DELETE**: Corresponding flattened records are removed
3. **Search Vector**: Full-text search indexes are automatically maintained

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
- **Name parsing**: Automatically splits full names into first/last
- **Date handling**: Parses various date formats and handles "current" positions
- **Experience calculation**: Computes total years and current company tenure
- **Array deduplication**: Removes duplicate skills, companies, etc.

### 2. Current Position Detection
- Identifies current employment from work experience
- Handles "current", "present", "ongoing" end dates
- Extracts company information for current employer

### 3. Full-Text Search
- Automatic search vector generation
- Weighted search terms (names and companies weighted higher)
- Supports complex search queries

### 4. Error Handling
- Graceful handling of malformed data
- Warning logs for failed extractions
- Original operations continue even if flattening fails

## Usage Examples

### Query Flattened Data
```sql
-- Find profiles by company
SELECT full_name, current_position, total_years_experience
FROM flattened_profiles 
WHERE current_company ILIKE '%google%';

-- Search by skills
SELECT full_name, current_company, skills
FROM flattened_profiles 
WHERE 'JavaScript' = ANY(skills);

-- Full-text search
SELECT full_name, headline, current_company
FROM flattened_profiles 
WHERE search_vector @@ plainto_tsquery('software engineer postgresql');
```

### Manual Operations
```sql
-- Manually sync a specific profile
SELECT * FROM flatten_profile_data(
    (SELECT profile_data FROM public_profiles WHERE id = 'profile_123'),
    'profile_123'
);

-- Rebuild all flattened data
TRUNCATE flattened_profiles;
INSERT INTO flattened_profiles (
    profile_id, full_name, first_name, last_name, email, phone,
    linkedin_url, github_url, website_url, location, headline, summary,
    current_company, current_position, current_start_date,
    total_years_experience, years_at_current_company,
    previous_companies, job_titles, industries,
    skills, technologies, programming_languages,
    education_degrees, education_schools, education_fields,
    certifications, company_size, company_industry, company_location,
    profile_source, original_data
)
SELECT * FROM (
    SELECT DISTINCT ON (profile_id) *
    FROM (
        SELECT * FROM flatten_profile_data(
            pp.profile_data, 
            COALESCE(pp.id::TEXT, pp.profile_data->>'id', pp.profile_data->>'profile_id')
        )
        FROM public_profiles pp
        WHERE pp.profile_data IS NOT NULL 
        AND pp.profile_data != '{}'::jsonb
    ) flattened_data
    WHERE profile_id IS NOT NULL
) unique_profiles;
```

## Monitoring & Maintenance

### Check Sync Status
```sql
-- Compare counts
SELECT 
    (SELECT COUNT(*) FROM public_profiles WHERE profile_data IS NOT NULL) as source_count,
    (SELECT COUNT(*) FROM flattened_profiles) as flattened_count;

-- Find recently updated profiles
SELECT profile_id, full_name, last_updated 
FROM flattened_profiles 
ORDER BY last_updated DESC 
LIMIT 10;
```

### Performance Optimization
```sql
-- Analyze table statistics
ANALYZE flattened_profiles;

-- Reindex search vectors if needed
REINDEX INDEX idx_flattened_profiles_search;
```

## Troubleshooting

### Common Issues

1. **Trigger not firing**: Ensure `public_profiles` table exists and trigger is created
2. **Missing profile IDs**: Check that profiles have `id` field in JSONB or table
3. **Date parsing errors**: Verify date formats in work experience
4. **Performance issues**: Consider partitioning for large datasets

### Debug Mode
Enable detailed logging:
```sql
SET log_min_messages = 'NOTICE';
```

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