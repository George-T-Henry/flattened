-- Migration: Create profile flattening function
-- This function extracts and flattens data from public_profiles JSONB to flattened_profiles structure

CREATE OR REPLACE FUNCTION flatten_profile_data(profile_json JSONB, source_original_id TEXT)
RETURNS TABLE (
    original_id TEXT,
    full_name TEXT,
    current_title TEXT,
    location TEXT,
    about_me TEXT,
    linkedin TEXT,
    gender TEXT,
    skills TEXT,
    current_company TEXT,
    current_title_from_workexp TEXT,
    past_experience TEXT,
    full_jsonb JSONB
) AS $$
DECLARE
    work_experience JSONB;
    experience_item JSONB;
    current_job JSONB;
    past_jobs TEXT[] := '{}';
    skills_array TEXT[] := '{}';
    temp_text TEXT;
BEGIN
    -- Set basic fields - handle both simple and complex data structures
    original_id := source_original_id;
    
    -- Try new structure first (candidate.full_name), then fallback to old structure (name)
    full_name := COALESCE(profile_json->'candidate'->>'full_name', profile_json->>'name');
    current_title := COALESCE(profile_json->'candidate'->>'title', profile_json->>'headline');
    location := COALESCE(profile_json->'candidate'->>'location_raw', profile_json->>'location');
    about_me := COALESCE(profile_json->'candidate'->>'about_me', profile_json->>'summary');
    linkedin := COALESCE(profile_json->'candidate'->>'linkedin', profile_json->>'linkedin');
    gender := COALESCE(profile_json->'candidate'->>'gender', profile_json->>'gender');
    full_jsonb := profile_json;
    
    -- Extract skills (handle both array and string formats)
    IF profile_json ? 'skills' THEN
        IF jsonb_typeof(profile_json->'skills') = 'array' THEN
            SELECT string_agg(value::text, ', ')
            FROM jsonb_array_elements_text(profile_json->'skills')
            INTO skills;
        ELSE
            skills := profile_json->>'skills';
        END IF;
    END IF;
    
    -- Process work experience to find current job and past experience
    -- Handle both 'workexp' (new structure) and 'work_experience' (old structure) 
    work_experience := COALESCE(profile_json->'workexp', profile_json->'work_experience');
    IF work_experience IS NOT NULL AND jsonb_typeof(work_experience) = 'array' THEN
        FOR experience_item IN SELECT * FROM jsonb_array_elements(work_experience)
        LOOP
            -- Handle new structure: check duration.to_present or duration.end_date
            IF experience_item ? 'duration' THEN
                -- New structure with duration object
                IF (experience_item->'duration'->>'to_present')::boolean = true OR 
                   experience_item->'duration'->'end_date' IS NULL THEN
                    IF current_job IS NULL THEN -- Take first current job found
                        current_job := experience_item;
                        current_company := experience_item->'company'->>'name';
                        -- Get title from projects array if available
                        IF jsonb_typeof(experience_item->'projects') = 'array' AND 
                           jsonb_array_length(experience_item->'projects') > 0 THEN
                            current_title_from_workexp := experience_item->'projects'->0->'role_and_group'->>'title';
                        END IF;
                    END IF;
                ELSE
                    -- Add to past experience (new structure)
                    temp_text := CONCAT(
                        COALESCE(
                            (CASE WHEN jsonb_typeof(experience_item->'projects') = 'array' AND 
                                      jsonb_array_length(experience_item->'projects') > 0 
                                  THEN experience_item->'projects'->0->'role_and_group'->>'title'
                                  ELSE ''
                             END), ''
                        ), 
                        ' at ', 
                        COALESCE(experience_item->'company'->>'name', '')
                    );
                    past_jobs := array_append(past_jobs, temp_text);
                END IF;
            ELSE
                -- Old structure: check end_date directly
                temp_text := experience_item->>'end_date';
                
                IF temp_text IS NULL OR temp_text = '' OR temp_text ~* '(current|present|ongoing)' THEN
                    IF current_job IS NULL THEN -- Take first current job found
                        current_job := experience_item;
                        current_company := experience_item->>'company';
                        current_title_from_workexp := experience_item->>'title';
                    END IF;
                ELSE
                    -- Add to past experience (old structure)
                    temp_text := CONCAT(
                        COALESCE(experience_item->>'title', ''), 
                        ' at ', 
                        COALESCE(experience_item->>'company', ''),
                        CASE 
                            WHEN experience_item->>'start_date' IS NOT NULL THEN 
                                ' (' || experience_item->>'start_date' || ' - ' || experience_item->>'end_date' || ')'
                            ELSE ''
                        END
                    );
                    past_jobs := array_append(past_jobs, temp_text);
                END IF;
            END IF;
        END LOOP;
        
        -- Convert past jobs array to string
        IF array_length(past_jobs, 1) > 0 THEN
            past_experience := array_to_string(past_jobs, '; ');
        END IF;
    END IF;
    
    -- If no current job found in work experience, use headline/title fields
    IF current_company IS NULL THEN
        current_company := profile_json->>'current_company';
    END IF;
    
    IF current_title_from_workexp IS NULL THEN
        current_title_from_workexp := current_title;
    END IF;
    
    RETURN NEXT;
END;
$$ LANGUAGE plpgsql;