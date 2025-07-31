-- Migration: Create flattened_profiles table
-- This table stores flattened profile data synchronized from public_profiles

CREATE TABLE IF NOT EXISTS flattened_profiles (
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

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_flattened_profiles_original_id ON flattened_profiles(original_id);
CREATE INDEX IF NOT EXISTS idx_flattened_profiles_full_name ON flattened_profiles(full_name);
CREATE INDEX IF NOT EXISTS idx_flattened_profiles_current_company ON flattened_profiles(current_company);
CREATE INDEX IF NOT EXISTS idx_flattened_profiles_location ON flattened_profiles(location);
CREATE INDEX IF NOT EXISTS idx_flattened_profiles_search ON flattened_profiles USING GIN(search_text);
CREATE INDEX IF NOT EXISTS idx_flattened_profiles_skills ON flattened_profiles(skills);
CREATE INDEX IF NOT EXISTS idx_flattened_profiles_current_title ON flattened_profiles(current_title);

-- Create a function to update the search text vector
CREATE OR REPLACE FUNCTION update_flattened_profiles_search_text()
RETURNS TRIGGER AS $$
BEGIN
    NEW.search_text := to_tsvector('english', COALESCE(NEW.full_jsonb::text, ''));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically update search text
CREATE TRIGGER update_flattened_profiles_search_text_trigger
    BEFORE INSERT OR UPDATE ON flattened_profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_flattened_profiles_search_text();