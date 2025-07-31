-- Migration: Create profile flattening function
-- This function extracts and flattens data from public_profiles JSONB to flattened_profiles structure

CREATE OR REPLACE FUNCTION flatten_profile_data(profile_json JSONB, source_profile_id TEXT)
RETURNS TABLE (
    profile_id TEXT,
    full_name TEXT,
    first_name TEXT,
    last_name TEXT,
    email TEXT,
    phone TEXT,
    linkedin_url TEXT,
    github_url TEXT,
    website_url TEXT,
    location TEXT,
    headline TEXT,
    summary TEXT,
    current_company TEXT,
    current_position TEXT,
    current_start_date DATE,
    total_years_experience INTEGER,
    years_at_current_company INTEGER,
    previous_companies TEXT[],
    job_titles TEXT[],
    industries TEXT[],
    skills TEXT[],
    technologies TEXT[],
    programming_languages TEXT[],
    education_degrees TEXT[],
    education_schools TEXT[],
    education_fields TEXT[],
    certifications TEXT[],
    company_size TEXT,
    company_industry TEXT,
    company_location TEXT,
    profile_source TEXT,
    original_data JSONB
) AS $$
DECLARE
    work_experience JSONB;
    experience_item JSONB;
    education_item JSONB;
    cert_item JSONB;
    current_job JSONB;
    total_exp INTEGER := 0;
    current_exp INTEGER := 0;
    prev_companies TEXT[] := '{}';
    all_titles TEXT[] := '{}';
    all_industries TEXT[] := '{}';
    all_skills TEXT[] := '{}';
    all_technologies TEXT[] := '{}';
    all_languages TEXT[] := '{}';
    all_degrees TEXT[] := '{}';
    all_schools TEXT[] := '{}';
    all_fields TEXT[] := '{}';
    all_certs TEXT[] := '{}';
    temp_array TEXT[];
    temp_text TEXT;
    start_year INTEGER;
    end_year INTEGER;
    current_year INTEGER := EXTRACT(YEAR FROM CURRENT_DATE);
