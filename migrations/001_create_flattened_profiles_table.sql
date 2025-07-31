-- Migration: Create flattened_profiles table
-- This table stores flattened profile data synchronized from public_profiles

CREATE TABLE IF NOT EXISTS flattened_profiles (
    id SERIAL PRIMARY KEY,
    profile_id TEXT UNIQUE NOT NULL,
    
    -- Basic Information
    full_name TEXT,
    first_name TEXT,
    last_name TEXT,
    email TEXT,
    phone TEXT,
    linkedin_url TEXT,
    github_url TEXT,
    website_url TEXT,
    location TEXT,
    
    -- Professional Summary
    headline TEXT,
    summary TEXT,
    
    -- Current Position
    current_company TEXT,
    current_position TEXT,
    current_start_date DATE,
    
    -- Experience Analysis
    total_years_experience INTEGER DEFAULT 0,
    years_at_current_company INTEGER DEFAULT 0,
    previous_companies TEXT[], -- Array of previous company names
    job_titles TEXT[], -- Array of all job titles held
    industries TEXT[], -- Array of industries worked in
    
    -- Skills and Technologies
    skills TEXT[], -- Array of skills
    technologies TEXT[], -- Array of technologies/tools
    programming_languages TEXT[], -- Array of programming languages
    
    -- Education
    education_degrees TEXT[], -- Array of degrees earned
    education_schools TEXT[], -- Array of schools attended
    education_fields TEXT[], -- Array of fields of study
    
    -- Certifications
    certifications TEXT[], -- Array of certifications
    
    -- Company Information (for current employer)
    company_size TEXT,
    company_industry TEXT,
    company_location TEXT,
    
    -- Metadata
    profile_source TEXT, -- Source of the profile data
    last_updated TIMESTAMP DEFAULT NOW(),
    created_at TIMESTAMP DEFAULT NOW(),
    
    -- Original JSON data (for reference)
    original_data JSONB,
    
    -- Search optimization
    search_vector tsvector
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_flattened_profiles_profile_id ON flattened_profiles(profile_id);
CREATE INDEX IF NOT EXISTS idx_flattened_profiles_full_name ON flattened_profiles(full_name);
CREATE INDEX IF NOT EXISTS idx_flattened_profiles_current_company ON flattened_profiles(current_company);
CREATE INDEX IF NOT EXISTS idx_flattened_profiles_location ON flattened_profiles(location);
CREATE INDEX IF NOT EXISTS idx_flattened_profiles_experience ON flattened_profiles(total_years_experience);
CREATE INDEX IF NOT EXISTS idx_flattened_profiles_skills ON flattened_profiles USING GIN(skills);
CREATE INDEX IF NOT EXISTS idx_flattened_profiles_technologies ON flattened_profiles USING GIN(technologies);
CREATE INDEX IF NOT EXISTS idx_flattened_profiles_search ON flattened_profiles USING GIN(search_vector);
CREATE INDEX IF NOT EXISTS idx_flattened_profiles_updated ON flattened_profiles(last_updated);

-- Create a function to update the search vector
CREATE OR REPLACE FUNCTION update_flattened_profiles_search_vector()
RETURNS TRIGGER AS $$
BEGIN
    NEW.search_vector := 
        setweight(to_tsvector('english', COALESCE(NEW.full_name, '')), 'A') ||
        setweight(to_tsvector('english', COALESCE(NEW.current_company, '')), 'A') ||
        setweight(to_tsvector('english', COALESCE(NEW.current_position, '')), 'A') ||
        setweight(to_tsvector('english', COALESCE(NEW.headline, '')), 'B') ||
        setweight(to_tsvector('english', COALESCE(NEW.summary, '')), 'C') ||
        setweight(to_tsvector('english', COALESCE(array_to_string(NEW.skills, ' '), '')), 'B') ||
        setweight(to_tsvector('english', COALESCE(array_to_string(NEW.technologies, ' '), '')), 'B') ||
        setweight(to_tsvector('english', COALESCE(NEW.location, '')), 'C');
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically update search vector
CREATE TRIGGER update_flattened_profiles_search_vector_trigger
    BEFORE INSERT OR UPDATE ON flattened_profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_flattened_profiles_search_vector();