BEGIN
    -- Basic personal information extraction
    profile_id := source_profile_id;
    full_name := profile_json->>'name';
    first_name := SPLIT_PART(COALESCE(profile_json->>'name', ''), ' ', 1);
    last_name := CASE WHEN profile_json->>'name' ~ '\s' THEN 
                     TRIM(SUBSTRING(profile_json->>'name' FROM POSITION(' ' IN profile_json->>'name')))
                 ELSE NULL END;
    
    email := profile_json->>'email';
    phone := profile_json->>'phone';
    linkedin_url := profile_json->>'linkedin';
    github_url := profile_json->>'github';
    website_url := profile_json->>'website';
    location := profile_json->>'location';
    headline := profile_json->>'headline';
    summary := profile_json->>'summary';
    
    -- Extract skills arrays
    IF profile_json ? 'skills' AND jsonb_typeof(profile_json->'skills') = 'array' THEN
        SELECT ARRAY(SELECT jsonb_array_elements_text(profile_json->'skills')) INTO all_skills;
    END IF;
    
    IF profile_json ? 'technologies' AND jsonb_typeof(profile_json->'technologies') = 'array' THEN
        SELECT ARRAY(SELECT jsonb_array_elements_text(profile_json->'technologies')) INTO all_technologies;
    END IF;
    
    IF profile_json ? 'programming_languages' AND jsonb_typeof(profile_json->'programming_languages') = 'array' THEN
        SELECT ARRAY(SELECT jsonb_array_elements_text(profile_json->'programming_languages')) INTO all_languages;
    END IF;
    
    -- Process work experience
    work_experience := profile_json->'work_experience';
    IF work_experience IS NOT NULL AND jsonb_typeof(work_experience) = 'array' THEN
        FOR experience_item IN SELECT * FROM jsonb_array_elements(work_experience)
        LOOP
            -- Add company to previous companies list
            temp_text := experience_item->>'company';
            IF temp_text IS NOT NULL AND temp_text != '' THEN
                prev_companies := array_append(prev_companies, temp_text);
            END IF;
            
            -- Add job title
            temp_text := experience_item->>'title';
            IF temp_text IS NOT NULL AND temp_text != '' THEN
                all_titles := array_append(all_titles, temp_text);
            END IF;
            
            -- Add industry
            temp_text := experience_item->>'industry';
            IF temp_text IS NOT NULL AND temp_text != '' THEN
                all_industries := array_append(all_industries, temp_text);
            END IF;
            
            -- Calculate experience duration
            start_year := NULL;
            end_year := NULL;
            
            -- Parse start date
            temp_text := experience_item->>'start_date';
            IF temp_text IS NOT NULL AND temp_text ~ '^\d{4}' THEN
                start_year := SUBSTRING(temp_text FROM '^\d{4}')::INTEGER;
            END IF;
            
            -- Parse end date (or use current year if still employed)
            temp_text := experience_item->>'end_date';
            IF temp_text IS NOT NULL AND temp_text != '' AND temp_text !~ '(?i)(current|present|ongoing)' THEN
                IF temp_text ~ '^\d{4}' THEN
                    end_year := SUBSTRING(temp_text FROM '^\d{4}')::INTEGER;
                END IF;
            ELSE
                end_year := current_year;
                -- This might be current job
                IF current_job IS NULL OR 
                   (experience_item->>'end_date' IS NULL OR 
                    experience_item->>'end_date' ~ '(?i)(current|present|ongoing)') THEN
                    current_job := experience_item;
                END IF;
            END IF;
            
            -- Add to total experience
            IF start_year IS NOT NULL AND end_year IS NOT NULL AND end_year >= start_year THEN
                total_exp := total_exp + (end_year - start_year + 1);
                
                -- Check if this is current job for years at current company
                IF current_job IS NOT NULL AND current_job = experience_item THEN
                    current_exp := end_year - start_year + 1;
                END IF;
            END IF;
        END LOOP;
        
        -- Remove duplicates from arrays
        prev_companies := ARRAY(SELECT DISTINCT unnest(prev_companies) WHERE unnest IS NOT NULL AND unnest != '');
        all_titles := ARRAY(SELECT DISTINCT unnest(all_titles) WHERE unnest IS NOT NULL AND unnest != '');
        all_industries := ARRAY(SELECT DISTINCT unnest(all_industries) WHERE unnest IS NOT NULL AND unnest != '');
    END IF;
    
    -- Set current job information
    IF current_job IS NOT NULL THEN
        current_company := current_job->>'company';
        current_position := current_job->>'title';
        
        -- Parse current start date
        temp_text := current_job->>'start_date';
        IF temp_text IS NOT NULL AND temp_text ~ '^\d{4}-\d{2}' THEN
            current_start_date := temp_text::DATE;
        ELSIF temp_text IS NOT NULL AND temp_text ~ '^\d{4}' THEN
            current_start_date := (SUBSTRING(temp_text FROM '^\d{4}') || '-01-01')::DATE;
        END IF;
        
        -- Company information from current job
        company_size := current_job->>'company_size';
        company_industry := current_job->>'industry';
        company_location := current_job->>'location';
    END IF;
    
    -- Process education
    IF profile_json ? 'education' AND jsonb_typeof(profile_json->'education') = 'array' THEN
        FOR education_item IN SELECT * FROM jsonb_array_elements(profile_json->'education')
        LOOP
            -- Add degree
            temp_text := education_item->>'degree';
            IF temp_text IS NOT NULL AND temp_text != '' THEN
                all_degrees := array_append(all_degrees, temp_text);
            END IF;
            
            -- Add school
            temp_text := education_item->>'school';
            IF temp_text IS NOT NULL AND temp_text != '' THEN
                all_schools := array_append(all_schools, temp_text);
            END IF;
            
            -- Add field of study
            temp_text := education_item->>'field';
            IF temp_text IS NOT NULL AND temp_text != '' THEN
                all_fields := array_append(all_fields, temp_text);
            END IF;
        END LOOP;
        
        -- Remove duplicates
        all_degrees := ARRAY(SELECT DISTINCT unnest(all_degrees) WHERE unnest IS NOT NULL AND unnest != '');
        all_schools := ARRAY(SELECT DISTINCT unnest(all_schools) WHERE unnest IS NOT NULL AND unnest != '');
        all_fields := ARRAY(SELECT DISTINCT unnest(all_fields) WHERE unnest IS NOT NULL AND unnest != '');
    END IF;
    
    -- Process certifications
    IF profile_json ? 'certifications' AND jsonb_typeof(profile_json->'certifications') = 'array' THEN
        FOR cert_item IN SELECT * FROM jsonb_array_elements(profile_json->'certifications')
        LOOP
            temp_text := cert_item->>'name';
            IF temp_text IS NOT NULL AND temp_text != '' THEN
                all_certs := array_append(all_certs, temp_text);
            END IF;
        END LOOP;
        
        all_certs := ARRAY(SELECT DISTINCT unnest(all_certs) WHERE unnest IS NOT NULL AND unnest != '');
    END IF;
    
    -- Set final values
    total_years_experience := total_exp;
    years_at_current_company := current_exp;
    previous_companies := prev_companies;
    job_titles := all_titles;
    industries := all_industries;
    skills := all_skills;
    technologies := all_technologies;
    programming_languages := all_languages;
    education_degrees := all_degrees;
    education_schools := all_schools;
    education_fields := all_fields;
    certifications := all_certs;
    profile_source := 'public_profiles';
    original_data := profile_json;
    
    RETURN NEXT;
END;
$$ LANGUAGE plpgsql;